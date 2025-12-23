# backend/services.py - UPGRADED VERSION
"""
Enhanced services initialization with industry-standard caching
"""

import os
import firebase_admin
from firebase_admin import credentials, firestore
import google.generativeai as genai
from dotenv import load_dotenv

# Import the new cache manager
from cache_manager import CacheManager, get_cache_manager

load_dotenv()

# --- Global Variables ---
db = None
note_generation_model = None
chat_model = None
paper_solver_model = None
HyDE_generation_model = None

# --- NEW: Global Cache Manager ---
cache_manager: CacheManager = None


def init_all_services():
    """
    【Enhanced】Initialize all external services with industry-standard caching
    """
    global db, cache_manager
    global note_generation_model, chat_model, paper_solver_model, HyDE_generation_model

    print("\n" + "="*70)
    print("🚀 INITIALIZING SERVICES")
    print("="*70)

    # === 1. Initialize Cache Manager FIRST ===
    print("\n📦 Step 1: Initializing Cache System...")
    try:
        cache_manager = CacheManager(
            l1_config={
                'max_size': 2000,        # Increased capacity
                'default_ttl': 300,      # 5 minutes
                'name': 'AppCache-L1'
            },
            l2_config={
                'host': os.getenv('REDIS_HOST', 'localhost'),
                'port': int(os.getenv('REDIS_PORT', 6379)),
                'password': os.getenv('REDIS_PASSWORD'),
                'default_ttl': 3600,     # 1 hour
                'name': 'AppCache-L2',
                'max_connections': 50
            },
            enable_l1=True,
            enable_l2=True
        )
        print("✅ Cache Manager initialized successfully")
        
        # Print initial stats
        stats = cache_manager.get_all_stats()
        print(f"   L1: {stats['tiers']['l1']['max_size']} max entries")
        print(f"   L2: {'Connected' if stats['tiers']['l2']['available'] else 'Unavailable'}")
        
    except Exception as e:
        print(f"⚠️ Cache initialization failed (will continue without caching): {e}")
        cache_manager = None

    # === 2. Gemini Initialization ===
    print("\n🤖 Step 2: Initializing Gemini AI Models...")
    API_KEY = os.getenv("GEMINI_API_KEY")
    if not API_KEY:
        raise ValueError("GEMINI_API_KEY missing in .env")
    
    genai.configure(api_key=API_KEY, transport='rest')
    
    note_generation_model = genai.GenerativeModel("gemini-2.5-flash")
    chat_model = genai.GenerativeModel("gemini-2.5-flash-lite")
    paper_solver_model = genai.GenerativeModel('gemini-2.5-flash-lite')
    HyDE_generation_model = genai.GenerativeModel('gemini-2.5-flash-lite')
    
    print("✅ Gemini models initialized")

    # === 3. Firebase Initialization ===
    print("\n🔥 Step 3: Initializing Firebase...")
    try:
        firebase_admin.get_app()
        print("✅ Firebase already initialized")
    except ValueError:
        cred = credentials.Certificate("../firebase-credentials.json")
        firebase_admin.initialize_app(cred)
        print("✅ Firebase initialized")
    
    db = firestore.client()

    print("\n" + "="*70)
    print("✅ ALL SERVICES INITIALIZED SUCCESSFULLY")
    print("="*70 + "\n")


# Keep backward compatibility
def init_services():
    """Legacy function name - kept for compatibility"""
    init_all_services()


# Export cache manager for use in other modules
__all__ = [
    'db',
    'cache_manager',
    'note_generation_model',
    'chat_model',
    'paper_solver_model',
    'HyDE_generation_model',
    'init_all_services',
    'init_services'
]