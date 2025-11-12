# backend/sync_service_routes.py
import json
from pathlib import Path
from flask import Blueprint, request, jsonify
from firebase_admin import firestore
import hashlib 
from utils import (
    get_file_hash, 
    convert_and_upload_to_firestore, 
    get_converted_file_ref, 
    delete_collection, 
    generate_tree_text_from_paths,
    DOT_REPLACEMENT
)

# --- BLUEPRINT SETUP ---
sync_service_bp = Blueprint('sync_service_bp', __name__)
db = None

CONFIG_COLLECTION = "sync_configs"

def set_dependencies(db_instance):
    global db
    db = db_instance

# --- CORE SYNC LOGIC (The "Check Synchronize" button) ---
def perform_sync(config_id: str, config_data: dict):
    project_id = config_data.get('project_id')
    source_dir = config_data.get('local_path')
    extensions = config_data.get('allowed_extensions', [])
    ignored_paths = config_data.get('ignored_paths', [])

    try:
        print("\n" + "="*60)
        print(f"SYNC-SERVICE: Starting sync – config_id: {config_id}")
        print(f"SYNC-SERVICE: Ignoring paths: {ignored_paths}") # Log the ignored paths

        source_path = Path(source_dir)
        if not source_path.is_dir():
            raise FileNotFoundError(f"Source directory not found: {source_dir}")

        logs = []
        updated_count = deleted_count = 0

        # ------------------------------------------------------------------
        # 0. Mark as syncing
        # ------------------------------------------------------------------
        config_ref = db.collection(CONFIG_COLLECTION).document(config_id)
        config_ref.update({'status': 'syncing'})

        # ------------------------------------------------------------------
        # 1. READ manifest
        # ------------------------------------------------------------------
        manifest_ref = db.collection('projects') \
                         .document(project_id) \
                         .collection('converted_files') \
                         .document('_manifest')
        manifest_doc = manifest_ref.get()
        files_in_db = manifest_doc.to_dict().get('files', {}) if manifest_doc.exists else {}

        # ------------------------------------------------------------------
        # 2. Scan local files
        # ------------------------------------------------------------------
        print("SYNC-SERVICE: Step 2/7 - Scanning and filtering local files...")

        # Normalize ignored paths to use forward slashes
        normalized_ignored_paths = [Path(p.replace('\\', '/')) for p in ignored_paths]

        all_local_files = []
        for f in source_path.rglob("*"):
            if not f.is_file() or '.git' in f.parts:
                continue

            rel_path = f.relative_to(source_path)
            
            # Check if the file's path is a subpath of any ignored path
            is_ignored = any(
                rel_path.is_relative_to(ignored) for ignored in normalized_ignored_paths
            )
            
            if is_ignored:
                # print(f"  - Ignoring {rel_path}") # Optional: for verbose logging
                continue
            
            all_local_files.append(f)
        
        dot_ext = [f".{e.lstrip('.').lower()}" for e in extensions] if extensions else None
        files_to_process = [f for f in all_local_files
                           if not dot_ext or f.suffix.lower() in dot_ext]
        print(f"SYNC-SERVICE: Found {len(files_to_process)} files to process after filtering.")

        # ------------------------------------------------------------------
        # 3. UPDATE / CREATE
        # ------------------------------------------------------------------
        processed_paths = set()
        for file_path in files_to_process:
            rel_path = str(file_path.relative_to(source_path)).replace('\\', '/')
            processed_paths.add(rel_path)

            local_hash = get_file_hash(file_path)
            db_hash    = files_in_db.get(rel_path, {}).get('hash')

            if local_hash != db_hash:
                logs.append(f"UPDATE: {rel_path}")
                result = convert_and_upload_to_firestore(db, project_id, file_path, source_path)
                if result:
                    uploaded_hash, doc_id = result
                    files_in_db[rel_path] = {'hash': uploaded_hash, 'doc_id': doc_id}
                    updated_count += 1

        # ------------------------------------------------------------------
        # 4. DELETE
        # ------------------------------------------------------------------
        db_paths = {p for p in files_in_db
                    if not dot_ext or Path(p).suffix.lower() in dot_ext}
        to_delete = db_paths - processed_paths

        for p in to_delete:
            logs.append(f"DELETE: {p}")
            doc_id = files_in_db[p].get('doc_id')
            if doc_id:
                db.collection('projects').document(project_id) \
                  .collection('converted_files').document(doc_id).delete()
            del files_in_db[p]
            deleted_count += 1

        # ------------------------------------------------------------------
        # 5. WRITE MANIFEST (ALWAYS if we touched anything)
        # ------------------------------------------------------------------
        manifest_changed = bool(updated_count or deleted_count or files_to_process)
        if manifest_changed:
            payload = {
                'files': files_in_db,
                'last_updated': firestore.SERVER_TIMESTAMP
            }
            if manifest_doc.exists:
                manifest_ref.update(payload)
            else:
                manifest_ref.set(payload)
            print("SYNC-SERVICE: Manifest written.")
        else:
            print("SYNC-SERVICE: Nothing to sync – manifest untouched.")

        # ------------------------------------------------------------------
        # 6. SPECIAL FILES (tree.txt + _full_context.txt) – ONLY if we have files
        # ------------------------------------------------------------------
        try:
            # Use the final, correct in-memory manifest as the source of truth
            final_file_paths = sorted(list(files_in_db.keys()))

            # ----- Part A: tree.txt -----
            print("SYNC-SERVICE: Generating filtered tree.txt...")
            # Use the new utility that builds from a list of paths
            tree_content = generate_tree_text_from_paths(source_path.name, final_file_paths)
            
            db.collection('projects').document(project_id) \
            .collection('converted_files').document('project_tree_txt').set({
                'original_path': 'tree.txt',
                'content': tree_content,
                'hash': hashlib.sha256(tree_content.encode('utf-8')).hexdigest(),
                'timestamp': firestore.SERVER_TIMESTAMP,
            })
            print("SYNC-SERVICE: ✅ Saved filtered tree.txt.")

            # ----- Part B: _full_context.txt -----
            print("SYNC-SERVICE: Generating filtered _full_context.txt...")
            chunks = []
            # Iterate through the final, sorted, filtered list of paths
            for rel_path in final_file_paths:
                doc_id = files_in_db[rel_path].get('doc_id')
                if not doc_id:
                    logs.append(f"WARN: Missing doc_id for {rel_path} in manifest.")
                    continue
                
                doc = db.collection('projects').document(project_id) \
                        .collection('converted_files').document(doc_id).get()
                
                if doc.exists:
                    chunks.append(f"--- FILE: {rel_path} ---\n\n{doc.to_dict().get('content','')}\n\n")
                else:
                    logs.append(f"WARN: Doc {doc_id} not found for path {rel_path} during full_context generation.")

            full_txt = "".join(chunks)
            db.collection('projects').document(project_id) \
            .collection('converted_files').document('project_full_context_txt').set({
                'original_path': '_full_context.txt',
                'content': full_txt,
                'hash': hashlib.sha256(full_txt.encode('utf-8')).hexdigest(),
                'timestamp': firestore.SERVER_TIMESTAMP,
            })
            print("SYNC-SERVICE: ✅ Saved filtered _full_context.txt.")

        except Exception as e:
            logs.append(f"ERROR generating special files: {e}")
            # Optionally re-raise if this should be a critical failure
            # raise


        # ------------------------------------------------------------------
        # 7. FINISH
        # ------------------------------------------------------------------
        print(f"SYNC-SERVICE: Sync complete – {updated_count} updated, {deleted_count} deleted")
        config_ref.update({'status': 'idle', 'last_synced': firestore.SERVER_TIMESTAMP})
        return {"logs": logs, "updated": updated_count, "deleted": deleted_count}

    except Exception as e:
        # ------------------------------------------------------------------
        # GLOBAL ERROR HANDLER
        # ------------------------------------------------------------------
        print("\n" + "!"*60)
        print("CRITICAL ERROR IN perform_sync")
        print(f"Type: {type(e).__name__} | Msg: {e}")
        import traceback
        print(traceback.format_exc())
        print("!"*60 + "\n")

        try:
            config_ref.update({'status': 'error'})
        except Exception:
            pass
        raise

