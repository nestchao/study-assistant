import pytesseract
import PyPDF2 
from pdf2image import convert_from_bytes
from PIL import Image # Add this import: pip install Pillow
import git  # Ensure you have run 'pip install GitPython'
from git.exc import InvalidGitRepositoryError
from pathlib import Path
import hashlib
from firebase_admin import firestore, auth
from collections import OrderedDict
import time
from functools import wraps 
from langchain_text_splitters import RecursiveCharacterTextSplitter
from flask import request, jsonify
import fitz
import io
import re
import cv2
import numpy as np

TXT_OUTPUT_DIR = Path("converted_txt_projects") # Main output directory
STRUCTURE_FILE_NAME = "file_structure.json"
HASH_DB_FILE_NAME = "file_hashes.json"
DOT_REPLACEMENT = "__DOT__"

# Make sure this path is correct for your system
try:
    pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'
except Exception:
    print("Warning: Tesseract path not found. OCR will fail if needed.")

def preprocess_for_ocr(image: Image.Image) -> Image.Image:
    """
    Prepares an image for OCR by applying a standard set of cleaning filters.
    
    Args:
        image: A PIL Image object.

    Returns:
        A cleaned-up PIL Image object, ready for Tesseract.
    """
    print("    - Pre-processing image for OCR...")
    # 1. Convert PIL Image to an OpenCV format (numpy array)
    #    Make sure it's in a color format that OpenCV expects (BGR)
    open_cv_image = np.array(image.convert('RGB'))
    open_cv_image = open_cv_image[:, :, ::-1].copy() # Convert RGB to BGR

    # 2. Grayscale: Simplifies the image, removing color noise.
    gray = cv2.cvtColor(open_cv_image, cv2.COLOR_BGR2GRAY)

    # 3. Binarization (Thresholding): Converts the image to pure black and white.
    #    This is CRUCIAL for Tesseract. Otsu's thresholding is great because it
    #    automatically determines the best threshold value.
    _, thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY | cv2.THRESH_OTSU)

    # 4. Denoising (Optional but often helpful)
    #    Removes small dots/speckles from the image.
    denoised = cv2.medianBlur(thresh, 3)

    # 5. Convert back to PIL Image format to pass to Pytesseract
    final_image = Image.fromarray(denoised)
    print("    - Pre-processing complete.")
    return final_image

def simplify_text(text):
    """A helper to normalize text for comparison by removing whitespace and making it lowercase."""
    return re.sub(r'\s+', '', text).lower()

def extract_text(pdf_stream):
    """
    Extracts text from a PDF stream using a MAXIMUM COMPLETENESS approach.
    For each page, it extracts native text and performs OCR, then intelligently
    merges the results to capture all possible content.

    Args:
        pdf_stream: A file-like object representing the PDF file.

    Returns:
        A string containing all extracted text from the PDF.
    """
    print("  🔎 Starting Maximum Completeness text extraction...")
    all_page_texts = []
    
    try:
        doc = fitz.open(stream=pdf_stream.read(), filetype="pdf")

        for page_num, page in enumerate(doc):
            print(f"  - Processing Page {page_num + 1}/{len(doc)}...")

            # --- Step 1: Get Native Text (The High-Quality Base) ---
            native_text = page.get_text("text")
            print(f"    - Native text found: {len(native_text)} chars.")

            # --- Step 2: Perform OCR (The Comprehensive Source) ---
            ocr_text = ""
            try:
                pix = page.get_pixmap(dpi=300)
                img_bytes = pix.tobytes("ppm")
                img = Image.open(io.BytesIO(img_bytes))

                # --- THIS IS THE NEW LINE ---
                processed_img = preprocess_for_ocr(img) 
                # ---------------------------

                ocr_text = pytesseract.image_to_string(processed_img) # Use the processed image
                print(f"    - OCR text found: {len(ocr_text)} chars.")
            except Exception as ocr_error:
                print(f"    - ❌ OCR failed for page {page_num + 1}: {ocr_error}")

            # --- Step 3: Intelligently Merge ---
            # If there's no native text, the page is purely an image. Use OCR text directly.
            if not native_text.strip():
                print("    - Verdict: Image-only page. Using OCR text.")
                all_page_texts.append(ocr_text)
                continue

            # If OCR text is negligible, the page is purely text. Use native text.
            if not ocr_text.strip():
                 print("    - Verdict: Text-only page. Using native text.")
                 all_page_texts.append(native_text)
                 continue

            # The complex case: Mixed content. Merge them.
            print("    - Verdict: Mixed content page. Merging results.")
            
            # Use the clean native text as our starting point.
            final_page_text = native_text
            
            # Create a simplified version of the native text for fast searching.
            simplified_native = simplify_text(native_text)

            # Find lines in OCR text that are NOT in the native text.
            unique_ocr_lines = []
            for line in ocr_text.splitlines():
                if line.strip() and simplify_text(line) not in simplified_native:
                    unique_ocr_lines.append(line)
            
            if unique_ocr_lines:
                print(f"    - Found {len(unique_ocr_lines)} unique lines from OCR. Appending them.")
                # Append the unique findings, separated clearly.
                unique_content = "\n".join(unique_ocr_lines)
                final_page_text += f"\n\n--- OCR Additions ---\n{unique_content}"

            all_page_texts.append(final_page_text)

    except Exception as e:
        print(f"  ❌ CRITICAL ERROR during PDF processing: {e}")
        return "\n\n".join(all_page_texts)
    
    finally:
        if 'doc' in locals() and doc:
            doc.close()
            
    full_text = "\n\n".join(all_page_texts)
    print(f"  ✅ Max-completeness extraction complete. Total characters: {len(full_text)}")
    return full_text
    

