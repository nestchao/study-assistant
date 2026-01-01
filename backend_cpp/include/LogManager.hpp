#pragma once
#include <deque>
#include <mutex>
#include <vector>
#include <string>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

namespace code_assistance {

struct AgentTrace {
    std::string session_id;
    std::string timestamp;
    std::string state;    // "RETRIEVING", "REFLECTING", etc.
    std::string detail;   // "E-Graph found 84 nodes", "Critic says context missing"
    double duration_ms;
};

struct InteractionLog {
    long long timestamp;
    std::string project_id;
    std::string user_query; 
    std::string prompt_preview;
    std::string full_prompt; // The raw prompt sent to AI
    std::string ai_response;
    int token_count_est;     // Rough estimate
    double duration_ms;
    int prompt_tokens = 0;
    int completion_tokens = 0;
    int total_tokens = 0;
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

    void add_trace(const AgentTrace& trace) {
        std::lock_guard<std::mutex> lock(mtx_);
        agent_traces_.push_back(trace);
        if (agent_traces_.size() > 100) agent_traces_.pop_front();
    }

    nlohmann::json get_traces_json() {
        std::lock_guard<std::mutex> lock(mtx_);
        nlohmann::json j = nlohmann::json::array();
        for (const auto& t : agent_traces_) {
            j.push_back({
                {"session_id", t.session_id},
                {"state", t.state},
                {"detail", t.detail},
                {"duration", t.duration_ms}
            });
        }
        return j;
    }

private:
    LogManager() {} // Private constructor
    std::deque<InteractionLog> logs_;
    std::deque<AgentTrace> agent_traces_;
    std::mutex mtx_;
};

}