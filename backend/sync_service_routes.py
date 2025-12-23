from pathlib import Path
from flask import Blueprint, request, jsonify
from firebase_admin import firestore
import hashlib 
import shutil 
from services import db

from utils import (
    get_file_hash, 
    convert_and_upload_to_firestore, 
    delete_collection, 
    generate_tree_text_from_paths
)

# --- 从配置文件导入 ---
from config import (
    CODE_PROJECTS_COLLECTION,
    CODE_FILES_SUBCOLLECTION,
    CODE_GRAPH_COLLECTION,
    VECTOR_STORE_ROOT
)

from code_graph_engine import FaissVectorStore
from code_graph_utils import extract_functions_and_classes, generate_embeddings, calculate_static_weights

# --- Rabbit MQ ---
from tasks import background_perform_sync 
from sync_logic import force_reindex_project 

sync_service_bp = Blueprint('sync_service_bp', __name__)

@sync_service_bp.route('/sync/register/<project_id>', methods=['POST'])
def register_folder(project_id):
    data = request.json
    local_path = data.get('local_path')
    allowed_extensions = data.get('extensions', [])
    ignored_paths = data.get('ignored_paths', [])
    # --- NEW: Accept new fields ---
    included_paths = data.get('included_paths', [])
    sync_mode = data.get('sync_mode', 'ignore')

    if not local_path:
        return jsonify({"error": "Missing 'local_path'"}), 400
    
    # Check if path exists locally
    if not Path(local_path).is_dir():
        return jsonify({"error": f"Path is not a valid directory: {local_path}"}), 400

    try:
        project_ref = db.collection(CODE_PROJECTS_COLLECTION).document(project_id)
        
        config_data = {
            "name": project_id, # Ensure it has a name if creating new
            "local_path": local_path,
            "allowed_extensions": allowed_extensions,
            "ignored_paths": ignored_paths,
            "included_paths": included_paths, # Add to document
            "sync_mode": sync_mode,         # Add to document
            "is_active": True,
            "status": "idle",
            "last_synced": None,
            "timestamp": firestore.SERVER_TIMESTAMP
        }
        
        project_ref.set(config_data, merge=True)

        return jsonify({"success": True, "project_id": project_id}), 200
    except Exception as e:
        import traceback
        print(traceback.format_exc())
        return jsonify({"error": str(e)}), 500

@sync_service_bp.route('/sync/projects', methods=['GET'])
def list_sync_projects():
    try:
        projects = []
        docs = db.collection(CODE_PROJECTS_COLLECTION).where('local_path', '!=', None).stream()
        projects = [{"id": d.id, **d.to_dict()} for d in docs]
        return jsonify(projects)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@sync_service_bp.route('/sync/project/<project_id>', methods=['PUT'])
def update_sync_project(project_id):
    data = request.json
    # --- NEW: Add new fields to allowed updates ---
    allowed_updates = [
        'allowed_extensions', 'is_active', 'ignored_paths',
        'included_paths', 'sync_mode'
    ]
    updates = {key: data[key] for key in data if key in allowed_updates}
    try:
        db.collection(CODE_PROJECTS_COLLECTION).document(project_id).update(updates)
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@sync_service_bp.route('/sync/project/<project_id>', methods=['DELETE'])
def delete_sync_project(project_id):
    try:
        project_ref = db.collection(CODE_PROJECTS_COLLECTION).document(project_id)
        # Unregister by setting local_path to None and deactivating
        project_ref.update({
            "local_path": None, 
            "is_active": False, 
            "status": "unregistered",
            "included_paths": firestore.DELETE_FIELD,
            "ignored_paths": firestore.DELETE_FIELD,
            "allowed_extensions": firestore.DELETE_FIELD
        })
        store_path = VECTOR_STORE_ROOT / project_id
        if store_path.exists():
            shutil.rmtree(store_path)
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@sync_service_bp.route('/sync/run/<project_id>', methods=['POST'])
def run_sync_route(project_id):
    """
    Triggers background sync via RabbitMQ.
    """
    try:
        project_doc = db.collection(CODE_PROJECTS_COLLECTION).document(project_id).get()
        if not project_doc.exists:
            return jsonify({"error": "Code project not found"}), 404
        
        config_data = project_doc.to_dict()
        if not config_data.get('is_active'):
            return jsonify({"message": "Sync is disabled."}), 200

        task = background_perform_sync.delay(project_id)

        return jsonify({
            "success": True,
            "message": "Background sync started.",
            "task_id": task.id
        }), 202

    except Exception as e:
        import traceback
        print(traceback.format_exc())
        return jsonify({"error": str(e)}), 500

