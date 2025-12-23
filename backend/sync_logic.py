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
from code_graph_utils import (
    extract_functions_and_classes, 
    generate_embeddings, 
    calculate_static_weights, 
    enrich_nodes_with_critic
)
from services import HyDE_generation_model

# Firestore document size limit is ~1MB, we use 900KB as safe threshold
MAX_CHUNK_SIZE = 900_000  # ~900KB per chunk


def perform_sync(db, project_id: str, config_data: dict):
    """
    Enhanced sync with Hybrid Path Filtering based on Specificity.
    Rule: The most specific (longest) matching path determines fate.
    """
    source_dir = config_data.get('local_path')
    extensions = config_data.get('allowed_extensions', [])
    included_paths = config_data.get('included_paths', [])
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

    # === PHASE 1: Check Manifest ===
    manifest_ref = project_ref.collection(CODE_FILES_SUBCOLLECTION).document('_manifest')
    manifest_doc = manifest_ref.get()
    files_in_db = manifest_doc.to_dict().get('files', {}) if manifest_doc.exists else {}

    # === PHASE 2: Scan & Apply Deepest Match Filtering ===
    
    # Normalize filters
    normalized_included = [Path(p.replace('\\', '/')) for p in included_paths if p.strip()]
    normalized_ignored = [Path(p.replace('\\', '/')) for p in ignored_paths if p.strip()]
    
    # Scan everything except .git
    all_local_files = [f for f in source_path.rglob("*") if f.is_file() and '.git' not in f.parts]

    filtered_files = []
    
    for f in all_local_files:
        rel_path = f.relative_to(source_path)
        
        # 1. Calculate Ignore Specificity (Depth)
        # If file is in 'A/B/C', specificity is 3. If in 'A', specificity is 1.
        ignore_depth = 0
        for ign in normalized_ignored:
            if rel_path == ign or rel_path.is_relative_to(ign):
                # Count parts to determine specificity (e.g., 'src/utils' = 2)
                d = len(ign.parts)
                if d > ignore_depth:
                    ignore_depth = d
        
        # 2. Calculate Include Specificity (Depth)
        include_depth = 0
        for inc in normalized_included:
            if rel_path == inc or rel_path.is_relative_to(inc):
                d = len(inc.parts)
                if d > include_depth:
                    include_depth = d
        
        # 3. Decision Logic (Deepest Wins)
        if include_depth > ignore_depth:
            # Explicitly included at a deeper level than any ignore
            # Example: Ignore 'A' (1), Include 'A/B' (2). 2 > 1 -> Keep.
            filtered_files.append(f)
        elif ignore_depth > 0 and ignore_depth >= include_depth:
            # Ignored at a deeper or equal level
            # Example: Include 'A/B' (2), Ignore 'A/B/C' (3). 3 > 2 -> Drop.
            # Example: Ignore 'A' (1), Include None (0). 1 > 0 -> Drop.
            continue 
        else:
            # Neither ignored nor included (Default behavior: Keep)
            filtered_files.append(f)

    # Filter by Extension
    dot_ext = [f".{e.lstrip('.').lower()}" for e in extensions] if extensions else None
    
    files_to_process = [
        f for f in filtered_files 
        if not dot_ext or f.suffix.lower() in dot_ext
    ]
    
    # === PHASE 3: Compare Hashes & Upload Changed Files ===
    processed_paths = set()
    for file_path in files_to_process:
        rel_path = str(file_path.relative_to(source_path)).replace('\\', '/')
        processed_paths.add(rel_path)
        local_hash = get_file_hash(file_path)
        db_hash = files_in_db.get(rel_path, {}).get('hash')
        
        if local_hash != db_hash:
            logs.append(f"UPDATE: {rel_path}")
            result = convert_and_upload_to_firestore(
                db, project_id, file_path, source_path, 
                CODE_FILES_SUBCOLLECTION, CODE_PROJECTS_COLLECTION
            )
            if result:
                uploaded_hash, doc_id = result
                files_in_db[rel_path] = {'hash': uploaded_hash, 'doc_id': doc_id}
                updated_count += 1

    # === PHASE 4: Handle Deletions ===
    # Only delete files that match our extensions (don't touch other existing DB data)
    db_paths = {
        p for p in files_in_db 
        if not dot_ext or Path(p).suffix.lower() in dot_ext
    }
    to_delete = db_paths - processed_paths
    for p in to_delete:
        logs.append(f"DELETE: {p}")
        doc_id = files_in_db[p].get('doc_id')
        if doc_id:
            project_ref.collection(CODE_FILES_SUBCOLLECTION).document(doc_id).delete()
        del files_in_db[p]
        deleted_count += 1

    # === PHASE 5: Update Manifest & Special Files ===
    manifest_ref.set({'files': files_in_db})
    final_file_paths = sorted(list(files_in_db.keys()))
    
    print("\n📂 PRIORITY: Generating tree.txt...")
    tree_content = generate_tree_text_from_paths(source_path.name, final_file_paths)
    project_ref.collection(CODE_FILES_SUBCOLLECTION).document('project_tree_txt').set({
        'original_path': 'tree.txt',
        'content': tree_content,
        'timestamp': firestore.SERVER_TIMESTAMP
    })
    
    print("\n📝 Generating _full_context.txt...")
    try:
        # Import moved inside to avoid circular dependency issues if any
        from sync_logic import generate_chunked_full_context 
        generate_chunked_full_context(db, project_ref, files_in_db, final_file_paths)
    except Exception as e:
        # Fallback if function is defined in this file (which it is below)
        try:
            generate_chunked_full_context_local(db, project_ref, files_in_db, final_file_paths)
        except:
            print(f"⚠️ Failed to generate context: {e}")

    project_ref.update({
        'status': 'idle', 
        'last_synced': firestore.SERVER_TIMESTAMP
    })
    
    return {
        "logs": logs, 
        "updated": updated_count, 
        "deleted": deleted_count
    }

