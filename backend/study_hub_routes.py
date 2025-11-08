# backend/study_hub_routes.py
import re
import markdown
import google.generativeai as genai
from flask import Blueprint, request, jsonify
from firebase_admin import firestore
from langchain_text_splitters import RecursiveCharacterTextSplitter
from utils import extract_text, delete_collection # We'll create this utils.py file next
import redis

# --- BLUEPRINT SETUP ---
study_hub_bp = Blueprint('study_hub_bp', __name__)
db = None
genai_model = None
redis_client = None 

def set_dependencies(db_instance, genai_instance, redis_instance):
    """Injects dependencies from the main app."""
    global db, genai_model, redis_client
    db = db_instance
    genai_model = genai_instance
    redis_client = redis_instance

# --- HELPER FUNCTIONS for Study Hub ---
def split_chunks(text):
    splitter = RecursiveCharacterTextSplitter(chunk_size=1500, chunk_overlap=200)
    return splitter.split_text(text)

def generate_note(text):
    prompt = f"""
    You are an expert universal study assistant. Your mission is to transform dense academic texts from **any language** into simplified, well-structured, and exceptionally easy-to-understand study notes.

    Your output must be in the **same language as the source text**. Follow these rules meticulously, as they are your core programming.

    **1. 💡 The Golden Rule: Simplify Everything**
    *   This is your most important task. Your absolute priority is to make the content easy to understand for a student who finds the original text difficult.
    *   **Step A: Simplify Vocabulary.** Find any complex, technical, or **unfamiliar words** in the original text and replace them with simpler, more common words in that **same language**.
        *   *English Example:* Change "leverage synergistic paradigms" to "use teamwork effectively."
        *   *Spanish Example:* Change "implementar una metodología vanguardista" to "usar un método nuevo y moderno."
    *   **Step B: Simplify Sentences.** Break down long, complex sentences into shorter, clearer ones that are easy to read and digest.
    *   **Step C: Simplify Structure.** Convert dense paragraphs into scannable bullet points, numbered lists, and short, focused sections.

    **2. ✍️ Annotation Rule: Translate ALL Simplified Words (NEW & IMPROVED)**
    *   Your annotation is not just for major keywords. For **every single word** that you simplified in Rule #1 because it was complex or unfamiliar, you **must** provide its Chinese translation.
    *   The format is always: `new simplified word (中文翻译)`.
    *   **Example of Scope:** If the original text said "The *ubiquitous* nature of the *phenomenon*...", and you simplify it to "The *widespread* nature of the *event*...", your output must be: "The **widespread (普遍的)** nature of the **event (事件)**..." This applies to all such words.

    **3. 🎨 Formatting Rule: Make it Engaging and Clear**
    *   **Headings and Emojis:** Use markdown headings (`#`, `##`) to create a clear structure. Add a relevant emoji next to each main heading to make it visually appealing (e.g., 🔍 for Definitions, ⚙️ for Processes, ✅ for Key Takeaways).
    *   **Highlighting:** Use **bold text** to emphasize the most important simplified keywords and concepts.
    *   **Tone:** Adopt a friendly, encouraging, and helpful tone, as if you are a tutor guiding the student through the material.

    **4. 🎯 Content Rule: Be Comprehensive and Accurate**
    *   While simplifying, you must still cover **all major topics and key concepts** from the original text. Do not skip sections.
    *   Your notes should follow the same logical flow and structure as the source document.
    *   Extract only the most critical information—definitions, key arguments, and essential examples.

    **5. 🧠 Memory Aid: Add a Mnemonic Tip (记忆技巧)**
    *   At the end of each major section, create a short, creative **Mnemonic Tip (记忆技巧)**. This could be an acronym, a simple rhyme, or a memorable phrase to help the student recall the main points.

    **Constraint:**
    *   You must not add any new information that is not present in the original text. Your job is to simplify and structure, not to invent or add external knowledge.

    Here is the text to process:
    ---
    {text}
    ---
    """
    try:
        response = genai_model.generate_content(prompt)
        return markdown.markdown(response.text)
    except Exception as e:
        print(f"  ❌ Generation failed: {e}")
        raise

@study_hub_bp.route('/get-projects')
def get_projects():
    docs = db.collection('projects').order_by('timestamp', direction=firestore.Query.DESCENDING).stream()
    return jsonify([{"id": d.id, "name": d.to_dict().get('name')} for d in docs])

