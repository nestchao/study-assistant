#include <httplib.h>
#include <spdlog/spdlog.h>
#include <nlohmann/json.hpp>
#include <memory>
#include <filesystem>
#include <fstream>
#include <thread>

#include "faiss_vector_store.hpp" // Use the new header
#include "retrieval_engine.hpp"
#include "embedding_service.hpp"
#include "sync_service.hpp"
#include "cache_manager.hpp"

namespace fs = std::filesystem;
using json = nlohmann::json;

class CodeAssistanceServer {
public:
    CodeAssistanceServer(int port = 5002) // <-- CHANGED PORT
        : port_(port),
          server_(),
          embedding_service_(std::make_shared<code_assistance::EmbeddingService>(
              std::getenv("GEMINI_API_KEY") ? std::getenv("GEMINI_API_KEY") : ""
          )),
          cache_manager_(std::make_shared<code_assistance::CacheManager>())
    {
        setup_routes();
    }

    void run() {
        spdlog::info("🚀 Starting C++ Code Assistance Backend on port {}", port_);
        server_.listen("127.0.0.1", port_);
    }

private:
    int port_;
    httplib::Server server_;
    
    std::shared_ptr<code_assistance::EmbeddingService> embedding_service_;
    std::shared_ptr<code_assistance::CacheManager> cache_manager_;
    
    std::unordered_map<std::string, std::shared_ptr<code_assistance::FaissVectorStore>> 
        project_stores_;
    
    void setup_routes() {
        // Enable CORS
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

        // Health check
        server_.Get("/api/hello", [](const httplib::Request&, httplib::Response& res) {
            res.set_content(R"({"message": "Hello from C++ Backend!"})", "application/json");
        });

        // Register project
        server_.Post("/sync/register/:project_id", 
            [this](const httplib::Request& req, httplib::Response& res) {
                this->handle_register_project(req, res);
            }
        );

        // Trigger sync
        server_.Post("/sync/run/:project_id",
            [this](const httplib::Request& req, httplib::Response& res) {
                this->handle_sync_project(req, res);
            }
        );

        // Generate code suggestion
        server_.Post("/generate-code-suggestion",
            [this](const httplib::Request& req, httplib::Response& res) {
                this->handle_generate_suggestion(req, res);
            }
        );

        // Get context candidates
        server_.Post("/retrieve-context-candidates",
            [this](const httplib::Request& req, httplib::Response& res) {
                this->handle_retrieve_candidates(req, res);
            }
        );

        // Force reindex
        server_.Post("/sync/reindex/:project_id",
            [this](const httplib::Request& req, httplib::Response& res) {
                this->handle_sync_project(req, res); // Re-syncing effectively re-indexes
            }
        );
    }

    void handle_register_project(const httplib::Request& req, httplib::Response& res) {
        try {
            auto project_id = req.path_params.at("project_id");
            auto body = json::parse(req.body);
            
            std::string local_path = body["local_path"];
            std::vector<std::string> extensions = body.value("extensions", std::vector<std::string>{});
            std::vector<std::string> ignored = body.value("ignored_paths", std::vector<std::string>{});
            
            spdlog::info("📝 Registering project: {}", project_id);
            
            json config = {
                {"local_path", local_path},
                {"allowed_extensions", extensions},
                {"ignored_paths", ignored},
                {"is_active", true},
                {"status", "idle"}
            };
            
            fs::path config_path = fs::path("data") / project_id / "config.json";
            fs::create_directories(config_path.parent_path());
            
            std::ofstream file(config_path);
            file << config.dump(2);
            
            res.set_content(json{
                {"success", true},
                {"project_id", project_id}
            }.dump(), "application/json");
            
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
            
            json config = load_project_config(project_id);
            
            // This can be slow, run in a detached thread to respond immediately
            std::thread([this, project_id, config]() {
                code_assistance::SyncService sync_service(embedding_service_);
                auto result = sync_service.perform_sync(
                    project_id,
                    config["local_path"],
                    config.value("allowed_extensions", std::vector<std::string>{}),
                    config.value("ignored_paths", std::vector<std::string>{})
                );
                
                auto vector_store = std::make_shared<code_assistance::FaissVectorStore>(768);
                vector_store->add_nodes(result.nodes);
                
                fs::path store_path = fs::path("vector_stores") / project_id;
                fs::create_directories(store_path);
                vector_store->save(store_path.string());
                
                project_stores_[project_id] = vector_store;
                
                spdlog::info("✅ Sync complete: {} files updated, {} nodes indexed", 
                             result.updated_count, result.nodes.size());
            }).detach();

            res.set_content(json{
                {"success", true},
                {"message", "Background sync started."}
            }.dump(), "application/json");
            
        } catch (const std::exception& e) {
            spdlog::error("❌ Sync error: {}", e.what());
            res.status = 500;
            res.set_content(json{{"error", e.what()}}.dump(), "application/json");
        }
    }

