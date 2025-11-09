import re
import markdown
import html2text
from flask import Blueprint, request, jsonify
from firebase_admin import firestore
from utils import L1_CACHE

# Import shared utility functions
from utils import extract_text, delete_collection, split_chunks, token_required
import redis

# --- BLUEPRINT SETUP ---
# Create a blueprint for study hub features
study_hub_bp = Blueprint('study_hub_bp', __name__)

# Global variables to hold dependencies injected from app.py
db = None
note_gen_model = None
chat_model = None
redis_client = None 

def set_dependencies(db_instance, note_model_instance, chat_model_instance, redis_instance):
    """Injects database and AI model dependencies from the main app."""
    global db, note_gen_model, chat_model, redis_client
    db = db_instance
    note_gen_model = note_model_instance
    chat_model = chat_model_instance
    print("✅ Study Hub dependencies injected.")
    redis_client = redis_instance

# --- HELPER FUNCTIONS for Study Hub ---

def generate_note(text):
    """Generates a simplified study note using the injected AI model."""
    print("  🤖 Generating AI study note...")
    prompt = f"""
    You are an expert academic study assistant. Your mission is to transform dense academic texts into simplified, well-structured study notes that are easy to understand, while strictly preserving the original document's structure.

    Your output must be in the **same language as the source text**. Follow these rules meticulously.

    **0. 🏛️ The Golden Rule: Preserve the Original Structure**
    *   This is your most important command. You MUST follow the structure, headings, and topic order of the original text EXACTLY.
    *   Do not merge sections, re-order paragraphs, or write new introductory paragraphs. Your task is to simplify the content *within* each original section.

    **1. 💡 The Simplification Rule: Clarify In-Place**
    *   Replace complex, technical, or academic words with simpler, more common equivalents in the same language.
    *   Break down long, complex sentences into shorter, clearer ones.

    **2. ✍️ The Annotation Rule: Translate Simplified Words**
    *   For **every single word** that you simplified, you MUST provide its Chinese translation immediately after.
    *   Format: `new simplified word (中文翻译)`. Example: "The **widespread (普遍的)** nature of the **event (事件)**..."

    **3. 🎨 The Formatting & Tone Rule: Be Clear and Direct**
    *   Use markdown headings (`#`, `##`) that match the original text's structure. Add a relevant emoji to each main heading.
    *   Use **bold text** to emphasize key simplified concepts.
    *   Adopt a clear, direct, and helpful academic tone.

    **4. 🎯 The Content Rule: Be Comprehensive and Accurate**
    *   Cover all major topics and key concepts from the original text. Do not skip sections.
    *   Extract only the most critical information—definitions, key arguments, and essential examples.

    **5. 🧠 The Memory Aid Rule: Add a Mnemonic Tip (记忆技巧)**
    *   At the end of each major section, create a short, creative Mnemonic Tip (记忆技巧) to help recall the main points.

    **Constraint:**
    *   You must not add any new information that is not present in the original text.

    Here is the text to process:
    ---
    {text}
    ---
    """
    try:
        # Use the injected note_gen_model
        response = note_gen_model.generate_content(prompt)
        return markdown.markdown(response.text)
    except Exception as e:
        print(f"  ❌ Note generation failed: {e}")
        raise

def get_simplified_note_context(project_id, source_id=None):
    """Fetches and combines all simplified note pages into clean text for the chatbot."""
    print(f"  📚 Retrieving simplified note context for project {project_id}...")
    full_html_content = ""
    sources_to_query = []

    if source_id:
        source_ref = db.collection('projects').document(project_id).collection('sources').document(source_id)
        sources_to_query.append(source_ref)
    else:
        sources_stream = db.collection('projects').document(project_id).collection('sources').stream()
        sources_to_query = [source.reference for source in sources_stream]

    for source_ref in sources_to_query:
        pages_query = source_ref.collection('note_pages').order_by('order').stream()
        for page in pages_query:
            full_html_content += page.to_dict().get('html', '')

    if not full_html_content:
        print("  ⚠️ No note content found.")
        return ""

    # Convert HTML back to clean text for the AI model
    h = html2text.HTML2Text()
    h.ignore_links = True
    h.ignore_images = True
    clean_text = h.handle(full_html_content)
    
    print(f"  ✅ Assembled {len(clean_text)} characters of simplified note text.")
    return clean_text

# --- ROUTES ---

@study_hub_bp.route('/get-projects', methods=['GET'])
def get_projects():
    docs = db.collection('projects').order_by('timestamp', direction=firestore.Query.DESCENDING).stream()
    projects = [{"id": d.id, "name": d.to_dict().get('name')} for d in docs]
    return jsonify(projects)

@study_hub_bp.route('/create-project', methods=['POST'])
@token_required 
def create_project():
    name = request.json.get('name')
    user_id = request.user_id # <-- Get the verified user ID from the decorator
    
    ref = db.collection('projects').document()
    # --- ADD THE userId TO THE DOCUMENT ---
    ref.set({
        'name': name,
        'timestamp': firestore.SERVER_TIMESTAMP,
        'userId': user_id 
    })
    return jsonify({"id": ref.id})

