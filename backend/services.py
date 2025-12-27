# backend/services.py
import os
import threading  # <--- Added missing import
import firebase_admin
from firebase_admin import credentials, firestore
from google import genai # New SDK
from dotenv import load_dotenv

# Import the new cache manager
from cache_manager import CacheManager

load_dotenv()

# --- Global Variables ---
db = None
ai_client = None  # <--- New SDK uses a Client object
# These will now store model NAMES (strings) for use with the new client
note_generation_model = "gemini-2.0-flash" 
chat_model = "gemini-2.0-flash-lite"
paper_solver_model = "gemini-2.0-flash-lite"
HyDE_generation_model = "gemini-2.0-flash-lite"

# --- NEW: Global Cache Manager ---
cache_manager: CacheManager = None


def init_all_services(start_browser=False): # <--- Added flag to control Browser
    """
    【Enhanced】Initialize all external services with industry-standard caching
    """
    global db, cache_manager, ai_client

    print("\n" + "="*70)
    print("🚀 INITIALIZING SERVICES")
    print("="*70)

    # === 1. Initialize Cache Manager FIRST ===
    print("\n📦 Step 1: Initializing Cache System...")
    try:
        cache_manager = CacheManager(
            l1_config={'max_size': 2000, 'default_ttl': 300, 'name': 'AppCache-L1'},
            l2_config={
                'host': os.getenv('REDIS_HOST', 'localhost'),
                'port': int(os.getenv('REDIS_PORT', 6379)),
                'password': os.getenv('REDIS_PASSWORD'),
                'default_ttl': 3600,
                'name': 'AppCache-L2',
                'max_connections': 50
            },
            enable_l1=True,
            enable_l2=True
        )
        print("✅ Cache Manager initialized successfully")
    except Exception as e:
        print(f"⚠️ Cache initialization failed: {e}")
        cache_manager = None

    # === 2. Gemini Initialization (NEW SDK SYNTAX) ===
    print("\n🤖 Step 2: Initializing Gemini AI Client...")
    API_KEY = os.getenv("GEMINI_API_KEY")
    if not API_KEY:
        raise ValueError("GEMINI_API_KEY missing in .env")
    
    # New google-genai Client initialization
    ai_client = genai.Client(api_key=API_KEY)
    print("✅ New Gemini GenAI Client initialized")

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

    # === 4. Initialize Browser Bridge (Conditional) ===
    if start_browser:
        print("\n🌐 Step 4: Launching Browser Bridge...")
        try:
            # We import here (Lazy Loading) to prevent Celery from crashing
            from browser_bridge import browser_bridge
            
            # FIX: Call start directly. The method itself handles threading.
            browser_bridge.start()
            
            print("✅ Browser Bridge thread started")
        except Exception as e:
            print(f"⚠️ Browser bridge failed: {e}")

    print("\n" + "="*70)
    print("✅ INITIALIZATION COMPLETE")
    print("="*70 + "\n")


def init_services():
    init_all_services(start_browser=False)

# Export variables
__all__ = [
    'db',
    'cache_manager',
    'ai_client',
    'note_generation_model',
    'chat_model',
    'paper_solver_model',
    'HyDE_generation_model',
    'init_all_services',
    'init_services'
]