# --- ROUTES FOR CRUD ON SYNC CONFIGURATIONS ---

# [CREATE] Register a new folder to sync
@sync_service_bp.route('/sync/register', methods=['POST'])
def register_folder():
    data = request.json
    project_id = data.get('project_id')
    local_path = data.get('local_path')
    allowed_extensions = data.get('extensions', [])
    ignored_paths = data.get('ignored_paths', []) 

    if not all([project_id, local_path]):
        return jsonify({"error": "Missing 'project_id' or 'local_path'"}), 400
    if not Path(local_path).is_dir():
        return jsonify({"error": f"Path is not a valid directory: {local_path}"}), 400

    try:
        config_data = {
            "project_id": project_id,
            "local_path": local_path,
            "allowed_extensions": allowed_extensions,
            "ignored_paths": ignored_paths,
            "is_active": True,
            "status": "idle",
            "created_at": firestore.SERVER_TIMESTAMP,
            "last_synced": None
        }
        config_ref = db.collection(CONFIG_COLLECTION).document()
        config_ref.set(config_data)
        return jsonify({"success": True, "config_id": config_ref.id}), 201
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# [READ] List all registered folders
@sync_service_bp.route('/sync/configs', methods=['GET'])
def list_configs():
    try:
        configs = []
        docs = db.collection(CONFIG_COLLECTION).stream()
        for doc in docs:
            config = doc.to_dict()
            config['id'] = doc.id
            configs.append(config)
        return jsonify(configs)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# [UPDATE] Modify a registered folder (e.g., change extensions, activate/deactivate)
