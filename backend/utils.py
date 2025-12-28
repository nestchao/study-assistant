import pytesseract
import PyPDF2 
from PIL import Image 
import git  
from git.exc import InvalidGitRepositoryError
from pathlib import Path
import hashlib
from firebase_admin import firestore
from collections import OrderedDict
import time
from langchain_text_splitters import RecursiveCharacterTextSplitter
from flask import request, jsonify
import fitz
import io
import re
import cv2
import numpy as np
import os
import tempfile
import comtypes.client
import pythoncom
from browser_bridge import browser_bridge

TXT_OUTPUT_DIR = Path("converted_txt_projects") 
STRUCTURE_FILE_NAME = "file_structure.json"
HASH_DB_FILE_NAME = "file_hashes.json"
DOT_REPLACEMENT = "__DOT__"

try:
    pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'
except Exception:
    print("Warning: Tesseract path not found. OCR will fail if needed.")

# -------------------------------------------------------------------------
# 1. HELPER: WINDOWS COM CONVERSION (NEW)
# -------------------------------------------------------------------------
def convert_pptx_to_pdf_windows(input_path, output_path):
    """
    Uses Microsoft PowerPoint (via COM) to convert a PPTX file to PDF.
    """
    # Initialize COM for the current thread (Essential for Flask/Threading)
    pythoncom.CoInitialize() 
    powerpoint = None
    presentation = None
    
    try:
        # Use absolute paths (Required for COM automation)
        abs_input = os.path.abspath(input_path)
        abs_output = os.path.abspath(output_path)

        # Create PowerPoint Application Instance
        powerpoint = comtypes.client.CreateObject("Powerpoint.Application")
        # powerpoint.Visible = 1 # Keep this commented out (runs hidden)
        
        # Open Presentation
        presentation = powerpoint.Presentations.Open(abs_input, WithWindow=False)
        
        # Save as PDF (Format ID 32 = ppSaveAsPDF)
        presentation.SaveAs(abs_output, 32)
        return True
        
    except Exception as e:
        print(f"    ❌ PowerPoint Conversion Error: {e}")
        return False
        
    finally:
        # Close everything safely
        if presentation:
            try: presentation.Close()
            except: pass
        if powerpoint:
            try: powerpoint.Quit()
            except: pass
        # Uninitialize COM
        pythoncom.CoUninitialize()

# -------------------------------------------------------------------------
# 2. MAIN PPTX EXTRACTION LOGIC (REPLACED)
# -------------------------------------------------------------------------
def extract_text_from_pptx(pptx_stream):
    """
    Extracts text from PPTX by:
    1. Saving stream to temp file.
    2. Converting to PDF (Windows COM).
    3. Extracting text from PDF (using extract_text).
    4. Deleting temp files.
    """
    print("  📽️ Starting PPTX -> PDF -> Text extraction...")
    
    temp_dir = tempfile.gettempdir()
    
    # 1. Save stream to temp PPTX
    # delete=False is required on Windows so we can close it before PPT opens it
    with tempfile.NamedTemporaryFile(suffix=".pptx", delete=False, dir=temp_dir) as temp_pptx:
        temp_pptx_path = temp_pptx.name
        pptx_stream.seek(0)
        temp_pptx.write(pptx_stream.read())

    # Define temp PDF path
    temp_pdf_path = temp_pptx_path.replace(".pptx", ".pdf")
    
    full_text = ""
    
    try:
        # 2. Convert to PDF using the helper
        success = convert_pptx_to_pdf_windows(temp_pptx_path, temp_pdf_path)
        
        if success and os.path.exists(temp_pdf_path):
            print(f"    ✅ PDF created at temp path. Extracting text...")
            
            # 3. Read PDF into memory
            with open(temp_pdf_path, "rb") as f:
                pdf_bytes = f.read()
            
            # Create a memory stream and use your existing PDF extractor
            pdf_stream_memory = io.BytesIO(pdf_bytes)
            full_text = extract_text(pdf_stream_memory)
            
        else:
            print("    ⚠️ Conversion failed or PDF file missing.")

    except Exception as e:
        print(f"  ❌ Error processing PPTX: {e}")

    finally:
        # 4. Cleanup: Delete both temporary files
        print("  🧹 Cleaning up temp files...")
        try:
            if os.path.exists(temp_pptx_path):
                os.remove(temp_pptx_path)
            if os.path.exists(temp_pdf_path):
                os.remove(temp_pdf_path)
        except Exception as cleanup_err:
            print(f"    ⚠️ Cleanup warning: {cleanup_err}")

    return full_text

