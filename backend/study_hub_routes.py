import re
import markdown
import html2text
from flask import Blueprint, request, jsonify
from firebase_admin import firestore
from utils import L1_CACHE
import random  # For the random TTL in get_note
import time 
from pathlib import Path #

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

NULL_CACHE_VALUE = "##NULL##"

def set_dependencies(db_instance, note_model_instance, chat_model_instance, redis_instance):
    """Injects database and AI model dependencies from the main app."""
    global db, note_gen_model, chat_model, redis_client
    db = db_instance
    note_gen_model = note_model_instance
    chat_model = chat_model_instance
    print("✅ Study Hub dependencies injected.")
    redis_client = redis_instance

# --- HELPER FUNCTIONS for Study Hub ---
def get_original_text(project_id, source_id):
    """Fetches and reassembles the original, unprocessed text for a specific source."""
    print(f"  📚 Retrieving original text for source '{source_id}' in project '{project_id}'...")
    
    try:
        source_ref = db.collection('projects').document(project_id).collection('sources').document(source_id)
        chunks_query = source_ref.collection('chunks').order_by('order').stream()
        
        all_chunks = []
        page_count = 0
        for chunk_page in chunks_query:
            page_count += 1
            page_data = chunk_page.to_dict()
            chunks_in_page = page_data.get('chunks', [])
            all_chunks.extend(chunks_in_page)
            print(f"    - Fetched page {page_count}, found {len(chunks_in_page)} chunks.")
        
        if page_count == 0:
            print("    - ‼️  Query returned 0 documents from the 'chunks' subcollection.")

        full_text = "\n".join(all_chunks)
        print(f"  ✅ Assembled {len(full_text)} characters of original text from {len(all_chunks)} total chunks.")
        return full_text
    except Exception as e:
        print(f"  ❌ An error occurred while fetching original text: {e}")
        return "" # Return empty on failure

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
            source_ref.set({
                'filename': filename, 
                'timestamp': firestore.SERVER_TIMESTAMP, 
                'character_count': len(text)
            })
            
            # CRITICAL: Save original text chunks FIRST (before note generation)
            # This ensures regeneration will work even if note generation fails
            print(f"  💾 Saving original text chunks...")
            text_chunks = split_chunks(text)
            for i in range(0, len(text_chunks), 100):
                batch = text_chunks[i:i+100]
                page_num = i // 100
                source_ref.collection('chunks').document(f'page_{page_num}').set({
                    'chunks': batch, 
                    'order': page_num
                })
            print(f"  ✅ Saved {len(text_chunks)} chunks in {(len(text_chunks) + 99) // 100} pages")
            
            # Now try to generate the note (this can fail without breaking everything)
            try:
                note_html = generate_note(text)
                
                # Save note in chunks to avoid Firestore document size limits
                chunk_size = 900000 
                for i in range(0, len(note_html), chunk_size):
                    chunk = note_html[i:i+chunk_size]
                    page_num = i // chunk_size
                    source_ref.collection('note_pages').document(f'page_{page_num}').set({
                        'html': chunk, 
                        'order': page_num
                    })
                print(f"  ✅ Generated and saved study note")
                
            except Exception as note_error:
                # If note generation fails, log it but don't fail the entire upload
                print(f"  ⚠️ Note generation failed (source still saved): {note_error}")
                # Save a placeholder note page
                source_ref.collection('note_pages').document('page_0').set({
                    'html': '<p>Note generation failed. Please try regenerating the note.</p>',
                    'order': 0
                })
            
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

    # 1. Check L1 Cache
    cached_value = L1_CACHE.get(note_key)
    if cached_value:
        print(f"✅ L1 CACHE HIT for note: {note_key}")
        # If the cached value is our special null marker, return empty
        return jsonify({"note_html": "" if cached_value == NULL_CACHE_VALUE else cached_value})

    # 2. Check L2 Cache (Redis)
    if redis_client:
        try:
            cached_bytes = redis_client.get(note_key)
            if cached_bytes:
                print(f"✅ L2 CACHE HIT (Redis) for note: {note_key}")
                content = cached_bytes.decode('utf-8')
                L1_CACHE.set(note_key, content) # Backfill L1
                return jsonify({"note_html": "" if content == NULL_CACHE_VALUE else content})
        except Exception as e:
            print(f"⚠️ Redis cache check failed for note: {e}")

    print(f"CACHE MISS for note: {note_key}. Fetching from Firestore...")

    # 3. If miss, get from Firestore
    # --- THIS IS THE FIX FOR CACHE BREAKDOWN (MUTEX LOCK) ---
    lock_key = f"lock:{note_key}"
    # Try to acquire a lock with a short timeout (e.g., 10s)
    # nx=True means "set if not exists" - this is an atomic operation
    lock_acquired = redis_client.set(lock_key, "1", ex=10, nx=True) if redis_client else False

    if lock_acquired:
        print(f"  ✅ Lock acquired for {note_key}. Rebuilding cache...")
        try:
            # 3. Get from Firestore
            pages_query = db.collection('projects').document(project_id).collection('sources').document(source_id).collection('note_pages').order_by('order').stream()
            html = "".join(p.to_dict().get('html', '') for p in pages_query)
            
            # (Cache Penetration logic from before)
            value_to_cache = html if html else NULL_CACHE_VALUE
            ttl = 300 + random.randint(0, 60) if html else 30

            if redis_client:
                redis_client.setex(note_key, ttl, value_to_cache)
            L1_CACHE.set(note_key, value_to_cache)
            
            return jsonify({"note_html": "" if value_to_cache == NULL_CACHE_VALUE else value_to_cache})

        finally:
            # IMPORTANT: Release the lock
            if redis_client:
                redis_client.delete(lock_key)
            print(f"  🔑 Lock released for {note_key}.")
            
    else:
        # We failed to get the lock, another process is rebuilding.
        print(f"  ...Could not acquire lock. Waiting briefly for cache to be rebuilt...")
        time.sleep(0.1) # Wait 100ms
        # Try the whole function again. This time it should be a cache hit.
        return get_note(project_id, source_id)

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
    