def generate_chunked_full_context(db, project_ref, files_in_db, final_file_paths):
    """
    Generates _full_context.txt with automatic chunking if content exceeds size limits.
    Stores chunks in a subcollection for scalability.
    """
    print("  🔨 Building full context from all files...")
    
    # Build the complete context string
    chunks_content = []
    total_chars = 0
    for rel_path in final_file_paths:
        doc_id = files_in_db[rel_path].get('doc_id')
        if not doc_id: continue
        try:
            doc = project_ref.collection(CODE_FILES_SUBCOLLECTION).document(doc_id).get()
            if doc.exists:
                file_content = doc.to_dict().get('content', '')
                chunk_text = f"--- FILE: {rel_path} ---\n{file_content}\n"
                chunks_content.append(chunk_text)
                total_chars += len(chunk_text)
        except: pass
    
    full_context = "\n".join(chunks_content)
    if total_chars <= MAX_CHUNK_SIZE:
        project_ref.collection(CODE_FILES_SUBCOLLECTION).document('project_full_context_txt').set({
            'original_path': '_full_context.txt', 'content': full_context,
            'timestamp': firestore.SERVER_TIMESTAMP, 'is_chunked': False, 'total_size': total_chars
        })
    else:
        from sync_logic import store_chunked_context # Import helper
        store_chunked_context(db, project_ref, full_context, total_chars)

def store_chunked_context(db, project_ref, full_context, total_chars):
    """
    Stores large context as multiple chunks in a subcollection.
    """
    # Delete existing full_context document and its chunks
    full_context_ref = project_ref.collection(CODE_FILES_SUBCOLLECTION).document('project_full_context_txt')
    chunks_subcollection = full_context_ref.collection('chunks')
    delete_collection(chunks_subcollection, batch_size=50)
    
    chunks = []
    current_pos = 0
    chunk_num = 0
    while current_pos < len(full_context):
        chunk_end = min(current_pos + MAX_CHUNK_SIZE, len(full_context))
        chunk_data = full_context[current_pos:chunk_end]
        chunks.append({'order': chunk_num, 'content': chunk_data, 'size': len(chunk_data)})
        current_pos = chunk_end
        chunk_num += 1
        
    full_context_ref.set({
        'original_path': '_full_context.txt', 'timestamp': firestore.SERVER_TIMESTAMP,
        'is_chunked': True, 'total_size': total_chars, 'total_chunks': len(chunks), 'chunk_size': MAX_CHUNK_SIZE
    })
    
    for i, chunk_info in enumerate(chunks):
        chunks_subcollection.document(f'chunk_{i}').set(chunk_info)

