#pragma once

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

struct SyncResult {
    std::vector<std::shared_ptr<CodeNode>> nodes;
    int updated_count = 0;
    int deleted_count = 0;
    std::vector<std::string> logs;
};

class SyncService {
public:
    explicit SyncService(std::shared_ptr<EmbeddingService> embedding_service)
        : embedding_service_(embedding_service) {}

    SyncResult perform_sync(
        const std::string& project_id,
        const std::string& source_dir,
        const std::vector<std::string>& allowed_extensions,
        const std::vector<std::string>& ignored_paths
    );

private:
    std::shared_ptr<EmbeddingService> embedding_service_;
    
    std::vector<fs::path> scan_directory(
        const fs::path& root,
        const std::vector<std::string>& extensions,
        const std::vector<std::string>& ignored
    );
    
    std::string calculate_file_hash(const fs::path& file_path);
    
    std::unordered_map<std::string, std::string> load_manifest(const std::string& project_id);
    void save_manifest(const std::string& project_id, const std::unordered_map<std::string, std::string>& manifest);
    
    void generate_embeddings_batch(std::vector<std::shared_ptr<CodeNode>>& nodes, int batch_size = 50);
};


inline SyncResult SyncService::perform_sync(
    const std::string& project_id,
    const std::string& source_dir_str,
    const std::vector<std::string>& allowed_extensions,
    const std::vector<std::string>& ignored_paths)
{
    fs::path source_dir(source_dir_str);
    SyncResult result;
    
    auto manifest = load_manifest(project_id);
    auto files = scan_directory(source_dir, allowed_extensions, ignored_paths);
    
    std::unordered_map<std::string, std::string> new_manifest;
    std::unordered_set<std::string> processed_paths;
    
    for (const auto& file_path : files) {
        std::string rel_path_str = fs::relative(file_path, source_dir).lexically_normal().string();
        std::replace(rel_path_str.begin(), rel_path_str.end(), '\\', '/');

        processed_paths.insert(rel_path_str);
        
        std::string current_hash = calculate_file_hash(file_path);
        std::string old_hash = manifest.count(rel_path_str) ? manifest.at(rel_path_str) : "";
        
        if (current_hash != old_hash) {
            result.logs.push_back("UPDATE: " + rel_path_str);
            
            std::ifstream file(file_path);
            std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
            
            auto nodes = CodeParser::extract_nodes_from_file(rel_path_str, content);
            for (auto& node : nodes) {
                result.nodes.push_back(std::make_shared<CodeNode>(node));
            }
            result.updated_count++;
        }
        new_manifest[rel_path_str] = current_hash;
    }
    
    for (const auto& [path, hash] : manifest) {
        if (processed_paths.find(path) == processed_paths.end()) {
            result.logs.push_back("DELETE: " + path);
            result.deleted_count++;
        }
    }
    
    if (!result.nodes.empty()){
        generate_embeddings_batch(result.nodes, 50);
    
        CodeGraph graph;
        for (const auto& node : result.nodes) {
            graph.add_node(node);
        }
        graph.calculate_static_weights();
    }
    
    save_manifest(project_id, new_manifest);
    return result;
}

inline std::vector<fs::path> SyncService::scan_directory(
    const fs::path& root,
    const std::vector<std::string>& extensions,
    const std::vector<std::string>& ignored)
{
    std::vector<fs::path> files;
    std::unordered_set<std::string> ext_set;
    for (const auto& ext : extensions) {
        ext_set.insert("." + ext);
    }

    for (const auto& entry : fs::recursive_directory_iterator(root)) {
        if (!entry.is_regular_file()) continue;
        
        const auto& path = entry.path();
        bool should_ignore = false;
        for (const auto& part : path) {
            if (std::find(ignored.begin(), ignored.end(), part.string()) != ignored.end()) {
                should_ignore = true;
                break;
            }
        }
        if (should_ignore) continue;
        
        if (!extensions.empty() && ext_set.find(path.extension().string()) == ext_set.end()) {
            continue;
        }
        
        files.push_back(path);
    }
    return files;
}

inline std::string SyncService::calculate_file_hash(const fs::path& file_path) {
    // In a real app, use a proper hash like SHA256.
    // For this example, file size + last write time is good enough and fast.
    try {
        auto size = fs::file_size(file_path);
        auto time = fs::last_write_time(file_path).time_since_epoch().count();
        return std::to_string(size) + "-" + std::to_string(time);
    } catch (...) {
        return "error-hash";
    }
}

inline void SyncService::generate_embeddings_batch(
    std::vector<std::shared_ptr<CodeNode>>& nodes,
    int batch_size)
{
    spdlog::info("Generating embeddings for {} nodes...", nodes.size());
    for (size_t i = 0; i < nodes.size(); i += batch_size) {
        std::vector<std::string> texts;
        size_t end = std::min(i + batch_size, nodes.size());
        
        for (size_t j = i; j < end; ++j) {
            auto& node = nodes[j];
            std::string text = "Type: " + node->type + ". Name: " + node->name + 
                             ". \nCode:\n" + node->content.substr(0, 800);
            texts.push_back(text);
        }
        
        try {
            auto embeddings = embedding_service_->generate_embeddings_batch(texts);
            for (size_t j = 0; j < embeddings.size(); ++j) {
                nodes[i + j]->embedding = embeddings[j];
            }
        } catch (const std::exception& e) {
            spdlog::error("Embedding batch failed: {}", e.what());
        }
        spdlog::info("  - Embedded batch {}/{}", (i/batch_size)+1, (nodes.size()/batch_size)+1);
    }
}


inline std::unordered_map<std::string, std::string> 
SyncService::load_manifest(const std::string& project_id) {
    fs::path manifest_path = fs::path("data") / project_id / "manifest.json";
    if (!fs::exists(manifest_path)) return {};
    
    std::ifstream file(manifest_path);
    json j;
    file >> j;
    return j.get<std::unordered_map<std::string, std::string>>();
}

inline void SyncService::save_manifest(
    const std::string& project_id,
    const std::unordered_map<std::string, std::string>& manifest)
{
    fs::path manifest_path = fs::path("data") / project_id / "manifest.json";
    fs::create_directories(manifest_path.parent_path());
    
    json j = manifest;
    std::ofstream file(manifest_path);
    file << j.dump(2);
}

} // namespace code_assistance