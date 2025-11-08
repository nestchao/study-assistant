import json
import mimetypes
from flask import Blueprint, request, jsonify
from firebase_admin import firestore
from utils import extract_text_from_image, extract_text
import google.generativeai as genai

# --- BLUEPRINT SETUP ---
paper_solver_bp = Blueprint('paper_solver_bp', __name__)
db = None
genai_model = None

def set_dependencies(db_instance, genai_instance):
    """Injects dependencies from the main app."""
    global db, genai_model
    db = db_instance
    genai_model = genai_instance

# ... (solve_paper_with_file and solve_paper_with_text functions are fine) ...
def get_project_context(project_id):
    """Fetches all text chunks from all sources in a project."""
    all_chunks = []
    sources_ref = db.collection('projects').document(project_id).collection('sources')
    for source_doc in sources_ref.stream():
        chunks_ref = source_doc.reference.collection('chunks')
        for chunk_doc in chunks_ref.stream():
            all_chunks.extend(chunk_doc.to_dict().get('chunks', []))
    context = "\n---\n".join(all_chunks)
    print(f"  📚 Retrieved context of {len(context)} characters for project {project_id}")
    return context

def solve_paper_with_file(file_stream, filename, context):
    """
    Uploads a file directly to the Gemini API and asks it to solve the paper.
    """
    print("  🧠 Solving paper using direct file (multimodal) method...")
    print("    - Uploading file to Gemini API...")
    file_stream.seek(0)
    mime_type, _ = mimetypes.guess_type(filename)
    if mime_type is None:
        mime_type = "application/octet-stream"
    print(f"    - Inferred MIME type for upload: {mime_type}")
    uploaded_file = genai.upload_file(
        path=file_stream,
        display_name=filename,
        mime_type=mime_type
    )
    print(f"    - File uploaded successfully. URI: {uploaded_file.uri}")
    prompt = f"""
    You are an expert exam solver. Based ONLY on the provided CONTEXT and the attached FILE, answer the questions from the file.
    The file contains a past exam paper which may include images, diagrams, and complex layouts.
    For each question you can identify, provide a clear, concise, and accurate answer in markdown format.
    Format your entire output as a valid JSON array of objects, where each object has a "question" and "answer" key. Do not include any other text or explanations outside of the JSON array.
    
    CONTEXT:
    ---
    {context}
    ---
    
    FILE:
    (See attached file: {filename})
    
    JSON OUTPUT:
    """
    print("    - Generating content from file and context...")
    response = genai_model.generate_content([prompt, uploaded_file])
    print(f"    - Deleting temporary file: {uploaded_file.name}")
    genai.delete_file(uploaded_file.name)
    cleaned_json_string = response.text.strip().replace('```json', '').replace('```', '')
    return json.loads(cleaned_json_string)

def solve_paper_with_text(file_stream, filename, context):
    """
    Extracts text from the file first and then sends it to the Gemini API.
    """
    print("  📝 Solving paper using text extraction (text-only) method...")
    paper_text = ""
    if filename.lower().endswith(('.png', '.jpg', '.jpeg')):
        paper_text = extract_text_from_image(file_stream)
    elif filename.lower().endswith('.pdf'):
        paper_text = extract_text(file_stream)
    if not paper_text.strip():
        raise ValueError(f"Could not extract any text from '{filename}'.")
    prompt = f"""
    You are an expert exam solver. Based ONLY on the provided CONTEXT, answer the questions from the PAST PAPER TEXT.
    For each question, provide a clear, concise, and accurate answer in markdown format.
    Format your entire output as a valid JSON array of objects, where each object has a "question" and "answer" key. Do not include any other text or explanations outside of the JSON array.
    CONTEXT:
    ---
    {context}
    ---
    PAST PAPER TEXT:
    ---
    {paper_text}
    ---
    JSON OUTPUT:
    """
    response = genai_model.generate_content(prompt)
    cleaned_json_string = response.text.strip().replace('```json', '').replace('```', '')
    return json.loads(cleaned_json_string)


@paper_solver_bp.route('/get-papers/<project_id>')
def get_papers(project_id):
    try:
        papers_ref = db.collection('projects').document(project_id).collection('past_papers').order_by('timestamp', direction=firestore.Query.DESCENDING)
        # The .to_dict() method correctly converts Firestore Timestamps to Python datetimes, which are JSON serializable
        papers = [{"id": doc.id, **doc.to_dict()} for doc in papers_ref.stream()]
        return jsonify(papers)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@paper_solver_bp.route('/upload-paper/<project_id>', methods=['POST'])
def upload_paper(project_id):
    print(f"📄 UPLOAD PAST PAPER request for project: {project_id}")
    
    if 'paper' not in request.files:
        return jsonify({"error": "No 'paper' file provided"}), 400
    
    analysis_mode = request.form.get('analysis_mode', 'text_only')
    file = request.files['paper']
    filename = file.filename
    print(f"  Processing file: {filename} with mode: {analysis_mode}")

    try:
        context = get_project_context(project_id)
        
        qa_pairs = []
        if analysis_mode == 'multimodal':
            qa_pairs = solve_paper_with_file(file.stream, filename, context)
        else:
            qa_pairs = solve_paper_with_text(file.stream, filename, context)

        paper_ref = db.collection('projects').document(project_id).collection('past_papers').document()
        
        # --- THIS IS THE FIX ---

        # 1. This dictionary is for saving to the database. It contains the Sentinel.
        paper_data_for_db = {
            "filename": filename,
            "timestamp": firestore.SERVER_TIMESTAMP,
            "qa_pairs": qa_pairs,
            "analysis_mode": analysis_mode
        }
        paper_ref.set(paper_data_for_db)

        # 2. This dictionary is for the JSON response. It does NOT contain the Sentinel.
        response_data = {
            "id": paper_ref.id,
            "filename": filename,
            "qa_pairs": qa_pairs,
            "analysis_mode": analysis_mode
            # The client doesn't need the timestamp immediately. It will get it on the next fetch.
        }

        # 3. Return the safe dictionary.
        return jsonify(response_data), 200

        # --- END OF FIX ---

    except Exception as e:
        import traceback
        print(f"❌ Error processing past paper: {e}")
        print(traceback.format_exc())
        return jsonify({"error": str(e)}), 500