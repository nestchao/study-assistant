# backend/study_hub_routes.py

import re
import markdown
import html2text
from flask import Blueprint, request, jsonify
from firebase_admin import firestore
from utils import L1_CACHE
import random
import time 
from pathlib import Path 
import google.api_core.exceptions

from utils import extract_text, delete_collection, split_chunks
import redis

# --- 从配置文件导入 ---
from config import (
    STUDY_PROJECTS_COLLECTION,
    CODE_PROJECTS_COLLECTION,
    CODE_FILES_SUBCOLLECTION,
    VECTOR_STORE_ROOT,
    NULL_CACHE_VALUE
)

from code_graph_engine import (
    FaissVectorStore, 
    CrossEncoderReranker,
    hybrid_retrieval_pipeline,
    build_hierarchical_context
)

from services import db, note_generation_model, chat_model, cache_manager 

cross_encoder = CrossEncoderReranker()
study_hub_bp = Blueprint('study_hub_bp', __name__)

# def set_dependencies(db_instance, note_model_instance, chat_model_instance, redis_instance):
#     """Injects database and AI model dependencies from the main app."""
#     global cross_encoder
    
#     # --- 新增：初始化 Cross-Encoder（只加载一次） ---
#     print("✅ Loading Cross-Encoder model...")
#     cross_encoder = CrossEncoderReranker()
#     print("✅ Study Hub dependencies injected.")

