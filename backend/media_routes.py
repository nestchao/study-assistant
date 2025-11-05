# backend/media_routes.py
import time
import base64
from flask import Blueprint, request, jsonify, Response
from firebase_admin import firestore
import redis

try:
    redis_client = redis.Redis(host='localhost', port=6379, db=0, decode_responses=False)
    redis_client.ping()
    print("✅ Redis client connected successfully.")
except redis.exceptions.ConnectionError as e:
    print(f"❌ Redis connection failed: {e}. Caching will be disabled.")
    redis_client = None

# Create a Blueprint. This is like a mini-Flask app that can be registered with the main app.
media_bp = Blueprint('media_bp', __name__)

# Constants
MEDIA_COLLECTION = "media_metadata"
MAX_CHUNK_SIZE_BYTES = 900_000

# We'll get the db instance from the main app when this blueprint is registered.
# For now, we'll use a placeholder.
db = None

def set_db_instance(db_instance):
    """Allows the main app to pass its db instance to this blueprint."""
    global db
    db = db_instance

# --- HELPER / AUTH MOCK ---
def get_current_user_id():
    """Placeholder for your authentication logic."""
    return request.headers.get("X-User-ID")

# --- CORE MEDIA LOGIC ---

def store_media(media_id: str, base64_string: str, file_name: str, media_type: str, user_id: str):
    """
    Splits a Base64 string into chunks and stores it in Firestore using firebase-admin SDK.
    """
    if not db:
        raise ConnectionError("Firestore client is not available.")

    print(f"Attempting to store media. mediaId: {media_id}, userId: {user_id}")
    metadata_ref = db.collection(MEDIA_COLLECTION).document(media_id)
    
    try:
        total_size = len(base64_string)
        chunks = [
            base64_string[i:i + MAX_CHUNK_SIZE_BYTES]
            for i in range(0, total_size, MAX_CHUNK_SIZE_BYTES)
        ]
        total_chunks = len(chunks)

        metadata = {
            "userId": user_id,
            "type": media_type,
            "fileName": file_name,
            "totalChunks": total_chunks,
            "originalSize": total_size,
            "timestamp": firestore.SERVER_TIMESTAMP,
            "status": "uploading"
        }
        
        transaction = db.transaction()
        @firestore.transactional
        def upload_in_transaction(transaction):
            transaction.set(metadata_ref, metadata)
            for i, chunk_data in enumerate(chunks):
                chunk_ref = metadata_ref.collection("chunks").document(str(i))

                transaction.set(chunk_ref, {
                    "chunk": chunk_data,
                    "order": i  # Add the numeric index
                })

            transaction.update(metadata_ref, {"status": "completed"})

        upload_in_transaction(transaction)
        
        print(f"{media_type.capitalize()} '{file_name}' stored successfully as {media_id}")

    except Exception as e:
        print(f"Error storing {media_type}: {e}")
        try:
            metadata_ref.update({"status": "failed", "error": str(e)})
        except Exception as update_exception:
            print(f"Failed to update error status: {update_exception}")
        raise

def get_media_data(media_id: str) -> bytes:
    """
    Retrieves media data, using Redis as a cache, and falling back to Firestore.
    """
    # 1. Check Redis cache first
    if redis_client:
        try:
            cached_data = redis_client.get(media_id)
            if cached_data:
                print(f"CACHE HIT for mediaId: {media_id}")
                return cached_data
        except Exception as e:
            print(f"Redis cache check failed: {e}")

    print(f"CACHE MISS for mediaId: {media_id}. Fetching from Firestore...")

    # 2. If miss, get from Firestore
    if not db:
        raise ConnectionError("Firestore client is not available.")
        
    metadata_ref = db.collection(MEDIA_COLLECTION).document(media_id)
    metadata_doc = metadata_ref.get()

    if not metadata_doc.exists:
        raise FileNotFoundError(f"Media metadata not found for ID: {media_id}")

    metadata = metadata_doc.to_dict()
    status = metadata.get("status")
    if status != "completed":
        raise ValueError(f"Media is not ready. Status: {status}")
    
    total_chunks = metadata.get("totalChunks")
    if total_chunks is None:
        raise ValueError("Invalid metadata: totalChunks missing.")

    chunk_docs = metadata_ref.collection("chunks").order_by("order").stream()

    chunk_list = list(chunk_docs)
    if len(chunk_list) != total_chunks:
        raise IOError(f"Incomplete media data: Expected {total_chunks} chunks, but found {len(chunk_list)}")

    full_base64_string = "".join([doc.to_dict().get("chunk", "") for doc in chunk_list])
    
    media_bytes = base64.b64decode(full_base64_string)

    # 3. Store the reassembled data in Redis for next time
    if redis_client and media_bytes:
        try:
            # Cache for 1 hour
            redis_client.setex(media_id, 3600, media_bytes)
            print(f"Successfully stored mediaId {media_id} in Redis cache.")
        except Exception as e:
            print(f"Failed to store media in Redis cache: {e}")
            
    return media_bytes

@media_bp.route('/media/upload', methods=['POST'])
def upload_media_route():
    data = request.json
    if not data:
        return jsonify({"error": "Invalid JSON payload"}), 400
        
    base64_content = data.get('content')
    file_name = data.get('fileName', 'unknown_file')
    media_type = data.get('type')
    
    user_id = get_current_user_id()
    if not user_id:
        return jsonify({"error": "Authentication required. Provide 'X-User-ID' header."}), 401

    if not all([base64_content, media_type]):
        return jsonify({"error": "Missing required fields: 'content', 'type'"}), 400

    prefix = "img" if media_type == "image" else "aud"
    media_id = f"{prefix}_{int(time.time() * 1000)}"

    try:
        store_media(media_id, base64_content, file_name, media_type, user_id)
        return jsonify({
            "success": True,
            "mediaId": media_id,
            "message": "File uploaded successfully."
        }), 201
    except Exception as e:
        return jsonify({"error": f"Failed to upload file: {e}"}), 500


@media_bp.route('/media/get/<string:media_id>', methods=['GET'])
def get_media_route(media_id):
    user_id = get_current_user_id()
    if not user_id:
        return jsonify({"error": "Authentication required. Provide 'X-User-ID' header."}), 401
    
    try:
        media_bytes = get_media_data(media_id) # This calls your single, correct, caching function
        
        # --- THIS IS THE FIX FOR THE WEBSITE ---
        # 1. Create the response object.
        response = Response(media_bytes, mimetype='image/jpeg')
        
        # 2. Add the crucial CORS header to the response.
        #    The '*' allows any website to request this image.
        response.headers['Access-Control-Allow-Origin'] = '*'
        
        # 3. Return the response with the new header.
        return response

    except FileNotFoundError as e:
        return jsonify({"error": str(e)}), 404
    except (ValueError, IOError) as e:
        return jsonify({"error": str(e)}), 409
    except Exception as e:
        import traceback
        print(f"CRITICAL ERROR in get_media_route: {e}")
        print(traceback.format_exc())
        return jsonify({"error": str(e)}), 500

