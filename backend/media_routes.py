# backend/media_routes.py - UPGRADED VERSION
"""
Media routes with industry-standard multi-tier caching
"""

import time
import base64
from flask import Blueprint, request, jsonify, Response
from firebase_admin import firestore

# Import the new cache manager
from services import db, cache_manager

media_bp = Blueprint('media_bp', __name__)

# Constants
MEDIA_COLLECTION = "media_metadata"
MAX_CHUNK_SIZE_BYTES = 900_000


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def get_current_user_id():
    """Placeholder for authentication logic."""
    return request.headers.get("X-User-ID")


def store_media(media_id: str, base64_string: str, file_name: str, 
                media_type: str, user_id: str):
    """
    Splits a Base64 string into chunks and stores it in Firestore.
    Invalidates cache after successful storage.
    """
    if not db:
        raise ConnectionError("Firestore client is not available.")

    print(f"📤 Storing media: {media_id} ({media_type})")
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
        
        # Use transaction for consistency
        transaction = db.transaction()
        
        @firestore.transactional
        def upload_in_transaction(transaction):
            transaction.set(metadata_ref, metadata)
            
            for i, chunk_data in enumerate(chunks):
                chunk_ref = metadata_ref.collection("chunks").document(str(i))
                transaction.set(chunk_ref, {
                    "chunk": chunk_data,
                    "order": i
                })
            
            transaction.update(metadata_ref, {"status": "completed"})

        upload_in_transaction(transaction)
        
        print(f"✅ Media stored: {media_id}")
        
        # Invalidate cache (new version might be uploaded)
        if cache_manager:
            cache_key = f"media:{media_id}"
            cache_manager.delete(cache_key)
            print(f"  🗑️ Cache invalidated for: {cache_key}")

    except Exception as e:
        print(f"❌ Error storing media: {e}")
        try:
            metadata_ref.update({"status": "failed", "error": str(e)})
        except:
            pass
        raise


def get_media_data(media_id: str) -> bytes:
    """
    Fetches media data with industry-standard multi-tier caching.
    
    Cache Strategy:
        - L1 (In-Memory): 5 min TTL
        - L2 (Redis): 1 hour TTL with jitter
        - L3 (Firestore): Source of truth
    """
    if not cache_manager:
        # Fallback to direct DB fetch if cache unavailable
        return _fetch_from_firestore(media_id)
    
    cache_key = f"media:{media_id}"
    
    # Use cache manager's get_or_set with stampede prevention
    return cache_manager.get_or_set(
        key=cache_key,
        factory=lambda: _fetch_from_firestore(media_id),
        ttl_l1=300,   # 5 minutes in L1
        ttl_l2=3600,  # 1 hour in L2
        use_lock=True  # Prevent cache stampede
    )


def _fetch_from_firestore(media_id: str) -> bytes:
    """
    Internal function to fetch media from Firestore.
    Called only on cache miss.
    """
    print(f"💾 Fetching from Firestore: {media_id}")
    
    if not db:
        raise ConnectionError("Firestore client is not available.")
        
    metadata_ref = db.collection(MEDIA_COLLECTION).document(media_id)
    metadata_doc = metadata_ref.get()

    if not metadata_doc.exists:
        raise FileNotFoundError(f"Media not found: {media_id}")

    metadata = metadata_doc.to_dict()
    status = metadata.get("status")
    
    if status != "completed":
        raise ValueError(f"Media not ready. Status: {status}")
    
    total_chunks = metadata.get("totalChunks")
    if total_chunks is None:
        raise ValueError("Invalid metadata: totalChunks missing")

    # Fetch chunks in order
    chunk_docs = metadata_ref.collection("chunks").order_by("order").stream()
    chunk_list = list(chunk_docs)
    
    if len(chunk_list) != total_chunks:
        raise IOError(
            f"Incomplete media: Expected {total_chunks} chunks, "
            f"found {len(chunk_list)}"
        )

    # Reassemble
    full_base64_string = "".join([
        doc.to_dict().get("chunk", "") 
        for doc in chunk_list
    ])
    
    media_bytes = base64.b64decode(full_base64_string)
    
    print(f"✅ Fetched from Firestore: {len(media_bytes):,} bytes")
    return media_bytes


