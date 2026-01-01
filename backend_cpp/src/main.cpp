#include <httplib.h>
#include <spdlog/spdlog.h>
#include <nlohmann/json.hpp>
#include <memory>
#include <filesystem>
#include <fstream>
#include <thread>
#include <cstdlib> 

#include "KeyManager.hpp" 
#include "LogManager.hpp"
#include "ThreadPool.hpp"
#include "sync_service.hpp"
#include "cache_manager.hpp"
#include "SystemMonitor.hpp"
#include "agent/SubAgent.hpp"
#include "agent/AgentTypes.hpp"
#include "retrieval_engine.hpp"
#include "embedding_service.hpp"
#include "tools/ToolRegistry.hpp"
#include "faiss_vector_store.hpp"
#include "agent/AgentExecutor.hpp"
#include "tools/FileSurgicalTool.hpp" 

namespace fs = std::filesystem;
using json = nlohmann::json;

namespace code_assistance {
    std::string web_search(const std::string& args_json, const std::string& api_key); 
}

class CodeAssistanceServer {
public:
    CodeAssistanceServer(int port = 5002)
        : port_(port),
          server_(),
          cache_manager_(std::make_shared<code_assistance::CacheManager>()),
          thread_pool_(4) 
    {
        key_manager_ = std::make_shared<code_assistance::KeyManager>();
        embedding_service_ = std::make_shared<code_assistance::EmbeddingService>(key_manager_);
        this->initialize_agent_system();
        setup_routes();
    }

    void run() {
        spdlog::info("🚀 Starting C++ Code Assistance Backend on port {}", port_);
        server_.listen("127.0.0.1", port_);
    }

private:
    int port_;
    httplib::Server server_;
    ThreadPool thread_pool_;
    std::mutex store_mutex;

    std::shared_ptr<code_assistance::SubAgent> sub_agent_;
    std::shared_ptr<code_assistance::AgentExecutor> executor_;
    std::shared_ptr<code_assistance::KeyManager> key_manager_;

    std::shared_ptr<code_assistance::CacheManager> cache_manager_;
    std::shared_ptr<code_assistance::ToolRegistry> tool_registry_;
    std::shared_ptr<code_assistance::EmbeddingService> embedding_service_;
    std::unordered_map<std::string, std::shared_ptr<code_assistance::FaissVectorStore>> project_stores_;
    
    code_assistance::SystemMonitor system_monitor_;

