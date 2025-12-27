# backend/code_graph_engine.py

import math
import numpy as np
import faiss
import pickle
from pathlib import Path
from sentence_transformers import CrossEncoder
import google.generativeai as genai
from collections import deque
import tiktoken

# --- MODIFIED: Import Browser Bridge ---
from browser_bridge import browser_bridge 

# --- 从配置文件导入 ---
from config import (
    EMBEDDING_MODEL,
    EMBEDDING_DIM,
    CROSS_ENCODER_MODEL,
    DECAY_ALPHA,
    SOFTMAX_TEMPERATURE,
    MAX_HOPS,
    ENTROPY_THRESHOLD,
    MAX_CONTEXT_TOKENS
)

# ============================================================================
# INDUSTRY STANDARD: FAISS Vector Store
# ============================================================================

class FaissVectorStore:
    """
    使用 FAISS 的高性能向量存储
    支持百万级节点的毫秒级检索
    """
    
    def __init__(self, dimension=EMBEDDING_DIM):
        self.dimension = dimension
        self.index = faiss.IndexHNSWFlat(dimension, 32)
        self.index.hnsw.efConstruction = 40
        self.index.hnsw.efSearch = 16
        self.node_map = {}
        self.id_to_name = {}
        self.name_to_id = {}
        self.nodes_list = []
        
    def add_nodes(self, nodes):
        if not nodes: return
        vectors = [n.vector for n in nodes if n.vector]
        if not vectors: return
        start_idx = self.index.ntotal
        vectors = np.array(vectors).astype('float32')
        faiss.normalize_L2(vectors)
        self.index.add(vectors)
        
        idx = start_idx
        for node in nodes:
            if not node.vector: continue
            node_dict = node.to_dict()
            # Use ID as the unique key
            unique_key = node.id 
            self.node_map[idx] = node_dict
            self.id_to_name[idx] = unique_key
            self.name_to_id[unique_key] = idx
            self.nodes_list.append(node_dict)
            idx += 1
        print(f"  ✅ Added {len(vectors)} nodes to FAISS. Total: {self.index.ntotal}")
    
    def search(self, query_vector, k=200): 
        if self.index.ntotal == 0: return []
        query_vec = np.array([query_vector]).astype('float32')
        faiss.normalize_L2(query_vec)
        scores, indices = self.index.search(query_vec, min(k, self.index.ntotal))
        results = []
        for i, idx in enumerate(indices[0]):
            if idx == -1 or idx not in self.node_map: continue
            results.append({'node': self.node_map[idx], 'faiss_score': float(scores[0][i])})
        return results

    def get_all_nodes(self):
        return self.nodes_list
    
    def get_node_by_name(self, name):
        """通过名称查找节点"""
        idx = self.name_to_id.get(name)
        if idx is not None:
            return self.node_map.get(idx)
        return None
    
    def save(self, path: Path):
        path.mkdir(parents=True, exist_ok=True)
        if not self.nodes_list and self.node_map:
             self.nodes_list = list(self.node_map.values())
        faiss.write_index(self.index, str(path / "faiss.index"))
        with open(path / "metadata.pkl", 'wb') as f:
            pickle.dump({'node_map': self.node_map, 'nodes_list': self.nodes_list}, f)
    
    @classmethod
    def load(cls, path: Path):
        store = cls()
        store.index = faiss.read_index(str(path / "faiss.index"))
        with open(path / "metadata.pkl", 'rb') as f:
            d = pickle.load(f)
            store.node_map = d.get('node_map', {})
            store.nodes_list = d.get('nodes_list', [])
            
            # --- FIX: Rebuild lookup maps ---
            print(f"  🔄 Rebuilding lookup maps for {len(store.node_map)} nodes...")
            for idx, node_data in store.node_map.items():
                unique_key = node_data['id']
                store.id_to_name[idx] = unique_key
                store.name_to_id[unique_key] = idx
            print("  ✅ Lookup maps rebuilt.")
            # -------------------------------
            
        return store

# ============================================================================
# E-BASED: Exponential Decay Graph Traversal
# ============================================================================

