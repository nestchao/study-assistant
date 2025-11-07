import pytesseract
from pdf2image import convert_from_bytes
from PIL import Image # Add this import: pip install Pillow

# Make sure this path is correct for your system
try:
    pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'
except Exception:
    print("Warning: Tesseract path not found. OCR will fail if needed.")

def extract_text(pdf_stream):
    """OCR + Text Extract with logging"""
    print("  🔍 Attempting text extraction...")
    text = ""
    
    try:
        reader = PyPDF2.PdfReader(pdf_stream)
        print(f"  📄 PDF has {len(reader.pages)} pages")
        
        for i, page in enumerate(reader.pages):
            page_text = page.extract_text() or ""
            text += page_text
            if i == 0:
                print(f"  ✓ Page 1 extracted: {len(page_text)} chars")
        
        print(f"  ✅ PyPDF2 extracted: {len(text)} chars total")
    except Exception as e:
        print(f"  ⚠️  PyPDF2 failed: {e}")
    
    if len(text.strip()) < 100:
        print("  🔄 Text too short, trying OCR...")
        try:
            pdf_stream.seek(0)
            images = convert_from_bytes(pdf_stream.read())
            print(f"  📸 Converted to {len(images)} images")
            
            ocr_text = ""
            for i, img in enumerate(images):
                page_text = pytesseract.image_to_string(img)
                ocr_text += page_text
                if i == 0:
                    print(f"  ✓ OCR page 1: {len(page_text)} chars")
            
            text = ocr_text
            print(f"  ✅ OCR extracted: {len(text)} chars total")
        except Exception as e:
            print(f"  ❌ OCR failed: {e}")
    
    return text

def extract_text_from_image(image_stream):
    """Extracts text from an image file stream using OCR."""
    print("  🖼️  Extracting text from image via OCR...")
    try:
        image = Image.open(image_stream)
        text = pytesseract.image_to_string(image)
        print(f"  ✅ OCR extracted {len(text)} characters from image.")
        return text
    except Exception as e:
        print(f"  ❌ Image OCR failed: {e}")    
        return ""

def delete_collection(coll_ref, batch_size):
    """
    Recursively deletes all documents and subcollections within a collection.
    """
    docs = coll_ref.limit(batch_size).stream()
    deleted = 0

    for doc in docs:
        print(f"  Deleting doc: {doc.id}")
        # Recursively delete subcollections
        for sub_coll_ref in doc.reference.collections():
            print(f"    Found subcollection: {sub_coll_ref.id}. Deleting...")
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