@sync_service_bp.route('/sync/config/<config_id>', methods=['PUT'])
def update_config(config_id):
    data = request.json
    allowed_updates = ['allowed_extensions', 'is_active', 'ignored_paths']
    
    if 'ignored_paths' in data:
        # Validate that each path is a valid subpath
        try:
            config_doc = db.collection(CONFIG_COLLECTION).document(config_id).get()
            if not config_doc.exists:
                return jsonify({"error": "Config not found"}), 404
            
            root_path_str = config_doc.to_dict().get('local_path')
            if not root_path_str:
                return jsonify({"error": "Root path not set for this config"}), 400
            
            root_path = Path(root_path_str)
            for path_to_ignore in data['ignored_paths']:
                full_path_to_ignore = root_path / Path(path_to_ignore)
                # This check ensures it's a valid subdirectory and prevents ".." traversal attacks
                if not full_path_to_ignore.is_relative_to(root_path):
                    return jsonify({"error": f"Invalid path: '{path_to_ignore}' is not a subpath of the root directory."}), 400
        except Exception as path_error:
             return jsonify({"error": f"Path validation error: {path_error}"}), 400

    updates = {key: data[key] for key in data if key in allowed_updates}

    if not updates:
        return jsonify({"error": "No valid fields to update provided."}), 400

    try:
        db.collection(CONFIG_COLLECTION).document(config_id).update(updates)
        return jsonify({"success": True, "message": "Sync configuration updated."})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# [DELETE] Unregister a folder
@sync_service_bp.route('/sync/config/<config_id>', methods=['DELETE'])
def delete_config(config_id):
    try:
        db.collection(CONFIG_COLLECTION).document(config_id).delete()
        # Note: This does NOT delete the converted files, just the sync config.
        # You could add logic here to delete the files if desired.
        return jsonify({"success": True, "message": "Sync configuration deleted."})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@sync_service_bp.route('/sync/run/<config_id>', methods=['POST'])
def run_sync_route(config_id):
    try:
        # 1. Fetch the configuration for this sync job from Firestore.
        config_doc = db.collection(CONFIG_COLLECTION).document(config_id).get()
        if not config_doc.exists:
            return jsonify({"error": "Sync configuration not found"}), 404
        
        config_data = config_doc.to_dict()
        if not config_data.get('is_active'):
            return jsonify({"message": "Sync is disabled for this configuration."}), 200

        # 2. Call the main logic function with the fetched data.
        result = perform_sync(config_id, config_data)
        
        # 3. Return the results from the sync operation.
        return jsonify({"success": True, **result})

    except Exception as e:
        # This will catch any crashes from perform_sync and log them.
        import traceback
        print("="*50)
        print(f"‼️  CRITICAL ERROR in run_sync_route for config_id: {config_id} ‼️")
        print(traceback.format_exc())
        print("="*50)
        return jsonify({"error": str(e), "traceback": traceback.format_exc()}), 500

# def _generate_special_files(db, project_id, source_path, extensions, files_in_db):
#     # 1. tree.txt
#     _generate_tree_txt(db, project_id, source_path, extensions)

#     # 2. _full_context.txt – **only from the in-memory manifest**
#     _generate_full_context_txt(db, project_id)

# def _generate_tree_txt(db, project_id, source_path, extensions):
#     tree_content = f"{source_path.name}/\n" + generate_tree_text_from_paths(source_path, allowed_extensions=extensions)
#     db.collection('projects').document(project_id) \
#       .collection('converted_files').document('project_tree_txt').set({
#           'original_path': 'tree.txt',
#           'content': tree_content,
#           'hash': hashlib.sha256(tree_content.encode('utf-8')).hexdigest(),
#           'timestamp': firestore.SERVER_TIMESTAMP,
#       })

# def _generate_full_context_txt(db, project_id):
#     full = []
#     for rel_path, info in files_in_db.items():
#         doc_id = info.get('doc_id')
#         if not doc_id:
#             continue
#         doc = db.collection('projects').document(project_id) \
#                 .collection('converted_files').document(doc_id).get()
#         if doc.exists:
#             full.append(f"--- FILE: {rel_path} ---\n\n{doc.to_dict().get('content','')}\n\n")

#     full_txt = "".join(full)
#     db.collection('projects').document(project_id) \
#       .collection('converted_files').document('project_full_context_txt').set({
#           'original_path': '_full_context.txt',
#           'content': full_txt,
#           'hash': hashlib.sha256(full_txt.encode('utf-8')).hexdigest(),
#           'timestamp': firestore.SERVER_TIMESTAMP,
#       })
