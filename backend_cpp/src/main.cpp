#include <httplib.h>
#include <spdlog/spdlog.h>
#include <nlohmann/json.hpp>
#include <memory>
#include <filesystem>
#include <fstream>
#include <thread>
#include <cstdlib> 

#include "faiss_vector_store.hpp"
#include "retrieval_engine.hpp"
#include "embedding_service.hpp"
#include "sync_service.hpp"
#include "cache_manager.hpp"
#include "SystemMonitor.hpp"
#include "LogManager.hpp"
#include "ThreadPool.hpp"
#include "KeyManager.hpp" 

namespace fs = std::filesystem;
using json = nlohmann::json;

class CodeAssistanceServer {
public:
    CodeAssistanceServer(int port = 5002)
        : port_(port),
          server_(),
          cache_manager_(std::make_shared<code_assistance::CacheManager>()),
          thread_pool_(4) 
    {
        auto key_manager = std::make_shared<KeyManager>();
        embedding_service_ = std::make_shared<code_assistance::EmbeddingService>(key_manager);
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

    std::shared_ptr<code_assistance::EmbeddingService> embedding_service_;
    std::shared_ptr<code_assistance::CacheManager> cache_manager_;
    std::unordered_map<std::string, std::shared_ptr<code_assistance::FaissVectorStore>> project_stores_;
    
    code_assistance::SystemMonitor system_monitor_;
    
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
                {"logs", logs}
            };
            res.set_content(response.dump(), "application/json");
        });

        server_.Get("/admin", [](const httplib::Request&, httplib::Response& res) {
            std::ifstream f("dashboard.html");
            if (f) {
                std::stringstream buffer;
                buffer << f.rdbuf();
                res.set_content(buffer.str(), "text/html");
            } else {
                res.set_content("<h1>Dashboard file not found.</h1>", "text/html");
            }
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
        auto start_time = std::chrono::high_resolution_clock::now();
        std::string project_id;
        std::string user_prompt;
        std::string final_ai_prompt; // Unified name
        std::string ai_response;

        try {
            auto body = json::parse(req.body);
            project_id = body["project_id"];
            user_prompt = body["prompt"];
            
            auto store = load_vector_store(project_id);
            if (!store) throw std::runtime_error("Project not indexed.");
            
            // 1. Retrieval
            auto query_emb = embedding_service_->generate_embedding(user_prompt);
            code_assistance::RetrievalEngine engine(store);
            auto results = engine.retrieve(user_prompt, query_emb, 80, true);
            std::string rag_context = engine.build_hierarchical_context(results, 32000);

            // 2. Metadata Cleaning
            std::string raw_active_path = body.value("active_file_path", "Unknown");
            std::string active_content = body.value("active_file_content", "");
            std::string clean_path = clean_internal_path(raw_active_path);

            // 3. Prompt Construction
            final_ai_prompt = 
                "### ROLE\n"
                "You are a Senior Software Architect with project-wide write access.\n"
                "Your primary focus is: " + clean_path + ".\n\n"
                "### INSTRUCTIONS (STRICT PROTOCOL)\n"
                "1. If you are suggesting code changes, you MUST use triple backticks: ```language ... ```\n"
                "2. At the VERY FIRST LINE inside the code block, you MUST specify the target file using this tag:\n"
                "   // [TARGET: path/to/file.ext]\n"
                "3. DO NOT include explanations OR natural language INSIDE the code block. Use comments instead.\n"
                "4. DO NOT ramble. If the user asks to write to a file, just provide the code block for that file.\n\n"
                "### CONTEXT\n" + rag_context + "\n\n"
                "### USER QUESTION\n" + user_prompt + "\n\n"
                "### ANSWER (Code First)\n";

            // 4. Dispatch to Gemini
            spdlog::info("🚀 Calling Gemini API for: {}", clean_path);
            ai_response = embedding_service_->generate_text(final_ai_prompt);
            
            // 5. Transmit to Extension
            res.set_content(json{{"suggestion", ai_response}}.dump(), "application/json");

        } catch (const std::exception& e) {
            spdlog::error("❌ Generation error: {}", e.what());
            res.status = 500;
            res.set_content(json{{"error", e.what()}}.dump(), "application/json");
        }

        // Telemetry
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::high_resolution_clock::now() - start_time).count();
        
        code_assistance::LogManager::instance().add_log({
            std::time(nullptr), project_id, user_prompt, user_prompt, 
            final_ai_prompt, ai_response, 0, (double)duration
        });
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

int main(int argc, char* argv[]) {
    spdlog::set_pattern("[%H:%M:%S] [%^%l%$] %v");
    spdlog::set_level(spdlog::level::info);
    
    CodeAssistanceServer server(5002);
    server.run();
    return 0;
}