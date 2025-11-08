# backend/code_converter_routes.py
import json
import hashlib
from pathlib import Path
from flask import Blueprint, request, jsonify
from firebase_admin import firestore # <-- Add this import
# Import the specific utils you need for this blueprint
from utils import get_file_hash, get_converted_file_ref, convert_and_upload_to_firestore

# --- BLUEPRINT SETUP ---
code_converter_bp = Blueprint('code_converter_bp', __name__)
db = None

def set_dependencies(db_instance):
    """Injects the Firestore db instance from the main app."""
    global db
    db = db_instance

# --- ROUTES (CRUD for Firestore-based file conversion) ---

# [CREATE / UPDATE / DELETE] Sync a local folder with Firestore
@code_converter_bp.route('/code-converter/sync/<project_id>', methods=['POST'])
def sync_project_files(project_id):
    data = request.json
    source_dir = data.get('path')
    extensions = data.get('extensions', [])

    if not source_dir:
        return jsonify({"error": "Missing 'path' in request body"}), 400

    source_path = Path(source_dir)
    if not source_path.is_dir():
        return jsonify({"error": f"Source directory not found: {source_dir}"}), 404

    try:
        logs = []
        updated_count = 0
        deleted_count = 0
        
        # 1. Get all current file hashes from Firestore for this project
        files_in_db = {}
        docs = db.collection('projects').document(project_id).collection('converted_files').stream()
        for doc in docs:
            doc_data = doc.to_dict()
            if 'original_path' in doc_data and 'hash' in doc_data:
                 files_in_db[doc_data['original_path']] = {'hash': doc_data['hash'], 'id': doc.id}

        # 2. Filter local files based on extensions
        all_local_files = [f for f in source_path.rglob("*") if f.is_file() and '.git' not in f.parts]
        files_to_process = []
        if not extensions:
            files_to_process = all_local_files
        else:
            dot_extensions = [f".{ext.lstrip('.').lower()}" for ext in extensions]
            files_to_process = [f for f in all_local_files if f.suffix.lower() in dot_extensions]
        
        logs.append(f"Found {len(files_to_process)} files to process based on filter: {extensions}")

        # 3. Walk through local files, compare hashes, and upload if changed
        processed_paths = set()
        for file_path in files_to_process:
            rel_path_str = str(file_path.relative_to(source_path)).replace('\\', '/')
            processed_paths.add(rel_path_str)

            current_hash = get_file_hash(file_path)
            db_hash = files_in_db.get(rel_path_str, {}).get('hash')

            if current_hash != db_hash:
                logs.append(f"UPDATE: {rel_path_str}")
                convert_and_upload_to_firestore(db, project_id, file_path, source_path)
                updated_count += 1
        
        # 4. Find and delete files from Firestore that are no longer present locally
        db_paths_to_consider = {path for path in files_in_db if not extensions or Path(path).suffix.lower() in dot_extensions}
        paths_to_delete = db_paths_to_consider - processed_paths
        
        for path_to_delete in paths_to_delete:
            logs.append(f"DELETE: {path_to_delete}")
            doc_ref = get_converted_file_ref(db, project_id, path_to_delete)
            doc_ref.delete()
            deleted_count += 1
        
        return jsonify({
            "success": True, 
            "logs": logs, 
            "updated": updated_count,
            "deleted": deleted_count
        })

    except Exception as e:
        import traceback
        return jsonify({"error": str(e), "traceback": traceback.format_exc()}), 500


# [READ] Get the dynamic file structure
@code_converter_bp.route('/code-converter/structure/<project_id>', methods=['GET'])
def get_dynamic_project_structure(project_id):
    try:
        print(f"🌳 Building dynamic file tree for project: {project_id}")
        docs = db.collection('projects').document(project_id).collection('converted_files').stream()
        
        tree = {}
        file_count = 0
        for doc in docs:
            file_count += 1
            data = doc.to_dict()
            original_path = data.get("original_path")
            doc_id = doc.id

            if not original_path:
                continue

            parts = Path(original_path.replace('\\', '/')).parts
            d = tree
            for part in parts[:-1]:
                d = d.setdefault(part, {})
            d[parts[-1]] = doc_id
        
        print(f"  ✅ Built tree with {file_count} files.")
        return jsonify(tree)

    except Exception as e:
        import traceback
        return jsonify({"error": str(e), "traceback": traceback.format_exc()}), 500


# [READ] Get single file content from Firestore
@code_converter_bp.route('/code-converter/file/<project_id>/<doc_id>', methods=['GET'])
def get_converted_file(project_id, doc_id):
    try:
        doc_ref = db.collection('projects').document(project_id).collection('converted_files').document(doc_id)
        doc = doc_ref.get()
        if not doc.exists:
            return jsonify({"error": "File not found"}), 404
        return jsonify(doc.to_dict())
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# [UPDATE] Manually update a single file in Firestore
@code_converter_bp.route('/code-converter/file/<project_id>/<doc_id>', methods=['PUT'])
def update_converted_file(project_id, doc_id):
    data = request.json
    new_content = data.get('content')
    if new_content is None:
        return jsonify({"error": "Missing 'content' in request body"}), 400
    
    try:
        doc_ref = db.collection('projects').document(project_id).collection('converted_files').document(doc_id)
        new_hash = hashlib.sha256(new_content.encode('utf-8')).hexdigest()
        
        doc_ref.update({
            'content': new_content,
            'hash': new_hash,
            'timestamp': firestore.SERVER_TIMESTAMP,
        })
        return jsonify({"success": True, "message": "File updated successfully."})
    except Exception as e:
        return jsonify({"error": str(e)}), 500