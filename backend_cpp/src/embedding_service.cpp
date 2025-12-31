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
    int max_retries = 4; 
    cpr::Response r; 
    for (int i = 0; i < max_retries; ++i) {
        r = request_factory(); 
        if (r.status_code == 200) return r;
        if ((r.status_code == 429 || r.status_code == 503) && km) {
            spdlog::warn("⚠️ API {} ({}). Rotating key and cooling down (Attempt {}/{})...", 
                         r.status_code, (r.status_code == 429 ? "Quota" : "Overload"), i + 1, max_retries);
            
            km->report_rate_limit();
            
            // Exponential backoff: sleep longer each time (2s, 3s, 4s...)
            std::this_thread::sleep_for(std::chrono::milliseconds(2000 + (i * 1000)));
            continue; // This continue is now VALID because it's inside the 'for' loop
        }
        break;
    }
    return r;
}

std::vector<float> EmbeddingService::generate_embedding(const std::string& text) {
    if (auto cached = cache_manager_->get_embedding(text)) return *cached;

    auto start = std::chrono::high_resolution_clock::now();

    auto r = perform_request_with_retry([&]() {
        // 🚀 ARCHITECT'S NOTE: We ensure we get a fresh URL with the rotated key for every retry
        return cpr::Post(cpr::Url{get_endpoint_url("embedContent")},
                         cpr::Body(json{
                             {"model", "models/text-embedding-004"},
                             {"content", {{"parts", {{{"text", text}}}}}}
                         }.dump()),
                         cpr::Header{{"Content-Type", "application/json"}});
    }, key_manager_);

    auto end = std::chrono::high_resolution_clock::now();
    double duration = std::chrono::duration<double, std::milli>(end - start).count();
    SystemMonitor::global_embedding_latency_ms.store(duration);

    // After all retries, if we still don't have a 200, we fail the mission
    if (r.status_code != 200) {
        spdlog::error("❌ Embedding API Fatal Error [{}]: {}", r.status_code, r.text);
        throw std::runtime_error("Failed to generate embedding after retries");
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
    cpr::Response r;
    int max_retries = 4;

    for (int i = 0; i < max_retries; ++i) {
        // 🚀 THE FIX: Re-generate the URL inside the loop! 
        // This ensures the ROTATED KEY and NEW MODEL are used for the retry.
        std::string current_url = get_endpoint_url("generateContent");
        
        json payload = {
            {"contents", {{ {"parts", {{{"text", prompt}}}} }}}
        };

        r = cpr::Post(cpr::Url{current_url},
                      cpr::Body{payload.dump()},
                      cpr::Header{{"Content-Type", "application/json"}});

        if (r.status_code == 200) break;

        if (r.status_code == 429) {
            spdlog::warn("⚠️ Quota Exceeded (429). Rotating key and initiating 2s thermal cooldown...");
            key_manager_->report_rate_limit();
            // 🚀 SPACE-X FIX: Increase sleep to 2 seconds to allow quota window to reset
            std::this_thread::sleep_for(std::chrono::milliseconds(2000));
            continue;
        }

        // If it's a 400 or 404, the model name or prompt is wrong
        spdlog::error("❌ Fatal API Error [{}]: {}", r.status_code, r.text);
        return "ERROR: API Protocol Failure.";
    }

    if (r.status_code != 200) return "ERROR: System Throttled.";

    auto response_json = json::parse(r.text);
    return response_json["candidates"][0]["content"]["parts"][0]["text"];
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

std::string EmbeddingService::generate_autocomplete(const std::string& prefix) {
    // Use the aligned method name 'get_current_key'
    std::string key = key_manager_->get_current_key();
    std::string url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=" + key;

    json payload = {
        {"contents", {{ {"parts", {{{"text", "Finish this code: " + prefix}}}} }}},
        {"generationConfig", {
            {"maxOutputTokens", 64},
            {"stopSequences", {";", "\n", "}"}}
        }}
    };

    auto r = cpr::Post(cpr::Url{url}, cpr::Body{payload.dump()}, cpr::Header{{"Content-Type", "application/json"}});
    
    if (r.status_code == 429) {
        key_manager_->report_rate_limit(); // Aligned name
        return ""; 
    }

    if (r.status_code != 200) return "";

    // 🚀 FIX 3: Implementation of parse_gemini_response inline to avoid C3861
    try {
        auto j = json::parse(r.text);
        if (j.contains("candidates") && !j["candidates"].empty()) {
            return j["candidates"][0]["content"]["parts"][0]["text"];
        }
    } catch (...) {}
    return "";
}

} // namespace code_assistance