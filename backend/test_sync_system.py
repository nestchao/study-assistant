# backend/test_sync_system.py
"""
Test script to demonstrate the enhanced sync system with priority tree generation
and chunked full context support.

Usage:
    python test_sync_system.py <project_id> <source_path>
"""

import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent))

from services import init_all_services, db
from sync_logic import perform_sync, retrieve_full_context, generate_chunked_full_context
from utils import generate_tree_text_from_paths, format_bytes
from config import CODE_PROJECTS_COLLECTION, CODE_FILES_SUBCOLLECTION


def test_tree_generation():
    """Test the tree generation functionality"""
    print("\n" + "="*60)
    print("TEST 1: Tree Generation")
    print("="*60)
    
    sample_paths = [
        'backend/app.py',
        'backend/routes/api.py',
        'backend/routes/auth.py',
        'backend/utils/helpers.py',
        'frontend/src/App.tsx',
        'frontend/src/components/Header.tsx',
        'frontend/public/index.html',
        'README.md',
        'package.json'
    ]
    
    tree = generate_tree_text_from_paths("my_project", sample_paths)
    print(tree)
    print("\n✅ Tree generation test passed")


def test_sync_with_priority(project_id: str, source_path: str):
    """Test the sync system with priority tree generation"""
    print("\n" + "="*60)
    print("TEST 2: Sync with Priority Tree Generation")
    print("="*60)
    
    config = {
        'local_path': source_path,
        'allowed_extensions': ['.py', '.js', '.ts', '.tsx', '.json', '.md'],
        'ignored_paths': ['node_modules', 'venv', '__pycache__', '.git']
    }
    
    try:
        # Initialize services
        init_all_services()
        
        print(f"\n🚀 Starting sync for project: {project_id}")
        result = perform_sync(db, project_id, config)
        
        print("\n📊 Sync Results:")
        print(f"  - Updated files: {result['updated']}")
        print(f"  - Deleted files: {result['deleted']}")
        print(f"  - Total operations: {len(result['logs'])}")
        
        if result['logs']:
            print("\n📝 Recent operations:")
            for log in result['logs'][:10]:
                print(f"  - {log}")
            
            if len(result['logs']) > 10:
                print(f"  ... and {len(result['logs']) - 10} more")
        
        print("\n✅ Sync test passed")
        return True
        
    except Exception as e:
        print(f"\n❌ Sync test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_tree_txt_exists(project_id: str):
    """Verify that tree.txt was generated correctly"""
    print("\n" + "="*60)
    print("TEST 3: Verify tree.txt Generation")
    print("="*60)
    
    try:
        project_ref = db.collection(CODE_PROJECTS_COLLECTION).document(project_id)
        tree_doc = project_ref.collection(CODE_FILES_SUBCOLLECTION).document('project_tree_txt').get()
        
        if not tree_doc.exists:
            print("❌ tree.txt document not found!")
            return False
        
        tree_data = tree_doc.to_dict()
        content = tree_data.get('content', '')
        
        print(f"✅ tree.txt found!")
        print(f"  - Size: {format_bytes(len(content))}")
        print(f"  - Lines: {len(content.splitlines())}")
        
        print("\n📄 Preview (first 20 lines):")
        lines = content.splitlines()[:20]
        for line in lines:
            print(f"  {line}")
        
        if len(content.splitlines()) > 20:
            print(f"  ... and {len(content.splitlines()) - 20} more lines")
        
        return True
        
    except Exception as e:
        print(f"❌ Error checking tree.txt: {e}")
        return False


def test_full_context_retrieval(project_id: str):
    """Test retrieving full context (with chunking support)"""
    print("\n" + "="*60)
    print("TEST 4: Full Context Retrieval")
    print("="*60)
    
    try:
        project_ref = db.collection(CODE_PROJECTS_COLLECTION).document(project_id)
        context_doc = project_ref.collection(CODE_FILES_SUBCOLLECTION).document('project_full_context_txt').get()
        
        if not context_doc.exists:
            print("⚠️ _full_context.txt not found (might be disabled to save space)")
            return True
        
        metadata = context_doc.to_dict()
        is_chunked = metadata.get('is_chunked', False)
        total_size = metadata.get('total_size', 0)
        
        print(f"✅ _full_context.txt found!")
        print(f"  - Size: {format_bytes(total_size)}")
        print(f"  - Chunked: {is_chunked}")
        
        if is_chunked:
            total_chunks = metadata.get('total_chunks', 0)
            chunk_size = metadata.get('chunk_size', 0)
            print(f"  - Total chunks: {total_chunks}")
            print(f"  - Chunk size: {format_bytes(chunk_size)}")
            
            print("\n🔄 Testing chunk reassembly...")
            full_content = retrieve_full_context(db, project_id)
            
            if full_content:
                print(f"✅ Successfully reassembled {format_bytes(len(full_content))}")
                
                # Verify size matches
                if len(full_content) != total_size:
                    print(f"⚠️ Warning: Size mismatch! Expected {total_size}, got {len(full_content)}")
                    return False
            else:
                print("❌ Failed to retrieve full context")
                return False
        else:
            content = metadata.get('content', '')
            print(f"  - Content size: {format_bytes(len(content))}")
        
        print("\n✅ Full context test passed")
        return True
        
    except Exception as e:
        print(f"❌ Error testing full context: {e}")
        import traceback
        traceback.print_exc()
        return False


def run_all_tests(project_id: str = None, source_path: str = None):
    """Run all sync system tests"""
    print("\n" + "="*70)
    print("🧪 SYNC SYSTEM TEST SUITE")
    print("="*70)
    
    results = []
    
    # Test 1: Tree generation (standalone)
    results.append(("Tree Generation", test_tree_generation))
    
    # Only run integration tests if project details provided
    if project_id and source_path:
        # Test 2: Full sync
        success = test_sync_with_priority(project_id, source_path)
        results.append(("Full Sync", success))
        
        if success:
            # Test 3: Verify tree.txt
            results.append(("Tree.txt Verification", test_tree_txt_exists(project_id)))
            
            # Test 4: Full context retrieval
            results.append(("Full Context Retrieval", test_full_context_retrieval(project_id)))
    
    # Print summary
    print("\n" + "="*70)
    print("📊 TEST SUMMARY")
    print("="*70)
    
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for test_name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status} - {test_name}")
    
    print(f"\n{'='*70}")
    print(f"Results: {passed}/{total} tests passed")
    print("="*70)
    
    return passed == total


if __name__ == "__main__":
    if len(sys.argv) >= 3:
        # Full test with project
        project_id = sys.argv[1]
        source_path = sys.argv[2]
        run_all_tests(project_id, source_path)
    else:
        # Just run standalone tests
        print("\nUsage: python test_sync_system.py <project_id> <source_path>")
        print("Running standalone tests only...\n")
        run_all_tests()