# ============================================================================
# ROUTES
# ============================================================================

@media_bp.route('/media/upload', methods=['POST'])
def upload_media_route():
    """Upload media file"""
    data = request.json
    if not data:
        return jsonify({"error": "Invalid JSON payload"}), 400
        
    base64_content = data.get('content')
    file_name = data.get('fileName', 'unknown_file')
    media_type = data.get('type')
    
    user_id = get_current_user_id()
    if not user_id:
        return jsonify({
            "error": "Authentication required. Provide 'X-User-ID' header."
        }), 401

    if not all([base64_content, media_type]):
        return jsonify({
            "error": "Missing required fields: 'content', 'type'"
        }), 400

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
        return jsonify({"error": f"Failed to upload: {e}"}), 500


@media_bp.route('/media/get/<string:media_id>', methods=['GET'])
def get_media_route(media_id):
    """
    Get media file with automatic caching.
    Returns media with proper CORS headers.
    """
    user_id = get_current_user_id()
    if not user_id:
        return jsonify({
            "error": "Authentication required. Provide 'X-User-ID' header."
        }), 401
    
    try:
        # Get from cache (automatic L1 -> L2 -> DB fallback)
        media_bytes = get_media_data(media_id)
        
        # Create response with CORS headers
        response = Response(media_bytes, mimetype='image/jpeg')
        response.headers['Access-Control-Allow-Origin'] = '*'
        response.headers['Cache-Control'] = 'public, max-age=3600'  # Browser cache
        
        return response

    except FileNotFoundError as e:
        return jsonify({"error": str(e)}), 404
    except (ValueError, IOError) as e:
        return jsonify({"error": str(e)}), 409
    except Exception as e:
        import traceback
        print(f"❌ CRITICAL ERROR in get_media_route: {e}")
        print(traceback.format_exc())
        return jsonify({"error": str(e)}), 500


@media_bp.route('/media/delete/<string:media_id>', methods=['DELETE'])
def delete_media_route(media_id):
    """
    Delete media file and invalidate cache.
    """
    user_id = get_current_user_id()
    if not user_id:
        return jsonify({
            "error": "Authentication required"
        }), 401
    
    try:
        # Delete from Firestore
        metadata_ref = db.collection(MEDIA_COLLECTION).document(media_id)
        
        # Delete chunks
        for chunk in metadata_ref.collection("chunks").stream():
            chunk.reference.delete()
        
        # Delete metadata
        metadata_ref.delete()
        
        # Invalidate cache
        if cache_manager:
            cache_key = f"media:{media_id}"
            cache_manager.delete(cache_key)
            print(f"✅ Cache invalidated: {cache_key}")
        
        return jsonify({
            "success": True,
            "message": f"Media {media_id} deleted"
        }), 200
        
    except Exception as e:
        print(f"❌ Error deleting media: {e}")
        return jsonify({"error": str(e)}), 500


@media_bp.route('/media/cache/stats', methods=['GET'])
def get_cache_stats():
    """
    Get cache performance metrics (for monitoring/debugging).
    """
    if not cache_manager:
        return jsonify({
            "error": "Cache manager not available"
        }), 503
    
    try:
        stats = cache_manager.get_all_stats()
        return jsonify(stats), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@media_bp.route('/media/cache/clear', methods=['POST'])
def clear_cache():
    """
    Clear media cache (admin endpoint).
    """
    if not cache_manager:
        return jsonify({
            "error": "Cache manager not available"
        }), 503
    
    try:
        # Clear only media-related keys
        if cache_manager.l2 and cache_manager.l2.available:
            cache_manager.l2.clear(pattern="media:*")
        
        if cache_manager.l1:
            # L1 doesn't support pattern clearing, so clear all
            cache_manager.l1.clear()
        
        return jsonify({
            "success": True,
            "message": "Media cache cleared"
        }), 200
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500