@sync_service_bp.route('/sync/file/<project_id>', methods=['POST'])
def sync_file_route(project_id):
    try:
        data = request.json
        rel_path = data.get('file_path')
        if not rel_path:
            return jsonify({"error": "No file path"}), 400
            
        from sync_logic import sync_single_file
        node_count = sync_single_file(db, project_id, rel_path)
        
        return jsonify({"success": True, "nodes": node_count})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

def force_reindex_project(project_id):
    print(f"\n🔄 FORCE RE-INDEX initiated for project: {project_id}")
    project_ref = db.collection(CODE_PROJECTS_COLLECTION).document(project_id)
    
    # A. Fetch all existing code files from Firestore
    print("  1. Fetching code files from database...")
    docs = project_ref.collection(CODE_FILES_SUBCOLLECTION).stream()
    
    all_project_nodes = []
    file_count = 0
    
    for doc in docs:
        data = doc.to_dict()
        path = data.get('original_path')
        content = data.get('content')
        
        # Filter garbage
        if not path or not content: continue
        if path in ['tree.txt', '_full_context.txt']: continue
        if path.endswith(('.lock', '.png', '.jpg', '.ico')): continue
        
        # B. Run the NEW Extractor
        try:
            nodes = extract_functions_and_classes(content, path)
            all_project_nodes.extend(nodes)
            file_count += 1
        except Exception as e:
            print(f"  ⚠️ Failed to parse {path}: {e}")

    print(f"  ✅ Parsed {file_count} files. Found {len(all_project_nodes)} nodes.")
    
    if not all_project_nodes:
        return {"success": False, "message": "No nodes found to index."}

    # C. Generate Embeddings
    print("  3. Generating embeddings...")
    BATCH_SIZE = 50
    for i in range(0, len(all_project_nodes), BATCH_SIZE):
        batch = all_project_nodes[i:i+BATCH_SIZE]
        generate_embeddings(batch)
        print(f"     - Embedded batch {i//BATCH_SIZE + 1}")

    # D. Calculate Weights
    print("  4. Calculating Structural Weights...")
    calculate_static_weights(all_project_nodes)

    # E. Delete OLD Vector Store
    store_path = VECTOR_STORE_ROOT / project_id
    if store_path.exists():
        shutil.rmtree(store_path)
        print(f"  🗑️ Deleted old vector store at {store_path}")

    # F. Create NEW FAISS Index
    print("  5. Building new FAISS index...")
    vector_store = FaissVectorStore()
    vector_store.add_nodes(all_project_nodes)
    vector_store.save(store_path)
    
    # G. Save Light Metadata to Firestore (Optional, for debugging)
    graph_coll_ref = project_ref.collection(CODE_GRAPH_COLLECTION)
    delete_collection(graph_coll_ref, batch_size=50)
    
    print(f"  ✅ Re-indexing Complete. {len(all_project_nodes)} nodes indexed.")
    return {"success": True, "node_count": len(all_project_nodes)}

@sync_service_bp.route('/sync/reindex/<project_id>', methods=['POST'])
def reindex_route(project_id):
    """
    Manual endpoint - runs SYNCHRONOUSLY (Blocking) using the logic directly.
    Useful for debugging without waiting for the queue.
    """
    try:
        # We can call the logic function directly here for manual triggers
        result = force_reindex_project(db, project_id)
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


