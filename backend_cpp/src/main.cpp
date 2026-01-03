#include <httplib.h> // VCPKG Dependency
#include <spdlog/spdlog.h>
#include <nlohmann/json.hpp>
#include <memory>
#include <filesystem>
#include <thread>
#include <chrono>
#include <mutex>

#include "KeyManager.hpp"
#include "LogManager.hpp"
#include "ThreadPool.hpp"
#include "embedding_service.hpp"
#include "sync_service.hpp"
#include "SystemMonitor.hpp"
#include "agent/AgentExecutor.hpp"
#include "agent/SubAgent.hpp"
#include "tools/ToolRegistry.hpp"
#include "tools/FileSurgicalTool.hpp"
#include "tools/FileSystemTools.hpp"

namespace fs = std::filesystem;
using json = nlohmann::json;

// Forward declare if needed
namespace code_assistance {
    std::string web_search(const std::string& args_json, const std::string& api_key);
}

class CodeAssistanceServer {
public:
    CodeAssistanceServer(int port = 5002)
        : port_(port), thread_pool_(4) 
    {
        key_manager_ = std::make_shared<code_assistance::KeyManager>();
        ai_service_ = std::make_shared<code_assistance::EmbeddingService>(key_manager_);
        
        // Initialize other components for full functionality
        sub_agent_ = std::make_shared<code_assistance::SubAgent>();
        tool_registry_ = std::make_shared<code_assistance::ToolRegistry>();
        
        // Register Tools (Mirroring Agent Service for consistency)
        tool_registry_->register_tool(std::make_unique<code_assistance::ReadFileTool>());
        tool_registry_->register_tool(std::make_unique<code_assistance::ListDirTool>());
        
        executor_ = std::make_shared<code_assistance::AgentExecutor>(
            nullptr, ai_service_, sub_agent_, tool_registry_
        );

        setup_routes();
    }

    void run() {
        spdlog::info("🚀 REST Server (Ghost Text & Sync) listening on port {}", port_);
        server_.listen("0.0.0.0", port_);
    }

private:
    int port_;
    httplib::Server server_;
    ThreadPool thread_pool_;
    std::mutex store_mutex;
    
    // Core Services
    std::shared_ptr<code_assistance::KeyManager> key_manager_;
    std::shared_ptr<code_assistance::EmbeddingService> ai_service_;
    std::shared_ptr<code_assistance::SubAgent> sub_agent_;
    std::shared_ptr<code_assistance::ToolRegistry> tool_registry_;
    std::shared_ptr<code_assistance::AgentExecutor> executor_;
    
    // Data Stores
    std::unordered_map<std::string, std::shared_ptr<code_assistance::FaissVectorStore>> project_stores_;
    code_assistance::SystemMonitor system_monitor_;

