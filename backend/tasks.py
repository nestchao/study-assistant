# backend/tasks.py
import sys
from pathlib import Path

# === 关键修复：把 backend 目录加入 Python 路径 ===
sys.path.append(str(Path(__file__).parent))

from celery import Celery
from dotenv import load_dotenv
import services
import json

load_dotenv()

# === 关键：Celery worker 启动时也初始化一次 ===
services.init_all_services()

celery = Celery(
    'tasks',
    broker='amqp://guest:guest@localhost:5672//',
    backend='redis://localhost:6379/0'
)

# Firebase 客户端已经在 init_all_services 里初始化了
db = services.db

@celery.task(bind=True)
def background_perform_sync(self, project_id):
    print(f"RabbitMQ Worker: Starting sync for {project_id}")
    try:
        project_ref = db.collection("code_projects").document(project_id)
        project_doc = project_ref.get()
        if not project_doc.exists:
            return {"status": "error", "message": "Project not found"}

        config_data = project_doc.to_dict()
        from sync_logic import perform_sync, force_reindex_project

        file_result = perform_sync(db, project_id, config_data)
        graph_result = force_reindex_project(db, project_id)

        return {
            "status": "completed",
            "project_id": project_id,
            "files": file_result,
            "graph": graph_result
        }
    except Exception as e:
        print(f"Task Failed: {e}")
        import traceback
        traceback.print_exc()
        raise e