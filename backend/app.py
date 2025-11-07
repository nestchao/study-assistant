# backend/app.py
import os
import firebase_admin
import google.generativeai as genai
from firebase_admin import credentials, firestore
from flask import Flask, jsonify
from flask_cors import CORS
from dotenv import load_dotenv
import pytesseract # <-- MISSING IMPORT

# Import your blueprints and dependency setters
from media_routes import media_bp, set_dependencies as set_media_deps
from study_hub_routes import study_hub_bp, set_dependencies as set_study_hub_deps
from paper_solver_routes import paper_solver_bp, set_dependencies as set_paper_solver_deps

# --- LOAD .env ---
load_dotenv()

# --- CONFIG & INITIALIZATION ---

# Gemini
API_KEY = os.getenv("GEMINI_API_KEY")
if not API_KEY:
    raise ValueError("GEMINI_API_KEY missing in .env")
genai.configure(api_key=API_KEY, transport='rest')

# --- THIS IS THE FIX ---
# Create a single, shared instance of the Gemini model
gemini_pro_model = genai.GenerativeModel('models/gemini-pro-latest')
print("✅ Gemini Pro model initialized successfully.")
# --- END OF FIX ---

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


# --- FLASK APP SETUP ---
app = Flask(__name__)
CORS(app, expose_headers=["Content-Disposition"], allow_headers=["X-User-ID", "Content-Type"])


# --- INJECT DEPENDENCIES & REGISTER BLUEPRINTS ---
set_media_deps(db)
app.register_blueprint(media_bp)

set_study_hub_deps(db, gemini_pro_model)
app.register_blueprint(study_hub_bp)

set_paper_solver_deps(db, gemini_pro_model)
app.register_blueprint(paper_solver_bp)


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
    app.run(host='0.0.0.0', port=5000, debug=True)