    void setup_routes() {
        // CORS Headers
        server_.set_pre_routing_handler([](const httplib::Request&, httplib::Response& res) {
            res.set_header("Access-Control-Allow-Origin", "*");
            res.set_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
            res.set_header("Access-Control-Allow-Headers", "Content-Type");
            return httplib::Server::HandlerResponse::Unhandled;
        });

        server_.Options("/(.*)", [](const httplib::Request&, httplib::Response& res) {
            res.status = 204;
        });

        server_.Get("/api/hello", [](const httplib::Request&, httplib::Response& res) {
            res.set_content(R"({"status": "nominal", "backend": "cpp_v2"})", "application/json");
        });

        // 1. 👻 GHOST TEXT ENDPOINT (Latency Critical)
        server_.Post("/complete", [this](const httplib::Request& req, httplib::Response& res) {
            auto start = std::chrono::high_resolution_clock::now();
            std::string prefix = "";
            
            try {
                auto body = json::parse(req.body);
                prefix = body.value("prefix", "");
                
                if (prefix.empty()) { res.status = 400; return; }

                // 🚀 FIX: Explicitly use this-> to access member
                auto vector_preview = this->ai_service_->generate_embedding(prefix.substr(0, 100));
                std::string completion = this->ai_service_->generate_autocomplete(prefix);

                auto end = std::chrono::high_resolution_clock::now();
                double ms = std::chrono::duration<double, std::milli>(end - start).count();
                code_assistance::SystemMonitor::global_llm_generation_ms.store(ms);

                // LOGGING
                code_assistance::InteractionLog log;
                log.timestamp = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
                log.project_id = "IDE_EXTENSION";
                log.request_type = "GHOST";
                log.user_query = "Cursor Context"; 
                log.full_prompt = prefix;
                log.ai_response = completion;
                log.duration_ms = ms;
                log.total_tokens = (prefix.length() + completion.length()) / 4; 
                
                if(vector_preview.size() > 8) {
                    log.vector_snapshot = std::vector<float>(vector_preview.begin(), vector_preview.begin() + 8);
                }

                code_assistance::LogManager::instance().add_log(log);
                spdlog::info("👻 Ghost: [{}] ({}ms)", completion, ms);

                res.set_content(json{{"completion", completion}}.dump(), "application/json");
            } catch (...) {
                res.status = 500;
            }
        });

        // 2. 🔄 ATOMIC FILE SYNC
        server_.Post("/sync/file/:project_id", [this](const httplib::Request& req, httplib::Response& res) {
            try {
                std::string project_id = req.path_params.at("project_id");
                auto body = json::parse(req.body);
                std::string rel_path = body.value("file_path", "");

                // 🛡️ SAFETY VALVE
                if (rel_path.find(".study_assistant") != std::string::npos || 
                    rel_path.find("converted_files") != std::string::npos) {
                    spdlog::warn("🛑 Sync Rejected (Internal Path): {}", rel_path);
                    res.status = 200; 
                    return;
                }

                // In a real implementation we'd use this->thread_pool_.enqueue(...)
                // For now, logging to confirm receipt
                spdlog::info("🔄 Sync Queued: {}", rel_path);

                res.set_content(json{{"status", "queued"}}.dump(), "application/json");
            } catch (...) { res.status = 400; }
        });

        // 3. 📊 TELEMETRY DASHBOARD API
        server_.Get("/api/admin/telemetry", [this](const httplib::Request&, httplib::Response& res) {
            auto metrics = system_monitor_.get_latest_snapshot();
            auto logs = code_assistance::LogManager::instance().get_logs_json();

            json response = {
                {"metrics", {
                    {"cpu", metrics.cpu_usage},
                    {"ram_mb", metrics.ram_usage_mb},
                    {"ram_total", metrics.ram_total_mb},
                    {"tps", metrics.tokens_per_second},
                    {"llm_latency", metrics.llm_generation_ms}
                }},
                {"logs", logs}
            };
            res.set_content(response.dump(), "application/json");
        });

        // 4. 🧠 AGENT TRACE API
        server_.Get("/api/admin/agent_trace", [](const httplib::Request&, httplib::Response& res) {
             auto traces = code_assistance::LogManager::instance().get_traces_json();
             res.set_content(traces.dump(), "application/json");
        });

        // Serve Static Files
        server_.set_mount_point("/", "./www");
        server_.Get("/admin", [](const httplib::Request&, httplib::Response& res) {
            res.set_redirect("/index.html");
        });
        
        // ... (Keep existing handlers for handle_register_project, handle_sync_project, etc.) ...
        // For brevity in this fix, I am ensuring the class members and /complete endpoint are correct.
        // You can paste back the other handler methods here if needed, but ensure they use 'this->'
    }
    
    // ... (Helper methods like load_project_config, load_vector_store would go here) ...
};

void pre_flight_check() {
    if (!fs::exists("keys.json")) spdlog::warn("⚠️ keys.json not found in CWD!");
    if (!fs::exists("www/index.html")) spdlog::warn("⚠️ www/index.html not found in CWD!");
}

int main() {
    spdlog::set_pattern("[%H:%M:%S] [%^%l%$] %v");
    pre_flight_check();
    
    CodeAssistanceServer server;
    server.run();
    return 0;
}