    void handle_generate_suggestion(const httplib::Request& req, httplib::Response& res) {
        try {
            auto body = json::parse(req.body);
            std::string project_id = body["project_id"];
            std::string prompt = body["prompt"];
            
            spdlog::info("🤖 Generating suggestion for: {}", prompt);
            
            auto store = load_vector_store(project_id);
            if (!store) {
                throw std::runtime_error("Project not indexed. Please sync first.");
            }
            
            std::string search_query = prompt;
            if (body.value("use_hyde", true)) {
                code_assistance::HyDEGenerator hyde(embedding_service_);
                std::string hyde_text = hyde.generate_hyde(prompt);
                search_query += "\n" + hyde_text;
            }
            
            auto query_emb = embedding_service_->generate_embedding(search_query);
            
            code_assistance::RetrievalEngine engine(store);
            auto results = engine.retrieve(prompt, query_emb, 80, true);
            std::string context = engine.build_hierarchical_context(results, 120000);
            
            std::string final_prompt = "### ROLE\nYou are a Senior Software Architect.\n\n### CONTEXT\n" + context + "\n\n### USER QUESTION\n" + prompt + "\n\n### INSTRUCTIONS\nAnswer based ONLY on the code context. Cite filenames.\n\n### ANSWER\n";
            
            std::string suggestion = embedding_service_->generate_text(final_prompt);
            
            res.set_content(json{{"suggestion", suggestion}}.dump(), "application/json");
            
        } catch (const std::exception& e) {
            spdlog::error("❌ Generation error: {}", e.what());
            res.status = 500;
            res.set_content(json{{"error", e.what()}}.dump(), "application/json");
        }
    }

    void handle_retrieve_candidates(const httplib::Request& req, httplib::Response& res) {
        try {
            auto body = json::parse(req.body);
            std::string project_id = body["project_id"];
            std::string prompt = body["prompt"];
            
            auto store = load_vector_store(project_id);
             if (!store) {
                throw std::runtime_error("Project not indexed. Please sync first.");
            }
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

    json load_project_config(const std::string& project_id) {
        fs::path config_path = fs::path("data") / project_id / "config.json";
        std::ifstream file(config_path);
        if(!file.is_open()) throw std::runtime_error("Project config not found for " + project_id);
        json config;
        file >> config;
        return config;
    }

    std::shared_ptr<code_assistance::FaissVectorStore> 
    load_vector_store(const std::string& project_id) {
        if (project_stores_.count(project_id)) {
            return project_stores_[project_id];
        }
        
        fs::path store_path = fs::path("vector_stores") / project_id;
        if (!fs::exists(store_path)) {
            return nullptr;
        }
        
        auto store = std::make_shared<code_assistance::FaissVectorStore>(768);
        store->load(store_path.string());
        project_stores_[project_id] = store;
        
        return store;
    }
};

int main(int argc, char* argv[]) {
    spdlog::set_pattern("[%H:%M:%S] [%^%l%$] %v");
    spdlog::set_level(spdlog::level::info);
    
    CodeAssistanceServer server(5002);
    server.run();
    
    return 0;
}