# In create_project function
@study_hub_bp.route('/create-project', methods=['POST'])
def create_project():
    name = request.json.get('name')
    user_id = get_current_user_id() # Assuming this gets the user's UID
    if not user_id:
        return jsonify({"error": "Authentication required"}), 401
    
    ref = db.collection('projects').document()
    ref.set({
        'name': name,
        'timestamp': firestore.SERVER_TIMESTAMP,
        'userId': user_id  
    })
    return jsonify({"id": ref.id})

@study_hub_bp.route('/rename-project/<project_id>', methods=['PUT'])
def rename_project(project_id):
    print(f"\n✏️  RENAME REQUEST for project: {project_id}")
    try:
        new_name = request.json.get('new_name')
        if not new_name:
            return jsonify({"success": False, "error": "New name not provided"}), 400

        project_ref = db.collection('projects').document(project_id)
        project_ref.update({'name': new_name})
        
        print(f"✅ Successfully renamed project to: {new_name}")
        return jsonify({"success": True, "message": f"Project renamed to {new_name}."}), 200

    except Exception as e:
        import traceback
        print(f"❌ Error renaming project {project_id}: {e}")
        print(traceback.format_exc())
        return jsonify({"success": False, "error": str(e)}), 500

@study_hub_bp.route('/delete-project/<project_id>', methods=['DELETE'])
def delete_project(project_id):
    print(f"\n🗑️  DELETE REQUEST for project: {project_id}")
    try:
        project_ref = db.collection('projects').document(project_id)

        # 1. Delete all subcollections first
        for collection_ref in project_ref.collections():
            print(f"  Deleting subcollection: {collection_ref.id}")
            delete_collection(collection_ref, batch_size=50)

        # 2. After subcollections are gone, delete the project document itself
        project_ref.delete()
        print(f"✅ Successfully deleted project document: {project_id}")
        
        return jsonify({"success": True, "message": f"Project {project_id} deleted."}), 200

    except Exception as e:
        import traceback
        print(f"❌ Error deleting project {project_id}: {e}")
        print(traceback.format_exc())
        return jsonify({"success": False, "error": str(e)}), 500

@study_hub_bp.route('/get-sources/<project_id>')
def get_sources(project_id):
    docs = db.collection('projects').document(project_id) \
             .collection('sources').stream()
    return jsonify([{
        "id": d.id,                 
        "filename": d.to_dict().get('filename')
    } for d in docs])