@study_hub_bp.route('/rename-project/<project_id>', methods=['PUT'])
def rename_project(project_id):
    new_name = request.json.get('new_name')
    if not new_name:
        return jsonify({"success": False, "error": "New name not provided"}), 400
    try:
        project_ref = db.collection('projects').document(project_id)
        project_ref.update({'name': new_name})
        return jsonify({"success": True, "message": f"Project renamed to {new_name}."}), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@study_hub_bp.route('/delete-project/<project_id>', methods=['DELETE'])
def delete_project(project_id):
    print(f"\n🗑️  DELETE REQUEST for project: {project_id}")
    try:
        project_ref = db.collection('projects').document(project_id)
        for collection_ref in project_ref.collections():
            delete_collection(collection_ref, batch_size=50)
        project_ref.delete()
        print(f"✅ Successfully deleted project: {project_id}")
        return jsonify({"success": True}), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@study_hub_bp.route('/get-sources/<project_id>', methods=['GET'])
def get_sources(project_id):
    docs = db.collection('projects').document(project_id).collection('sources').stream()
    sources = [{"id": d.id, "filename": d.to_dict().get('filename')} for d in docs]
    return jsonify(sources)

@study_hub_bp.route('/upload-source/<project_id>', methods=['POST'])
def upload_source(project_id):
    print(f"\n📁 UPLOAD REQUEST for project: {project_id}")
    if 'pdfs' not in request.files:
        return jsonify({"error": "No files provided", "success": False}), 400
    
    files = request.files.getlist('pdfs')
    if not files or files[0].filename == '':
        return jsonify({"error": "No files selected", "success": False}), 400
    
    processed, errors = [], []
    for file in files:
        filename = file.filename
        safe_id = re.sub(r'[.#$/[\]]', '_', filename) # Make filename Firestore-safe
        print(f"\n🔄 Processing '{filename}'...")
        try:
            file.stream.seek(0)
            text = extract_text(file.stream)
            if not text.strip():
                errors.append({"filename": filename, "error": "No text could be extracted."})
                continue

            source_ref = db.collection('projects').document(project_id).collection('sources').document(safe_id)
            source_ref.set({'filename': filename, 'timestamp': firestore.SERVER_TIMESTAMP, 'character_count': len(text)})
            
            note_html = generate_note(text)
            
            # Save note in chunks to avoid Firestore document size limits
            chunk_size = 900000 
            for i in range(0, len(note_html), chunk_size):
                chunk = note_html[i:i+chunk_size]
                page_num = i // chunk_size
                source_ref.collection('note_pages').document(f'page_{page_num}').set({'html': chunk, 'order': page_num})
            
            # Save original text chunks for context-aware features
            text_chunks = split_chunks(text)
            for i in range(0, len(text_chunks), 100):
                batch = text_chunks[i:i+100]
                page_num = i // 100
                source_ref.collection('chunks').document(f'page_{page_num}').set({'chunks': batch, 'order': page_num})
            
            processed.append({"filename": filename, "id": safe_id})
            print(f"✅ SUCCESS: '{filename}' processed.")
        except Exception as e:
            import traceback
            print(f"❌ CRITICAL ERROR processing '{filename}': {e}")
            traceback.print_exc()
            errors.append({"filename": filename, "error": str(e)})

    return jsonify({"success": len(processed) > 0, "processed": processed, "errors": errors})

@study_hub_bp.route('/delete-source/<project_id>/<path:source_id>', methods=['DELETE'])
def delete_source(project_id, source_id):
    print(f"\n🗑️  DELETE REQUEST for source: {source_id}")
    try:
        source_ref = db.collection('projects').document(project_id).collection('sources').document(source_id)
        for collection_ref in source_ref.collections():
            delete_collection(collection_ref, batch_size=50)
        source_ref.delete()

        if redis_client:
            try:
                note_redis_key = f"note:{project_id}:{source_id}"
                redis_client.delete(note_redis_key)
                print(f"✅ Invalidated Redis cache for deleted source: {note_redis_key}")
            except Exception as e:
                print(f"⚠️ Failed to invalidate note cache for deleted source: {e}")

        print(f"✅ Successfully deleted source document: {source_id}")
        return jsonify({"success": True, "message": f"Source {source_id} deleted."}), 200

    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@study_hub_bp.route('/get-note/<project_id>/<path:source_id>')
