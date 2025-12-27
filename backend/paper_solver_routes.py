import json
import mimetypes
from flask import Blueprint, request, jsonify
from firebase_admin import firestore
from utils import extract_text_from_image, extract_text
import google.generativeai as genai
from services import db, paper_solver_model, cache_manager, ai_client
import os
from browser_bridge import browser_bridge
import tempfile
import re

# --- BLUEPRINT SETUP ---
paper_solver_bp = Blueprint('paper_solver_bp', __name__)

def get_project_context(project_id):
    """Fetches all text chunks from all sources in a project with Caching."""
    
    cache_key = f"project_context:{project_id}"

    def fetch_context_from_db():
        print(f"  🏗️  Building context from Firestore for {project_id}...")
        all_chunks = []
        sources_ref = db.collection('projects').document(project_id).collection('sources')
        for source_doc in sources_ref.stream():
            chunks_ref = source_doc.reference.collection('chunks')
            for chunk_doc in chunks_ref.stream():
                all_chunks.extend(chunk_doc.to_dict().get('chunks', []))
        return "\n---\n".join(all_chunks)

    # Use CacheManager
    # We use a shorter TTL because users might upload new files frequently
    context = cache_manager.get_or_set(
        key=cache_key,
        factory=fetch_context_from_db,
        ttl_l1=60,    # 1 min memory
        ttl_l2=600    # 10 min Redis
    )
    
    print(f"  📚 Retrieved context of {len(context)} characters")
    return context

def solve_paper_with_file(file, filename, context):
    """
    Saves file to a temp location to allow Gemini API to upload it correctly.
    """
    print("  🧠 Solving paper using direct file (multimodal) method...")
    
    # Create a temporary file because genai.upload_file needs a PATH, not a stream
    with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(filename)[1]) as tmp:
        file.save(tmp.name)
        tmp_path = tmp.name

    try:
        print(f"    - Uploading {filename} to Gemini API...")
        mime_type, _ = mimetypes.guess_type(filename)
        if mime_type is None:
            mime_type = "application/octet-stream"

        uploaded_file = genai.upload_file(path=tmp_path, display_name=filename, mime_type=mime_type)
        
        prompt = f"""
        You are an expert exam solver. Based ONLY on the provided CONTEXT and the attached FILE, answer the questions from the file.
        CONTEXT:
        ---
        {context}
        ---
        Format your entire output as a valid JSON array of objects: [{{"question": "...", "answer": "..."}}].
        """
        
        response = ai_client.models.generate_content(
        model=paper_solver_model,
        contents=[prompt, uploaded_file]
    )
    
        # Cleanup
        genai.delete_file(uploaded_file.name)
        
        # --- FIX: Apply Regex Extraction here too ---
        raw_text = response.text
        match = re.search(r'\[.*\]', raw_text, re.DOTALL)
        if match:
            return json.loads(match.group(0))
        else:
            # Fallback cleaning
            cleaned_json_string = raw_text.strip().replace('```json', '').replace('```', '')
            return json.loads(cleaned_json_string)
    
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

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
    response = ai_client.models.generate_content(
        model=paper_solver_model,
        contents=prompt
    )
    cleaned = response.text.strip().replace('```json', '').replace('```', '')
    return json.loads(cleaned)


@paper_solver_bp.route('/get-papers/<project_id>')
def get_papers(project_id):
    try:
        papers_ref = db.collection('projects').document(project_id).collection('past_papers').order_by('timestamp', direction=firestore.Query.DESCENDING)
        
        # --- THIS IS THE FIX ---
        papers = []
        for doc in papers_ref.stream():
            data = doc.to_dict()
            
            # 1. Check if 'timestamp' exists and is not None
            if 'timestamp' in data and data['timestamp']:
                # 2. Convert the Python datetime object to a standard ISO 8601 string.
                #    This format ('2025-11-13T18:29:01.123Z') is universally understood.
                data['timestamp'] = data['timestamp'].isoformat()
            
            # 3. Combine the document ID with the processed data.
            papers.append({"id": doc.id, **data})
            
        print(f"  ✅ Found and serialized {len(papers)} past papers for project {project_id}.")
        return jsonify(papers)
        # --- END OF FIX ---

    except Exception as e:
        import traceback
        print(f"❌ Error in get_papers for project {project_id}: {e}")
        print(traceback.format_exc())
        return jsonify({"error": str(e)}), 500

