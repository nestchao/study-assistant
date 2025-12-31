#pragma once
#include <vector>
#include <string>
#include <shared_mutex>
#include <nlohmann/json.hpp>
#include <fstream>
#include <spdlog/spdlog.h>

namespace code_assistance {

class KeyManager { // Standardized name
private:
    struct ApiKey {
        std::string key;
        bool is_active = true;
        int fail_count = 0;
    };

    std::vector<ApiKey> key_pool;
    mutable std::shared_mutex pool_mutex;
    size_t current_index = 0;
    std::string primary_model;
    std::string secondary_model;
    std::string serper_key;

public:
    KeyManager() {
        refresh_key_pool();
    }

    void refresh_key_pool() {
        std::unique_lock lock(pool_mutex);

        std::vector<std::string> search_paths = {
            "keys.json",                // 1. Current Working Directory
            "../keys.json",             // 2. Parent Directory (common in build/Release)
            "build/keys.json",          // 3. Build Directory
            "Release/keys.json",        // 4. Release Directory
            "../../keys.json"           // 5. Project Root (from build/Release)
        };

        std::ifstream f;
        std::string found_path = "";

        for (const auto& path : search_paths) {
            f.open(path);
            if (f.is_open()) {
                found_path = path;
                break;
            }
        }

        if (found_path.empty()) {
            spdlog::error("🚨 CRITICAL: Key Pool (keys.json) not found in any standard path!");
            return;
        }

        try {
            auto j = nlohmann::json::parse(f);
            
            // 1. Load Brain Keys (Gemini)
            key_pool.clear();
            for (auto& k : j["keys"]) {
                key_pool.push_back({k.get<std::string>(), true, 0});
            }

            // 2. Load Static Metadata
            primary_model = j.value("primary", "gemini-1.5-flash");
            
            // 🚀 Load Sensory Payload (Serper)
            serper_key = j.value("serper", ""); 

            if (serper_key.empty()) {
                spdlog::warn("⚠️ Web-Oculus (Serper) key is missing in keys.json!");
            }
            
            spdlog::info("🛰️ Unified Vault Synchronized: {} brain keys, Oculus status: {}", 
                         key_pool.size(), serper_key.empty() ? "OFFLINE" : "READY");
        } catch (const std::exception& e) {
            spdlog::error("💥 Failed to parse Intelligence Vault: {}", e.what());
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

    std::string get_serper_key() const {
        std::shared_lock lock(pool_mutex);
        return serper_key;
    }

    std::string get_current_key() const { 
        std::shared_lock lock(pool_mutex);
        if (key_pool.empty()) return "";
        return key_pool[current_index % key_pool.size()].key;
    }

    std::string get_current_model() const {
        return primary_model; // Or logic to switch to secondary
    }

    void report_rate_limit() {
        std::unique_lock lock(pool_mutex);
        if (key_pool.empty()) return;
        
        auto& current = key_pool[current_index % key_pool.size()];
        current.fail_count++;
        if (current.fail_count > 2) {
            current.is_active = false;
            spdlog::warn("⚠️ Key #{} Decommissioned", current_index);
        }
        current_index = (current_index + 1) % key_pool.size();
    }
};

} // namespace code_assistance