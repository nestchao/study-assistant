# backend/code_converter_routes.py
import json
import hashlib
from pathlib import Path
from flask import Blueprint, request, jsonify
from firebase_admin import firestore # <-- Add this import
# Import the specific utils you need for this blueprint
from utils import get_file_hash, get_converted_file_ref, convert_and_upload_to_firestore, DOT_REPLACEMENT

# --- BLUEPRINT SETUP ---
code_converter_bp = Blueprint('code_converter_bp', __name__)
db = None

def set_dependencies(db_instance):
    """Injects the Firestore db instance from the main app."""
    global db
    db = db_instance

# --- ROUTES (CRUD for Firestore-based file conversion) ---

# [READ] Get the dynamic file structure
@code_converter_bp.route('/code-converter/structure/<project_id>', methods=['GET'])
def get_dynamic_project_structure(project_id):
    try:
        print(f"🌳 Fetching file tree from manifest for project: {project_id}")
        # Use a consistent manifest document name
        manifest_ref = db.collection('projects').document(project_id).collection('converted_files').document('_manifest')
        manifest_doc = manifest_ref.get()

        if not manifest_doc.exists:
            print("  ⚠️ Manifest does not exist yet.")
            return jsonify({})
        
        files_map = manifest_doc.to_dict().get('files', {})
        
        tree = {}
        file_count = 0 

        for path_with_replacement, data in files_map.items():
            original_path = path_with_replacement.replace(DOT_REPLACEMENT, ".")
            doc_id = data.get('doc_id')
            
            parts = Path(original_path).parts
            d = tree
            for part in parts[:-1]:
                d = d.setdefault(part, {})
            d[parts[-1]] = doc_id

        print("  Checking for tree.txt document...")
        tree_doc_ref = db.collection('projects').document(project_id).collection('converted_files').document('project_tree_txt')
        if tree_doc_ref.get().exists:
            # If it exists, add it to the root of our tree structure.
            tree['tree.txt'] = 'project_tree_txt'
            file_count += 1
            print("  ✅ Added tree.txt to the file structure.")
        
        print(f"  ✅ Built tree with {len(files_map)} files.")
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