@study_hub_bp.route('/upload-source/<project_id>', methods=['POST'])
def upload_source(project_id):
    print("=" * 80)
    print(f"📁 UPLOAD REQUEST for project: {project_id}")
    print("=" * 80)
    
    if 'pdfs' not in request.files:
        print("❌ ERROR: No 'pdfs' field in request!")
        print(f"Available fields: {list(request.files.keys())}")
        return jsonify({"error": "No files provided", "success": False}), 400
    
    files = request.files.getlist('pdfs')
    print(f"📦 Received {len(files)} file(s)")
    
    if not files or files[0].filename == '':
        print("❌ ERROR: Empty file list or no filename")
        return jsonify({"error": "No files selected", "success": False}), 400
    
    processed = []
    errors = []

    for idx, file in enumerate(files):
        print(f"\n{'─' * 60}")
        print(f"🔄 Processing file {idx + 1}/{len(files)}")
        print(f"{'─' * 60}")
        
        filename = file.filename
        print(f"📄 Original filename: {filename}")
        
        safe_id = re.sub(r'[.#$/[\]]', '_', filename)
        print(f"🔐 Safe ID: {safe_id}")

        try:
            print("📖 Step 1: Extracting text from PDF...")
            file.stream.seek(0)
            text = extract_text(file.stream)
            
            print(f"✅ Text extracted: {len(text)} characters")
            
            if not text.strip():
                error_msg = f"No text extracted from {filename}"
                print(f"⚠️  WARNING: {error_msg}")
                errors.append({"filename": filename, "error": error_msg})
                continue
            
            print(f"📝 Preview: {text[:200]}...")

            print("💾 Step 2: Creating source document in Firestore...")
            source_ref = db.collection('projects').document(project_id) \
                             .collection('sources').document(safe_id)
            
            source_ref.set({
                'filename': filename, 
                'timestamp': firestore.SERVER_TIMESTAMP,
                'character_count': len(text)
            })
            print(f"✅ Source document created: projects/{project_id}/sources/{safe_id}")

            print("🤖 Step 3: Generating AI study note...")
            try:
                note_html = generate_note(text)
                print(f"✅ Note generated: {len(note_html)} characters")
            except Exception as e:
                error_msg = f"AI generation failed: {str(e)}"
                print(f"❌ ERROR: {error_msg}")
                note_html = f"<p>AI note generation failed: {e}</p>"

            print("💾 Step 4: Saving note pages to Firestore...")
            chunk_size = 900000
            note_pages_saved = 0
            
            for i in range(0, len(note_html), chunk_size):
                chunk = note_html[i:i+chunk_size]
                page_num = i // chunk_size
                
                source_ref.collection('note_pages').document(f'page_{page_num}').set({
                    'html': chunk,
                    'order': page_num
                })
                note_pages_saved += 1
                print(f"  ✓ Saved note page {page_num} ({len(chunk)} chars)")
            
            print(f"✅ Total note pages saved: {note_pages_saved}")

            print("✂️  Step 5: Splitting text into chunks for Q&A...")
            text_chunks = split_chunks(text)
            print(f"✅ Created {len(text_chunks)} text chunks")
            
            print("💾 Step 6: Saving Q&A chunks to Firestore...")
            chunks_docs_saved = 0
            
            for i in range(0, len(text_chunks), 100):
                batch_chunks = text_chunks[i:i+100]
                page_num = i // 100
                
                source_ref.collection('chunks').document(f'page_{page_num}').set({
                    'chunks': batch_chunks,
                    'order': page_num,
                    'count': len(batch_chunks)
                })
                chunks_docs_saved += 1
                print(f"  ✓ Saved chunk page {page_num} ({len(batch_chunks)} chunks)")
            
            print(f"✅ Total chunk pages saved: {chunks_docs_saved}")

            processed.append({
                "filename": filename, 
                "id": safe_id,
                "text_length": len(text),
                "note_pages": note_pages_saved,
                "chunk_pages": chunks_docs_saved
            })
            
            print(f"✅ ✅ ✅ SUCCESS: {filename} fully processed!")

        except Exception as e:
            error_msg = f"Failed to process {filename}: {str(e)}"
            print(f"❌ CRITICAL ERROR: {error_msg}")
            import traceback
            print(traceback.format_exc())
            errors.append({"filename": filename, "error": error_msg})

    print("\n" + "=" * 80)
    print(f"📊 UPLOAD SUMMARY")
    print("=" * 80)
    print(f"✅ Successfully processed: {len(processed)}")
    print(f"❌ Errors: {len(errors)}")
    
    if processed:
        print("\n✅ Processed files:")
        for p in processed:
            print(f"  - {p['filename']} (ID: {p['id']})")
    
    if errors:
        print("\n❌ Errors:")
        for e in errors:
            print(f"  - {e['filename']}: {e['error']}")
    
    print("=" * 80)

    return jsonify({
        "success": len(processed) > 0,
        "processed": processed,
        "errors": errors
    })

@study_hub_bp.route('/delete-source/<project_id>/<path:source_id>', methods=['DELETE'])
def delete_source(project_id, source_id):
    print(f"\n🗑️  DELETE REQUEST for source: {source_id} in project: {project_id}")
    try:
        source_ref = db.collection('projects').document(project_id).collection('sources').document(source_id)

        # 1. Delete subcollections (note_pages, chunks)
        for collection_ref in source_ref.collections():
            print(f"  Deleting subcollection: {collection_ref.id}")
            delete_collection(collection_ref, batch_size=50)

        # 2. Delete the source document itself
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
        import traceback
        print(f"❌ Error deleting source {source_id}: {e}")
        print(traceback.format_exc())
        return jsonify({"success": False, "error": str(e)}), 500

