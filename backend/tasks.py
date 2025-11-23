# backend/tasks.py
from celery import Celery
from firebase_admin import firestore, initialize_app, credentials, get_app
from dotenv import load_dotenv 
import google.generativeai as genai
import os

# --- CHANGE IMPORT HERE ---
from sync_logic import perform_sync, force_reindex_project 

load_dotenv() 

API_KEY = os.getenv("GEMINI_API_KEY")
if API_KEY:
    genai.configure(api_key=API_KEY, transport='rest')
    print("✅ Celery Worker: Gemini API Key configured.")
else:
    print("❌ Celery Worker: GEMINI_API_KEY missing!")

# Setup Celery
celery = Celery(
    'tasks',
    broker='amqp://guest:guest@localhost:5672//',
    backend='redis://localhost:6379/0'
)

# Setup DB for Worker
try:
    get_app() 
    db = firestore.client()
except ValueError:
    # Ensure this path is correct relative to where you run 'celery' command
    cred = credentials.Certificate("../firebase-credentials.json") 
    initialize_app(cred)
    db = firestore.client()

@celery.task(bind=True)
def background_perform_sync(self, project_id):
    print(f"🐰 RabbitMQ Worker: Starting sync for {project_id}")
    
    try:
        # 1. Fetch Config
        project_ref = db.collection("code_projects").document(project_id)
        project_doc = project_ref.get()
        
        if not project_doc.exists:
            return {"status": "error", "message": "Project not found"}
            
        config_data = project_doc.to_dict()

        # 2. Run Logic (Passing the worker's DB connection)
        file_result = perform_sync(db, project_id, config_data)
        graph_result = force_reindex_project(db, project_id)
        
        return {
            "status": "completed", 
            "project_id": project_id,
            "files": file_result,
            "graph": graph_result
        }
        
    except Exception as e:
        print(f"❌ Task Failed: {e}")
        self.update_state(state='FAILURE', meta={'error': str(e)})
        # Re-raise to ensure Celery marks it failed
        raise e