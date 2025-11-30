# backend/sync_logic.py
import shutil
import hashlib
from pathlib import Path
from firebase_admin import firestore
from utils import (
    get_file_hash, 
    convert_and_upload_to_firestore, 
    delete_collection, 
    generate_tree_text_from_paths
)
from config import (
    CODE_PROJECTS_COLLECTION,
    CODE_FILES_SUBCOLLECTION,
    CODE_GRAPH_COLLECTION,
    VECTOR_STORE_ROOT
)
from code_graph_engine import FaissVectorStore
from code_graph_utils import extract_functions_and_classes, generate_embeddings, calculate_static_weights, enrich_nodes_with_critic
from services import HyDE_generation_model

# --- MOVED LOGIC FUNCTIONS ---
# Note: We now pass 'db' as an argument so this file doesn't need its own connection

def perform_sync(db, project_id: str, config_data: dict):
    source_dir = config_data.get('local_path')
    extensions = config_data.get('allowed_extensions', [])
    ignored_paths = config_data.get('ignored_paths', [])

    project_ref = db.collection(CODE_PROJECTS_COLLECTION).document(project_id)

    print("\n" + "="*60)
    print(f"SYNC-LOGIC: Starting file scan for: {project_id}")

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
            # Ensure utils functions accept 'db' or handle it correctly
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

    project_ref.update({'status': 'idle', 'last_synced': firestore.SERVER_TIMESTAMP})
    return {"logs": logs, "updated": updated_count, "deleted": deleted_count}

def force_reindex_project(db, project_id):
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
        
        if not path or not content: continue
        if path in ['tree.txt', '_full_context.txt']: continue
        if path.endswith(('.lock', '.png', '.jpg', '.ico')): continue
        
        try:
            nodes = extract_functions_and_classes(content, path)
            all_project_nodes.extend(nodes)
            file_count += 1
        except Exception as e:
            print(f"  ⚠️ Failed to parse {path}: {e}")

    print(f"  ✅ Parsed {file_count} files. Found {len(all_project_nodes)} nodes.")
    
    if not all_project_nodes:
        return {"success": False, "message": "No nodes found to index."}

    print("  2.5 Running AI Critic...")
    important_nodes = [
        node for node in all_project_nodes
        if any(keyword in node.name.lower() for keyword in ['route', 'handler', 'service', 'controller', 'manager', 'process', 'generate', 'solve'])
    ][:8]

    if important_nodes:
        enrich_nodes_with_critic(important_nodes, HyDE_generation_model, max_nodes_to_process=8)

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
    
    # G. Save Light Metadata to Firestore
    graph_coll_ref = project_ref.collection(CODE_GRAPH_COLLECTION)
    delete_collection(graph_coll_ref, batch_size=50)
    
    print(f"  ✅ Re-indexing Complete. {len(all_project_nodes)} nodes indexed.")
    return {"success": True, "node_count": len(all_project_nodes)}