def extract_text_from_image(image_stream):
    """Extracts text from an image file stream using OCR."""
    print("  🖼️ Extracting text from image via OCR...")
    try:
        image = Image.open(image_stream)
        text = pytesseract.image_to_string(image)
        print(f"  ✅ OCR extracted {len(text)} characters from image.")
        return text
    except Exception as e:
        print(f"  ❌ Image OCR failed: {e}")    
        return ""

def split_chunks(text):
    """Splits a large text into smaller chunks for easier processing."""
    print("  ✂️ Splitting text into chunks...")
    splitter = RecursiveCharacterTextSplitter(chunk_size=1500, chunk_overlap=200)
    chunks = splitter.split_text(text)
    print(f"  ✅ Created {len(chunks)} chunks.")
    return chunks

def delete_collection(coll_ref, batch_size):
    """Recursively deletes all documents and subcollections within a collection."""
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
    """Returns the specific output path for a given project."""
    return TXT_OUTPUT_DIR / project_id

def init_txt_converter_for_project(project_id: str):
    project_output_path = get_project_output_path(project_id)
    project_output_path.mkdir(parents=True, exist_ok=True)
    # We only need to manage the structure file now
    structure_file = project_output_path / STRUCTURE_FILE_NAME
    if not structure_file.exists():
        structure_file.write_text("{}", encoding='utf-8')