# -------------------------------------------------------------------------
# 3. EXISTING UTILS (UNCHANGED)
# -------------------------------------------------------------------------

def preprocess_for_ocr(image: Image.Image) -> Image.Image:
    # (Kept for extract_text_from_image, though unused by PDF now)
    print("    - Pre-processing image for OCR...")
    open_cv_image = np.array(image.convert('RGB'))
    open_cv_image = open_cv_image[:, :, ::-1].copy() 
    gray = cv2.cvtColor(open_cv_image, cv2.COLOR_BGR2GRAY)
    _, thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY | cv2.THRESH_OTSU)
    denoised = cv2.medianBlur(thresh, 3)
    final_image = Image.fromarray(denoised)
    return final_image

def simplify_text(text):
    return re.sub(r'\s+', '', text).lower()

def extract_text(pdf_stream):
    """
    Extracts text from a PDF stream by uploading it to Google AI Studio via Browser Bridge.
    This replaces the previous PyMuPDF/OCR implementation.
    """
    print("  🤖 Starting Cloud-Based PDF Extraction (via Browser Bridge)...")
    
    # 1. Create a temporary file
    # We need a physical file path for the browser file chooser
    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as temp_pdf:
        # Write stream to file
        pdf_stream.seek(0)
        temp_pdf.write(pdf_stream.read())
        temp_pdf_path = temp_pdf.name

    try:
        # 2. Ensure bridge is running
        browser_bridge.start()
        
        # 3. Request upload and extraction
        extracted_text = browser_bridge.upload_and_extract(temp_pdf_path)
        
        if not extracted_text or extracted_text.startswith("Error"):
            print(f"  ❌ Extraction failed: {extracted_text}")
            return "" 
            
        print(f"  ✅ Extraction complete. Retrieved {len(extracted_text)} characters.")
        return extracted_text

    except Exception as e:
        print(f"  ❌ CRITICAL ERROR during PDF extraction: {e}")
        return ""
        
    finally:
        # 4. Cleanup: Delete the temporary file
        if os.path.exists(temp_pdf_path):
            try:
                os.remove(temp_pdf_path)
                print("  🧹 Temp PDF file cleaned up.")
            except Exception as e:
                print(f"  ⚠️ Failed to delete temp file: {e}")
    
def extract_text_from_image(image_stream):
    print("  🖼️ Extracting text from image via OCR...")
    try:
        pil_image = Image.open(image_stream)
        opencv_image = np.array(pil_image)
        gray_image = cv2.cvtColor(opencv_image, cv2.COLOR_BGR2GRAY)
        _, processed_image = cv2.threshold(gray_image, 150, 255, cv2.THRESH_BINARY | cv2.THRESH_OTSU)
        pil_processed_image = Image.fromarray(processed_image)
        text = pytesseract.image_to_string(pil_processed_image)
        return text
    except Exception as e:
        print(f"  ❌ Image OCR failed: {e}")    
        return ""

def split_chunks(text):
    print("  ✂️ Splitting text into chunks...")
    splitter = RecursiveCharacterTextSplitter(chunk_size=1500, chunk_overlap=200)
    chunks = splitter.split_text(text)
    print(f"  ✅ Created {len(chunks)} chunks.")
    return chunks

def delete_collection(coll_ref, batch_size):
    docs = coll_ref.limit(batch_size).stream()
    deleted = 0
    for doc in docs:
        for sub_coll_ref in doc.reference.collections():
            delete_collection(sub_coll_ref, batch_size)
        doc.reference.delete()
        deleted += 1
    if deleted >= batch_size:
        return delete_collection(coll_ref, batch_size)

