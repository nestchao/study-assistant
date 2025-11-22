from pathlib import Path
from flask import Blueprint, request, jsonify
from firebase_admin import firestore
import hashlib 
import shutil 

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

sync_service_bp = Blueprint('sync_service_bp', __name__)
db = None

def set_dependencies(db_instance):
    global db
    db = db_instance

def perform_sync(project_id: str, config_data: dict):
    source_dir = config_data.get('local_path')
    extensions = config_data.get('allowed_extensions', [])
    ignored_paths = config_data.get('ignored_paths', [])

    project_ref = db.collection(CODE_PROJECTS_COLLECTION).document(project_id)

    try:
        print("\n" + "="*60)
        print(f"SYNC-SERVICE: Starting file scan for: {project_id}")

        source_path = Path(source_dir)
        if not source_path.is_dir():
            raise FileNotFoundError(f"Source directory not found: {source_dir}")

        logs = []
        updated_count = deleted_count = 0

        project_ref.update({'status': 'syncing'})

        # Check Manifest
        manifest_ref = project_ref.collection(CODE_FILES_SUBCOLLECTION).document('_manifest')
        manifest_doc = manifest_ref.get()
        files_in_db = manifest_doc.to_dict().get('files', {}) if manifest_doc.exists else {}

        # Scan Local Files
        normalized_ignored_paths = [Path(p.replace('\\', '/')) for p in ignored_paths]
        all_local_files = [f for f in source_path.rglob("*") if f.is_file() and '.git' not in f.parts and not any(f.relative_to(source_path).is_relative_to(ignored) for ignored in normalized_ignored_paths)]
        dot_ext = [f".{e.lstrip('.').lower()}" for e in extensions] if extensions else None
        files_to_process = [f for f in all_local_files if not dot_ext or f.suffix.lower() in dot_ext]
        
        # Compare Hashes
        processed_paths = set()
        for file_path in files_to_process:
            rel_path = str(file_path.relative_to(source_path)).replace('\\', '/')
            processed_paths.add(rel_path)
            local_hash = get_file_hash(file_path)
            db_hash = files_in_db.get(rel_path, {}).get('hash')
            
            if local_hash != db_hash:
                logs.append(f"UPDATE: {rel_path}")
                result = convert_and_upload_to_firestore(db, project_id, file_path, source_path, CODE_FILES_SUBCOLLECTION, CODE_PROJECTS_COLLECTION)
                if result:
                    uploaded_hash, doc_id = result
                    files_in_db[rel_path] = {'hash': uploaded_hash, 'doc_id': doc_id}
                    updated_count += 1

        # Handle Deletions
        db_paths = {p for p in files_in_db if not dot_ext or Path(p).suffix.lower() in dot_ext}
        to_delete = db_paths - processed_paths
        for p in to_delete:
            logs.append(f"DELETE: {p}")
            doc_id = files_in_db[p].get('doc_id')
            if doc_id:
                project_ref.collection(CODE_FILES_SUBCOLLECTION).document(doc_id).delete()
            del files_in_db[p]
            deleted_count += 1

        # Update Manifest & Special Files
        manifest_ref.set({'files': files_in_db})
        final_file_paths = sorted(list(files_in_db.keys()))
        tree_content = generate_tree_text_from_paths(source_path.name, final_file_paths)
        project_ref.collection(CODE_FILES_SUBCOLLECTION).document('project_tree_txt').set({
            'original_path': 'tree.txt', 'content': tree_content,
            'timestamp': firestore.SERVER_TIMESTAMP
        })
        
        # Create Context Text
        try:
            chunks = []
            for rel_path in final_file_paths:
                doc_id = files_in_db[rel_path].get('doc_id')
                if doc_id:
                    doc = project_ref.collection(CODE_FILES_SUBCOLLECTION).document(doc_id).get()
                    if doc.exists:
                        chunks.append(f"--- FILE: {rel_path} ---\n{doc.to_dict().get('content','')}\n")
            
            full_txt = "\n".join(chunks)
            project_ref.collection(CODE_FILES_SUBCOLLECTION).document('project_full_context_txt').set({
                'original_path': '_full_context.txt', 'content': full_txt,
                'timestamp': firestore.SERVER_TIMESTAMP,
            })
        except Exception as e:
            print("Error: ?", e)
            print("  ⏩ Skipped _full_context.txt generation to save space.")

        project_ref.update({'status': 'idle', 'last_synced': firestore.SERVER_TIMESTAMP})
        return {"logs": logs, "updated": updated_count, "deleted": deleted_count}
        
    except Exception as e:
        try: project_ref.update({'status': 'error'})
        except: pass
        raise

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
        project_ref.update(config_data)
        return jsonify({"success": True, "project_id": project_id}), 200
    except Exception as e:
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
    allowed_updates = ['allowed_extensions', 'is_active', 'ignored_paths']
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
        project_ref.update({"local_path": None, "is_active": False, "status": "unregistered"})
        store_path = VECTOR_STORE_ROOT / project_id
        if store_path.exists():
            shutil.rmtree(store_path)
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@sync_service_bp.route('/sync/run/<project_id>', methods=['POST'])
def run_sync_route(project_id):
    """
    Standard Sync triggered by Frontend button.
    It now does BOTH:
    1. Syncs files (checks for changes)
    2. Forces a Graph Re-index (to ensure 1900+ nodes logic is applied)
    """
    try:
        project_doc = db.collection(CODE_PROJECTS_COLLECTION).document(project_id).get()
        if not project_doc.exists:
            return jsonify({"error": "Code project not found"}), 404
        
        config_data = project_doc.to_dict()
        if not config_data.get('is_active'):
            return jsonify({"message": "Sync is disabled."}), 200

        # 1. Sync Files
        file_result = perform_sync(project_id, config_data)
        
        # 2. Force Graph Re-index (Unconditional, to fix your graph structure)
        # In production, you might only do this if file_result['updated'] > 0
        # But for now, we force it to ensure you get your 1900 nodes.
        graph_result = force_reindex_project(project_id)

        return jsonify({
            "success": True,
            "file_sync": file_result,
            "graph_sync": graph_result
        })

    except Exception as e:
        import traceback
        print(traceback.format_exc())
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
    """Manual endpoint if you just want to rebuild the graph without scanning files."""
    try:
        result = force_reindex_project(project_id)
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
