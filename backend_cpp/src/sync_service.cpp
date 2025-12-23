#include "sync_service.hpp"
#include <string>
#include <vector>
#include <unordered_map>
#include <filesystem>
#include <fstream>
#include <memory>
#include <unordered_set>
#include <algorithm>
#include <cctype>
#include <spdlog/spdlog.h>
#include <nlohmann/json.hpp>
#include "code_graph.hpp"
#include "embedding_service.hpp"
#include <map>

namespace code_assistance {

namespace fs = std::filesystem;
using json = nlohmann::json;

struct VisualNode {
    std::map<std::string, VisualNode> children;
};

// --- UTILITIES ---

// Case-insensitive, separator-agnostic path comparison
bool paths_are_equal(const fs::path& p1, const fs::path& p2) {
    std::string s1 = p1.string();
    std::string s2 = p2.string();
    std::transform(s1.begin(), s1.end(), s1.begin(), ::tolower);
    std::transform(s2.begin(), s2.end(), s2.begin(), ::tolower);
    
    // Normalize separators
    std::replace(s1.begin(), s1.end(), '\\', '/');
    std::replace(s2.begin(), s2.end(), '\\', '/');
    
    // Strip trailing slashes
    if (!s1.empty() && s1.back() == '/') s1.pop_back();
    if (!s2.empty() && s2.back() == '/') s2.pop_back();

    return s1 == s2;
}

// Check if child is inside parent (or equal)
bool is_inside(const fs::path& child, const fs::path& parent) {
    if (parent.empty()) return false;
    
    // Normalize both paths to remove dots and redundant slashes
    auto c = child.lexically_normal();
    auto p = parent.lexically_normal();

    auto it_c = c.begin();
    auto it_p = p.begin();

    while (it_p != p.end()) {
        // If parent has a trailing slash, lexically_normal might leave a "." segment. 
        // We skip it.
        if (it_p->string() == "." || it_p->string().empty()) {
            ++it_p;
            continue;
        }

        if (it_c == c.end()) return false;
        
        std::string s_c = it_c->string();
        std::string s_p = it_p->string();
        
        // Windows Case-Insensitivity
        std::transform(s_c.begin(), s_c.end(), s_c.begin(), ::tolower);
        std::transform(s_p.begin(), s_p.end(), s_p.begin(), ::tolower);
        
        if (s_c != s_p) return false;
        
        ++it_c;
        ++it_p;
    }
    return true;
}

// --- SYNC SERVICE IMPLEMENTATION ---

SyncService::SyncService(std::shared_ptr<EmbeddingService> embedding_service)
    : embedding_service_(embedding_service) {}

std::unordered_map<std::string, std::shared_ptr<CodeNode>> 
SyncService::load_existing_nodes(const std::string& storage_path) {
    std::unordered_map<std::string, std::shared_ptr<CodeNode>> map;
    fs::path meta_path = fs::path(storage_path) / "vector_store" / "metadata.json";
    if (fs::exists(meta_path)) {
        try {
            std::ifstream f(meta_path);
            json j = json::parse(f);
            for (const auto& j_node : j) {
                auto node = std::make_shared<CodeNode>(CodeNode::from_json(j_node));
                map[node->id] = node;
            }
        } catch (...) {}
    }
    return map;
}

void SyncService::generate_tree_file(
    const fs::path& base_dir, 
    const std::vector<fs::path>& files, 
    const fs::path& output_file
) {
    VisualNode root;

    // 1. Build the Trie structure from flat paths
    for (const auto& file_path : files) {
        std::string rel = fs::relative(file_path, base_dir).string();
        std::replace(rel.begin(), rel.end(), '\\', '/');
        
        std::stringstream ss(rel);
        std::string part;
        VisualNode* current = &root;
        
        while (std::getline(ss, part, '/')) {
            if (part.empty()) continue;
            current = &(current->children[part]);
        }
    }

    // 2. Recursive Lambda to print with standard box-drawing characters
    std::ofstream out(output_file);
    out << base_dir.filename().string() << "/\n";

    // Helper function for recursive drawing
    std::function<void(VisualNode&, std::string)> draw_node;
    draw_node = [&](VisualNode& node, std::string prefix) {
        auto it = node.children.begin();
        while (it != node.children.end()) {
            bool is_last = (std::next(it) == node.children.end());
            
            // Standard ASCII Tree Characters
            std::string connector = is_last ? "└── " : "├── ";
            
            // Render folder trailing slash if it has children
            std::string name = it->first;
            if (!it->second.children.empty()) {
                name += "/";
            }

            out << prefix << connector << name << "\n";

            // Prepare prefix for children
            std::string new_prefix = prefix + (is_last ? "    " : "│   ");
            draw_node(it->second, new_prefix);
            
            ++it;
        }
    };

    draw_node(root, "");
    out.close();
}

std::string SyncService::calculate_file_hash(const fs::path& file_path) {
    try {
        auto size = fs::file_size(file_path);
        auto time = fs::last_write_time(file_path).time_since_epoch().count();
        return std::to_string(size) + "-" + std::to_string(time);
    } catch (...) { return "err"; }
}

// backend_cpp/src/sync_service.cpp

void scan_directory_recursive(
    const fs::path& current_dir,
    const fs::path& root_dir,
    const fs::path& storage_dir,
    const std::unordered_set<std::string>& ext_set,
    const std::vector<std::string>& ignored_paths,
    const std::vector<std::string>& included_paths,
    std::vector<fs::path>& results
) {
    try {
        for (const auto& entry : fs::directory_iterator(current_dir)) {
            const auto& path = entry.path();
            if (fs::equivalent(path, storage_dir)) continue;

            fs::path rel_fs = fs::relative(path, root_dir);
            std::string rel_str = rel_fs.generic_string(); // Always uses '/'

            // Check if explicitly ignored
            bool explicitly_ignored = false;
            for (const auto& ign : ignored_paths) {
                if (is_inside(rel_fs, fs::path(ign))) {
                    explicitly_ignored = true;
                    break;
                }
            }

            // Check exceptions
            bool is_explicit_exception = false;
            bool is_bridge_to_exception = false;
            for (const auto& inc : included_paths) {
                fs::path inc_path(inc);
                if (is_inside(rel_fs, inc_path)) { is_explicit_exception = true; break; }
                if (is_inside(inc_path, rel_fs)) { is_bridge_to_exception = true; }
            }

            if (entry.is_directory()) {
                bool enter = !explicitly_ignored || is_bridge_to_exception || is_explicit_exception;
                spdlog::info("DIR  | {} | Ignored: {} | Bridge: {} | Action: {}", 
                    rel_str, explicitly_ignored ? "YES" : "NO ", is_bridge_to_exception ? "YES" : "NO ", enter ? "ENTER" : "SKIP");
                
                if (enter) {
                    scan_directory_recursive(path, root_dir, storage_dir, ext_set, ignored_paths, included_paths, results);
                }
            } else {
                bool collect = !explicitly_ignored || is_explicit_exception;
                
                std::string ext = path.extension().string();
                if (!ext.empty() && ext[0] == '.') ext = ext.substr(1);
                std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
                
                bool ext_match = ext_set.empty() || ext_set.count(ext);

                if (collect && ext_match) {
                    spdlog::info("FILE | {} | Action: COLLECT", rel_str);
                    results.push_back(path);
                } else {
                    spdlog::info("FILE | {} | Action: SKIP (Ignored: {}, ExtMatch: {})", 
                        rel_str, explicitly_ignored ? "YES" : "NO ", ext_match ? "YES" : "NO ");
                }
            }
        }
    } catch (const std::exception& e) {
        spdlog::error("Scanner error at {}: {}", current_dir.string(), e.what());
    }
}

void SyncService::generate_embeddings_batch(std::vector<std::shared_ptr<CodeNode>>& nodes, int batch_size) {
    spdlog::info("Generating embeddings for {} nodes...", nodes.size());
    for (size_t i = 0; i < nodes.size(); i += batch_size) {
        std::vector<std::string> texts;
        size_t end = std::min(i + batch_size, nodes.size());
        for (size_t j = i; j < end; ++j) {
            std::string safe = utf8_safe_substr(nodes[j]->content, 800);
            texts.push_back("Name: " + nodes[j]->name + " Code: " + safe);
        }
        try {
            auto embs = embedding_service_->generate_embeddings_batch(texts);
            for (size_t j = 0; j < embs.size(); ++j) nodes[i + j]->embedding = embs[j];
        } catch(...) {}
        spdlog::info("  - Embedded batch {}/{}", (i/batch_size)+1, (nodes.size()/batch_size)+1);
    }
}

std::unordered_map<std::string, std::string> SyncService::load_manifest(const std::string& project_id) {
    fs::path p = fs::path("data") / project_id / "manifest.json";
    if (!fs::exists(p)) return {};
    try { std::ifstream f(p); json j; f >> j; return j; } catch(...) { return {}; }
}

void SyncService::save_manifest(const std::string& project_id, const std::unordered_map<std::string, std::string>& m) {
    fs::path p = fs::path("data") / project_id / "manifest.json";
    fs::create_directories(p.parent_path());
    std::ofstream f(p); json j = m; f << j.dump(2);
}

SyncResult SyncService::perform_sync(
    const std::string& project_id,
    const std::string& source_dir_str,
    const std::string& storage_path_str, 
    const std::vector<std::string>& allowed_extensions,
    const std::vector<std::string>& ignored_paths,
    const std::vector<std::string>& included_paths
) {
    fs::path source_dir(source_dir_str);
    fs::path storage_dir(storage_path_str);
    fs::path storage_dir_abs = fs::absolute(storage_dir); // Crucial for preventing recursion
    
    fs::path converted_files_dir = storage_dir / "converted_files";
    fs::create_directories(converted_files_dir);

    SyncResult result;
    auto manifest = load_manifest(project_id);
    auto existing_nodes_map = load_existing_nodes(storage_path_str);

    // 🚀 PHASE 1: ATOMIC SANITATION (Fixes C2086 and Filter Logic)
    
    // 1. Sanitize Extensions (Always dot-free and lowercase)
    std::unordered_set<std::string> ext_set;
    for (std::string ext : allowed_extensions) {
        if (!ext.empty() && ext[0] == '.') ext = ext.substr(1);
        std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
        ext_set.insert(ext);
    }

    // 2. Sanitize Paths (Remove trailing slashes and normalize)
    std::vector<std::string> clean_ignored;
    for (const auto& p : ignored_paths) {
        if (p.empty()) continue;
        clean_ignored.push_back(fs::path(p).lexically_normal().string());
    }

    std::vector<std::string> clean_included;
    for (const auto& p : included_paths) {
        if (p.empty()) continue;
        clean_included.push_back(fs::path(p).lexically_normal().string());
    }

    spdlog::info("🔍 Scanning {} | Ignore: {} | Include: {}", source_dir_str, clean_ignored.size(), clean_included.size());

    // 🚀 PHASE 2: RECURSIVE SCAN
    std::vector<fs::path> files;
    if (fs::exists(source_dir)) {
        scan_directory_recursive(
            source_dir, 
            source_dir, 
            storage_dir_abs, 
            ext_set, 
            clean_ignored, 
            clean_included, 
            files
        );
    }

    // 🚀 PHASE 3: FILE PROCESSING
    std::unordered_map<std::string, std::string> new_manifest;
    std::unordered_set<std::string> processed_paths;
    std::vector<std::shared_ptr<CodeNode>> nodes_to_embed;
    
    std::ofstream full_context_file(storage_dir / "_full_context.txt");

    for (const auto& file_path : files) {
        std::string rel_path_str = fs::relative(file_path, source_dir).generic_string(); // Always use '/'
        processed_paths.insert(rel_path_str);
        
        std::string current_hash = calculate_file_hash(file_path);
        std::string old_hash = manifest.count(rel_path_str) ? manifest.at(rel_path_str) : "";
        
        bool is_changed = (current_hash != old_hash);
        
        std::ifstream file(file_path);
        std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());

        // Store converted .txt
        try {
            fs::path target_file = converted_files_dir / (rel_path_str + ".txt");
            fs::create_directories(target_file.parent_path());
            std::ofstream out_file(target_file);
            out_file << content;
        } catch (...) {}
        
        full_context_file << "\n\n--- FILE: " << rel_path_str << " ---\n" << content << "\n";

        if (is_changed) {
            spdlog::info("UPDATE: {}", rel_path_str);
            result.logs.push_back("UPDATE: " + rel_path_str);
            auto new_nodes = CodeParser::extract_nodes_from_file(rel_path_str, content);
            for (auto& n : new_nodes) {
                auto ptr = std::make_shared<CodeNode>(n);
                result.nodes.push_back(ptr);
                nodes_to_embed.push_back(ptr);
            }
            result.updated_count++;
        } else {
            // Check memory cache first
            bool recovered = false;
            for (const auto& pair : existing_nodes_map) {
                if (pair.second->file_path == rel_path_str) {
                    result.nodes.push_back(pair.second);
                    recovered = true;
                }
            }
            if (!recovered) {
                auto new_nodes = CodeParser::extract_nodes_from_file(rel_path_str, content);
                for (auto& n : new_nodes) {
                    auto ptr = std::make_shared<CodeNode>(n);
                    result.nodes.push_back(ptr);
                    nodes_to_embed.push_back(ptr);
                }
            }
        }
        new_manifest[rel_path_str] = current_hash;
    }
    
