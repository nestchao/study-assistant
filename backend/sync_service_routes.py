# backend/sync_service_routes.py
import json
from pathlib import Path
from flask import Blueprint, request, jsonify
from firebase_admin import firestore
import hashlib 
from utils import (
    get_file_hash, 
    convert_and_upload_to_firestore, 
    delete_collection, 
    generate_tree_text_from_paths
)

# --- BLUEPRINT SETUP ---
sync_service_bp = Blueprint('sync_service_bp', __name__)
db = None

# --- CONSTANTS FOR NEW DATA MODEL ---
CODE_PROJECTS_COLLECTION = "code_projects"
CODE_FILES_SUBCOLLECTION = "synced_code_files"

def set_dependencies(db_instance):
    global db
    db = db_instance

# --- CORE SYNC LOGIC (The "Check Synchronize" button) ---
def perform_sync(project_id: str, config_data: dict):
    # Config data is now passed directly from the project document
    source_dir = config_data.get('local_path')
    extensions = config_data.get('allowed_extensions', [])
    ignored_paths = config_data.get('ignored_paths', [])

    project_ref = db.collection(CODE_PROJECTS_COLLECTION).document(project_id)

    try:
        print("\n" + "="*60)
        print(f"SYNC-SERVICE: Starting sync for code_project: {project_id}")
        print(f"SYNC-SERVICE: Ignoring paths: {ignored_paths}")

        source_path = Path(source_dir)
        if not source_path.is_dir():
            raise FileNotFoundError(f"Source directory not found: {source_dir}")

        logs = []
        updated_count = deleted_count = 0

        # 0. Mark as syncing (update the project doc)
        project_ref.update({'status': 'syncing'})

        # 1. READ manifest
        manifest_ref = project_ref.collection(CODE_FILES_SUBCOLLECTION).document('_manifest')
        manifest_doc = manifest_ref.get()
        files_in_db = manifest_doc.to_dict().get('files', {}) if manifest_doc.exists else {}

        # 2. Scan local files (No changes here)
        print("SYNC-SERVICE: Step 2/7 - Scanning and filtering local files...")
        normalized_ignored_paths = [Path(p.replace('\\', '/')) for p in ignored_paths]
        all_local_files = [f for f in source_path.rglob("*") if f.is_file() and '.git' not in f.parts and not any(f.relative_to(source_path).is_relative_to(ignored) for ignored in normalized_ignored_paths)]
        dot_ext = [f".{e.lstrip('.').lower()}" for e in extensions] if extensions else None
        files_to_process = [f for f in all_local_files if not dot_ext or f.suffix.lower() in dot_ext]
        print(f"SYNC-SERVICE: Found {len(files_to_process)} files to process.")

        # 3. UPDATE / CREATE
        processed_paths = set()
        for file_path in files_to_process:
            rel_path = str(file_path.relative_to(source_path)).replace('\\', '/')
            processed_paths.add(rel_path)
            local_hash = get_file_hash(file_path)
            db_hash    = files_in_db.get(rel_path, {}).get('hash')
            if local_hash != db_hash:
                logs.append(f"UPDATE: {rel_path}")
                result = convert_and_upload_to_firestore(db, project_id, file_path, source_path, CODE_FILES_SUBCOLLECTION, CODE_PROJECTS_COLLECTION)
                if result:
                    uploaded_hash, doc_id = result
                    files_in_db[rel_path] = {'hash': uploaded_hash, 'doc_id': doc_id}
                    updated_count += 1

        # 4. DELETE
        db_paths = {p for p in files_in_db if not dot_ext or Path(p).suffix.lower() in dot_ext}
        to_delete = db_paths - processed_paths
        for p in to_delete:
            logs.append(f"DELETE: {p}")
            doc_id = files_in_db[p].get('doc_id')
            if doc_id:
                project_ref.collection(CODE_FILES_SUBCOLLECTION).document(doc_id).delete()
            del files_in_db[p]
            deleted_count += 1
        
        # 5. WRITE MANIFEST
        manifest_changed = bool(updated_count or deleted_count or files_to_process)
        if manifest_changed:
            manifest_ref.set({'files': files_in_db, 'last_updated': firestore.SERVER_TIMESTAMP}, merge=True)
            print("SYNC-SERVICE: Manifest written.")
        else:
            print("SYNC-SERVICE: Nothing to sync – manifest untouched.")

        # 6. SPECIAL FILES
        final_file_paths = sorted(list(files_in_db.keys()))
        tree_content = generate_tree_text_from_paths(source_path.name, final_file_paths)
        project_ref.collection(CODE_FILES_SUBCOLLECTION).document('project_tree_txt').set({
            'original_path': 'tree.txt', 'content': tree_content,
            'hash': hashlib.sha256(tree_content.encode('utf-8')).hexdigest(),
            'timestamp': firestore.SERVER_TIMESTAMP
        })
        chunks = []
        for rel_path in final_file_paths:
            doc_id = files_in_db[rel_path].get('doc_id')
            if doc_id:
                doc = project_ref.collection(CODE_FILES_SUBCOLLECTION).document(doc_id).get()
                if doc.exists:
                    chunks.append(f"--- FILE: {rel_path} ---\n\n{doc.to_dict().get('content','')}\n\n")
        full_txt = "".join(chunks)
        project_ref.collection(CODE_FILES_SUBCOLLECTION).document('project_full_context_txt').set({
            'original_path': '_full_context.txt', 'content': full_txt,
            'hash': hashlib.sha256(full_txt.encode('utf-8')).hexdigest(),
            'timestamp': firestore.SERVER_TIMESTAMP,
        })
        print("SYNC-SERVICE: ✅ Special files updated.")
        
        # 7. FINISH
        print(f"SYNC-SERVICE: Sync complete – {updated_count} updated, {deleted_count} deleted")
        project_ref.update({'status': 'idle', 'last_synced': firestore.SERVER_TIMESTAMP})
        return {"logs": logs, "updated": updated_count, "deleted": deleted_count}
    except Exception as e:
        import traceback; traceback.print_exc()
        try: project_ref.update({'status': 'error'})
        except: pass
        raise

