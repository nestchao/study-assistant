#pragma once
#include <vector>
#include <string>
#include <shared_mutex>
#include <nlohmann/json.hpp>
#include <fstream>
#include <atomic>
#include <spdlog/spdlog.h>

namespace code_assistance {

class KeyManager {
private:
    struct ApiKey {
        std::string key;
        bool is_active = true;
        int fail_count = 0;
    };

    std::vector<ApiKey> key_pool;
    std::vector<std::string> model_pool; // 🚀 NEW: Store all available models
    mutable std::shared_mutex pool_mutex;
    std::atomic<size_t> current_key_index{0};
    std::atomic<size_t> current_model_index{0}; // 🚀 NEW: Track current model
    std::string serper_key;

public:
    KeyManager() {
        refresh_key_pool();
    }

    void refresh_key_pool() {
        std::unique_lock lock(pool_mutex);

        std::vector<std::string> search_paths = {
            "keys.json", "../keys.json", "build/keys.json", "Release/keys.json", "../../keys.json"
        };

        std::ifstream f;
        for (const auto& path : search_paths) {
            f.open(path);
            if (f.is_open()) break;
        }

        if (!f.is_open()) {
            spdlog::error("🚨 CRITICAL: keys.json not found!");
            return;
        }

        try {
            auto j = nlohmann::json::parse(f);
            
            // Load keys
            key_pool.clear();
            for (auto& k : j["keys"]) {
                key_pool.push_back({k.get<std::string>(), true, 0});
            }
            
            // 🚀 Load all models (prioritized order)
            model_pool.clear();
            if (j.contains("models") && j["models"].is_array()) {
                for (auto& m : j["models"]) {
                    model_pool.push_back(m.get<std::string>());
                }
            } else {
                // Fallback: use primary/secondary if models array doesn't exist
                if (j.contains("primary")) model_pool.push_back(j["primary"]);
                if (j.contains("secondary")) model_pool.push_back(j["secondary"]);
            }
            
            // Default models if none specified
            if (model_pool.empty()) {
                model_pool = {
                    "gemini-2.5-flash",
                    "gemini-2.5-flash-lite"
                };
            }
            
            serper_key = j.value("serper", "");
            current_key_index = 0;
            current_model_index = 0;
            
            spdlog::info("🛰️ Unified Vault: {} keys, {} models loaded.", 
                        key_pool.size(), model_pool.size());
            
        } catch (const std::exception& e) {
            spdlog::error("💥 Failed to parse keys.json: {}", e.what());
        }
    }

    // 🚀 NEW: Get current combination
    struct KeyModelPair {
        std::string key;
        std::string model;
        size_t key_index;
        size_t model_index;
    };

    KeyModelPair get_current_pair() const {
        std::shared_lock lock(pool_mutex);
        if (key_pool.empty() || model_pool.empty()) return {"", "", 0, 0};
        
        size_t key_idx = current_key_index.load() % key_pool.size();
        size_t model_idx = current_model_index.load() % model_pool.size();
        
        return {
            key_pool[key_idx].key,
            model_pool[model_idx],
            key_idx,
            model_idx
        };
    }

    std::string get_current_key() const { 
        std::shared_lock lock(pool_mutex);
        if (key_pool.empty()) return "";
        return key_pool[current_key_index.load() % key_pool.size()].key;
    }

    std::string get_current_model() const {
        std::shared_lock lock(pool_mutex);
        if (model_pool.empty()) return "gemini-1.5-flash";
        return model_pool[current_model_index.load() % model_pool.size()];
    }

    std::string get_serper_key() const { return serper_key; }

    // 🚀 NEW: Rotate to next key (same model)
    void rotate_key() {
        current_key_index++;
    }

    // 🚀 NEW: Rotate to next model (reset key index)
    void rotate_model() {
        current_model_index++;
        current_key_index = 0; // Start fresh with new model
    }

    void report_rate_limit() {
        std::unique_lock lock(pool_mutex);
        if (key_pool.empty()) return;
        
        size_t idx = current_key_index.load() % key_pool.size();
        key_pool[idx].fail_count++;
        
        if (key_pool[idx].fail_count > 2) {
            key_pool[idx].is_active = false;
            spdlog::warn("⚠️ Key #{} Decommissioned due to Rate Limits", idx);
        }
    }

    size_t get_active_key_count() const {
        std::shared_lock lock(pool_mutex);
        size_t count = 0;
        for (const auto& k : key_pool) {
            if (k.is_active) count++;
        }
        return count;
    }

    size_t get_total_keys() const {
        std::shared_lock lock(pool_mutex);
        return key_pool.size();
    }

    size_t get_total_models() const {
        std::shared_lock lock(pool_mutex);
        return model_pool.size();
    }
    
};

} // namespace code_assistance