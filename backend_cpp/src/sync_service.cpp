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

namespace code_assistance {

namespace fs = std::filesystem;
using json = nlohmann::json;

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
    std::string c = child.string();
    std::string p = parent.string();
    std::transform(c.begin(), c.end(), c.begin(), ::tolower);
    std::transform(p.begin(), p.end(), p.begin(), ::tolower);
    std::replace(c.begin(), c.end(), '\\', '/');
    std::replace(p.begin(), p.end(), '\\', '/');
    if (!c.empty() && c.back() == '/') c.pop_back();
    if (!p.empty() && p.back() == '/') p.pop_back();

    if (c == p) return true;
    if (c.length() > p.length()) {
        if (c.substr(0, p.length()) == p) {
            if (c[p.length()] == '/') return true;
        }
    }
    return false;
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

void SyncService::generate_tree_file(const fs::path& base_dir, const std::vector<fs::path>& files, const fs::path& output_file) {
    std::ofstream out(output_file);
    out << base_dir.filename().string() << "/\n";
    for (const auto& f : files) {
        std::string rel = fs::relative(f, base_dir).string();
        std::replace(rel.begin(), rel.end(), '\\', '/');
        int depth = 0;
        for(char c : rel) if(c == '/') depth++;
        std::string indent = "";
        for(int i=0; i<depth; i++) indent += "    ";
        out << indent << "|-- " << fs::path(rel).filename().string() << "\n";
    }
}

std::string SyncService::calculate_file_hash(const fs::path& file_path) {
    try {
        auto size = fs::file_size(file_path);
        auto time = fs::last_write_time(file_path).time_since_epoch().count();
        return std::to_string(size) + "-" + std::to_string(time);
    } catch (...) { return "err"; }
}

// --- THE SMART SCANNER ---
void scan_directory_recursive(
    const fs::path& current_dir,
    const fs::path& root_dir,
    const std::unordered_set<std::string>& ext_set,
    const std::vector<std::string>& ignored_paths,
    const std::vector<std::string>& included_paths,
    std::vector<fs::path>& results
) {
    if (fs::is_symlink(current_dir)) return;

    try {
        for (const auto& entry : fs::directory_iterator(current_dir, fs::directory_options::skip_permission_denied)) {
            const auto& path = entry.path();
            std::string filename = path.filename().string();
            
            // 1. HARD IGNORES (System junk)
            if (filename == ".git" || filename == ".vscode" || filename == ".idea" || filename == "__pycache__") continue;

            // Calculate Relative Path for Config Matching
            // e.g. "node_modules" or "src/utils"
            fs::path rel_fs = fs::relative(path, root_dir);

            // 2. CHECK CONFIG IGNORES
            bool is_ignored = false;
            for (const auto& ign : ignored_paths) {
                // "node_modules" matches "node_modules" AND "node_modules/foo"
                if (is_inside(rel_fs, fs::path(ign))) {
                    is_ignored = true;
                    break;
                }
            }

            // 3. CHECK EXCEPTIONS (Force Include)
            bool is_exception = false;
            bool is_path_to_exception = false;

            for (const auto& inc : included_paths) {
                fs::path inc_fs(inc);
                // Is this file the exception?
                if (is_inside(rel_fs, inc_fs)) {
                    is_exception = true;
                    break;
                }
                // Is this folder a parent of the exception? (Must traverse to find it)
                // e.g. We are at "node_modules", exception is "node_modules/zod"
                if (is_inside(inc_fs, rel_fs)) {
                    is_path_to_exception = true;
                }
            }

            // 4. ACTION
            if (entry.is_directory()) {
                if (is_ignored) {
                    if (is_path_to_exception) {
                        // spdlog::info("📂 Diving into ignored folder: {} (Targeting exception)", rel_fs.string());
                        scan_directory_recursive(path, root_dir, ext_set, ignored_paths, included_paths, results);
                    } else {
                        // spdlog::info("🚫 Pruning ignored folder: {}", rel_fs.string());
                        // PRUNE: Do not recurse
                    }
                } else {
                    scan_directory_recursive(path, root_dir, ext_set, ignored_paths, included_paths, results);
                }
            } 
            else if (entry.is_regular_file()) {
                if (is_ignored && !is_exception) continue;

                if (!ext_set.empty()) {
                    std::string ext = path.extension().string();
                    if (ext_set.find(ext) == ext_set.end()) continue;
                }

                results.push_back(path);
            }
        }
    } catch (const std::exception& e) {
        spdlog::warn("Error scanning {}: {}", current_dir.string(), e.what());
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
    
    // --- CHANGED: No more 'converted_files' duplication ---
    fs::path converted_files_dir = storage_dir / "converted_files";
    fs::create_directories(converted_files_dir);

    SyncResult result;
    auto manifest = load_manifest(project_id);
    auto existing_nodes_map = load_existing_nodes(storage_path_str);

    std::unordered_set<std::string> ext_set;
    for (const auto& ext : allowed_extensions) {
        ext_set.insert(ext[0] == '.' ? ext : "." + ext);
    }

    spdlog::info("🔍 Scanning {} | Ignore: {} | Include: {}", source_dir_str, ignored_paths.size(), included_paths.size());

    std::vector<fs::path> files;
    if (fs::exists(source_dir)) {
        scan_directory_recursive(source_dir, source_dir, ext_set, ignored_paths, included_paths, files);
    }

    std::unordered_map<std::string, std::string> new_manifest;
    std::unordered_set<std::string> processed_paths;
    std::vector<std::shared_ptr<CodeNode>> nodes_to_embed;
    
    // Optional: Keep full context for AI Chat (Single File)
    std::ofstream full_context_file(storage_dir / "_full_context.txt");

    for (const auto& file_path : files) {
        std::string rel_path_str = fs::relative(file_path, source_dir).lexically_normal().string();
        std::replace(rel_path_str.begin(), rel_path_str.end(), '\\', '/');
        processed_paths.insert(rel_path_str);
        
        std::string current_hash = calculate_file_hash(file_path);
        std::string old_hash = manifest.count(rel_path_str) ? manifest.at(rel_path_str) : "";
        
        bool is_changed = (current_hash != old_hash);
        
        // Read file only for parsing/indexing, not for copying
        std::ifstream file(file_path);
        std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());

        try {
            fs::path target_file = converted_files_dir / (rel_path_str + ".txt");
            fs::create_directories(target_file.parent_path());
            std::ofstream out_file(target_file);
            out_file << content;
        } catch (...) {
            spdlog::warn("Failed to write converted file: {}", rel_path_str);
        }
        
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
            // RETENTION LOGIC: Keep existing node if file hasn't changed
            bool recovered = false;
            for (const auto& pair : existing_nodes_map) {
                // Check if this existing node belongs to the current file
                // Note: existing_nodes_map keys are IDs (src/main.ts::func), file_path is src/main.ts
                if (pair.second->file_path == rel_path_str) {
                    result.nodes.push_back(pair.second);
                    // Also keep it for the new index
                    nodes_to_embed.push_back(pair.second); 
                    recovered = true;
                }
            }
            if (!recovered) {
                // If we lost it (e.g. previous crash), re-parse it
                spdlog::warn("♻️ Restoring missing node: {}", rel_path_str);
                auto new_nodes = CodeParser::extract_nodes_from_file(rel_path_str, content);
                for (auto& n : new_nodes) {
                    auto ptr = std::make_shared<CodeNode>(n);
                    result.nodes.push_back(ptr);
                    nodes_to_embed.push_back(ptr); // Re-embed or use cache
                }
            }
        }
        new_manifest[rel_path_str] = current_hash;
    }
    
    generate_tree_file(source_dir, files, storage_dir / "tree.txt");

    // 3. EMBED NEW NODES
    if (!nodes_to_embed.empty()) {
        generate_embeddings_batch(nodes_to_embed, 50);
    }
    
    // 4. GRAPH WEIGHTS
    if (!result.nodes.empty()){
        CodeGraph graph;
        for (const auto& node : result.nodes) graph.add_node(node);
        graph.calculate_static_weights();
    }
    
    save_manifest(project_id, new_manifest);
    return result;
}

} // namespace code_assistance