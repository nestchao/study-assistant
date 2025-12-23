#pragma once
#include <vector>
#include <string>
#include <sstream>
#include <iostream>
#include <fstream>
#include <atomic>
#include <mutex>
#include <algorithm>
#include <map>
#include <spdlog/spdlog.h>

class KeyManager {
private:
    std::vector<std::string> api_keys;
    std::string primary_model;
    std::string secondary_model;
    
    std::atomic<size_t> current_key_index{0};
    std::atomic<bool> using_secondary_model{false};
    std::mutex rotation_mutex;

    // --- INTERNAL .ENV PARSER ---
    // Why use a library when 20 lines of C++ does it faster and breaks less?
    std::map<std::string, std::string> load_env_file(const std::string& path = ".env") {
        std::map<std::string, std::string> env_map;
        std::ifstream file(path);
        
        if (!file.is_open()) {
            spdlog::warn("⚠️ .env file not found at '{}'. Relying on system environment variables.", path);
            return env_map;
        }

        std::string line;
        while (std::getline(file, line)) {
            // Trim whitespace
            line.erase(0, line.find_first_not_of(" \t\r\n"));
            line.erase(line.find_last_not_of(" \t\r\n") + 1);

            // Skip comments and empty lines
            if (line.empty() || line[0] == '#') continue;

            auto delimiterPos = line.find('=');
            if (delimiterPos != std::string::npos) {
                std::string key = line.substr(0, delimiterPos);
                std::string value = line.substr(delimiterPos + 1);
                
                // Remove quotes if present
                if (value.size() >= 2 && value.front() == '"' && value.back() == '"') {
                    value = value.substr(1, value.size() - 2);
                }
                
                env_map[key] = value;
            }
        }
        return env_map;
    }

    std::string get_env(const std::string& key, const std::map<std::string, std::string>& file_env, const std::string& default_val = "") {
        // 1. Try real Environment Variable (OS level)
        const char* val = std::getenv(key.c_str());
        if (val) return std::string(val);

        // 2. Try .env file content
        if (file_env.count(key)) return file_env.at(key);

        return default_val;
    }

public:
    KeyManager() {
        auto env_map = load_env_file();

        // Load Keys
        std::string keys_raw = get_env("GEMINI_API_KEYS", env_map);
        
        if (keys_raw.empty()) {
            // Fallback for legacy single key
            std::string single = get_env("GEMINI_API_KEY", env_map);
            if (!single.empty()) keys_raw = single;
            else {
                spdlog::error("❌ CRITICAL: No API Keys found. Please set GEMINI_API_KEYS in .env");
                throw std::runtime_error("Missing API Keys");
            }
        }

        std::stringstream ss(keys_raw);
        std::string segment;
        while (std::getline(ss, segment, ',')) {
            // Trim spaces from keys just in case user added spaces
            segment.erase(0, segment.find_first_not_of(" \t"));
            segment.erase(segment.find_last_not_of(" \t") + 1);
            if(!segment.empty()) api_keys.push_back(segment);
        }

        // Load Models
        primary_model = get_env("PRIMARY_MODEL", env_map, "gemini-2.5-flash-lite");
        secondary_model = get_env("SECONDARY_MODEL", env_map, "gemini-2.5-flash");

        spdlog::info("🔑 KeyManager Initialized | Keys: {} | Model: {}", api_keys.size(), primary_model);
    }

    std::string get_current_key() const {
        if (api_keys.empty()) return "";
        // Thread-safe access to the rotated index
        return api_keys[current_key_index.load() % api_keys.size()];
    }

    std::string get_current_model() const {
        return using_secondary_model.load() ? secondary_model : primary_model;
    }

    void report_rate_limit() {
        std::lock_guard<std::mutex> lock(rotation_mutex);
        
        size_t next_index = current_key_index.load() + 1;
        
        if (next_index >= api_keys.size()) {
            if (!using_secondary_model.load()) {
                spdlog::warn("⚠️ All keys exhausted for Primary Model. Downgrading to Secondary: {}", secondary_model);
                using_secondary_model.store(true);
                current_key_index.store(0);
            } else {
                spdlog::error("❌ CRITICAL: System Throttled. All keys/models exhausted.");
                current_key_index.store(0); 
            }
        } else {
            current_key_index.store(next_index);
            spdlog::warn("🔄 Switched to API Key #{}", next_index);
        }
    }
};