def get_note(project_id, source_id):
    note_key = f"note:{project_id}:{source_id}"

    # 1. Check Level 1 Cache (In-Memory)
    cached_html = L1_CACHE.get(note_key)
    if cached_html:
        print(f"✅ L1 CACHE HIT for note: {note_key}")
        return jsonify({"note_html": cached_html})

    # 2. Check Level 2 Cache (Redis)
    if redis_client:
        try:
            cached_html_bytes = redis_client.get(note_key)
            if cached_html_bytes:
                print(f"✅ L2 CACHE HIT (Redis) for note: {note_key}")
                html_content = cached_html_bytes.decode('utf-8')
                # Backfill L1 Cache
                L1_CACHE.set(note_key, html_content)
                return jsonify({"note_html": html_content})
        except Exception as e:
            print(f"⚠️ Redis cache check failed for note: {e}")

    print(f"CACHE MISS for note: {note_key}. Fetching from Firestore...")

    # 3. If miss, get from Firestore (Database)
    try:
        pages_query = db.collection('projects').document(project_id) \
                      .collection('sources').document(source_id) \
                      .collection('note_pages').order_by('order').stream()
        
        html = "".join(p.to_dict().get('html', '') for p in pages_query)
        
        if html:
            # --- APPLY RANDOM EXPIRATION ---
            # Base TTL of 5 minutes (300s) + a random value up to 60s
            random_ttl = 300 + random.randint(0, 60)
            
            # 4. Backfill L2 Cache (Redis) with random TTL
            if redis_client:
                try:
                    redis_client.setex(note_key, random_ttl, html)
                    print(f"💾 Stored note in Redis cache with TTL: {random_ttl}s")
                except Exception as e:
                    print(f"⚠️ Failed to store note in Redis cache: {e}")
            
            # 5. Backfill L1 Cache (In-Memory)
            L1_CACHE.set(note_key, html)
            print(f"💾 Stored note in L1 cache.")

        return jsonify({"note_html": html or "<p>No note generated yet.</p>"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@study_hub_bp.route('/update-note/<project_id>/<path:source_id>', methods=['POST'])
def update_note(project_id, source_id):
    new_html = request.json.get('html_content')
    if new_html is None:
        return jsonify({"error": "Missing 'html_content'"}), 400
    try:
        source_ref = db.collection('projects').document(project_id).collection('sources').document(source_id)
        note_pages_ref = source_ref.collection('note_pages')
        
        # Delete old pages
        for doc in note_pages_ref.stream():
            doc.reference.delete()
        
        # Save new content in chunks
        chunk_size = 900000
        for i in range(0, len(new_html), chunk_size):
            chunk = new_html[i:i+chunk_size]
            page_num = i // chunk_size
            
            note_pages_ref.document(f'page_{page_num}').set({
                'html': chunk,
                'order': page_num
            })
            note_pages_saved += 1
            print(f"  + Saving new note page {page_num}")

        if redis_client:
            try:
                note_redis_key = f"note:{project_id}:{source_id}"
                redis_client.delete(note_redis_key)
                print(f"✅ Invalidated Redis cache for note: {note_redis_key}")
            except Exception as e:
                print(f"⚠️ Failed to invalidate note cache: {e}")
        
        print(f"✅ Note updated successfully. {note_pages_saved} pages saved.")
        return jsonify({"success": True, "message": "Note updated successfully"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@study_hub_bp.route('/ask-chatbot/<project_id>', methods=['POST'])
def ask_chatbot(project_id):
    data = request.json
    question = data.get('question')
    source_id = data.get('source_id') # Can be a specific source ID or null for 'all'
    
    context = get_simplified_note_context(project_id, source_id)
    if not context:
        return jsonify({"answer": "I couldn't find any generated notes to read. Please upload a document first!"})

    prompt = f"You are a helpful study assistant. Answer the user's question based *only* on the provided study notes. The notes are simplified summaries, so be concise. If the answer is not in the notes, say 'I'm sorry, that information isn't in my simplified notes.'\n\nStudy Notes:\n---\n{context}\n---\n\nQuestion: {question}\n\nAnswer:"
    
    try:
        # Use the injected chat_model
        answer = chat_model.generate_content(prompt).text
        return jsonify({"answer": answer})
    except Exception as e:
        return jsonify({"answer": f"Sorry, an error occurred: {e}"})

@study_hub_bp.route('/generate-topic-note/<project_id>', methods=['POST'])
def topic_note(project_id):
    topic = request.json.get('topic')
    print(f"  🔍 Extracting topic '{topic}' from simplified notes...")

    simplified_notes_context = get_simplified_note_context(project_id)
    if not simplified_notes_context:
        return jsonify({"note_html": "<p>Could not find any notes to search through.</p>"})

    prompt = f"""
    You are an information retrieval assistant. Your task is to act like a "smart search".
    Given a TOPIC and existing STUDY NOTES, find and extract all sections, headings, paragraphs, and bullet points from the STUDY NOTES that are relevant to the TOPIC.

    RULES:
    1.  EXTRACT ONLY: Do NOT write new sentences or summaries. Your output must be a direct copy of relevant parts from the notes.
    2.  PRESERVE FORMATTING: Keep the original markdown formatting (headings, bold text, etc.).
    3.  NO COMMENTARY: Do not add text like "Here are the relevant sections...". Start immediately with the first extracted piece of content. If nothing is found, return only: "I could not find any information about that topic in the notes."

    ---
    TOPIC: {topic}
    ---
    EXISTING STUDY NOTES:
    {simplified_notes_context}
    ---
    """
    
    try:
        response_text = note_gen_model.generate_content(prompt).text
        html = markdown.markdown(response_text)
        return jsonify({"note_html": html})
    except Exception as e:
        return jsonify({"note_html": f"<p>Error generating topic note: {e}</p>"})