def batch_save(collection, items, batch_size=100):
    batch = db.batch()
    for i, item in enumerate(items):
        if i % batch_size == 0 and i > 0:
            batch.commit()
            batch = db.batch()
        ref = collection.document()
        batch.set(ref, item)
    batch.commit()

def get_project_output_path(project_id: str) -> Path:
    return TXT_OUTPUT_DIR / project_id

def init_txt_converter_for_project(project_id: str):
    project_output_path = get_project_output_path(project_id)
    project_output_path.mkdir(parents=True, exist_ok=True)
    structure_file = project_output_path / STRUCTURE_FILE_NAME
    if not structure_file.exists():
        structure_file.write_text("{}", encoding='utf-8')

def convert_to_txt(src_path: Path, txt_path: Path) -> bool:
    try:
        with open(src_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        txt_path.write_text(content, encoding='utf-8')
        return True
    except Exception as e:
        txt_path.write_text(f"[ERROR READING FILE: {src_path.name}]\n\n{e}", encoding='utf-8')
        return False

def build_file_tree(root_path: Path, allowed_extensions: list = None) -> dict:
    tree = {}
    if allowed_extensions:
        allowed_extensions = [f".{ext.lstrip('.')}" for ext in allowed_extensions]
    
    for item in sorted(root_path.rglob("*")):
        if item.is_file():
            if '.git' in item.parts: continue
            if allowed_extensions and item.suffix.lower() not in allowed_extensions: continue

            rel_path = item.relative_to(root_path)
            rel_path_str = str(rel_path).replace('\\', '/')
            doc_id = hashlib.sha1(rel_path_str.encode('utf-8')).hexdigest()

            parts = rel_path.parts
            d = tree
            for part in parts[:-1]:
                d = d.setdefault(part, {})
            d[parts[-1]] = doc_id
    return tree

def load_hashes(project_id: str) -> dict:
    import json # Added import here for safety
    hash_db_file = get_project_output_path(project_id) / HASH_DB_FILE_NAME
    if hash_db_file.exists():
        return json.loads(hash_db_file.read_text(encoding='utf-8'))
    return {}

def save_hashes(project_id: str, hashes: dict):
    import json # Added import here for safety
    hash_db_file = get_project_output_path(project_id) / HASH_DB_FILE_NAME
    hash_db_file.write_text(json.dumps(hashes, indent=2), encoding='utf-8')

def is_git_repo(path: Path):
    try:
        return git.Repo(path, search_parent_directories=True)
    except (InvalidGitRepositoryError, git.exc.NoSuchPathError):
        return None

def get_file_hash(filepath) -> str:
    hasher = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(4096):
            hasher.update(chunk)
    return hasher.hexdigest()

def get_converted_file_ref(db, project_id, original_path_str: str, sub_collection: str, top_level_collection: str = "projects"):
    path_hash = hashlib.sha1(original_path_str.encode('utf-8')).hexdigest()
    return db.collection(top_level_collection).document(project_id).collection(sub_collection).document(path_hash)

def convert_and_upload_to_firestore(db, project_id, file_path, source_root, sub_collection: str, top_level_collection: str):
    rel_path_str = str(file_path.relative_to(source_root)).replace('\\', '/')
    print(f"  Processing: {rel_path_str}")

    try:
        content = file_path.read_text(encoding='utf-8', errors='ignore')
        current_hash = hashlib.sha256(content.encode('utf-8')).hexdigest()

        doc_ref = db.collection(top_level_collection) \
                    .document(project_id) \
                    .collection(sub_collection) \
                    .document()

        doc_ref.set({
            'original_path': rel_path_str,
            'content': content,
            'hash': current_hash,
            'timestamp': firestore.SERVER_TIMESTAMP,
        })

        print(f"    -> Uploaded to '{top_level_collection}/{project_id}/{sub_collection}' (doc_id={doc_ref.id})")
        return current_hash, doc_ref.id

    except Exception as e:
        print(f"    -> FAILED {rel_path_str}: {e}")
        return None

class SimpleL1Cache:
    def __init__(self, max_size=256, ttl=10):
        self.cache = OrderedDict()
        self.max_size = max_size
        self.ttl = ttl

    def get(self, key):
        if key not in self.cache: return None
        value, expiry = self.cache[key]
        if time.time() > expiry:
            del self.cache[key]
            return None
        self.cache.move_to_end(key)
        return value

    def set(self, key, value):
        if len(self.cache) >= self.max_size:
            self.cache.popitem(last=False)
        expiry = time.time() + self.ttl
        self.cache[key] = (value, expiry)

L1_CACHE = SimpleL1Cache(max_size=512, ttl=20)

def generate_tree_text_from_paths(root_name: str, file_paths: list) -> str:
    trie = {}
    for path_str in file_paths:
        parts = Path(path_str).parts
        current_level = trie
        for part in parts:
            if part not in current_level:
                current_level[part] = {}
            current_level = current_level[part]

    def walk_trie(node, prefix=""):
        lines = []
        items = sorted(node.keys())
        for i, name in enumerate(items):
            is_last = (i == len(items) - 1)
            connector = "└── " if is_last else "├── "
            is_dir = len(node[name]) > 0
            display_name = f"{name}/" if is_dir else name
            lines.append(f"{prefix}{connector}{display_name}")
            if is_dir:
                extension = "    " if is_last else "│   "
                lines.extend(walk_trie(node[name], prefix + extension))
        return lines

    tree_lines = walk_trie(trie)
    return f"{root_name}/\n" + "\n".join(tree_lines)

def generate_tree_with_stats(root_name: str, file_paths: list, files_metadata: dict = None) -> str:
    tree = {}
    file_count = 0
    dir_count = 0
    total_size = 0
    
    for path_str in file_paths:
        parts = Path(path_str).parts
        current_dict = tree
        for part in parts[:-1]:
            if part not in current_dict: dir_count += 1
            current_dict = current_dict.setdefault(part, {})
        
        file_info = {'_is_file': True}
        if files_metadata and path_str in files_metadata:
            file_info.update(files_metadata[path_str])
            total_size += files_metadata[path_str].get('size', 0)
        
        current_dict[parts[-1]] = file_info
        file_count += 1

    def build_tree_lines(sub_tree, prefix=""):
        lines = []
        items = sorted(sub_tree.keys())
        for i, key in enumerate(items):
            is_last = (i == len(items) - 1)
            value = sub_tree[key]
            connector = "└── " if is_last else "├── "
            
            if isinstance(value, dict) and value.get('_is_file'):
                size_info = ""
                if 'size' in value:
                    size_kb = value['size'] / 1024
                    size_info = f" ({size_kb:.1f} KB)"
                lines.append(f"{prefix}{connector}{key}{size_info}")
            elif isinstance(value, dict):
                lines.append(f"{prefix}{connector}{key}/")
                extension = "    " if is_last else "│   "
                lines.extend(build_tree_lines(value, prefix + extension))
            else:
                lines.append(f"{prefix}{connector}{key}")
        return lines

    tree_lines = build_tree_lines(tree)
    summary = f"""
    {root_name}/
    {'='*60}
    Directories: {dir_count}
    Files: {file_count}
    Total Size: {total_size / 1024 / 1024:.2f} MB
    {'='*60}
    """
    return summary + "\n".join(tree_lines)

def format_bytes(size_bytes: int) -> str:
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if size_bytes < 1024.0:
            return f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.1f} PB"

def validate_tree_structure(tree: dict) -> bool:
    def check_node(node):
        if not isinstance(node, dict): return False
        for key, value in node.items():
            if not isinstance(key, str): return False
            if value is None or (isinstance(value, dict) and value.get('_is_file')): continue
            if not isinstance(value, dict): return False
            if not check_node(value): return False
        return True
    return check_node(tree)