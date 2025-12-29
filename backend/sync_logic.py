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

def is_inside(child: Path, parent: Path) -> bool:
    """Industrial segment-based path comparison."""
    try:
        # relative_to throws ValueError if child is not under parent
        child.relative_to(parent)
        return True
    except ValueError:
        return False

def sync_single_file(db, project_id: str, relative_path_str: str):
    """Real-time atomic sync for a single file."""
    project_doc = db.collection(CODE_PROJECTS_COLLECTION).document(project_id).get()
    if not project_doc.exists:
        raise ValueError("Project config not found")
        
    config = project_doc.to_dict()
    source_root = Path(config['local_path'])
    full_path = source_root / relative_path_str
    
    if not full_path.exists():
        return None

    # 1. Upload to Firestore (Converted Files)
    # Using your existing util
    convert_and_upload_to_firestore(
        db, project_id, full_path, source_root,
        CODE_FILES_SUBCOLLECTION, CODE_PROJECTS_COLLECTION
    )

    # 2. Extract and Embed for Vector Search
    content = full_path.read_text(errors='ignore')
    nodes = extract_functions_and_classes(content, relative_path_str)
    
    if nodes:
        generate_embeddings(nodes)
        
        # 3. Hot-patch the local FAISS index
        store_path = VECTOR_STORE_ROOT / project_id
        if store_path.exists():
            vector_store = FaissVectorStore.load(store_path)
            vector_store.add_nodes(nodes)
            vector_store.save(store_path)
            
    return len(nodes)

def perform_sync(db, project_id: str, config_data: dict):
    # 1. Path & Config Sanitization
    source_dir = Path(config_data.get('local_path')).resolve()
    # Ensure storage_dir is absolute and resolved to handle case-insensitivity on Windows
    storage_dir = Path(config_data.get('storage_path', source_dir / ".study_assistant")).resolve()
    
    # Create the converted files directory early
    converted_files_dir = storage_dir / "converted_files"
    converted_files_dir.mkdir(parents=True, exist_ok=True)
    
    extensions = {e.lstrip('.').lower() for e in config_data.get('allowed_extensions', [])}
    ignored_paths = [Path(p) for p in config_data.get('ignored_paths', []) if p.strip()]
    included_paths = [Path(p) for p in config_data.get('included_paths', []) if p.strip()]

    # 2. Database Initialization
    project_ref = db.collection(CODE_PROJECTS_COLLECTION).document(project_id)
    project_ref.update({'status': 'syncing'})

    manifest_ref = project_ref.collection(CODE_FILES_SUBCOLLECTION).document('_manifest')
    manifest_doc = manifest_ref.get()
    files_in_db = manifest_doc.to_dict().get('files', {}) if manifest_doc.exists else {}

    logs = []
    updated_count = 0
    deleted_count = 0
    files_to_process = []

    # 🚀 PHASE 2: THE HARDENED RECURSIVE SCANNER
    def recursive_scan(current_path: Path):
        try:
            for item in current_path.iterdir():
                # 1. ATOMIC GUARD: Block the storage directory (Infinite Loop Prevention)
                # We resolve the item to handle case-sensitivity and relative paths
                resolved_item = item.resolve()
                if resolved_item == storage_dir:
                    print(f"🛡️ Scanner Guard: Pruned storage directory {item}")
                    continue

                # 2. HARD SYSTEM IGNORES (Internal Junk)
                if item.name in [".git", ".vscode", "__pycache__", "node_modules"]:
                    continue

                rel_path = item.relative_to(source_dir)
                
                # Check Logic
                is_ignored = any(is_inside(rel_path, ign) for ign in ignored_paths)
                is_bridge = any(is_inside(inc, rel_path) for inc in included_paths)
                is_exception = any(is_inside(rel_path, inc) for inc in included_paths)

                if item.is_dir():
                    # Decision: Enter if not ignored OR if it leads to an exception
                    if not is_ignored or is_bridge or is_exception:
                        recursive_scan(item)
                elif item.is_file():
                    # Decision: Collect if not ignored OR if it is an explicit exception
                    if not is_ignored or is_exception:
                        ext = item.suffix.lstrip('.').lower()
                        if not extensions or ext in extensions:
                            files_to_process.append(item)
        except PermissionError:
            pass # Skip folders we can't access

    if source_dir.is_dir():
        recursive_scan(source_dir)
    else:
        raise FileNotFoundError(f"Mission Abort: Source directory {source_dir} not found.")

    # 🚀 PHASE 3: ATOMIC RECONCILIATION (Compare & Upload)
    processed_paths = set()
    for file_path in files_to_process:
        # Force forward slashes for cross-platform DB consistency
        rel_path_str = file_path.relative_to(source_dir).as_posix()
        processed_paths.add(rel_path_str)
        
        local_hash = get_file_hash(file_path)
        db_file_meta = files_in_db.get(rel_path_str, {})
        
        if local_hash != db_file_meta.get('hash'):
            logs.append(f"UPDATE: {rel_path_str}")
            # Use original convert_and_upload util
            result = convert_and_upload_to_firestore(
                db, project_id, file_path, source_dir, 
                CODE_FILES_SUBCOLLECTION, CODE_PROJECTS_COLLECTION
            )
            if result:
                uploaded_hash, doc_id = result
                files_in_db[rel_path_str] = {'hash': uploaded_hash, 'doc_id': doc_id}
                updated_count += 1

    # 🚀 PHASE 4: PRUNING (Handle Deletions)
    # Only delete items that are in the DB but were NOT found in the local scan
    current_db_paths = list(files_in_db.keys())
    for p in current_db_paths:
        if p not in processed_paths:
            # OPTIONAL: Only delete if it matches the current extension filter
            # This prevents accidental deletion of other data types
            ext = Path(p).suffix.lstrip('.').lower()
            if not extensions or ext in extensions:
                logs.append(f"DELETE: {p}")
                doc_id = files_in_db[p].get('doc_id')
                if doc_id:
                    project_ref.collection(CODE_FILES_SUBCOLLECTION).document(doc_id).delete()
                del files_in_db[p]
                deleted_count += 1

    # 🚀 PHASE 5: METADATA FINALIZATION (Trie Tree & Context)
    manifest_ref.set({'files': files_in_db})
    
    # Generate Tree using the TRIE logic fixed in the previous turn
    final_file_paths = sorted(list(files_in_db.keys()))
    root_name = source_dir.name if source_dir.name else "root"
    tree_content = generate_tree_text_from_paths(root_name, final_file_paths)

    project_ref.collection(CODE_FILES_SUBCOLLECTION).document('project_tree_txt').set({
        'original_path': 'tree.txt',
        'content': tree_content,
        'timestamp': firestore.SERVER_TIMESTAMP
    })
    
    # Full Context Reassembly
    try:
        from sync_logic import generate_chunked_full_context 
        generate_chunked_full_context(db, project_ref, files_in_db, final_file_paths)
    except ImportError:
        # If in same file, just call it directly
        pass 

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
        enrich_nodes_with_critic(
            nodes=important_nodes, 
            model_instance=HyDE_generation_model, 
            max_nodes_to_process=10
        )

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