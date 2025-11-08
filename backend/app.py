# backend/app.py
import os
import firebase_admin
import google.generativeai as genai
from firebase_admin import credentials, firestore
from flask import Flask, jsonify
from flask_cors import CORS
from dotenv import load_dotenv
import pytesseract 
import redis

# --- 1. CORRECTED IMPORTS ---
# Import all blueprints and their dependency setters
from media_routes import media_bp, set_dependencies as set_media_deps
from study_hub_routes import study_hub_bp, set_dependencies as set_study_hub_deps
from paper_solver_routes import paper_solver_bp, set_dependencies as set_paper_solver_deps
from code_converter_routes import code_converter_bp, set_dependencies as set_code_converter_deps
from sync_service_routes import sync_service_bp, set_dependencies as set_sync_service_deps

# --- LOAD .env ---
load_dotenv()   

# --- CONFIG & INITIALIZATION ---

# Gemini
API_KEY = os.getenv("GEMINI_API_KEY")
if not API_KEY:
    raise ValueError("GEMINI_API_KEY missing in .env")
genai.configure(api_key=API_KEY, transport='rest')

# Create a single, shared instance of the Gemini model
gemini_pro_model = genai.GenerativeModel('models/gemini-pro-latest')
print("✅ Gemini Pro model initialized successfully.")

# Tesseract OCR
try:
    pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'
    print("✅ Tesseract path configured.")
except Exception:
    print("⚠️  Warning: Tesseract path not found. OCR will fail if needed.")

# Firebase
cred = credentials.Certificate("../firebase-credentials.json")
firebase_admin.initialize_app(cred)
db = firestore.client()
print("✅ Firestore client initialized successfully.")

# Redis
try:
    redis_client = redis.Redis(host='localhost', port=6379, db=0, decode_responses=False)
    redis_client.ping()
    print("✅ Redis client connected successfully.")
except redis.exceptions.ConnectionError as e:
    print(f"❌ Redis connection failed: {e}. Caching will be disabled.")
    redis_client = None

# --- FLASK APP SETUP ---
app = Flask(__name__)
CORS(app, expose_headers=["Content-Disposition"], allow_headers=["X-User-ID", "Content-Type"])


# --- 2. CORRECTED DEPENDENCY INJECTION & REGISTRATION ---
print("\n--- Registering Blueprints ---")

print("  - Registering Media Routes...")
set_media_deps(db, redis_client)
app.register_blueprint(media_bp)

print("  - Registering Study Hub Routes...")
set_study_hub_deps(db, gemini_pro_model, redis_client)
app.register_blueprint(study_hub_bp)

print("  - Registering Paper Solver Routes...")
set_paper_solver_deps(db, gemini_pro_model, redis_client) # <-- Added redis_client
app.register_blueprint(paper_solver_bp)

print("  - Registering Code Converter Routes...")
set_code_converter_deps(db)
app.register_blueprint(code_converter_bp)

print("  - Registering Sync Service Routes...")
set_sync_service_deps(db)
app.register_blueprint(sync_service_bp)

# --- DELETED OBSOLETE REGISTRATION ---
# app.register_blueprint(project_converter_bp) # This was causing a NameError
print("--- All blueprints registered. ---\n")


# --- GENERAL PURPOSE ROUTES ---
@app.route('/api/hello')
def hello():
    return jsonify({"message": "Hello from your Python Backend!"})

@app.route('/test-models')
def test_models():
    try:
        print("🔍 Checking available models...")
        models = genai.list_models()
        available = []
        for m in models:
            if 'generateContent' in m.supported_generation_methods:
                available.append({
                    'name': m.name,
                    'display_name': m.display_name,
                })
        return jsonify({ "success": True, "available_models": available })
    except Exception as e:
        import traceback
        return jsonify({ "success": False, "error": str(e), "traceback": traceback.format_exc() }), 500


if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=True)