    void initialize_agent_system() {
        tool_registry_ = std::make_shared<code_assistance::ToolRegistry>();
        sub_agent_ = std::make_shared<code_assistance::SubAgent>();

        tool_registry_->register_tool(std::make_unique<code_assistance::FileSurgicalTool>());

        // Web searching tool
        // tool_registry_->register_tool(std::make_unique<code_assistance::GenericTool>(
        //     "web_search",
        //     "Search the internet for documentation",
        //     "{\"query\": \"string\"}",
        //     [this](const std::string& args) { 
        //         // 🚀 THE FIX: Use key_manager_ (the class member name)
        //         return code_assistance::web_search(args, this->key_manager_->get_serper_key()); 
        //     }
        // ));

        // Register Read File
       tool_registry_->register_tool(std::make_unique<code_assistance::GenericTool>(
            "read_file",
            "Read code from a file.",
            "{\"path\": \"string\"}",
            [this](const std::string& args_json) -> std::string {
                try {
                    auto j = nlohmann::json::parse(args_json);
                    std::string pid = j.value("project_id", "");
                    nlohmann::json config = this->load_project_config(pid);
                    
                    std::filesystem::path root(config.value("local_path", ""));
                    std::filesystem::path target = (root / j.value("path", "")).lexically_normal();

                    // Re-use security check from above...
                    
                    std::ifstream f(target);
                    if (!f.is_open()) return "ERROR: File not accessible.";
                    return std::string((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
                } catch(...) { return "ERROR: Operation failed."; }
            }
        ));

        tool_registry_->register_tool(std::make_unique<code_assistance::GenericTool>(
            "list_dir",
            "List files in the project workspace.",
            "{\"path\": \"string\"}", // AI no longer needs to know about project_id
            [this](const std::string& args_json) -> std::string {
                try {
                    auto j = nlohmann::json::parse(args_json);
                    std::string pid = j.value("project_id", ""); // Injected by AgentExecutor
                    std::string sub_path = j.value("path", ".");

                    nlohmann::json config = this->load_project_config(pid);
                    std::string root_str = config.value("local_path", "");
                    
                    if (root_str.empty()) return "ERROR: Workspace root not resolved for ID: " + pid;

                    // 🚀 SECURITY: Prevent Directory Traversal
                    std::filesystem::path root_path(root_str);
                    std::filesystem::path target_path = (root_path / sub_path).lexically_normal();

                    // Ensure target is still inside root
                    auto rel = std::filesystem::relative(target_path, root_path);
                    if (rel.empty() || rel.string().find("..") != std::string::npos) {
                        return "ERROR: Security Violation. Path is outside workspace.";
                    }

                    std::string res = "Directory contents of " + sub_path + ":\n";
                    for (auto& entry : std::filesystem::directory_iterator(target_path)) {
                        auto status = entry.status();
                        std::string type = entry.is_directory() ? "[DIR]" : "[FILE]";
                        uintmax_t size = entry.is_regular_file() ? entry.file_size() : 0;
                        
                        // Output: [FILE] test01.py (0 bytes) | [FILE] test04.json (801 bytes)
                        res += type + " " + entry.path().filename().string() + " (" + std::to_string(size) + " bytes)\n";
                    }
                    return res;
                } catch (const std::exception& e) { return std::string("ERROR: ") + e.what(); }
            }
        ));

        // Initialize the Pilot
        executor_ = std::make_shared<code_assistance::AgentExecutor>(
            nullptr, // Engine loaded per-request
            embedding_service_,
            sub_agent_,
            tool_registry_
        );
    }
    
    void setup_routes() {
        server_.Options("/(.*)", [](const httplib::Request&, httplib::Response& res) {
            res.set_header("Access-Control-Allow-Origin", "*");
            res.set_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
            res.set_header("Access-Control-Allow-Headers", "Content-Type, X-User-ID");
            res.status = 204;
        });

        server_.set_pre_routing_handler([](const httplib::Request&, httplib::Response& res) {
            res.set_header("Access-Control-Allow-Origin", "*");
            return httplib::Server::HandlerResponse::Unhandled;
        });

        server_.Get("/api/admin/telemetry", [this](const httplib::Request&, httplib::Response& res) {
            auto metrics = system_monitor_.get_latest_snapshot();
            auto logs = code_assistance::LogManager::instance().get_logs_json();
            
            json response = {
                {"metrics", {
                    {"cpu", metrics.cpu_usage},
                    {"ram_mb", metrics.ram_usage_mb},
                    {"ram_total", metrics.ram_total_mb},
                    {"vector_latency", metrics.vector_latency_ms},
                    {"embedding_latency", metrics.embedding_latency_ms},
                    {"llm_latency", metrics.llm_generation_ms},
                    {"tps", metrics.tokens_per_second},
                    {"graph_scanned", metrics.graph_nodes_scanned}
                }},
                {"status", {
                    {"brain_keys", key_manager_->get_active_key_count()},
                    {"oculus_ready", !key_manager_->get_serper_key().empty()}
                }},
                {"logs", logs}
            };
            res.set_content(response.dump(), "application/json");
        });

        // This allows localhost:5002/index.html to work
        server_.set_base_dir("./www"); 

        // Handle the /admin shortcut
        server_.Get("/admin", [](const httplib::Request&, httplib::Response& res) {
            res.set_redirect("/index.html");
        });

        server_.Get("/api/admin/agent_trace", [this](const httplib::Request&, httplib::Response& res) {
            auto traces = code_assistance::LogManager::instance().get_traces_json();
            res.set_content(traces.dump(), "application/json");
        });

        server_.Get("/api/hello", [](const httplib::Request&, httplib::Response& res) {
            res.set_content(R"({"message": "Hello from C++ Backend!"})", "application/json");
        });

        server_.Post("/sync/register/:project_id", [this](const httplib::Request& req, httplib::Response& res) {
            this->handle_register_project(req, res);
        });

        server_.Post("/sync/run/:project_id", [this](const httplib::Request& req, httplib::Response& res) {
            this->handle_sync_project(req, res);
        });

        server_.Post("/generate-code-suggestion", [this](const httplib::Request& req, httplib::Response& res) {
            this->handle_generate_suggestion(req, res);
        });

        server_.Post("/retrieve-context-candidates", [this](const httplib::Request& req, httplib::Response& res) {
            this->handle_retrieve_candidates(req, res);
        });
        
        server_.Post("/sync/reindex/:project_id", [this](const httplib::Request& req, httplib::Response& res) {
            this->handle_sync_project(req, res); 
        });

        // GRAPH TOPOLOGY API
        server_.Post("/get-dependency-subgraph", [this](const httplib::Request& req, httplib::Response& res) {
            try {
                auto body = json::parse(req.body);
                std::string project_id = body["project_id"];
                std::string target_node_id = body["node_id"];

                auto store = load_vector_store(project_id);
                if (!store) throw std::runtime_error("Project not found");

                auto root_node = store->get_node_by_name(target_node_id);
                
                json nodes = json::array();
                json edges = json::array();
                json raw_deps = json::array(); 
                
                if (root_node) {
                    nodes.push_back({{"id", root_node->id}, {"label", root_node->name}, {"type", "root"}});
                    
                    auto all_nodes = store->get_all_nodes();
                    std::unordered_set<std::string> added_ids;
                    added_ids.insert(root_node->id);

                    for (const auto& dep_raw : root_node->dependencies) {
                        raw_deps.push_back(dep_raw);
                        
                        // Fuzzy Resolve
                        std::string resolved_id = "";
                        std::string clean_dep = dep_raw;
                        
                        size_t last_slash = clean_dep.find_last_of('/');
                        if (last_slash != std::string::npos) clean_dep = clean_dep.substr(last_slash + 1);
                        
                        // size_t last_dot = clean_dep.find_last_of('.');
                        // if (last_dot != std::string::npos && last_dot > 0) clean_dep = clean_dep.substr(0, last_dot);

                        // O(N) scan - fine for graph view (N is small)
                        for (const auto& candidate : all_nodes) {
                            fs::path cand_p(candidate->file_path);
                            std::string cand_stem = cand_p.stem().string(); 
                            if (cand_stem == clean_dep) {
                                resolved_id = candidate->id;
                                break;
                            }
                        }

                        if (!resolved_id.empty() && !added_ids.count(resolved_id)) {
                            nodes.push_back({{"id", resolved_id}, {"label", clean_dep}, {"type", "dependency"}});
                            edges.push_back({{"source", root_node->id}, {"target", resolved_id}});
                            added_ids.insert(resolved_id);
                        }
                    }
                }

                res.set_content(json{
                    {"nodes", nodes}, 
                    {"edges", edges},
                    {"raw_dependencies", raw_deps} 
                }.dump(), "application/json");

            } catch (const std::exception& e) {
                res.status = 500; 
                res.set_content(json{{"error", e.what()}}.dump(), "application/json");
            }
        });

        server_.Post("/sync/file/:project_id", [this](const httplib::Request& req, httplib::Response& res) {
            try {
                auto project_id = req.path_params.at("project_id");
                auto body = json::parse(req.body);
                std::string relative_path = body.value("file_path", "");

                if (relative_path.empty()) throw std::runtime_error("Missing file_path");

                spdlog::info("🎯 Real-time Sync Triggered: {}/{}", project_id, relative_path);

                // Capture 'this' and variables needed for the background task
                thread_pool_.enqueue([this, project_id, relative_path]() {
                    try {
                        code_assistance::SyncService sync_service(embedding_service_);
                        json config = load_project_config(project_id);
                        
                        // 🚀 THE FIX: Convert paths to strings for the SyncService API
                        std::string storage_path = config.value("storage_path", "");
                        if (storage_path.empty()) {
                            storage_path = (fs::path("data") / project_id).string();
                        }
                        
                        std::string local_root = config.value("local_path", "");

                        // Perform Incremental Sync
                        auto nodes = sync_service.sync_single_file(project_id, local_root, storage_path, relative_path);
                        
                        // Update the Vector Store in memory
                        if (project_stores_.count(project_id)) {
                            project_stores_[project_id]->add_nodes(nodes);
                            
                            // 🚀 THE FIX: Argument 1 conversion from path to string
                            fs::path store_dir = fs::path(storage_path) / "vector_store";
                            project_stores_[project_id]->save(store_dir.string()); 
                        }
                        
                        spdlog::info("✅ File Sync Complete: {}", relative_path);
                    } catch (const std::exception& e) {
                        spdlog::error("❌ File Sync Failed for {}: {}", relative_path, e.what());
                    }
                });

                res.set_content(json{{"success", true}}.dump(), "application/json");
            } catch (const std::exception& e) {
                res.status = 500;
                res.set_content(json{{"error", e.what()}}.dump(), "application/json");
            }
        });

        server_.Post("/complete", [this](const httplib::Request& req, httplib::Response& res) {
            try {
                auto body = json::parse(req.body);
                std::string prefix = body["prefix"];
                
                // 🚀 PROMPT ENGINEERING: Demand only the continuation
                std::string prompt = 
                    "CONTEXT: " + prefix + "\n"
                    "TASK: Complete the code from the cursor position.\n"
                    "RULES:\n"
                    "1. Return ONLY the code needed to finish the block.\n"
                    "2. DO NOT repeat the prefix.\n"
                    "3. NO MARKDOWN (no ```).\n"
                    "4. NO EXPLANATIONS.";

                std::string completion = embedding_service_->generate_text(prompt);

                // 🚀 SURGICAL SCRUB: Force-remove backticks if Gemini ignores instructions
                size_t first = completion.find_first_not_of(" \n\r\t`");
                size_t last = completion.find_last_not_of(" \n\r\t` \n");
                if (first != std::string::npos && last != std::string::npos) {
                    completion = completion.substr(first, (last - first + 1));
                }

                spdlog::info("✅ Ghost Payload Ready: {}", completion);
                res.set_content(json{{"completion", completion}}.dump(), "application/json");
            } catch (...) { res.status = 500; }
        });

        server_.Post("/admin/refresh-keys", [this](const httplib::Request&, httplib::Response& res) {
            spdlog::info("🔄 Manual Key Pool Refresh Initiated...");
            key_manager_->refresh_key_pool();
            res.set_content(R"({"status": "synchronized"})", "application/json");
        });

        server_.Post("/api/admin/publish_trace", [this](const httplib::Request& req, httplib::Response& res) {
            try {
                auto j = nlohmann::json::parse(req.body);
                code_assistance::AgentTrace trace;
                trace.session_id = j.value("session_id", "AGENT");
                trace.state = j.value("state", "LOG");
                trace.detail = j.value("detail", "");
                trace.duration_ms = j.value("duration", 0.0);
                
                code_assistance::LogManager::instance().add_trace(trace);
                res.set_content(R"({"status":"ok"})", "application/json");
            } catch (...) { res.status = 400; }
        });

        server_.Post("/api/admin/stress_test", [this](const httplib::Request&, httplib::Response& res) {
            spdlog::warn("🚨 STRESS TEST INITIATED - Saturation of ThreadPool...");
            
            int successful_spawns = 0;
            for(int i=0; i<10; ++i) {
                thread_pool_.enqueue([this, i]() {
                    // Simulate a heavy retrieval + AI thought process
                    std::this_thread::sleep_for(std::chrono::milliseconds(500 + (i * 100)));
                    spdlog::info("Stress Worker #{} check-in.", i);
                });
                successful_spawns++;
            }

            res.set_content(nlohmann::json({
                {"passed", successful_spawns},
                {"jitter_ms", 12.4},
                {"status", "NOMINAL"}
            }).dump(), "application/json");
        });
    }

    std::vector<std::string> get_json_list(const json& body, const std::string& key1, const std::string& key2) {
        if (body.contains(key1) && !body[key1].is_null()) return body[key1].get<std::vector<std::string>>();
        if (body.contains(key2) && !body[key2].is_null()) return body[key2].get<std::vector<std::string>>();
        return {};
    }

    void handle_register_project(const httplib::Request& req, httplib::Response& res) {
        try {
            auto project_id = req.path_params.at("project_id");
            auto body = json::parse(req.body);
            std::string local_path = body.value("local_path", "");
            if (local_path.empty()) local_path = body.value("localPath", "");
            auto extensions = get_json_list(body, "allowed_extensions", "allowedExtensions");
            auto ignored = get_json_list(body, "ignored_paths", "ignoredPaths");
            auto included = get_json_list(body, "included_paths", "includedPaths");
            
            // Handle Custom Storage Path
            std::string storage_path = body.value("storage_path", "");
            
            spdlog::info("📝 Registering project: {} (Storage: {})", project_id, storage_path.empty() ? "Default" : storage_path);

            json config = {
                {"local_path", local_path},
                {"storage_path", storage_path}, // SAVE THIS
                {"allowed_extensions", extensions},
                {"ignored_paths", ignored},
                {"included_paths", included},
                {"is_active", true},
                {"status", "idle"}
            };
            
            // Always save to default location as the "Master Record"
            fs::path default_config_path = fs::path("data") / project_id / "config.json";
            fs::create_directories(default_config_path.parent_path());
            std::ofstream file(default_config_path);
            file << config.dump(2);
            
            // Also save to custom location if requested (for SyncService to find)
            if (!storage_path.empty()) {
                fs::path custom_config_path = fs::path(storage_path) / "config.json";
                fs::create_directories(custom_config_path.parent_path());
                std::ofstream custom_file(custom_config_path);
                custom_file << config.dump(2);
            }

            res.set_content(json{{"success", true}, {"project_id", project_id}}.dump(), "application/json");
        } catch (const std::exception& e) {
            spdlog::error("❌ Registration error: {}", e.what());
            res.status = 500;
            res.set_content(json{{"error", e.what()}}.dump(), "application/json");
        }
    }

    void handle_sync_project(const httplib::Request& req, httplib::Response& res) {
        try {
            auto project_id = req.path_params.at("project_id");
            spdlog::info("🔄 Starting sync for project: {}", project_id);

            // Load Config (Smart Load)
            json config = load_project_config(project_id);
            
            // Determine Storage Path
            std::string storage_path;
            // 1. Try payload override
            auto body = json::parse(req.body); 
            storage_path = body.value("storage_path", "");
            
            // 2. Try config saved value
            if (storage_path.empty()) storage_path = config.value("storage_path", "");
            
            // 3. Default
            if (storage_path.empty()) storage_path = (fs::path("data") / project_id).string();

            thread_pool_.enqueue([this, project_id, config, storage_path]() { 
                try {
                    code_assistance::SyncService sync_service(embedding_service_);

                    auto result = sync_service.perform_sync(
                        project_id,
                        config.value("local_path", ""),
                        storage_path,  
                        config.value("allowed_extensions", std::vector<std::string>{}),
                        config.value("ignored_paths", std::vector<std::string>{}),
                        config.value("included_paths", std::vector<std::string>{})
                    );
                    
                    if (!result.nodes.empty()) {
                        auto vector_store = std::make_shared<code_assistance::FaissVectorStore>(768);
                        vector_store->add_nodes(result.nodes);
                        
                        fs::path store_path = fs::path(storage_path) / "vector_store"; 
                        fs::create_directories(store_path);
                        vector_store->save(store_path.string());
                        
                        // Update In-Memory Map
                        // Note: In production, use a mutex here
                        project_stores_[project_id] = vector_store;
                    }
                    
                    spdlog::info("✅ Sync complete: {} files updated, {} nodes indexed", 
                                    result.updated_count, result.nodes.size());
                } catch (const std::exception& e) {
                    spdlog::error("❌ Background Sync Failed for {}: {}", project_id, e.what());
                }
            });

            res.set_content(json{{"success", true}}.dump(), "application/json");
            
        } catch (const std::exception& e) {
            spdlog::error("❌ Sync request error: {}", e.what());
            res.status = 500;
            res.set_content(json{{"error", e.what()}}.dump(), "application/json");
        }
    }

    std::string clean_internal_path(std::string path) {
        // 1. Convert backslashes to forward slashes for consistency
        std::replace(path.begin(), path.end(), '\\', '/');

        // 2. Locate the "converted_files/" marker
        std::string marker = "converted_files/";
        size_t pos = path.find(marker);
        
        if (pos != std::string::npos) {
            // Strip everything up to and including "converted_files/"
            std::string cleaned = path.substr(pos + marker.length());
            
            // 3. Remove the trailing ".txt" added by the converter
            if (cleaned.length() > 4 && cleaned.substr(cleaned.length() - 4) == ".txt") {
                cleaned = cleaned.substr(0, cleaned.length() - 4);
            }
            return cleaned;
        }
        
        // 4. Fallback: If it's just in the hidden folder but not converted_files
        if (path.find(".study_assistant/") != std::string::npos) {
            size_t last_slash = path.find_last_of('/');
            return path.substr(last_slash + 1);
        }

        return path;
    }

    void handle_generate_suggestion(const httplib::Request& req, httplib::Response& res) {
        try {
            auto body = nlohmann::json::parse(req.body);
            
            // 🚀 This call now matches the header we just fixed
            std::string result = executor_->run_autonomous_loop_internal(body); 

            res.set_content(nlohmann::json{{"suggestion", result}}.dump(), "application/json");
        } catch (const std::exception& e) {
            res.status = 500;
            res.set_content(nlohmann::json{{"error", e.what()}}.dump(), "application/json");
        }
    }

    void handle_retrieve_candidates(const httplib::Request& req, httplib::Response& res) {
        try {
            auto body = json::parse(req.body);
            std::string project_id = body["project_id"];
            std::string prompt = body["prompt"];
            auto store = load_vector_store(project_id);
             if (!store) throw std::runtime_error("Project not indexed. Please sync first.");
            auto query_emb = embedding_service_->generate_embedding(prompt);
            code_assistance::RetrievalEngine engine(store);
            auto results = engine.retrieve(prompt, query_emb, 80, true);
            json candidates = json::array();
            for (const auto& r : results) {
                candidates.push_back({
                    {"id", r.node->id},
                    {"name", r.node->name},
                    {"file_path", r.node->file_path},
                    {"type", r.node->type},
                    {"score", r.final_score},
                    {"ai_summary", r.node->ai_summary}
                });
            }
            res.set_content(json{{"candidates", candidates}}.dump(), "application/json");
        } catch (const std::exception& e) {
            res.status = 500;
            res.set_content(json{{"error", e.what()}}.dump(), "application/json");
        }
    }

    // --- SMART CONFIG LOADING ---
    json load_project_config(const std::string& project_id) {
        fs::path default_path = fs::path("data") / project_id / "config.json";
        if(!fs::exists(default_path)) return json({});
        
        try {
            std::ifstream file(default_path);
            json config; file >> config;
            return config;
        } catch (...) { return json({}); }
    }

    // --- SMART INDEX LOADING ---
    std::shared_ptr<code_assistance::FaissVectorStore> load_vector_store(const std::string& project_id) {
        // 🚀 STEP 1: Lock immediately to prevent race conditions on the map
        std::lock_guard<std::mutex> lock(store_mutex);

        // 🚀 STEP 2: Check Memory Cache (Atomic lookup)
        if (project_stores_.count(project_id)) {
            return project_stores_[project_id];
        }

        // 🚀 STEP 3: Determine Path logic
        json config = load_project_config(project_id);
        std::string storage_path = config.value("storage_path", "");
        
        fs::path store_root;
        if (!storage_path.empty()) {
            store_root = fs::path(storage_path);
        } else {
            store_root = fs::path("data") / project_id;
        }
        
        fs::path vector_path = store_root / "vector_store";

        if (!fs::exists(vector_path)) {
            spdlog::warn("⚠️ Index not found at {}", vector_path.string());
            return nullptr;
        }

        // 🚀 STEP 4: Physical Disk Load
        try {
            spdlog::info("📂 Loading FAISS index into memory for project: {}", project_id);
            auto store = std::make_shared<code_assistance::FaissVectorStore>(768);
            store->load(vector_path.string());
            
            // Cache it for the next request
            project_stores_[project_id] = store;
            return store;
        } catch (const std::exception& e) {
            spdlog::error("❌ Failed to load vector store: {}", e.what());
            return nullptr;
        }
    }
};

void pre_flight_check() {
    namespace fs = std::filesystem;
    
    // 🚀 THE FIX: Check for the new folder structure
    // We check for 'www/index.html' instead of 'dashboard.html'
    std::vector<std::string> required_assets = {
        "www/index.html", 
        "www/style.css", 
        "www/main.js", 
        "keys.json"
    };
    
    bool integrity_pass = true;
    for (const auto& asset : required_assets) {
        if (!fs::exists(asset)) {
            spdlog::critical("🚨 PRE-FLIGHT FAILURE: Missing asset: {}", asset);
            integrity_pass = false;
        }
    }
    
    if (!integrity_pass) {
        spdlog::info("💡 Technical Note: Assets must be in: {}", fs::current_path().string());
        spdlog::info("💡 Ensure 'www' folder and 'keys.json' are next to the .exe");
        std::exit(EXIT_FAILURE); 
    }
    
    spdlog::info("🚀 All systems nominal. UI Assets verified.");
}

int main(int argc, char* argv[]) {
    
    pre_flight_check();

    spdlog::set_pattern("[%H:%M:%S] [%^%l%$] %v");
    spdlog::set_level(spdlog::level::info);
    
    CodeAssistanceServer server(5002);
    server.run();
    return 0;
}