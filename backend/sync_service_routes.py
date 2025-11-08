# backend/sync_service_routes.py
import json
from pathlib import Path
from flask import Blueprint, request, jsonify
from firebase_admin import firestore
from utils import get_file_hash, convert_and_upload_to_firestore, get_converted_file_ref, delete_collection

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
    
    source_path = Path(source_dir)
    if not source_path.is_dir():
        raise FileNotFoundError(f"Source directory not found: {source_dir}")

    logs = []
    updated_count = 0
    deleted_count = 0
    
    config_ref = db.collection(CONFIG_COLLECTION).document(config_id)
    config_ref.update({'status': 'syncing'})

    # 1. Get current file hashes from Firestore for this project
    files_in_db = {}
    converted_files_ref = db.collection('projects').document(project_id).collection('converted_files')
    for doc in converted_files_ref.stream():
        doc_data = doc.to_dict()
        if 'original_path' in doc_data and 'hash' in doc_data:
            files_in_db[doc_data['original_path']] = {'hash': doc_data['hash'], 'id': doc.id}
    
    all_local_files = [f for f in source_path.rglob("*") if f.is_file() and '.git' not in f.parts]
    
    # --- THIS IS THE CORRECTED FILTERING LOGIC ---
    files_to_process = []
    if not extensions:
        # If no extensions are provided, process all files.
        files_to_process = all_local_files
    else:
        # If extensions are provided, filter the list.
        dot_extensions = [f".{ext.lstrip('.').lower()}" for ext in extensions]
        files_to_process = [f for f in all_local_files if f.suffix.lower() in dot_extensions]
    # --- END OF CORRECTION ---

    processed_paths = set()
    print("\n" + "="*40)
    print(f"🔍 Starting sync for: {source_dir}")
    print(f"  (Found {len(files_to_process)} files to process based on filter: {extensions})")
    print("="*40)

    for file_path in files_to_process: # <-- Loop over the correctly filtered list
        rel_path_str = str(file_path.relative_to(source_path)).replace('\\', '/')
        processed_paths.add(rel_path_str)
        
        print(f"  -> Checking file: {rel_path_str}")

        current_hash = get_file_hash(file_path)
        db_hash = files_in_db.get(rel_path_str, {}).get('hash')

        if current_hash != db_hash:
            logs.append(f"UPDATE: {rel_path_str}")
            convert_and_upload_to_firestore(db, project_id, file_path, source_path)
            updated_count += 1
    
    db_paths_to_consider = set()
    if not extensions:
        db_paths_to_consider = set(files_in_db.keys())
    else:
        dot_extensions = [f".{ext.lstrip('.').lower()}" for ext in extensions]
        db_paths_to_consider = {path for path in files_in_db if Path(path).suffix.lower() in dot_extensions}

    paths_to_delete = db_paths_to_consider - processed_paths
    for path_to_delete in paths_to_delete:
        logs.append(f"DELETE: {path_to_delete}")
        doc_ref = get_converted_file_ref(db, project_id, path_to_delete)
        doc_ref.delete()
        deleted_count += 1
    
    print("="*40)
    print(f"🏁 Sync complete.")
    print("="*40)
    
    config_ref.update({'status': 'idle', 'last_synced': firestore.SERVER_TIMESTAMP})
    
    return {"logs": logs, "updated": updated_count, "deleted": deleted_count}

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


# --- ROUTE TO TRIGGER THE SYNC ---

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