def exponential_graph_expansion(vector_store, seed_nodes, max_nodes=150, max_hops=4, alpha=0.05):
    print(f"START exponential_graph_expansion (Seed count: {len(seed_nodes)})")
    
    visited = {}
    queue = deque()

    # 1. Initialize Seeds
    # Take more seeds to guarantee volume
    for seed in seed_nodes[:40]:
        node = seed['node']
        uid = node['id']
        if uid not in visited:
            score = seed.get('faiss_score', 1.0)
            visited[uid] = {'node': node, 'distance': 0, 'graph_score': score}
            queue.append((node, 0, score))

    # 2. Build SMART Map (Simple Name -> [Nodes])
    all_nodes = vector_store.get_all_nodes()
    smart_map = {}

    unique_names = set()
    
    for n in all_nodes:
        smart_map.setdefault(n['name'], []).append(n)
        unique_names.add(n['name'])
        
        if '.' in n['name']:
            simple_name = n['name'].split('.')[-1]
            smart_map.setdefault(simple_name, []).append(n)

    # 3. Traverse
    while queue and len(visited) < max_nodes:
        curr, dist, base_score = queue.popleft()
        if dist >= max_hops: continue
        
        current_file_path = curr.get('file_path')

        for dep in curr.get('dependencies', []):
            candidates = smart_map.get(dep, [])
            
            for cand in candidates:
                uid = cand['id']
                if uid in visited: continue
                
                weight_boost = 1.0
                if cand['file_path'] == current_file_path: weight_boost = 1.5
                if cand['name'] == dep: weight_boost = 1.3

                new_dist = dist + 1
                new_score = base_score * math.exp(-alpha * new_dist) * weight_boost
                
                visited[uid] = {'node': cand, 'distance': new_dist, 'graph_score': new_score}
                queue.append((cand, new_dist, new_score))

    # 4. Force Fill if graph is sparse
    if len(visited) < 80:
        print(f"  ⚠️ Graph expansion weak ({len(visited)} nodes). Force-filling from FAISS seeds...")
        for seed in seed_nodes:
            if len(visited) >= 100: break
            node = seed['node']
            uid = node['id']
            if uid not in visited:
                visited[uid] = {'node': node, 'distance': 0, 'graph_score': seed.get('faiss_score', 0.5)}

    results = sorted(visited.values(), key=lambda x: x['graph_score'], reverse=True)
    return results

# ============================================================================
# E-BASED: Softmax Multi-Dimensional Scoring
# ============================================================================

def softmax(x, temperature=SOFTMAX_TEMPERATURE):
    x = np.array(x)
    if len(x) == 0: return []
    exp_x = np.exp((x - np.max(x)) / temperature)
    return exp_x / np.sum(exp_x)

def multi_dimensional_scoring(candidates, intent):
    for c in candidates:
        s_weight = c['node']['weights'].get('structural', 0.5)
        c['final_score'] = c['graph_score'] * (0.8 + (s_weight * 0.2))
    
    return sorted(candidates, key=lambda x: x['final_score'], reverse=True)

# ============================================================================
# INDUSTRY STANDARD: Cross-Encoder Reranking
# ============================================================================

class CrossEncoderReranker:
    def __init__(self, model_name=CROSS_ENCODER_MODEL):
        print(f"  🔄 Loading Cross-Encoder: {model_name}...")
        try:
            self.model = CrossEncoder(model_name, max_length=512)
            print(f"  ✅ Cross-Encoder loaded")
        except Exception as e:
            print(f"  ⚠️ Failed to load Cross-Encoder: {e}")
            self.model = None
    
    def rerank(self, query, candidates, top_k=20):
        if not candidates or not self.model:
            return candidates[:top_k]
        
        pairs = []
        for candidate in candidates:
            node = candidate['node']
            doc_text = f"""
            Function/Class: {node['name']}
            File: {node['file_path']}
            Type: {node.get('type', 'unknown')}
            Description: {node.get('docstring', 'No description')}
            Code Preview: {node['content'][:300]}
            """.strip()
            pairs.append([query, doc_text])
        
        try:
            scores = self.model.predict(pairs, show_progress_bar=False)
            
            if len(scores) > 0:
                min_score = min(scores)
                max_score = max(scores)
                if max_score > min_score:
                    scores = [(s - min_score) / (max_score - min_score) for s in scores]
                else:
                    scores = [0.5] * len(scores)
            
            for i, candidate in enumerate(candidates):
                candidate['cross_encoder_score'] = float(scores[i])
            
            reranked = sorted(candidates, key=lambda x: x['cross_encoder_score'], reverse=True)
            print(f"  🎯 Cross-Encoder reranking: Top score = {reranked[0]['cross_encoder_score']:.4f}")
            return reranked[:top_k]
            
        except Exception as e:
            print(f"  ❌ Cross-Encoder error: {e}")
            return candidates[:top_k]