@paper_solver_bp.route('/upload-paper/<project_id>', methods=['POST'])
def upload_paper(project_id):
    if 'paper' not in request.files:
        return jsonify({"error": "No paper file found"}), 400
    
    file = request.files['paper']
    filename = file.filename
    analysis_mode = request.form.get('analysis_mode', 'text_only')

    try:
        context = get_project_context(project_id)
        file.stream.seek(0) # IMPORTANT: Always seek to 0 before reading

        if analysis_mode == 'multimodal':
            # This uses the tempfile fix I provided in the previous message
            qa_pairs = solve_paper_with_file(file, filename, context)
        else:
            ext = filename.split('.')[-1].lower()
            if ext == 'pdf':
                paper_text = extract_text(file.stream)
            elif ext == 'pptx':
                from utils import extract_text_from_pptx
                paper_text = extract_text_from_pptx(file.stream)
            else:
                # Handle images
                paper_text = extract_text_from_image(file.stream)
            
            qa_pairs = solve_paper_with_text_logic(paper_text, context)

        paper_ref = db.collection('projects').document(project_id).collection('past_papers').document()
        
        paper_data_for_db = {
            "filename": filename,
            "timestamp": firestore.SERVER_TIMESTAMP,
            "qa_pairs": qa_pairs,
            "analysis_mode": analysis_mode
        }
        paper_ref.set(paper_data_for_db)

        response_data = {
            "id": paper_ref.id,
            "filename": filename,
            "qa_pairs": qa_pairs,
            "analysis_mode": analysis_mode
        }

        return jsonify(response_data), 200

    except Exception as e:
        import traceback
        print(f"❌ Error processing past paper: {e}")
        print(traceback.format_exc())
        return jsonify({"error": str(e)}), 500
    
@paper_solver_bp.route('/delete-paper/<project_id>/<paper_id>', methods=['DELETE'])
def delete_paper(project_id, paper_id):
    """Deletes a specific past paper document from Firestore."""
    print(f"🗑️ DELETE request for past paper: {paper_id} in project: {project_id}")
    try:
        paper_ref = db.collection('projects').document(project_id).collection('past_papers').document(paper_id)
        
        # Check if the document exists before trying to delete
        if not paper_ref.get().exists:
            print(f"  - Paper not found: {paper_id}")
            return jsonify({"error": "Past paper not found"}), 404

        paper_ref.delete()
        print(f"  ✅ Successfully deleted past paper: {paper_id}")
        return jsonify({"success": True, "message": "Past paper deleted successfully."}), 200
    except Exception as e:
        import traceback
        print(f"❌ Error deleting past paper {paper_id}: {e}")
        print(traceback.format_exc())
        return jsonify({"error": str(e)}), 500
    
def solve_paper_with_text_logic(paper_text, context):
    """
    Core logic to solve papers using the Browser Bridge (API Key Free).
    """
    if not paper_text.strip():
        raise ValueError("Could not extract any text from the file.")

    print("  🤖 Sending Paper Solver prompt via Browser Bridge...")

    prompt = f"""
    You are an expert exam solver. Based ONLY on the provided CONTEXT, answer the questions from the PAST PAPER TEXT.
    
    1. Answer every question found in the paper text.
    2. Be concise but accurate.
    3. Format your ENTIRE output as a valid JSON array of objects.
    4. Each object must have "question" and "answer" keys.
    5. Do NOT output markdown code blocks (```json). Just the raw JSON array.
    
    CONTEXT:
    ---
    {context[:30000]} 
    ---
    
    PAST PAPER TEXT:
    ---
    {paper_text}
    ---
    
    JSON OUTPUT (Example: [{{"question": "...", "answer": "..."}}]):
    """
    
    # --- USE BROWSER BRIDGE ---
    browser_bridge.start()
    raw_response = browser_bridge.send_prompt(prompt)
    
    print("  🧹 Cleaning AI Response...")

    # --- 🛠️ FIX START: Robust JSON Extraction ---
    try:
        # 1. Use Regex to find the JSON array (starts with [ and ends with ])
        #    re.DOTALL allows the dot (.) to match newlines
        match = re.search(r'\[.*\]', raw_response, re.DOTALL)
        
        if match:
            json_str = match.group(0)
            return json.loads(json_str)
        else:
            # Fallback: Try standard cleaning if regex fails
            cleaned = raw_response.strip()
            if cleaned.startswith("```json"):
                cleaned = cleaned.replace("```json", "", 1)
            if cleaned.startswith("```"):
                cleaned = cleaned.replace("```", "", 1)
            if cleaned.endswith("```"):
                cleaned = cleaned[:-3]
            return json.loads(cleaned.strip())

    except json.JSONDecodeError as e:
        print(f"  ⚠️ JSON Parse Error: {e}")
        # Only fallback to error message if we truly can't parse it
        return [{"question": "Parsing Error", "answer": f"Could not parse AI response. Raw output:\n\n{raw_response}"}]