def retrieve_full_context(db, project_id):
    """
    Retrieves the full context, automatically reassembling chunks if needed.
    """
    project_ref = db.collection(CODE_PROJECTS_COLLECTION).document(project_id)
    context_ref = project_ref.collection(CODE_FILES_SUBCOLLECTION).document('project_full_context_txt')
    
    context_doc = context_ref.get()
    if not context_doc.exists:
        return None
    
    metadata = context_doc.to_dict()
    
    # Check if it's chunked
    if not metadata.get('is_chunked', False):
        # Simple case - return content directly
        return metadata.get('content', '')
    
    # Chunked case - reassemble
    print(f"  🔄 Reassembling {metadata['total_chunks']} chunks...")
    chunks_ref = context_ref.collection('chunks').order_by('order').stream()
    
    chunks_data = []
    for chunk_doc in chunks_ref:
        chunks_data.append(chunk_doc.to_dict()['content'])
    
    full_context = "".join(chunks_data)
    print(f"  ✅ Reassembled {len(full_context):,} characters")
    return full_context

def force_reindex_project(db, project_id):
    """Enhanced reindexing with critic analysis"""
    print(f"\n🔄 FORCE RE-INDEX initiated for project: {project_id}")
    project_ref = db.collection(CODE_PROJECTS_COLLECTION).document(project_id)
    
    # Fetch all existing code files from Firestore
    print("  1. Fetching code files from database...")
    docs = project_ref.collection(CODE_FILES_SUBCOLLECTION).stream()
    
    all_project_nodes = []
    file_count = 0
    
    for doc in docs:
        data = doc.to_dict()
        path = data.get('original_path')
        content = data.get('content')
        
        # Filter special files and invalid content
        if not path or not content:
            continue
        if path in ['tree.txt', '_full_context.txt']:
            continue
        if path.endswith(('.lock', '.png', '.jpg', '.ico', '.json')):
            continue
        
        try:
            nodes = extract_functions_and_classes(content, path)
            all_project_nodes.extend(nodes)
            file_count += 1
        except Exception as e:
            print(f"  ⚠️ Failed to parse {path}: {e}")

    print(f"  ✅ Parsed {file_count} files. Found {len(all_project_nodes)} nodes.")
    
    if not all_project_nodes:
        return {"success": False, "message": "No nodes found to index."}

    # Run AI Critic on important nodes
    print("  2. Running AI Critic analysis...")
    important_nodes = [
        node for node in all_project_nodes
        if any(keyword in node.name.lower() for keyword in [
            'route', 'handler', 'service', 'controller', 'manager', 
            'process', 'generate', 'solve', 'sync', 'upload'
        ])
    ][:10]

    if important_nodes:
        enrich_nodes_with_critic(important_nodes, HyDE_generation_model, max_nodes_to_process=10)

    # Generate Embeddings
    print("  3. Generating embeddings...")
    BATCH_SIZE = 50
    for i in range(0, len(all_project_nodes), BATCH_SIZE):
        batch = all_project_nodes[i:i+BATCH_SIZE]
        generate_embeddings(batch)
        print(f"     - Embedded batch {i//BATCH_SIZE + 1}/{(len(all_project_nodes) + BATCH_SIZE - 1)//BATCH_SIZE}")

    # Calculate Weights
    print("  4. Calculating structural weights...")
    calculate_static_weights(all_project_nodes)

    # Delete old vector store
    store_path = VECTOR_STORE_ROOT / project_id
    if store_path.exists():
        shutil.rmtree(store_path)
        print(f"  🗑️ Deleted old vector store at {store_path}")

    # Create new FAISS index
    print("  5. Building new FAISS index...")
    vector_store = FaissVectorStore()
    vector_store.add_nodes(all_project_nodes)
    vector_store.save(store_path)
    
    # Clean up old graph collection
    graph_coll_ref = project_ref.collection(CODE_GRAPH_COLLECTION)
    delete_collection(graph_coll_ref, batch_size=50)
    
    print(f"  ✅ Re-indexing complete. {len(all_project_nodes)} nodes indexed.")
    return {"success": True, "node_count": len(all_project_nodes)}