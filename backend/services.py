# backend/services.py
import os
import firebase_admin
from firebase_admin import credentials, firestore
import google.generativeai as genai
import redis
from dotenv import load_dotenv

load_dotenv()

# --- 1. 全局变量 ---
db = None
redis_client = None
note_generation_model = None
chat_model = None
paper_solver_model = None
HyDE_generation_model = None


def init_all_services():
    """
    【统一入口】初始化所有外部服务
    被 app.py、tasks.py、任何脚本调用一次即可
    """
    global db, redis_client, note_generation_model, chat_model, paper_solver_model, HyDE_generation_model

    # === Gemini 初始化 ===
    API_KEY = os.getenv("GEMINI_API_KEY")
    if not API_KEY:
        raise ValueError("GEMINI_API_KEY missing in .env")
    genai.configure(api_key=API_KEY, transport='rest')

    note_generation_model = genai.GenerativeModel("gemini-2.5-flash")
    chat_model = genai.GenerativeModel("gemini-2.5-flash-lite")
    paper_solver_model = genai.GenerativeModel('gemini-2.5-flash-lite')
    HyDE_generation_model = genai.GenerativeModel('gemini-2.5-flash-lite')
    print("Gemini models initialized.")

    # === Firebase 初始化 ===
    try:
        firebase_admin.get_app()
    except ValueError:
        cred = credentials.Certificate("../firebase-credentials.json")
        firebase_admin.initialize_app(cred)
    db = firestore.client()
    print("Firestore initialized.")

    # === Redis 初始化（可选）===
    try:
        redis_client = redis.Redis(host='localhost', port=6379, db=0, decode_responses=False)
        redis_client.ping()
        print("Redis initialized.")
    except Exception as e:
        print(f"Redis unavailable: {e}. Caching partially disabled.")
        redis_client = None

    print("--- All services initialized successfully ---\n")


# 保留旧函数名是为了兼容现有代码（app.py 里已经用了 init_services）
def init_services():
    """旧接口，保持向后兼容"""
    init_all_services()