@study_hub_bp.route('/get-note/<project_id>/<path:source_id>')
def get_note(project_id, source_id):
    note_redis_key = f"note:{project_id}:{source_id}"

    if redis_client:
        try:
            cached_html_bytes = redis_client.get(note_redis_key)
            if cached_html_bytes:
                print(f"✅ CACHE HIT for note: {note_redis_key}")
                # --- THIS IS THE FIX ---
                # Decode the bytes from Redis into a UTF-8 string.
                return jsonify({"note_html": cached_html_bytes.decode('utf-8')})
                # --- END OF FIX ---
        except Exception as e:
            print(f"⚠️ Redis cache check failed for note: {e}")

    print(f"CACHE MISS for note: {note_redis_key}. Fetching from Firestore...")

    # 2. If miss, get from Firestore
    try:
        pages_query = db.collection('projects').document(project_id) \
                      .collection('sources').document(source_id) \
                      .collection('note_pages').order_by('order').stream()
        
        html = "".join(p.to_dict().get('html', '') for p in pages_query)
        
        # 3. Store the assembled HTML in Redis for next time
        if redis_client and html:
            try:
                # Cache for 1 hour (3600 seconds)
                redis_client.setex(note_redis_key, 3600, html)
                print(f"💾 Successfully stored note in Redis cache: {note_redis_key}")
            except Exception as e:
                print(f"⚠️ Failed to store note in Redis cache: {e}")

        return jsonify({"note_html": html or "<p>No note generated yet.</p>"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@study_hub_bp.route('/update-note/<project_id>/<path:source_id>', methods=['POST'])
def update_note(project_id, source_id):
    print(f"🔄 UPDATE NOTE request for project: {project_id}, source: {source_id}")
    data = request.json
    new_html = data.get('html_content')

    if not new_html:
        return jsonify({"error": "Missing 'html_content'"}), 400

    try:
        source_ref = db.collection('projects').document(project_id).collection('sources').document(source_id)
        note_pages_ref = source_ref.collection('note_pages')

        # 1. Delete all old note pages to prevent leftovers
        docs = note_pages_ref.stream()
        for doc in docs:
            print(f"  - Deleting old note page: {doc.id}")
            doc.reference.delete()

        # 2. Re-chunk and save the new note content
        chunk_size = 900000  # Must match the chunk size from your upload logic
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
        import traceback
        print(f"❌ CRITICAL ERROR updating note: {e}")
        print(traceback.format_exc())
        return jsonify({"error": str(e)}), 500

@study_hub_bp.route('/ask-chatbot/<project_id>', methods=['POST'])
def ask_chatbot(project_id):
    data = request.json
    q = data.get('question')
    src = data.get('source_id')
    
    # Get chunks
    all_chunks = []
    
    if src:
        # Get chunks from specific source
        chunk_docs = db.collection('projects').document(project_id) \
            .collection('sources').document(src) \
            .collection('chunks').stream()
        
        for doc in chunk_docs:
            all_chunks.extend(doc.to_dict().get('chunks', []))
    else:
        # Get chunks from all sources
        sources = db.collection('projects').document(project_id) \
            .collection('sources').stream()
        
        for source in sources:
            chunk_docs = source.reference.collection('chunks').stream()
            for doc in chunk_docs:
                all_chunks.extend(doc.to_dict().get('chunks', []))

    if not all_chunks:
        return jsonify({"answer": "Please upload a PDF first!"})

    # Use first 10 chunks as context
    context = "\n---\n".join(all_chunks[:10])
    
    model = genai.GenerativeModel('models/gemini-pro-latest')
    prompt = f"Answer using only this context:\n{context}\n\nQuestion: {q}\nAnswer:"
    
    try:
        answer = model.generate_content(prompt).text
        return jsonify({"answer": answer})
    except Exception as e:
        return jsonify({"answer": f"Error: {e}"})

@study_hub_bp.route('/generate-topic-note/<project_id>', methods=['POST'])
def topic_note(project_id):
    topic = request.json.get('topic')
    
    all_chunks = []
    sources = db.collection('projects').document(project_id).collection('sources').stream()
    
    for source in sources:
        chunk_docs = source.reference.collection('chunks').stream()
        for doc in chunk_docs:
            all_chunks.extend(doc.to_dict().get('chunks', []))
    
    context = "\n".join(all_chunks[:20])
    
    model = genai.GenerativeModel('models/gemini-pro-latest')
    prompt = f"Make a study note about: {topic}\nUse this:\n{context}"
    
    try:
        html = markdown.markdown(model.generate_content(prompt).text)
        return jsonify({"note_html": html})
    except Exception as e:
        return jsonify({"note_html": f"<p>Error generating note: {e}</p>"})