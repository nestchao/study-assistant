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
    mutable std::shared_mutex pool_mutex;
    std::atomic<size_t> current_index{0}; // Atomic for lock-free reading of index
    std::string primary_model;
    std::string secondary_model;
    std::string serper_key;

public:
    KeyManager() {
        refresh_key_pool();
    }

    // Heavy operation: File I/O + Parsing. Call only on startup or admin command.
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
            key_pool.clear();
            for (auto& k : j["keys"]) {
                key_pool.push_back({k.get<std::string>(), true, 0});
            }
            primary_model = j.value("primary", "gemini-1.5-flash");
            serper_key = j.value("serper", "");
            current_index = 0;
            
            spdlog::info("🛰️ Unified Vault: {} keys loaded.", key_pool.size());
        } catch (const std::exception& e) {
            spdlog::error("💥 Failed to parse keys.json: {}", e.what());
        }
    }

    std::string get_current_key() const { 
        std::shared_lock lock(pool_mutex); // Reader lock
        if (key_pool.empty()) return "";
        return key_pool[current_index.load() % key_pool.size()].key;
    }

    std::string get_current_model() const { return primary_model; }
    std::string get_serper_key() const { return serper_key; }

    void report_rate_limit() {
        std::unique_lock lock(pool_mutex); // Writer lock
        if (key_pool.empty()) return;
        
        size_t idx = current_index.load() % key_pool.size();
        key_pool[idx].fail_count++;
        
        if (key_pool[idx].fail_count > 2) {
            key_pool[idx].is_active = false;
            spdlog::warn("⚠️ Key #{} Decommissioned due to Rate Limits", idx);
        }
        
        current_index++; // Rotate
    }

    size_t get_active_key_count() const {
        std::shared_lock lock(pool_mutex);
        size_t count = 0;
        for (const auto& k : key_pool) {
            if (k.is_active) count++;
        }
        return count;
    }
    
};

} // namespace code_assistance