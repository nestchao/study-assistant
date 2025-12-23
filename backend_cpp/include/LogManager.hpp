#pragma once
#include <deque>
#include <mutex>
#include <vector>
#include <string>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

namespace code_assistance {

struct InteractionLog {
    long long timestamp;
    std::string project_id;
    std::string user_query; 
    std::string prompt_preview;
    std::string full_prompt; // The raw prompt sent to AI
    std::string ai_response;
    int token_count_est;     // Rough estimate
    double duration_ms;
};

class LogManager {
public:
    // Singleton access
    static LogManager& instance() {
        static LogManager instance;
        return instance;
    }

    void add_log(const InteractionLog& log) {
        std::lock_guard<std::mutex> lock(mtx_);
        logs_.push_back(log);
        if (logs_.size() > 50) { // Keep last 50 only
            logs_.pop_front();
        }
    }

    json get_logs_json() {
        std::lock_guard<std::mutex> lock(mtx_);
        json j_list = json::array();
        // Return in reverse order (newest first)
        for (auto it = logs_.rbegin(); it != logs_.rend(); ++it) {
            j_list.push_back({
                {"timestamp", it->timestamp},
                {"project_id", it->project_id},
                {"user_query", it->user_query},
                {"full_prompt", it->full_prompt},
                {"ai_response", it->ai_response},
                {"duration_ms", it->duration_ms}
            });
        }
        return j_list;
    }

private:
    LogManager() {} // Private constructor
    std::deque<InteractionLog> logs_;
    std::mutex mtx_;
};

}