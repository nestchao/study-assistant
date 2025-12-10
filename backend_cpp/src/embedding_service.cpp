#include "embedding_service.hpp"
#include <cpr/cpr.h>
#include <nlohmann/json.hpp>
#include <spdlog/spdlog.h>

namespace code_assistance {

using json = nlohmann::json;

EmbeddingService::EmbeddingService(const std::string& api_key)
    : api_key_(api_key), cache_manager_(std::make_shared<CacheManager>()) {}

std::vector<float> EmbeddingService::generate_embedding(const std::string& text) {
    // Check cache first
    if (auto cached = cache_manager_->get_embedding(text)) {
        return *cached;
    }

    json payload = {
        {"model", "models/text-embedding-004"},
        {"content", {
            {"parts", {{{"text", text}}}}
        }}
    };

    std::string url = base_url_ + "text-embedding-004:embedContent?key=" + api_key_;
    
    cpr::Response r = cpr::Post(cpr::Url{url},
                                cpr::Body{payload.dump()},
                                cpr::Header{{"Content-Type", "application/json"}});

    if (r.status_code != 200) {
        spdlog::error("Embedding API error [{}]: {}", r.status_code, r.text);
        throw std::runtime_error("Failed to generate embedding");
    }

    auto response_json = json::parse(r.text);
    std::vector<float> embedding = response_json["embedding"]["values"];
    
    // Cache the result
    cache_manager_->set_embedding(text, embedding);
    
    return embedding;
}

std::vector<std::vector<float>> EmbeddingService::generate_embeddings_batch(const std::vector<std::string>& texts) {
    json requests = json::array();
    for(const auto& text : texts){
        requests.push_back({
            {"model", "models/text-embedding-004"},
            {"content", {
                {"parts", {{{"text", text}}}}
            }}
        });
    }
    json payload = {{"requests", requests}};

    std::string url = base_url_ + "text-embedding-004:batchEmbedContents?key=" + api_key_;
    cpr::Response r = cpr::Post(cpr::Url{url}, cpr::Body{payload.dump()}, cpr::Header{{"Content-Type", "application/json"}});

    if (r.status_code != 200) {
        spdlog::error("Batch Embedding API error [{}]: {}", r.status_code, r.text);
        throw std::runtime_error("Failed to generate batch embeddings");
    }
    
    auto response_json = json::parse(r.text);
    std::vector<std::vector<float>> embeddings;
    for(const auto& emb : response_json["embeddings"]){
        embeddings.push_back(emb["values"]);
    }
    return embeddings;
}


std::string EmbeddingService::generate_text(const std::string& prompt) {
    json payload = {
        {"contents", {{
            {"parts", {{{"text", prompt}}}}
        }}}
    };
    
    std::string url = base_url_ + "gemini-2.5-flash-lite:generateContent?key=" + api_key_;
    
    cpr::Response r = cpr::Post(cpr::Url{url},
                                cpr::Body{payload.dump()},
                                cpr::Header{{"Content-Type", "application/json"}});

    if (r.status_code != 200) {
        spdlog::error("Text Generation API error [{}]: {}", r.status_code, r.text);
        return "Error: Could not generate response from AI model.";
    }
    
    auto response_json = json::parse(r.text);
    if (response_json.contains("candidates") && !response_json["candidates"].empty()) {
        return response_json["candidates"][0]["content"]["parts"][0]["text"];
    }
    
    return "Error: AI response was empty or blocked.";
}

std::string HyDEGenerator::generate_hyde(const std::string& query) {
    std::string prompt = "Write python code for: " + query;
    try {
        return embedding_service_->generate_text(prompt);
    } catch (const std::exception& e) {
        spdlog::warn("HyDE generation failed: {}", e.what());
        return "";
    }
}

} // namespace code_assistance