# ============================================================================
# E-BASED: Information Entropy Diversity Filter
# ============================================================================

def entropy_diversity_filter(candidates, max_nodes=80):
    selected = []
    seen = set()
    for c in candidates:
        if len(selected) >= max_nodes: break
        if c['node']['id'] in seen: continue
        seen.add(c['node']['id'])
        selected.append(c)
    return selected

# ============================================================================
# HYBRID: Hierarchical Context Assembly
# ============================================================================

def build_hierarchical_context(candidates, max_tokens=MAX_CONTEXT_TOKENS):
    print(f"  📝 Assembling context with limit: {max_tokens} tokens...")
    try:
        enc = tiktoken.get_encoding("cl100k_base")
    except:
        enc = None 

    context_parts = []
    current_tokens = 0
    
    for i, cand in enumerate(candidates):
        node = cand['node']
        
        entry = f"\n\n# FILE: {node['file_path']} | NODE: {node['name']} (Type: {node['type']})\n"
        entry += f"{'-'*50}\n{node['content']}\n{'-'*50}\n"
        
        count = len(enc.encode(entry)) if enc else len(entry) // 4
        
        if current_tokens + count > max_tokens:
            print(f"  🛑 Token limit reached at node {i+1}/{len(candidates)}")
            break
            
        context_parts.append(entry)
        current_tokens += count

    final_ctx = "".join(context_parts)
    print(f"  ✅ Context assembled: {current_tokens:,} tokens from {len(context_parts)} nodes.")
    return final_ctx

# ============================================================================
# MAIN RETRIEVAL PIPELINE
# ============================================================================

def hybrid_retrieval_pipeline(project_id, user_query, db_instance, vector_store, cross_encoder, use_hyde=True, return_nodes_only=False):
    print(f"🚀 Starting Hybrid Retrieval for: {user_query}")
    
    # 1. HyDE via BROWSER BRIDGE (Updated)
    search_query = user_query
    if use_hyde:
        try:
            print("  🧠 Generating HyDE via Browser Bridge...")
            # Make sure bridge is started
            browser_bridge.start()
            
            # Send prompt to generate hypothetical code
            # Note: This will result in code being typed in the browser window
            hyde = browser_bridge.send_prompt(f"Write a short, high-level python pseudo-code implementation for: {user_query}")
            
            # Use the result to augment the search
            search_query += "\n" + hyde
            print("  ✅ HyDE generated.")
        except Exception as e:
            print(f"  ⚠️ HyDE failed: {e}")

    # 2. Search (Get many seeds)
    query_emb = genai.embed_content(model=EMBEDDING_MODEL, content=search_query, task_type="retrieval_query")['embedding']
    seeds = vector_store.search(query_emb, k=150)
    
    # 3. Expand (Aggressive)
    expanded = exponential_graph_expansion(vector_store, seeds, max_nodes=150)
    
    # 4. Score
    scored = multi_dimensional_scoring(expanded, 'explain')
    
    # 5. Filter (Keep lots)
    final_nodes = entropy_diversity_filter(scored, max_nodes=80)
    
    if return_nodes_only:
        print(f"  🔙 Returning {len(final_nodes)} candidate nodes for user review.")
        sanitized_nodes = []
        for item in final_nodes:
            node = item['node']
            sanitized_nodes.append({
                'id': node['id'],
                'name': node['name'],
                'file_path': node['file_path'],
                'type': node['type'],
                'score': item.get('final_score', 0.0),
                'ai_summary': node.get('ai_summary', '') 
            })
        return sanitized_nodes

    # 6. Context
    context = build_hierarchical_context(final_nodes)
    
    return context