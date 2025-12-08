#pragma once
#include <string>
#include <vector>
#include <optional>
#include <memory>
#include "cache_manager.hpp"

namespace code_assistance {

class EmbeddingService {
public:
    explicit EmbeddingService(const std::string& api_key);
    
    std::vector<float> generate_embedding(const std::string& text);
    std::vector<std::vector<float>> generate_embeddings_batch(const std::vector<std::string>& texts);
    std::string generate_text(const std::string& prompt);

private:
    std::string api_key_;
    std::shared_ptr<CacheManager> cache_manager_;
    const std::string base_url_ = "https://generativelanguage.googleapis.com/v1beta/models/";
};

class HyDEGenerator {
public:
    explicit HyDEGenerator(std::shared_ptr<EmbeddingService> service) : embedding_service_(service) {}
    std::string generate_hyde(const std::string& query);
private:
    std::shared_ptr<EmbeddingService> embedding_service_;
};

} // namespace code_assistance