def convert_to_txt(src_path: Path, txt_path: Path) -> bool:
    """Converts a source file to a .txt file with its content."""
    try:
        # For common text-based files, just copy the content directly.
        with open(src_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        txt_path.write_text(content, encoding='utf-8')
        return True
    except Exception as e:
        txt_path.write_text(f"[ERROR READING FILE: {src_path.name}]\n\n{e}\n\n[This might be a binary file or have an unsupported encoding.]", encoding='utf-8')
        return False

def build_file_tree(root_path: Path, allowed_extensions: list = None) -> dict:
    # ... (This function is correct, but ensure it creates paths to the FIRESTORE documents now)
    # Let's refine this function to be more generic.
    tree = {}
    if allowed_extensions:
        allowed_extensions = [f".{ext.lstrip('.')}" for ext in allowed_extensions]
    
    for item in sorted(root_path.rglob("*")):
        if item.is_file():
            if '.git' in item.parts: continue
            if allowed_extensions and item.suffix.lower() not in allowed_extensions: continue

            rel_path = item.relative_to(root_path)
            # We need the Firestore doc ID, which is a hash of the relative path.
            rel_path_str = str(rel_path).replace('\\', '/')
            doc_id = hashlib.sha1(rel_path_str.encode('utf-8')).hexdigest()

            parts = rel_path.parts
            d = tree
            for part in parts[:-1]:
                d = d.setdefault(part, {})
            # The value is now the Firestore document ID
            d[parts[-1]] = doc_id
    return tree

def load_hashes(project_id: str) -> dict:
    hash_db_file = get_project_output_path(project_id) / HASH_DB_FILE_NAME
    if hash_db_file.exists():
        return json.loads(hash_db_file.read_text(encoding='utf-8'))
    return {}

def save_hashes(project_id: str, hashes: dict):
    hash_db_file = get_project_output_path(project_id) / HASH_DB_FILE_NAME
    hash_db_file.write_text(json.dumps(hashes, indent=2), encoding='utf-8')

def is_git_repo(path: Path):
    try:
        return git.Repo(path, search_parent_directories=True)
    except (InvalidGitRepositoryError, NoSuchPathError):
        return None

def get_file_hash(filepath) -> str:
    """Computes SHA256 hash of a file's content."""
    hasher = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(4096):
            hasher.update(chunk)
    return hasher.hexdigest()

def get_converted_file_ref(db, project_id, original_path_str: str):
    """Creates a consistent and safe document ID from the original file path."""
    # Use a hash of the path for a predictable, safe document ID
    path_hash = hashlib.sha1(original_path_str.encode('utf-8')).hexdigest()
    return db.collection('projects').document(project_id).collection('converted_files').document(path_hash)

def convert_and_upload_to_firestore(db, project_id, file_path, source_root):
    """
    Reads a local file → text → uploads to Firestore.
    Returns (hash, doc_id) on success, otherwise None.
    """
    rel_path_str = str(file_path.relative_to(source_root)).replace('\\', '/')
    print(f"  Processing: {rel_path_str}")

    try:
        # 1. Read content
        content = file_path.read_text(encoding='utf-8', errors='ignore')

        # 2. Hash
        current_hash = hashlib.sha256(content.encode('utf-8')).hexdigest()

        # 3. **Create a document with an auto-generated ID**
        doc_ref = db.collection('projects') \
                    .document(project_id) \
                    .collection('converted_files') \
                    .document()               # <-- auto ID

        # 4. Write
        doc_ref.set({
            'original_path': rel_path_str,
            'content': content,
            'hash': current_hash,
            'timestamp': firestore.SERVER_TIMESTAMP,
        })

        print(f"    -> Uploaded (doc_id={doc_ref.id})")
        return current_hash, doc_ref.id          # <-- RETURN BOTH!

    except Exception as e:
        print(f"    -> FAILED {rel_path_str}: {e}")
        return None

def generate_tree_text(root_path: Path, allowed_extensions: list = None, prefix: str = "") -> str:
    """
    Recursively generates a tree structure string for a directory,
    optionally filtering by file extensions and omitting empty directories.
    """
    lines = []
    
    # Prepare the filter
    dot_extensions = None
    if allowed_extensions:
        dot_extensions = [f".{ext.lstrip('.').lower()}" for ext in allowed_extensions]

    # Get all items in the current directory
    try:
        items = sorted(
            [item for item in root_path.iterdir() if '.git' not in item.parts and '__pycache__' not in item.parts and item.name != '.DS_Store']
        )
    except FileNotFoundError:
        return "" # Directory might have been deleted during sync

    # --- THIS IS THE IMPROVED LOGIC ---
    # We need to filter the items we're going to display *before* we loop
    displayable_items = []
    for item in items:
        if item.is_dir():
            # For a directory, we only include it if it will contain matching files
            # This is a recursive check, so it's accurate.
            if generate_tree_text(item, allowed_extensions=allowed_extensions):
                displayable_items.append(item)
        elif item.is_file():
            # For a file, we check its extension against the filter
            if not dot_extensions or item.suffix.lower() in dot_extensions:
                displayable_items.append(item)
    # --- END OF IMPROVEMENT ---

    for i, item in enumerate(displayable_items):
        is_last = (i == len(displayable_items) - 1)
        connector = "└── " if is_last else "├── "
        
        if item.is_dir():
            lines.append(f"{prefix}{connector}{item.name}/")
            new_prefix = prefix + ("    " if is_last else "│   ")
            # The recursive call will now only be on non-empty, relevant directories
            lines.append(generate_tree_text(item, allowed_extensions=allowed_extensions, prefix=new_prefix))
        else: # It must be a file
            lines.append(f"{prefix}{connector}{item.name}")

    return "\n".join(lines)

def token_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # This check should only run on the actual POST/GET request, not the OPTIONS preflight.
        # Flask and flask-cors handle this automatically.
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return jsonify({'error': 'Authorization header is missing or invalid'}), 401
        
        id_token = auth_header.split('Bearer ')[1]
        
        try:
            decoded_token = auth.verify_id_token(id_token)
            request.user_id = decoded_token['uid']
        except Exception as e:
            return jsonify({'error': f'Token verification failed: {e}'}), 401

        return f(*args, **kwargs)
    return decorated_function

# cache
class SimpleL1Cache:
    def __init__(self, max_size=256, ttl=10):
        """
        A simple in-memory LRU (Least Recently Used) cache.
        :param max_size: The maximum number of items to store.
        :param ttl: Time-to-live in seconds for each item.
        """
        self.cache = OrderedDict()
        self.max_size = max_size
        self.ttl = ttl

    def get(self, key):
        if key not in self.cache:
            return None
        
        value, expiry = self.cache[key]
        
        # Check if the item has expired
        if time.time() > expiry:
            del self.cache[key]
            return None
            
        # Move the item to the end to mark it as recently used
        self.cache.move_to_end(key)
        return value

    def set(self, key, value):
        # Check if we need to make space
        if len(self.cache) >= self.max_size:
            # Remove the oldest item
            self.cache.popitem(last=False)
            
        expiry = time.time() + self.ttl
        self.cache[key] = (value, expiry)

L1_CACHE = SimpleL1Cache(max_size=512, ttl=20) # Store 512 items for 20 seconds

        