# --- ROUTES FOR MANAGING SYNC ---

# [CREATE] Register a folder to a code project
@sync_service_bp.route('/sync/register/<project_id>', methods=['POST'])
def register_folder(project_id):
    data = request.json
    local_path = data.get('local_path')
    allowed_extensions = data.get('extensions', [])
    ignored_paths = data.get('ignored_paths', []) 

    if not local_path:
        return jsonify({"error": "Missing 'local_path'"}), 400
    if not Path(local_path).is_dir():
        return jsonify({"error": f"Path is not a valid directory: {local_path}"}), 400

    try:
        project_ref = db.collection(CODE_PROJECTS_COLLECTION).document(project_id)
        config_data = {
            "local_path": local_path,
            "allowed_extensions": allowed_extensions,
            "ignored_paths": ignored_paths,
            "is_active": True,
            "status": "idle",
            "last_synced": None
        }
        project_ref.update(config_data) # Use update to add fields
        return jsonify({"success": True, "project_id": project_id}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# [READ] List all code projects that can be synced
@sync_service_bp.route('/sync/projects', methods=['GET'])
def list_sync_projects():
    try:
        projects = []
        # We only list projects that have a local_path, meaning they are configured for sync
        docs = db.collection(CODE_PROJECTS_COLLECTION).where('local_path', '!=', None).stream()
        for doc in docs:
            project_data = doc.to_dict()
            project_data['id'] = doc.id
            projects.append(project_data)
        return jsonify(projects)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# [UPDATE] Modify a project's sync config
@sync_service_bp.route('/sync/project/<project_id>', methods=['PUT'])
def update_sync_project(project_id):
    data = request.json
    allowed_updates = ['allowed_extensions', 'is_active', 'ignored_paths']
    updates = {key: data[key] for key in data if key in allowed_updates}

    if not updates:
        return jsonify({"error": "No valid fields to update provided."}), 400

    try:
        db.collection(CODE_PROJECTS_COLLECTION).document(project_id).update(updates)
        return jsonify({"success": True, "message": "Sync configuration updated."})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# [DELETE] Unregister a folder (clears sync fields from project)
@sync_service_bp.route('/sync/project/<project_id>', methods=['DELETE'])
def delete_sync_project(project_id):
    try:
        project_ref = db.collection(CODE_PROJECTS_COLLECTION).document(project_id)
        # We set the fields to None to effectively "unregister" it
        fields_to_clear = {
            "local_path": None,
            "allowed_extensions": [],
            "ignored_paths": [],
            "is_active": False,
            "status": "unregistered",
        }
        project_ref.update(fields_to_clear)
        return jsonify({"success": True, "message": "Sync configuration removed from project."})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# [RUN] Trigger a sync for a specific project
@sync_service_bp.route('/sync/run/<project_id>', methods=['POST'])
def run_sync_route(project_id):
    try:
        project_doc = db.collection(CODE_PROJECTS_COLLECTION).document(project_id).get()
        if not project_doc.exists:
            return jsonify({"error": "Code project not found"}), 404
        
        config_data = project_doc.to_dict()
        if not config_data.get('is_active'):
            return jsonify({"message": "Sync is disabled for this project."}), 200

        result = perform_sync(project_id, config_data)
        return jsonify({"success": True, **result})
    except Exception as e:
        import traceback
        print(f"‼️ CRITICAL ERROR in run_sync_route for {project_id} ‼️\n{traceback.format_exc()}")
        return jsonify({"error": str(e), "traceback": traceback.format_exc()}), 500