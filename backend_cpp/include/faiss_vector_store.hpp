#pragma once

#include "code_graph.hpp"
#include <string>
#include <vector>
#include <memory>
#include <faiss/utils/distances.h>

// Forward declare FAISS Index to avoid including faiss headers here
namespace faiss { struct Index; }

namespace code_assistance {

struct FaissSearchResult {
    std::shared_ptr<CodeNode> node;
    float faiss_score;
};

class FaissVectorStore {
public:
    explicit FaissVectorStore(int dimension);
    ~FaissVectorStore();

    void add_nodes(const std::vector<std::shared_ptr<CodeNode>>& nodes);
    std::vector<FaissSearchResult> search(const std::vector<float>& query_vector, int k);
    
    void save(const std::string& path) const;
    void load(const std::string& path);

    const std::vector<std::shared_ptr<CodeNode>>& get_all_nodes() const;
    std::shared_ptr<CodeNode> get_node_by_name(const std::string& name) const;

private:
    int dimension_;
    faiss::Index* index_; // Use a pointer to manage the FAISS index
    
    // Mappings for retrieval
    std::vector<std::shared_ptr<CodeNode>> nodes_list_;
    std::unordered_map<long, std::shared_ptr<CodeNode>> id_to_node_map_;
    std::unordered_map<std::string, long> name_to_id_map_;
};

} // namespace code_assistance