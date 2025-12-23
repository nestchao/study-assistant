#pragma once

#include <string>
#include <vector>
#include <memory>
#include <unordered_map>
#include <filesystem>
#include "code_graph.hpp"
#include "embedding_service.hpp"

namespace code_assistance {

struct SyncResult {
    std::vector<std::shared_ptr<CodeNode>> nodes;
    int updated_count = 0;
    int deleted_count = 0;
    std::vector<std::string> logs;
};

class SyncService {
public:
    // Constructor Declaration
    explicit SyncService(std::shared_ptr<EmbeddingService> embedding_service);

    // Main Method Declaration
    SyncResult perform_sync(
        const std::string& project_id,
        const std::string& source_dir,
        const std::string& storage_path, 
        const std::vector<std::string>& allowed_extensions,
        const std::vector<std::string>& ignored_paths,
        const std::vector<std::string>& included_paths
    );

    std::vector<std::shared_ptr<CodeNode>> sync_single_file(
        const std::string& project_id,
        const std::string& local_root,
        const std::string& storage_path,
        const std::string& relative_path
    );

private:
    std::shared_ptr<EmbeddingService> embedding_service_;

    // Helper Declarations
    std::string calculate_file_hash(const std::filesystem::path& file_path);
    std::unordered_map<std::string, std::string> load_manifest(const std::string& project_id);
    void save_manifest(const std::string& project_id, const std::unordered_map<std::string, std::string>& manifest);
    void generate_embeddings_batch(std::vector<std::shared_ptr<CodeNode>>& nodes, int batch_size = 50);
    void generate_tree_file(const std::filesystem::path& base_dir, const std::vector<std::filesystem::path>& files, const std::filesystem::path& output_file);
    std::unordered_map<std::string, std::shared_ptr<CodeNode>> load_existing_nodes(const std::string& storage_path);
};

} // namespace code_assistance