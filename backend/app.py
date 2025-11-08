import os
import firebase_admin
import google.generativeai as genai
import pytesseract
from firebase_admin import credentials, firestore
from flask import Flask, jsonify
from flask_cors import CORS
from dotenv import load_dotenv

# Import your blueprints and their dependency setters
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

# Initialize model objects ONCE and reuse them
note_generation_model = genai.GenerativeModel("gemini-2.5-flash-lite") # Updated for better performance
chat_model = genai.GenerativeModel("gemini-2.5-flash-lite")
paper_solver_model = genai.GenerativeModel('gemini-2.5-flash-lite')
print("✅ Gemini models initialized successfully.")

# Tesseract OCR (Optional, for PDF image text extraction)
try:
    # On Windows, you might need to set the path explicitly
    pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'
    print("✅ Tesseract path configured.")
except Exception:
    # On other OS (Linux, Mac), Tesseract is often in the system PATH
    print("⚠️  Warning: Tesseract explicit path not found. It must be in the system's PATH for OCR to work.")

# Firebase
try:
    # Ensure your credentials file is in the parent directory or update the path
    cred = credentials.Certificate("../firebase-credentials.json")
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    print("✅ Firestore client initialized successfully.")
except Exception as e:
    print(f"❌ Failed to initialize Firebase: {e}")
    # Exit if Firebase connection fails, as the app is unusable
    exit()

# --- FLASK APP SETUP ---
app = Flask(__name__)
# Configure CORS to allow headers needed by your frontend
CORS(app, expose_headers=["Content-Disposition"], allow_headers=["X-User-ID", "Content-Type"])

# --- INJECT DEPENDENCIES & REGISTER BLUEPRINTS ---
# Each blueprint is configured and registered ONLY ONCE.

# Media Routes (for general file handling, if any)
set_media_deps(db)
app.register_blueprint(media_bp)

# Study Hub Routes (for projects, sources, notes, chatbot)
set_study_hub_deps(db, note_generation_model, chat_model)
app.register_blueprint(study_hub_bp)

# Paper Solver Routes
set_paper_solver_deps(db, paper_solver_model)
app.register_blueprint(paper_solver_bp)

print("✅ All blueprints registered successfully.")

# --- GENERAL PURPOSE & HEALTH-CHECK ROUTES ---

@app.route('/api/hello')
def hello():
    """A simple health-check endpoint."""
    return jsonify({"message": "Hello from your Python Backend!"})

@app.route('/test-models')
def test_models():
    """Endpoint to verify connection to Google AI and list available models."""
    try:
        print("🔍 Checking available Gemini models...")
        models = genai.list_models()
        available = [
            {'name': m.name, 'display_name': m.display_name}
            for m in models if 'generateContent' in m.supported_generation_methods
        ]
        return jsonify({"success": True, "available_models": available})
    except Exception as e:
        import traceback
        print(f"❌ Model test failed: {e}")
        return jsonify({"success": False, "error": str(e), "traceback": traceback.format_exc()}), 500

# --- RUN THE APP ---
if __name__ == '__main__':
    # Use port 5001 or another port if 5000 is in use
    app.run(host='0.0.0.0', port=5000, debug=True)