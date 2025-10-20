# app.py (DEFINITIVE Final Version with OCR, Subcollections, and Secure API Key Handling)

import os
import google.generativeai as genai
import PyPDF2
from flask import Flask, request, jsonify, render_template
import markdown
import time
import firebase_admin
from firebase_admin import credentials, firestore
from langchain_text_splitters import RecursiveCharacterTextSplitter
import io
from pdf2image import convert_from_bytes
import pytesseract
from PIL import Image
from dotenv import load_dotenv # <-- ADD THIS IMPORT

# --- Load Environment Variables ---
# This line loads the variables from your .env file (e.g., GEMINI_API_KEY)
load_dotenv() # <-- ADD THIS LINE

# --- OCR Configuration (Windows Users MUST do this) ---
try:
    # IMPORTANT: Update this path if you are on Windows
    pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'
except:
    print("Tesseract path not explicitly set. Assuming it's in the PATH or on a non-Windows OS.")


# --- Configuration & Initialization ---
# MODIFIED: Get the API key from the environment variables
API_KEY = os.getenv("GEMINI_API_KEY") 
if not API_KEY:
    raise ValueError("GEMINI_API_KEY not found. Please set it in your .env file.")

genai.configure(api_key=API_KEY)

# It's also a good practice to load the Firebase credentials path from .env if you want
# For now, we'll assume firebase-credentials.json is present locally but ignored by git
cred = credentials.Certificate("firebase-credentials.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

app = Flask(__name__)

# --- Helper Function for splitting the note (for HTML storage) ---
def split_large_string(text, chunk_size=900000): 
    """Splits a large string into chunks safely under the 1MB Firestore limit."""
    return [text[i:i+chunk_size] for i in range(0, len(text), chunk_size)]

# --- Helper Function for batching lists (for Q&A chunks storage) ---
def batch_list(data, batch_size=100):
    """Yield successive n-sized chunks from a list."""
    for i in range(0, len(data), batch_size):
        yield data[i:i + batch_size]

# --- MODIFIED Helper Function to include OCR ---
def extract_text_from_pdf_with_ocr(file_stream):
    """
    Tries to extract text directly from a PDF. If that fails (e.g., it's a scanned PDF), 
    it falls back to converting pages to images and running OCR (Tesseract).
    """
    # Read the entire file content into memory as bytes
    file_bytes = file_stream.read()
    
    # 1. First, try the fast direct text extraction (PDFs with text layers)
    text = ""
    try:
        reader = PyPDF2.PdfReader(io.BytesIO(file_bytes))
        for page in reader.pages:
            text += page.extract_text() or ""
    except Exception as e:
        print(f"PyPDF2 direct extraction failed: {e}")

    # 2. If direct extraction yields little or no text, perform OCR
    if len(text.strip()) < 100:
        print("Direct text extraction failed or insufficient. Falling back to OCR...")
        ocr_text = ""
        try:
            # You might need to specify poppler_path for convert_from_bytes on Windows
            # poppler_path=r"C:\path\to\poppler-xx\bin"
            images = convert_from_bytes(file_bytes) 
            for i, image in enumerate(images):
                print(f"  - OCR on page {i+1}...")
                ocr_text += pytesseract.image_to_string(image, lang='eng') # Specify language if needed
            text = ocr_text
        except Exception as ocr_error:
            print(f"An error occurred during OCR: {ocr_error}. Is Tesseract and Poppler installed and configured?")
            return text
            
    return text

# --- Helper Functions (Remaining ones are perfect) ---
def split_into_chunks(text):
    text_splitter = RecursiveCharacterTextSplitter(chunk_size=1500, chunk_overlap=200, length_function=len)
    return text_splitter.split_text(text)

def generate_note_for_text(text):
    model = genai.GenerativeModel('gemini-2.5-flash') # Using 1.5-flash as it's a newer, efficient model
    prompt = f"""
    You are an expert universal study assistant. Your mission is to transform dense academic texts from **any language** into simplified, well-structured, and easy-to-understand study notes.

    Your output should be in the **same language as the source text**, enhanced with specific annotations. Follow these rules meticulously to create the perfect study guide.

    **1. 🎯 Core Mission: Comprehensive Distillation**
    *   Your primary goal is to distill the *entire* document. Do not skip any major topics or concepts.
    *   Process the text section by section, ensuring your notes mirror the structure and flow of the original document.
    *   Extract the most critical information—key definitions, core arguments, and important examples. Discard repetitive fluff and unnecessary details.

    **2. 💡 The Golden Rule: Radical Simplification**
    *   This is your most important task. Your priority is to make the content understandable to someone who finds the original text difficult.
    *   **Simplify In-Language First:** Before anything else, rewrite complex sentences and vocabulary using simpler words and shorter sentences *in the original language of the text*.
        *   **Example:** If the source text (in English) says "leverage synergistic paradigms," you should rewrite it as "use teamwork effectively."
        *   **Example:** If the source text (in Spanish) says "implementar una metodología vanguardista," you might rewrite it as "usar un método nuevo y moderno."
    *   Break down long paragraphs into easy-to-digest bullet points or short, numbered lists.

    **3. ✍️ Annotation Rule: Chinese Translation**
    *   Identify all key technical terms, important concepts, and any words that might be unfamiliar to a student.
    *   **Immediately after** the simplified term in the original language, add its **Chinese translation** in parentheses.
        *   **English Example:** "This process is called **photosynthesis (光合作用)**, which is how plants make their own food."
        *   **Japanese Example:** "これは**量子力学 (量子力学)**の基本原則です。"

    **4. 🎨 Structure and Engagement**
    *   **Headings and Emojis:** Use markdown headings (`#`, `##`) for clear structure. Add a relevant emoji next to each main heading to make it visually engaging and signal its purpose (e.g., 🔍 for Definitions, ⚙️ for Processes, ✅ for Key Takeaways).
    *   **Formatting:** Use **bold text** for key terms, `code blocks` for formulas or specific names, and tables to organize comparisons.
    *   **Tone:** Adopt a friendly, encouraging, and conversational tone. Act like a helpful tutor explaining things one-on-one. Use simple analogies to clarify abstract ideas.

    **5. 🧠 Memory Aid: Mnemonic Tip**
    *   At the end of each major section, create a short, creative **Mnemonic Tip**. This could be an acronym, a simple rhyme, or a memorable phrase to help the student recall the main points of that section.

    **Constraint:**
    *   You must not add any new information that is not present in the original text. Your role is to simplify and structure, not to add external knowledge.

    Here is the text to process:
    ---
    {text}
    ---
    """
    response = model.generate_content(prompt)
    generated_note_markdown = response.text
    return markdown.markdown(generated_note_markdown, extensions=['tables'])

# --- Main App Routes ---
@app.route('/')
def dashboard():
    """Renders the main project dashboard."""
    return render_template('dashboard.html')

@app.route('/workspace/<project_id>')
def workspace(project_id):
    """Renders the workspace for a specific project."""
    project_doc = db.collection('projects').document(project_id).get()
    if not project_doc.exists:
        return "Project not found", 404
    project_name = project_doc.to_dict().get('name', 'Untitled Project')
    return render_template('workspace.html', project_id=project_id, project_name=project_name)

# --- Dashboard API Endpoints ---
@app.route('/get-projects', methods=['GET'])
def get_projects():
    try:
        projects_ref = db.collection('projects').order_by('timestamp', direction=firestore.Query.DESCENDING).stream()
        projects = [{"id": proj.id, "name": proj.to_dict().get('name')} for proj in projects_ref]
        return jsonify(projects)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/create-project', methods=['POST'])
def create_project():
    project_name = request.get_json().get('name')
    if not project_name:
        return jsonify({"error": "Project name is required"}), 400
    try:
        doc_ref = db.collection('projects').document()
        doc_ref.set({'name': project_name, 'timestamp': firestore.SERVER_TIMESTAMP})
        return jsonify({"success": True, "id": doc_ref.id})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# --- Workspace API Endpoints ---
@app.route('/get-sources/<project_id>', methods=['GET'])
def get_sources(project_id):
    try:
        sources_ref = db.collection('projects').document(project_id).collection('sources').stream()
        sources = [{"id": source.id, "filename": source.to_dict().get('filename')} for source in sources_ref]
        return jsonify(sources)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/upload-source/<project_id>', methods=['POST'])
def upload_source(project_id):
    files = request.files.getlist('pdfs')
    if not files: return jsonify({"error": "No files selected"}), 400
    
    processed_files = []
    try:
        for file in files:
            print(f"Processing file with OCR support: {file.filename}...")
            
            file.stream.seek(0)
            text = extract_text_from_pdf_with_ocr(file.stream)
            
            if not text.strip(): 
                print(f"Could not extract any text from {file.filename}, skipping.")
                continue

            note_html = generate_note_for_text(text)
            qna_chunks = split_into_chunks(text)
            
            source_ref = db.collection('projects').document(project_id).collection('sources').document(file.filename)
            
            source_ref.set({
                'filename': file.filename,
                'timestamp': firestore.SERVER_TIMESTAMP
            })
            
            note_pages_ref = source_ref.collection('note_pages')
            for doc in note_pages_ref.stream(): doc.reference.delete()
            for i, note_part in enumerate(split_large_string(note_html)):
                note_pages_ref.document(f'page_{i}').set({'content': note_part})

            qna_pages_ref = source_ref.collection('qna_pages')
            for doc in qna_pages_ref.stream(): doc.reference.delete()
            for i, qna_batch in enumerate(batch_list(qna_chunks, batch_size=100)):
                qna_pages_ref.document(f'page_{i}').set({'content': qna_batch})
            
            processed_files.append(file.filename)
            time.sleep(1) 
        return jsonify({"success": True, "processed_files": processed_files})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/get-note/<project_id>/<source_id>', methods=['GET'])
def get_note(project_id, source_id):
    try:
        note_pages_ref = db.collection('projects').document(project_id).collection('sources').document(source_id).collection('note_pages').stream()
        note_parts = [doc.to_dict().get('content', '') for doc in note_pages_ref]
        full_note_html = "".join(note_parts)
        
        if not full_note_html:
            return jsonify({"error": "Note pages not found or note is empty."}), 404

        return jsonify({"note_html": full_note_html})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/ask-chatbot/<project_id>', methods=['POST'])
def ask_chatbot(project_id):
    data = request.get_json()
    question, source_id, history = data.get('question'), data.get('source_id'), data.get('history', [])
    if not question: return jsonify({"error": "No question provided"}), 400

    try:
        all_chunks = []
        source_refs = []

        if source_id:
            source_refs.append(db.collection('projects').document(project_id).collection('sources').document(source_id))
        else:
            source_refs = db.collection('projects').document(project_id).collection('sources').list_documents()

        for source_ref in source_refs:
            qna_pages = source_ref.collection('qna_pages').stream()
            source_id_name = source_ref.id
            
            for page in qna_pages:
                chunks_from_page = page.to_dict().get('content', [])
                for chunk in chunks_from_page:
                    all_chunks.append({"text": chunk, "source": source_id_name})
        
        if not all_chunks:
            return jsonify({"answer": "This project is empty. Please upload documents to this project first."})

        question_words = set(question.lower().split())
        relevant_chunks = [c for c in all_chunks if any(word in c['text'].lower() for word in question_words)]
        
        if not relevant_chunks: relevant_chunks = all_chunks[:5]

        context = "\n---\n".join([f"Source: {c['source']}\nContent: {c['text']}" for c in relevant_chunks[:5]])

        formatted_history = "\n".join([f"{'User' if msg['role'] == 'user' else 'Model'}: {msg['content']}" for msg in history])
        model = genai.GenerativeModel('gemini-2.5-flash')
        
        prompt = f"""
        You are an AI study assistant. Answer the user's NEW QUESTION using the SOURCE MATERIAL and CONVERSATION HISTORY.
        Base your answer ONLY on the source material. If the answer isn't there, state that the information is not in the sources.
        
        --- SOURCE MATERIAL (Context derived from relevant document chunks) ---
        {context}
        --- END SOURCE ---
        
        --- CONVERSATION HISTORY ---
        {formatted_history}
        --- END HISTORY ---
        
        NEW QUESTION: {question}\nANSWER:"""
        
        response = model.generate_content(prompt)
        return jsonify({"answer": response.text})

    except Exception as e:
        print(f"Chatbot error: {e}")
        return jsonify({"error": f"An error occurred while communicating with the chatbot: {str(e)}"}), 500

if __name__ == '__main__':
    app.run(debug=True)