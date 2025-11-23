# backend/services.py
import os
import firebase_admin
from firebase_admin import credentials, firestore
import google.generativeai as genai
import redis
from dotenv import load_dotenv
from google.api_core import retry, exceptions

# Load env immediately
load_dotenv()

# --- 1. GLOBALS (Defined once here) ---
db = None
redis_client = None
note_generation_model = None
chat_model = None
paper_solver_model = None
HyDE_generation_model = None

def init_services():
    """Initializes all external services. Call this once in app.py"""
    global db, redis_client, note_generation_model, chat_model, paper_solver_model

    # --- GEMINI SETUP ---
    API_KEY = os.getenv("GEMINI_API_KEY")
    if not API_KEY:
        raise ValueError("GEMINI_API_KEY missing in .env")
    genai.configure(api_key=API_KEY, transport='rest')

    # Initialize Models
    note_generation_model = genai.GenerativeModel("gemini-2.5-flash")
    chat_model = genai.GenerativeModel("gemini-2.5-flash-lite")
    paper_solver_model = genai.GenerativeModel('gemini-2.5-flash-lite')
    HyDE_generation_model = genai.GenerativeModel('gemini-2.5-flash-lite')
    print("✅ Gemini services initialized.")

    # --- FIREBASE SETUP ---
    try:
        # Check if already initialized (for Celery/Hot Reload)
        try:
            firebase_admin.get_app()
        except ValueError:
            cred = credentials.Certificate("../firebase-credentials.json")
            firebase_admin.initialize_app(cred)
        
        db = firestore.client()
        print("✅ Firestore initialized.")
    except Exception as e:
        print(f"❌ Firebase init failed: {e}")
        raise e

    # --- REDIS SETUP ---
    try:
        redis_client = redis.Redis(host='localhost', port=6379, db=0, decode_responses=False)
        redis_client.ping()
        print("✅ Redis initialized.")
    except Exception as e:
        print(f"⚠️ Redis failed: {e}. Caching disabled.")
        redis_client = None

    print("✅ --- Initialization completed ---")