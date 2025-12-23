#include "embedding_service.hpp"
#include <cpr/cpr.h>
#include <nlohmann/json.hpp>
#include <spdlog/spdlog.h>
#include <thread>
#include <chrono>
#include "SystemMonitor.hpp" 

namespace code_assistance {

using json = nlohmann::json;

std::string utf8_safe_substr(const std::string& str, size_t length) {
    if (str.length() <= length) return str;
    std::string sub = str.substr(0, length);
    if (sub.empty()) return sub;
    while (!sub.empty()) {
        unsigned char c = static_cast<unsigned char>(sub.back());
        if (c < 0x80) break;
        if (c >= 0xC0) { sub.pop_back(); break; }
        sub.pop_back();
    }
    return sub;
}

EmbeddingService::EmbeddingService(std::shared_ptr<KeyManager> key_manager)
    : key_manager_(key_manager), cache_manager_(std::make_shared<CacheManager>()) {}

std::string EmbeddingService::get_endpoint_url(const std::string& action) {
    std::string model = (action == "embedContent" || action == "batchEmbedContents") 
        ? "text-embedding-004" 
        : key_manager_->get_current_model();
        
    return base_url_ + model + ":" + action + "?key=" + key_manager_->get_current_key();
}

template<typename Func>
cpr::Response perform_request_with_retry(Func request_factory, std::shared_ptr<KeyManager> km) {
    int max_retries = 3; 
    
    for (int i = 0; i <= max_retries; ++i) {
        cpr::Response r = request_factory(); 
        
        if (r.status_code == 200) return r;
        
        if (r.status_code == 429 || r.status_code == 503) {
            spdlog::warn("⚠️ API Limit ({}) hit. Rotating key...", r.status_code);
            km->report_rate_limit(); 
            std::this_thread::sleep_for(std::chrono::milliseconds(500)); 
            continue;
        }
        return r;
    }
    return cpr::Response{};
}

std::vector<float> EmbeddingService::generate_embedding(const std::string& text) {
    if (auto cached = cache_manager_->get_embedding(text)) return *cached;

    auto start = std::chrono::high_resolution_clock::now();

    auto r = perform_request_with_retry([&]() {
        json payload = {
            {"model", "models/text-embedding-004"},
            {"content", { {"parts", {{{"text", text}}}} }}
        };
        return cpr::Post(cpr::Url{get_endpoint_url("embedContent")},
                         cpr::Body{payload.dump()},
                         cpr::Header{{"Content-Type", "application/json"}});
    }, key_manager_);

    auto end = std::chrono::high_resolution_clock::now();
    double duration = std::chrono::duration<double, std::milli>(end - start).count();
    SystemMonitor::global_embedding_latency_ms.store(duration);

    if (r.status_code != 200) {
        spdlog::error("Embedding API error [{}]: {}", r.status_code, r.text);
        throw std::runtime_error("Failed to generate embedding");
    }

    auto response_json = json::parse(r.text);
    std::vector<float> embedding = response_json["embedding"]["values"];
    cache_manager_->set_embedding(text, embedding);
    return embedding;
}

std::vector<std::vector<float>> EmbeddingService::generate_embeddings_batch(const std::vector<std::string>& texts) {
    json requests = json::array();
    for(const auto& raw_text : texts){
        requests.push_back({
            {"model", "models/text-embedding-004"},
            {"content", { {"parts", {{{"text", raw_text}}}} }}
        });
    }
    
    std::string payload_str = json{{"requests", requests}}.dump(-1, ' ', false, json::error_handler_t::replace);
    
    // --- KEY FIX: Use perform_request_with_retry correctly ---
    auto r = perform_request_with_retry([&]() {
        return cpr::Post(cpr::Url{get_endpoint_url("batchEmbedContents")}, 
                         cpr::Body{payload_str}, 
                         cpr::Header{{"Content-Type", "application/json"}});
    }, key_manager_);

    if (r.status_code != 200) {
        spdlog::error("Batch Embedding API error [{}]: {}", r.status_code, r.text);
        throw std::runtime_error("Failed to generate batch embeddings");
    }
    
    auto response_json = json::parse(r.text);
    std::vector<std::vector<float>> embeddings;
    
    if (response_json.contains("embeddings")) {
        // --- KEY FIX: Correct Loop Syntax ---
        for(const auto& emb : response_json["embeddings"]){
            if (emb.contains("values")) {
                std::vector<float> vec = emb["values"].get<std::vector<float>>();
                embeddings.push_back(vec);
            }
        }
    }
    return embeddings;
}

std::string EmbeddingService::generate_text(const std::string& prompt) {
    auto start = std::chrono::high_resolution_clock::now();

    auto r = perform_request_with_retry([&]() {
        json payload = {
            {"contents", {{ {"parts", {{{"text", prompt}}}} }}}
        };
        return cpr::Post(cpr::Url{get_endpoint_url("generateContent")},
                         cpr::Body{payload.dump(-1, ' ', false, json::error_handler_t::replace)},
                         cpr::Header{{"Content-Type", "application/json"}});
    }, key_manager_);

    auto end = std::chrono::high_resolution_clock::now();
    double duration = std::chrono::duration<double, std::milli>(end - start).count();
    SystemMonitor::global_llm_generation_ms.store(duration);

    if (r.status_code != 200) {
        spdlog::error("Text Generation API error [{}]: {}", r.status_code, r.text);
        return "Error: AI response blocked.";
    }
    
    auto response_json = json::parse(r.text);
    if (response_json.contains("candidates") && !response_json["candidates"].empty()) {
        std::string text = response_json["candidates"][0]["content"]["parts"][0]["text"];
        int estimated_tokens = text.length() / 4; 
        if (estimated_tokens == 0 && text.length() > 0) estimated_tokens = 1;
        SystemMonitor::global_output_tokens.store(estimated_tokens);
        return text;
    }
    
    return "Error: AI response was empty.";
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