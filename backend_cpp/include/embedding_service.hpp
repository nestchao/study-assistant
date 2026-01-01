#pragma once
#include <string>
#include <vector>
#include <optional>
#include <memory>
#include "cache_manager.hpp"
#include "KeyManager.hpp" 

namespace code_assistance {

struct GenerationResult {
    std::string text;
    int prompt_tokens = 0;
    int completion_tokens = 0;
    int total_tokens = 0;
    bool success = false;
};

// Declaration only
std::string utf8_safe_substr(const std::string& str, size_t length);

class EmbeddingService {
public:
    explicit EmbeddingService(std::shared_ptr<KeyManager> key_manager);
    
    std::vector<float> generate_embedding(const std::string& text);
    std::vector<std::vector<float>> generate_embeddings_batch(const std::vector<std::string>& texts);
    std::string generate_text(const std::string& prompt);
    std::string generate_autocomplete(const std::string& prefix);
    GenerationResult generate_text_elite(const std::string& prompt); 

private:
    std::shared_ptr<KeyManager> key_manager_;
    std::shared_ptr<CacheManager> cache_manager_;
    const std::string base_url_ = "https://generativelanguage.googleapis.com/v1beta/models/";
    std::string get_endpoint_url(const std::string& action);
};

class HyDEGenerator {
public:
    explicit HyDEGenerator(std::shared_ptr<EmbeddingService> service) : embedding_service_(service) {}
    std::string generate_hyde(const std::string& query);
private:
    std::shared_ptr<EmbeddingService> embedding_service_;
};

} // namespace code_assistance