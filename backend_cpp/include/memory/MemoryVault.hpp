// backend_cpp/include/memory/MemoryVault.hpp
#pragma once
#include <string>
#include <vector>
#include <mutex>
#include <nlohmann/json.hpp>
#include <spdlog/spdlog.h>
#include "faiss_vector_store.hpp" // Reuse our wrapper

namespace code_assistance {

struct Experience {
    std::string id;
    std::string prompt;
    std::string solution;
    double outcome_score; // 1.0 = Success, -1.0 = Rejected
    std::vector<float> embedding;
};

class MemoryVault {
public:
    MemoryVault(const std::string& storage_path) : path_(storage_path) {
        // Initialize distinct index for experiences
        store_ = std::make_unique<FaissVectorStore>(768); 
        load();
    }

    void add_experience(const std::string& prompt, const std::string& solution, 
                        const std::vector<float>& embedding, bool success) {
        std::lock_guard<std::mutex> lock(mtx_);
        
        auto exp = std::make_shared<CodeNode>(); // Reusing CodeNode structure for simplicity
        exp->id = "EXP_" + std::to_string(std::chrono::system_clock::now().time_since_epoch().count());
        exp->content = solution; // Store solution in content
        exp->docstring = prompt; // Store prompt in docstring
        exp->embedding = embedding;
        exp->weights["outcome"] = success ? 1.0 : -1.0;

        store_->add_nodes({exp});
        spdlog::info("🧠 Experience Vault: Learned new {} pattern.", success ? "positive" : "negative");
    }

    std::vector<std::string> recall_relevant(const std::vector<float>& query_vec) {
        std::lock_guard<std::mutex> lock(mtx_);
        auto results = store_->search(query_vec, 3); // Top 3 relevant memories
        
        std::vector<std::string> insights;
        for (const auto& res : results) {
            double outcome = res.node->weights.count("outcome") ? res.node->weights["outcome"] : 0.0;
            std::string type = (outcome > 0) ? "SUCCESSFUL STRATEGY" : "FAILED ATTEMPT";
            
            insights.push_back("[" + type + "] Context: " + res.node->docstring + "\nResult: " + res.node->content);
        }
        return insights;
    }

    void save() {
        // In a real implementation, we'd serialize to disk here
        // store_->save(path_);
    }

private:
    void load() {
        // store_->load(path_);
    }

    std::string path_;
    std::unique_ptr<FaissVectorStore> store_;
    std::mutex mtx_;
};

}