# backend/config.py
from pathlib import Path

# --- Database Collections ---
STUDY_PROJECTS_COLLECTION = "projects"
CODE_PROJECTS_COLLECTION = "code_projects"
CODE_FILES_SUBCOLLECTION = "synced_code_files"
CODE_GRAPH_COLLECTION = "code_graph_nodes"

# --- Vector Store ---
VECTOR_STORE_ROOT = Path("vector_stores")
VECTOR_STORE_ROOT.mkdir(parents=True, exist_ok=True)

# --- Cache ---
NULL_CACHE_VALUE = "##NULL##"

# --- Embedding ---
EMBEDDING_MODEL = "models/text-embedding-004"
EMBEDDING_DIM = 768
CROSS_ENCODER_MODEL = "cross-encoder/ms-marco-MiniLM-L-6-v2"

# --- 🚀 TUNED RETRIEVAL PARAMETERS (Aggressive) ---
MAX_HOPS = 4                # Explore deeper dependencies
DECAY_ALPHA = 0.1           # Very slow decay (keeps distant nodes relevant)
SOFTMAX_TEMPERATURE = 0.3   # Flattens probability distribution
ENTROPY_THRESHOLD = 0.05    # Allow very similar nodes (don't filter much)
MAX_CONTEXT_TOKENS = 120000 # Massive context window for Gemini 1.5/2.0