# --- HELPER FUNCTIONS for Study Hub ---
def get_original_text(project_id, source_id):
    """Fetches and reassembles the original, unprocessed text for a specific source."""
    print(f"  📚 Retrieving original text for source '{source_id}' in project '{project_id}'...")
    
    try:
        source_ref = db.collection(STUDY_PROJECTS_COLLECTION).document(project_id).collection('sources').document(source_id)
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
    You are an expert academic study assistant. Your mission is to transform dense academic texts into simplified, well-structured study notes that are easy to understand.
    
    Your output must be in the **same language as the source text**. Follow these rules meticulously.

    # 🚀 Core Transformation Rules

    ## 0. 🏛️ Preserve the Original Structure (The Golden Rule)
    *   You MUST follow the structure, headings, and topic order of the original text **EXACTLY**.
    *   Do not merge or re-order sections. Simplify content **within** the original structure.

    ## 1. 💡 Simplify and Shorten Content (Aggressive Simplification)
    *   **Clarity Priority:** **REWRITE** dense, convoluted academic sentences into short, direct, simple statements. The resulting text must be immediately clear to a novice reader.
    *   **Sentence Compression:** Aim for maximum brevity. Sentences should be **as short as possible** where grammatically possible. Keep the flow simple (Subject-Verb-Object).
    *   **Word Replacement:** Replace complex or academic terminology (e.g., 'paradigm,' 'utilization,' 'delineate') with simpler, everyday equivalents (e.g., 'model,' 'use,' 'show').
    *   **Keep Key Points:** Retain all essential definitions, data, and core arguments accurately.
    *   **Exam Purpose:** The note is generate for exam purpose, so the key word can't miss. 

    ## 3. 🎨 Formatting and Tone
    *   Use markdown headings (`#`, `##`) that match the original text's structure. Add a relevant **emoji** to each main heading.
    *   Use **bold text** to emphasize key simplified concepts.
    *   Maintain a clear, direct, and helpful academic tone.

    ## 4. 🧠 Memory Aid and Accuracy
    *   Cover all major topics accurately. Do not skip sections or add new information.
    *   At the end of each major section, create a short, creative **Mnemonic Tip (记忆技巧)** to aid recall.

    ---
    Here is the text to process:
    ---
    {text}
    ---
    """
    try:
        # Use the injected note_generation_model
        response = note_generation_model.generate_content(prompt)
        return markdown.markdown(response.text, extensions=['tables'])
    except Exception as e:
        print(f"  ❌ Note generation failed: {e}")
        raise

def get_simplified_note_context(project_id, source_id=None):
    """Fetches and combines all simplified note pages into clean text for the chatbot."""
    print(f"  📚 Retrieving simplified note context for project {project_id}...")
    full_html_content = ""
    sources_to_query = []

    if source_id:
        source_ref = db.collection(STUDY_PROJECTS_COLLECTION).document(project_id).collection('sources').document(source_id)
        sources_to_query.append(source_ref)
    else:
        sources_stream = db.collection(STUDY_PROJECTS_COLLECTION).document(project_id).collection('sources').stream()
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

# --- STUDY HUB PROJECT ROUTES ---
@study_hub_bp.route('/get-projects', methods=['GET'])
def get_projects():
    docs = db.collection(STUDY_PROJECTS_COLLECTION).order_by('timestamp', direction=firestore.Query.DESCENDING).stream()
    projects = [{"id": d.id, "name": d.to_dict().get('name')} for d in docs]
    return jsonify(projects)

@study_hub_bp.route('/create-project', methods=['POST'])
def create_project():
    name = request.json.get('name')
    
    ref = db.collection(STUDY_PROJECTS_COLLECTION).document()
    ref.set({
        'name': name,
        'timestamp': firestore.SERVER_TIMESTAMP,
    })
    return jsonify({"id": ref.id})

@study_hub_bp.route('/rename-project/<project_id>', methods=['PUT'])
def rename_project(project_id):
    new_name = request.json.get('new_name')
    if not new_name:
        return jsonify({"success": False, "error": "New name not provided"}), 400
    try:
        project_ref = db.collection(STUDY_PROJECTS_COLLECTION).document(project_id)
        project_ref.update({'name': new_name})
        return jsonify({"success": True, "message": f"Project renamed to {new_name}."}), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@study_hub_bp.route('/delete-project/<project_id>', methods=['DELETE'])
def delete_project(project_id):
    print(f"\n🗑️  DELETE REQUEST for project: {project_id}")
    try:
        project_ref = db.collection(STUDY_PROJECTS_COLLECTION).document(project_id)
        for collection_ref in project_ref.collections():
            delete_collection(collection_ref, batch_size=50)
        project_ref.delete()
        print(f"✅ Successfully deleted project: {project_id}")
        return jsonify({"success": True}), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500
        
# --- NEW: CODE ASSISTANT PROJECT ROUTES ---
@study_hub_bp.route('/get-code-projects', methods=['GET'])
def get_code_projects():
    docs = db.collection(CODE_PROJECTS_COLLECTION).order_by('timestamp', direction=firestore.Query.DESCENDING).stream()
    projects = [{"id": d.id, "name": d.to_dict().get('name')} for d in docs]
    return jsonify(projects)

@study_hub_bp.route('/create-code-project', methods=['POST'])
def create_code_project():
    name = request.json.get('name')

    ref = db.collection(CODE_PROJECTS_COLLECTION).document()
    ref.set({
        'name': name,
        'timestamp': firestore.SERVER_TIMESTAMP,
    })
    return jsonify({"id": ref.id})


@study_hub_bp.route('/get-sources/<project_id>', methods=['GET'])
def get_sources(project_id):
    docs = db.collection(STUDY_PROJECTS_COLLECTION).document(project_id).collection('sources').stream()
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

            source_ref = db.collection(STUDY_PROJECTS_COLLECTION).document(project_id).collection('sources').document(safe_id)
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
        source_ref = db.collection(STUDY_PROJECTS_COLLECTION).document(project_id).collection('sources').document(source_id)
        for collection_ref in source_ref.collections():
            delete_collection(collection_ref, batch_size=50)
        source_ref.delete()

        # Invalidate Cache using unified CacheManager
        if cache_manager:
            note_key = f"note:{project_id}:{source_id}"
            cache_manager.delete(note_key)
            print(f"✅ Invalidated cache for deleted source: {note_key}")

        print(f"✅ Successfully deleted source document: {source_id}")
        return jsonify({"success": True, "message": f"Source {source_id} deleted."}), 200

    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@study_hub_bp.route('/get-note/<project_id>/<path:source_id>')
def get_note(project_id, source_id):
    # 1. Define the cache key
    cache_key = f"note:{project_id}:{source_id}"

    # 2. Define the factory function (what to do if cache misses)
    def fetch_note_from_db():
        print(f"  🔍 Fetching note from Firestore for {cache_key}...")
        pages_query = db.collection(STUDY_PROJECTS_COLLECTION)\
            .document(project_id).collection('sources').document(source_id)\
            .collection('note_pages').order_by('order').stream()
        
        html = "".join(p.to_dict().get('html', '') for p in pages_query)
        
        # Return empty string if nothing found
        return html if html else ""

    # 3. Use CacheManager
    if cache_manager:
        try:
            note_html = cache_manager.get_or_set(
                key=cache_key,
                factory=fetch_note_from_db,
                ttl_l1=300,   # 5 mins in memory
                ttl_l2=3600   # 1 hour in Redis
            )
            return jsonify({"note_html": note_html})
        except Exception as e:
            print(f"Cache Error: {e}")
            # Fallback if cache fails
            return jsonify({"note_html": fetch_note_from_db()})
    else:
        # Fallback if no cache manager
        return jsonify({"note_html": fetch_note_from_db()})

@study_hub_bp.route('/update-note/<project_id>/<path:source_id>', methods=['POST'])
def update_note(project_id, source_id):
    new_html = request.json.get('html_content')
    if new_html is None:
        return jsonify({"error": "Missing 'html_content'"}), 400
    try:
        source_ref = db.collection(STUDY_PROJECTS_COLLECTION).document(project_id).collection('sources').document(source_id)
        note_pages_ref = source_ref.collection('note_pages')
        
        for doc in note_pages_ref.stream():
            doc.reference.delete()
        
        chunk_size = 900000
        note_pages_saved = 0
        for i in range(0, len(new_html), chunk_size):
            chunk = new_html[i:i+chunk_size]
            page_num = i // chunk_size
            
            note_pages_ref.document(f'page_{page_num}').set({
                'html': chunk,
                'order': page_num
            })
            note_pages_saved += 1
            print(f"  + Saving new note page {page_num}")

        # Invalidate Cache
        if cache_manager:
            cache_key = f"note:{project_id}:{source_id}"
            cache_manager.delete(cache_key)
            print(f"✅ Invalidated cache for {cache_key}")
        
        print(f"✅ Note updated successfully. {note_pages_saved} pages saved.")
        return jsonify({"success": True, "message": "Note updated successfully"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@study_hub_bp.route('/ask-chatbot/<project_id>', methods=['POST'])
def ask_chatbot(project_id):
    data = request.json
    question = data.get('question')
    source_id = data.get('source_id') 
    history = data.get('history', []) 
    
    context = get_simplified_note_context(project_id, source_id)
    if not context:
        return jsonify({"answer": "I couldn't find any generated notes to read. Please upload a document first!"})

    system_prompt = f"""You are a helpful study assistant. Your primary goal is to answer the user's questions based *only* on the provided study notes.
    - Be concise and clear in your answers.
    - If the answer is not in the notes, you MUST say 'I'm sorry, that information isn't in my simplified notes.'
    - Do not use any external knowledge.

    Here are the study notes you must use as your knowledge base:
    ---
    {context}
    ---
    """

    messages = [{'role': 'user', 'parts': [system_prompt]}]
    messages.append({'role': 'model', 'parts': ["Okay, I have read the study notes. I am ready to answer your questions based on them."]})
    
    for turn in history:
        role = turn.get('role')
        content = turn.get('content')
        if role and content: # The frontend sends 'bot', but Gemini expects 'model'
            role = 'model' if role == 'bot' else role 
            messages.append({'role': role, 'parts': [content]})
 
    messages.append({'role': 'user', 'parts': [question]})

    try:
        print(f"  🤖 Sending chat request with {len(history)} history turns...")
        response = chat_model.generate_content(messages)
        answer = response.text
        print("  ✅ Received chat response.")
        return jsonify({"answer": answer})
    except Exception as e:
        print(f"  ❌ Error during chatbot generation: {e}")
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
        response_text = note_generation_model.generate_content(prompt).text
        html = markdown.markdown(response_text, extensions=['tables'])
        return jsonify({"note_html": html})
    except Exception as e:
        return jsonify({"note_html": f"<p>Error generating topic note: {e}</p>"})
    
@study_hub_bp.route('/regenerate-note/<project_id>/<path:source_id>', methods=['POST'])
def regenerate_note(project_id, source_id):
    print(f"\n🔄 REGENERATE NOTE request for source: {source_id} in project: {project_id}")
    try:
        original_text = get_original_text(project_id, source_id)
        if not original_text:
            return jsonify({"error": "Original source text not found or is empty. Please re-upload the document."}), 404

        new_note_html = generate_note(original_text)
        
        source_ref = db.collection(STUDY_PROJECTS_COLLECTION).document(project_id).collection('sources').document(source_id)
        note_pages_ref = source_ref.collection('note_pages')
        
        for doc in note_pages_ref.stream():
            doc.reference.delete()
            
        chunk_size = 900000 
        for i in range(0, len(new_note_html), chunk_size):
            page_content = new_note_html[i:i + chunk_size]
            page_num = i // chunk_size
            note_pages_ref.document(f'page_{page_num}').set({
                'html': page_content, 
                'order': page_num
            })
            print(f"  + Saved note page {page_num}")

        # Invalidate Cache
        if cache_manager:
            note_key = f"note:{project_id}:{source_id}"
            cache_manager.delete(note_key)
            print(f"  ✅ Invalidated cache for regenerated note: {note_key}")

        print(f"  ✅ SUCCESS: Note for '{source_id}' regenerated.")
        return jsonify({"success": True, "note_html": new_note_html})

    except Exception as e:
        import traceback
        print(f"❌ CRITICAL ERROR regenerating note '{source_id}': {e}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500

@study_hub_bp.route('/generate-code-suggestion', methods=['POST'])
def generate_code_suggestion():
    data = request.json
    project_id = data.get('project_id')
    prompt_text = data.get('prompt')
    
    print("\n" + "="*80)
    print(f"🚀 Generating Code Suggestion (Hybrid e-based + Industry Standard)")
    print(f"Project: {project_id}")
    print(f"Query: {prompt_text}")
    print("="*80)
    
    if not all([project_id, prompt_text]):
        return jsonify({"error": "Missing 'project_id' or 'prompt'"}), 400

    try:
        # --- 1. 加载向量存储 ---
        store_path = Path("vector_stores") / project_id
        
        if not store_path.exists():
            return jsonify({
                "suggestion": "⚠️ This project hasn't been synced yet. Please run 'Check Synchronize' first."
            })
        
        print(f"  📂 Loading vector store from {store_path}...")
        vector_store = FaissVectorStore.load(store_path)
        
        # --- 2. 运行混合检索流程 ---
        context = hybrid_retrieval_pipeline(
            project_id=project_id,
            user_query=prompt_text,
            db_instance=db,
            vector_store=vector_store,
            cross_encoder=cross_encoder,
            use_hyde=True  # 使用 HyDE
        )
        
        # --- 3. 生成最终答案 ---
        final_prompt = f"""
        ### ROLE
        You are a Senior Software Architect and Codebase Expert. You are assisting a developer by analyzing the provided code context to answer their questions accurately.

        ### CONTEXT (Retrieved Code)
        The following text contains the most relevant files and code snippets from the project. The format is: `# FILE: <path>` followed by the code.
        --------------------------------------------------
        {context}
        --------------------------------------------------

        ### USER QUESTION
        {prompt_text}

        ### INSTRUCTIONS
        1. **Source-Based Truth:** Answer ONLY based on the code provided in the CONTEXT. If the answer is not in the context, admit it. Do not make up functions or files that do not exist.
        2. **Citation:** When explaining logic, explicitly mention the filename (e.g., "In `backend/app.py`...") so the user knows where to look.
        3. **Actionable Output:**
        - If explaining concepts: Use clear, high-level summaries followed by technical details.
        - If fixing bugs: Explain the root cause, then provide the corrected code block.
        - If writing new code: Ensure it matches the style and patterns found in the CONTEXT.
        4. **Formatting:** Use Markdown. Use code blocks (```language) for code. Use bold text for variable names or file paths.

        ### ANSWER
        """

        print("  🤖 Generating final response with Gemini...")
        response = chat_model.generate_content(final_prompt)
        
        if not response.candidates:
            return jsonify({"error": "AI response blocked or empty."}), 400
        
        suggestion_text = response.candidates[0].content.parts[0].text
        
        print("="*80)
        print("✅ Response generated successfully")
        print("="*80 + "\n")
        
        return jsonify({"suggestion": suggestion_text})
    
    except FileNotFoundError as e:
        return jsonify({
            "suggestion": f"⚠️ Vector store not found: {e}. Please sync your project first."
        })
    except Exception as e:
        import traceback
        print(f"  ❌ CRITICAL ERROR: {e}")
        print(traceback.format_exc())
        return jsonify({"error": str(e)}), 500

@study_hub_bp.route('/retrieve-context-candidates', methods=['POST'])
def retrieve_candidates():
    data = request.json
    project_id = data.get('project_id')
    prompt_text = data.get('prompt')
    
    try:
        store_path = VECTOR_STORE_ROOT / project_id
        if not store_path.exists():
             return jsonify({"error": "Project index not found"}), 404

        vector_store = FaissVectorStore.load(store_path)
        
        # Get candidates with return_nodes_only=True
        candidates = hybrid_retrieval_pipeline(
            project_id=project_id,
            user_query=prompt_text,
            db_instance=db,
            vector_store=vector_store,
            cross_encoder=cross_encoder,
            use_hyde=True,
            return_nodes_only=True 
        )
        
        return jsonify({"candidates": candidates})
    except Exception as e:
        print(f"Error retrieving candidates: {e}")
        return jsonify({"error": str(e)}), 500

@study_hub_bp.route('/generate-answer-from-context', methods=['POST'])
def generate_answer_from_context():
    data = request.json
    project_id = data.get('project_id')
    prompt_text = data.get('prompt')
    selected_ids = data.get('selected_ids', [])

    if not selected_ids:
        return jsonify({"suggestion": "❌ No context selected. Please select at least one file for me to analyze."})

    print(f"📥 Received {len(selected_ids)} IDs for generation: {selected_ids}")
    
    try:
        store_path = VECTOR_STORE_ROOT / project_id
        vector_store = FaissVectorStore.load(store_path)
        
        # Re-fetch full node content
        selected_nodes = []
        all_keys = list(vector_store.name_to_id.keys())
        print(f"🔎 DEBUG: First 5 keys in Vector Store: {all_keys[:5]}")

        for uid in selected_ids:
            node_data = vector_store.get_node_by_name(uid)
            if node_data:
                selected_nodes.append({'node': node_data})
            else:
                print(f"⚠️ Node not found for ID: {uid}")
        
        # Build Context
        context = build_hierarchical_context(selected_nodes)
        
        final_prompt = f"""
        ### ROLE
        You are a Senior Software Architect.

        ### CONTEXT
        {context}

        ### QUESTION
        {prompt_text}

        ### INSTRUCTION
        Answer based on the code above.
        """
        response = chat_model.generate_content(final_prompt)
        return jsonify({"suggestion": response.text})
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500