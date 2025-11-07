# backend/paper_solver_routes.py
from flask import Blueprint, request, jsonify
from firebase_admin import firestore
from utils import extract_text_from_image # We'll use the shared utility function

# --- BLUEPRINT SETUP ---
paper_solver_bp = Blueprint('paper_solver_bp', __name__)
db = None
genai_model = None

def set_dependencies(db_instance, genai_instance):
    """Injects dependencies from the main app."""
    global db, genai_model
    db = db_instance
    genai_model = genai_instance

def get_project_context(project_id):
    """Fetches all text chunks from all sources in a project."""
    all_chunks = []
    sources_ref = db.collection('projects').document(project_id).collection('sources')
    for source_doc in sources_ref.stream():
        chunks_ref = source_doc.reference.collection('chunks')
        for chunk_doc in chunks_ref.stream():
            all_chunks.extend(chunk_doc.to_dict().get('chunks', []))
    
    # Join the first 30 chunks for a reasonably sized context
    context = "\n---\n".join(all_chunks[:30])
    print(f"  📚 Retrieved context of {len(context)} characters for project {project_id}")
    return context

# --- ROUTES ---
@paper_solver_bp.route('/get-papers/<project_id>')
def get_papers(project_id):
    try:
        papers_ref = db.collection('projects').document(project_id).collection('past_papers').order_by('timestamp', direction=firestore.Query.DESCENDING)
        papers = []
        for doc in papers_ref.stream():
            paper_data = doc.to_dict()
            papers.append({
                "id": doc.id,
                "filename": paper_data.get("filename"),
                "qa_pairs": paper_data.get("qa_pairs", [])
            })
        return jsonify(papers)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@paper_solver_bp.route('/upload-paper/<project_id>', methods=['POST'])
def upload_paper(project_id):
    """
    NEW ROUTE: This is where you'll put the logic to handle past paper uploads.
    This will involve OCR, calling Gemini with context, and saving the Q&A pairs.
    """
    print(f"📄 UPLOAD PAST PAPER request for project: {project_id}")
    
    if 'paper' not in request.files:
        return jsonify({"error": "No 'paper' file provided"}), 400
    
    file = request.files['paper']
    filename = file.filename
    print(f"  Processing file: {filename}")

    try:
        # 1. Get context from existing study materials
        context = get_project_context(project_id)
        
        # 2. Extract questions from the uploaded paper (using OCR)
        # This assumes the paper is an image. You'll need to handle PDFs differently.
        if filename.lower().endswith(('.png', '.jpg', '.jpeg')):
            paper_text = extract_text_from_image(file.stream)
        else:
            # Add PDF extraction logic if needed
            return jsonify({"error": "Unsupported file type for papers (only images supported for now)"}), 400

        # 3. Call Gemini to answer the questions based on the context
        prompt = f"""
        You are an expert exam solver. Based ONLY on the provided CONTEXT, answer the following questions from the PAST PAPER TEXT.
        For each question, provide a clear, concise, and accurate answer.
        Format your entire output as a JSON array of objects, where each object has a "question" and "answer" key.
        
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
        # Clean up Gemini's response to be valid JSON
        cleaned_json_string = response.text.strip().replace('```json', '').replace('```', '')
        qa_pairs = json.loads(cleaned_json_string)

        # 4. Save to Firestore
        paper_ref = db.collection('projects').document(project_id).collection('past_papers').document()
        paper_ref.set({
            "filename": filename,
            "timestamp": firestore.SERVER_TIMESTAMP,
            "qa_pairs": qa_pairs
        })

        return jsonify({"success": True, "paper_id": paper_ref.id, "qa_pairs_found": len(qa_pairs)}), 201

    except Exception as e:
        import traceback
        print(f"❌ Error processing past paper: {e}")
        print(traceback.format_exc())
        return jsonify({"error": str(e)}), 500