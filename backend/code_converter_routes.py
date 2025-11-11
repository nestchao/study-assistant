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
# backend/code_converter_routes.py

@code_converter_bp.route('/code-converter/structure/<project_id>', methods=['GET'])
def get_dynamic_project_structure(project_id):
    try:
        print(f"🌳 Building dynamic file tree for project: {project_id}")
        
        # --- PART 1: Build the tree from the _manifest document ---
        manifest_ref = db.collection('projects').document(project_id).collection('converted_files').document('_manifest')
        manifest_doc = manifest_ref.get()

        tree = {}
        file_count = 0 

        if manifest_doc.exists:
            files_map = manifest_doc.to_dict().get('files', {})
            file_count = len(files_map)
            print(f"  - Found {file_count} entries in manifest. Building tree...")
            
            for path_str, data in files_map.items():
                doc_id = data.get('doc_id')
                if not doc_id: continue
                
                parts = Path(path_str).parts
                d = tree
                for part in parts[:-1]:
                    d = d.setdefault(part, {})
                d[parts[-1]] = doc_id
        else:
            print("  - WARNING: Manifest document does not exist for this project yet.")

        # --- PART 2: Manually check for and add special files ---

        converted_files_coll = db.collection('projects').document(project_id).collection('converted_files')

        # Check for tree.txt
        print("  - Checking for special 'tree.txt' document...")
        tree_doc_ref = converted_files_coll.document('project_tree_txt')
        if tree_doc_ref.get().exists:
            tree['tree.txt'] = 'project_tree_txt'
            file_count += 1
            print("  - Found and added tree.txt to the structure.")

        # --- THIS IS THE NEW ADDITION ---
        # Check for _full_context.txt
        print("  - Checking for special '_full_context.txt' document...")
        context_doc_ref = converted_files_coll.document('project_full_context_txt')
        if context_doc_ref.get().exists:
            tree['_full_context.txt'] = 'project_full_context_txt'
            file_count += 1
            print("  - Found and added _full_context.txt to the structure.")
        # --- END OF ADDITION ---
        
        print(f"  ✅ Built final tree with {file_count} total items.")
        return jsonify(tree)

    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        print(f"  ❌ CRITICAL ERROR building dynamic tree: {e}")
        print(error_details)
        return jsonify({"error": str(e), "traceback": error_details}), 500

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