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
    generate_tree_text,
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
    
    # --- WRAP THE ENTIRE FUNCTION IN A try...except BLOCK ---
    try:
        print("\n" + "="*50)
        print(f"SYNC-SERVICE: Starting sync for config_id: {config_id}")
        
        source_path = Path(source_dir)
        if not source_path.is_dir():
            raise FileNotFoundError(f"Source directory not found: {source_dir}")

        logs = []
        updated_count = 0
        deleted_count = 0
        
        config_ref = db.collection(CONFIG_COLLECTION).document(config_id)
        config_ref.update({'status': 'syncing'})
        print(f"SYNC-SERVICE: Status updated to 'syncing' for {config_id}")

        # 1. READ ONCE: Get the manifest
        print("SYNC-SERVICE: Step 1/5 - Reading manifest from Firestore...")
        manifest_ref = db.collection('projects').document(project_id).collection('converted_files').document('_manifest')
        manifest_doc = manifest_ref.get()
        files_in_db = manifest_doc.to_dict().get('files', {}) if manifest_doc.exists else {}
        print(f"SYNC-SERVICE: Found {len(files_in_db)} files in existing manifest.")

        # 2. Filter local files
        print("SYNC-SERVICE: Step 2/5 - Scanning and filtering local files...")
        all_local_files = [f for f in source_path.rglob("*") if f.is_file() and '.git' not in f.parts]
        dot_extensions = [f".{ext.lstrip('.').lower()}" for ext in extensions] if extensions else None
        files_to_process = [f for f in all_local_files if not dot_extensions or f.suffix.lower() in dot_extensions]
        print(f"SYNC-SERVICE: Found {len(files_to_process)} local files to process.")
        
        # 3. Process local files for updates/creations
        print("SYNC-SERVICE: Step 3/5 - Comparing hashes and processing updates...")
        processed_paths = set()
        manifest_has_changed = False

        for file_path in files_to_process:
            rel_path_str = str(file_path.relative_to(source_path)).replace('\\', '/')
            processed_paths.add(rel_path_str)

            current_hash = get_file_hash(file_path)
            db_hash = files_in_db.get(rel_path_str, {}).get('hash')

            if current_hash != db_hash:
                logs.append(f"UPDATE: {rel_path_str}")
                uploaded_hash = convert_and_upload_to_firestore(db, project_id, file_path, source_path)
                if uploaded_hash:
                    updated_count += 1
                    doc_id = get_converted_file_ref(db, project_id, rel_path_str).id
                    files_in_db[rel_path_str] = {'hash': uploaded_hash, 'doc_id': doc_id}
                    manifest_has_changed = True
        print(f"SYNC-SERVICE: Processed {len(files_to_process)} local files. {updated_count} updates found.")
        
        # 4. Process deletions
        print("SYNC-SERVICE: Step 4/5 - Checking for deleted files...")
        db_paths_to_consider = {path for path in files_in_db if not dot_extensions or Path(path).suffix.lower() in dot_extensions}
        paths_to_delete = db_paths_to_consider - processed_paths
        
        for path_to_delete in paths_to_delete:
            logs.append(f"DELETE: {path_to_delete}")
            doc_id_to_delete = files_in_db[path_to_delete].get('doc_id')
            if doc_id_to_delete:
                db.collection('projects').document(project_id).collection('converted_files').document(doc_id_to_delete).delete()
            
            del files_in_db[path_to_delete]
            deleted_count += 1
            manifest_has_changed = True
        print(f"SYNC-SERVICE: Found {deleted_count} files to delete.")

        # 5. WRITE ONCE: Update the manifest
        print("SYNC-SERVICE: Step 5/5 - Updating manifest...")
        if manifest_has_changed:
            manifest_payload = {'files': files_in_db, 'last_updated': firestore.SERVER_TIMESTAMP}
            if manifest_doc.exists:
                manifest_ref.update(manifest_payload)
            else:
                manifest_ref.set(manifest_payload)
            print("SYNC-SERVICE: ✅ Manifest updated successfully.")
        else:
            print("SYNC-SERVICE: No changes to manifest needed.")

        # (Logic for generating tree.txt is omitted for now to isolate the bug, you can add it back later)

        print(f"SYNC-SERVICE: 🏁 Sync complete: {updated_count} updated, {deleted_count} deleted")
        config_ref.update({'status': 'idle', 'last_synced': firestore.SERVER_TIMESTAMP})

        try:
            print("SYNC-SERVICE: Step 6/6 - Generating and saving tree.txt...")
            tree_content = f"{source_path.name}/\n"
            tree_content += generate_tree_text(source_path, allowed_extensions=extensions)
            
            # Use a predictable ID for the tree document
            tree_doc_ref = db.collection('projects').document(project_id).collection('converted_files').document('project_tree_txt')
            
            tree_doc_ref.set({
                'original_path': 'tree.txt',
                'content': tree_content,
                'hash': hashlib.sha256(tree_content.encode('utf-8')).hexdigest(),
                'timestamp': firestore.SERVER_TIMESTAMP,
            })
            print("SYNC-SERVICE: ✅ Saved tree.txt to Firestore.")
        except Exception as tree_error:
            print(f"SYNC-SERVICE: ❌ Failed to generate tree.txt: {tree_error}")
            logs.append(f"ERROR: Failed to generate file tree: {tree_error}")
        
        return {"logs": logs, "updated": updated_count, "deleted": deleted_count}

    except Exception as e:
        # --- THIS WILL CATCH THE ERROR AND PRINT A DETAILED TRACEBACK ---
        print("\n" + "!"*50)
        print("‼️  CRITICAL ERROR INSIDE perform_sync  ‼️")
        print(f"Error Type: {type(e).__name__}")
        print(f"Error Details: {e}")
        print("Full Traceback:")
        print(traceback.format_exc())
        print("!"*50 + "\n")
        
        # Try to update the config status to 'error'
        try:
            config_ref.update({'status': 'error'})
        except Exception as status_update_error:
            print(f"  - Also failed to update config status to 'error': {status_update_error}")
        
        # Re-raise the exception so the route handler still returns a 500
        raise

# --- ROUTES FOR CRUD ON SYNC CONFIGURATIONS ---

# [CREATE] Register a new folder to sync
@sync_service_bp.route('/sync/register', methods=['POST'])
def register_folder():
    data = request.json
    project_id = data.get('project_id')
    local_path = data.get('local_path')
    allowed_extensions = data.get('extensions', [])

    if not all([project_id, local_path]):
        return jsonify({"error": "Missing 'project_id' or 'local_path'"}), 400
    if not Path(local_path).is_dir():
        return jsonify({"error": f"Path is not a valid directory: {local_path}"}), 400

    try:
        config_data = {
            "project_id": project_id,
            "local_path": local_path,
            "allowed_extensions": allowed_extensions,
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
    # We only allow updating these specific fields for safety
    allowed_updates = ['allowed_extensions', 'is_active']
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
        config_doc = db.collection(CONFIG_COLLECTION).document(config_id).get()
        if not config_doc.exists:
            return jsonify({"error": "Configuration not found"}), 404
        
        config_data = config_doc.to_dict()
        if not config_data.get('is_active'):
            return jsonify({"message": "Sync is disabled for this configuration."}), 200

        result = perform_sync(config_id, config_data)
        return jsonify({"success": True, **result})

    except Exception as e:
        import traceback
        return jsonify({"error": str(e), "traceback": traceback.format_exc()}), 500