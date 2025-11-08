import pytesseract
import PyPDF2 
from pdf2image import convert_from_bytes
from PIL import Image
from langchain_text_splitters import RecursiveCharacterTextSplitter

def extract_text(pdf_stream):
    """Extracts text from a PDF stream, falling back to OCR if needed."""
    print("  🔍 Attempting direct text extraction from PDF...")
    text = ""
    try:
        reader = PyPDF2.PdfReader(pdf_stream)
        print(f"  📄 PDF has {len(reader.pages)} pages.")
        for i, page in enumerate(reader.pages):
            page_text = page.extract_text() or ""
            text += page_text
        print(f"  ✅ PyPDF2 extracted {len(text)} characters.")
    except Exception as e:
        print(f"  ⚠️ PyPDF2 failed: {e}")
    
    # If direct extraction yields very little text, attempt OCR as a fallback
    if len(text.strip()) < 100 * len(reader.pages):
        print("  🔄 Text seems short, trying OCR fallback...")
        try:
            pdf_stream.seek(0) # Reset stream pointer
            images = convert_from_bytes(pdf_stream.read())
            print(f"  📸 Converted PDF to {len(images)} images for OCR.")
            ocr_text = ""
            for i, img in enumerate(images):
                page_text = pytesseract.image_to_string(img)
                ocr_text += page_text
            text = ocr_text
            print(f"  ✅ OCR extracted {len(text)} characters.")
        except Exception as e:
            print(f"  ❌ OCR failed: {e}. Returning any text found so far.")
    
    return text

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
        # Recursively delete subcollections first
        for sub_coll_ref in doc.reference.collections():
            print(f"    Deleting subcollection: {sub_coll_ref.id}...")
            delete_collection(sub_coll_ref, batch_size)
        
        # Delete the document
        print(f"  - Deleting doc: {doc.id}")
        doc.reference.delete()
        deleted += 1

    # If there might be more documents, recurse
    if deleted >= batch_size:
        return delete_collection(coll_ref, batch_size)