    // Finalize Metadata and Tree
    generate_tree_file(source_dir, files, storage_dir / "tree.txt");

    if (!nodes_to_embed.empty()) {
        generate_embeddings_batch(nodes_to_embed, 50);
    }
    
    if (!result.nodes.empty()){
        CodeGraph graph;
        for (const auto& node : result.nodes) graph.add_node(node);
        graph.calculate_static_weights();
    }
    
    save_manifest(project_id, new_manifest);
    return result;
}

std::vector<std::shared_ptr<CodeNode>> SyncService::sync_single_file(
    const std::string& project_id,
    const std::string& local_root,
    const std::string& storage_path,
    const std::string& relative_path
) {
    fs::path full_path = fs::path(local_root) / relative_path;
    if (!fs::exists(full_path)) throw std::runtime_error("File not found locally");

    // 1. Read Content
    std::ifstream file(full_path);
    std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());

    // 2. Parse into Nodes
    auto raw_nodes = CodeParser::extract_nodes_from_file(relative_path, content);
    std::vector<std::shared_ptr<CodeNode>> nodes;
    
    // 3. Generate Embeddings (Atomic Batch)
    std::vector<std::string> texts_to_embed;
    for (auto& n : raw_nodes) {
        auto ptr = std::make_shared<CodeNode>(n);
        nodes.push_back(ptr);
        texts_to_embed.push_back("Name: " + ptr->name + " Code: " + utf8_safe_substr(ptr->content, 800));
    }

    auto embs = embedding_service_->generate_embeddings_batch(texts_to_embed);
    for (size_t i = 0; i < embs.size(); ++i) nodes[i]->embedding = embs[i];

    // 4. Update the storage .txt (for full context chat)
    fs::path target_txt = fs::path(storage_path) / "converted_files" / (relative_path + ".txt");
    fs::create_directories(target_txt.parent_path());
    std::ofstream out(target_txt);
    out << content;

    return nodes;
}

} // namespace code_assistance