@study_hub_bp.route('/regenerate-note/<project_id>/<path:source_id>', methods=['POST'])
def regenerate_note(project_id, source_id):
    """Regenerates the simplified note for a single source and returns the new HTML."""
    print(f"\n🔄 REGENERATE NOTE request for source: {source_id} in project: {project_id}")
    try:
        # 1. Get the original text from Firestore
        original_text = get_original_text(project_id, source_id)
        if not original_text:
            return jsonify({"error": "Original source text not found or is empty. Please re-upload the document."}), 404

        # 2. Generate the new note using the same function as upload
        new_note_html = generate_note(original_text)
        
        # 3. Overwrite the old note pages in Firestore
        source_ref = db.collection('projects').document(project_id).collection('sources').document(source_id)
        note_pages_ref = source_ref.collection('note_pages')
        
        # Delete old pages first for a clean slate
        for doc in note_pages_ref.stream():
            doc.reference.delete()
            
        # Save new content in chunks - FIXED LOGIC
        chunk_size = 900000 
        for i in range(0, len(new_note_html), chunk_size):
            page_content = new_note_html[i:i + chunk_size]
            page_num = i // chunk_size
            note_pages_ref.document(f'page_{page_num}').set({
                'html': page_content, 
                'order': page_num
            })
            print(f"  + Saved note page {page_num}")

        # 4. Invalidate the Redis cache for this specific note
        if redis_client:
            note_redis_key = f"note:{project_id}:{source_id}"
            redis_client.delete(note_redis_key)
            print(f"  ✅ Invalidated Redis cache for regenerated note: {note_redis_key}")

        # 5. Invalidate L1 cache as well
        note_key = f"note:{project_id}:{source_id}"
        L1_CACHE.delete(note_key)
        print(f"  ✅ Invalidated L1 cache for regenerated note")

        print(f"  ✅ SUCCESS: Note for '{source_id}' regenerated.")
        # 6. Return the new HTML directly to the frontend
        return jsonify({"success": True, "note_html": new_note_html})

    except Exception as e:
        import traceback
        print(f"❌ CRITICAL ERROR regenerating note '{source_id}': {e}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500

@study_hub_bp.route('/generate-code-suggestion', methods=['POST'])
@token_required
def generate_code_suggestion(): # You can keep the function name or change it too, it doesn't matter
    data = request.json
    project_id = data.get('project_id')
    extensions = data.get('extensions', [])
    prompt_text = data.get('prompt')
    
    # --- ADDED LOGGING ---
    print("\n" + "="*50)
    print(f"🤖 Generating PROJECT-WIDE code suggestion for project: {project_id}")
    print(f"   Prompt: '{prompt_text[:100]}...'")
    print(f"   Filtering for extensions: {extensions or 'All'}")
    
    if not all([project_id, prompt_text]):
        return jsonify({"error": "Missing 'project_id' or 'prompt'"}), 400

    full_project_context = ""
    file_count = 0
    try:
        print("  - Building project context from Firestore...")
        docs = db.collection('projects').document(project_id).collection('converted_files').stream()
        dot_extensions = [f".{ext.lstrip('.').lower()}" for ext in extensions] if extensions else None
        
        for doc in docs:
            file_data = doc.to_dict()
            original_path = file_data.get('original_path', '')
            
            # Don't include the tree.txt file in the context
            if original_path == 'tree.txt':
                continue
            
            if not dot_extensions or Path(original_path).suffix.lower() in dot_extensions:
                full_project_context += f"--- FILE: {original_path} ---\n"
                full_project_context += file_data.get('content', '')
                full_project_context += "\n\n"
                file_count += 1
        
        print(f"  - Assembled context from {file_count} files ({len(full_project_context)} chars).")
    except Exception as e:
        print(f"  - ❌ ERROR building project context: {e}")
        return jsonify({"error": f"Failed to build project context: {e}"}), 500
    
    if not full_project_context:
        print("  - ⚠️ No matching files found to build context.")
        return jsonify({"suggestion": "Could not find any code to analyze. Please sync your project with the correct file extensions first."})

    system_prompt = f"""... (your system prompt is good) ..."""
    
    try:
        print("  - Sending request to Gemini model...")
        response = chat_model.generate_content([system_prompt, prompt_text])
        print("  - ✅ Received response from Gemini.")
        print("="*50 + "\n")
        return jsonify({"suggestion": response.text})
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        print(f"  - ❌ ERROR calling Gemini model: {e}")
        print(error_details)
        print("="*50 + "\n")
        return jsonify({"error": str(e), "traceback": error_details}), 500