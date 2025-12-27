#include <grpcpp/grpcpp.h>
#include <spdlog/spdlog.h>
#include <fstream>
#include <filesystem>

#include "agent.pb.h"
#include "agent.grpc.pb.h"
#include "agent/AgentExecutor.hpp"
#include "tools/ToolRegistry.hpp"
#include "KeyManager.hpp"
#include "embedding_service.hpp"

// Forward declare the web_search function
namespace code_assistance { std::string web_search(const std::string& args_json); }

namespace fs = std::filesystem;
using grpc::Server;
using grpc::ServerBuilder;

class AgentServiceImpl final : public ::code_assistance::AgentService::Service {
    std::shared_ptr<::code_assistance::AgentExecutor> executor;
public:
    AgentServiceImpl(std::shared_ptr<::code_assistance::AgentExecutor> exec) : executor(exec) {}

    grpc::Status ExecuteTask(grpc::ServerContext* context, 
                            const ::code_assistance::UserQuery* request, 
                            grpc::ServerWriter<::code_assistance::AgentResponse>* writer) override {
        executor->run_autonomous_loop(*request, writer);
        return grpc::Status::OK;
    }
};

// Helper to resolve any path the AI gives us
fs::path resolve_safe_path(const std::string& input_path) {
    // 🚀 FIXED: Call via the class name
    std::string root_str = code_assistance::AgentExecutor::find_project_root();
    fs::path root(root_str);
    fs::path requested(input_path);
    
    fs::path combined = root / requested;
    if (fs::exists(combined)) return combined;
    return requested; 
}

int main() {
    spdlog::set_pattern("[%H:%M:%S] [%^%l%$] %v");
    std::string server_address("127.0.0.1:50051");

    // 1. Initialize Core Services
    auto keys = std::make_shared<code_assistance::KeyManager>();
    auto ai = std::make_shared<code_assistance::EmbeddingService>(keys);
    auto sub = std::make_shared<code_assistance::SubAgent>();
    auto tools = std::make_shared<code_assistance::ToolRegistry>();

    // 2. 🚀 WIRE THE TOOLS (The Missing Step)
    
    // TOOL A: list_dir
    tools->register_tool(std::make_unique<code_assistance::GenericTool>(
        "list_dir",
        "List files. Paths are relative to PROJECT_ROOT.",
        "{\"path\": \"string\"}",
        [](const std::string& args_json) -> std::string {
            auto j = nlohmann::json::parse(args_json);
            fs::path p = resolve_safe_path(j.value("path", ""));
            std::string res = "Contents of " + p.generic_string() + ":\n";
            try {
                for (auto& entry : fs::directory_iterator(p)) {
                    res += (entry.is_directory() ? "[DIR] " : "[FILE] ") + entry.path().filename().string() + "\n";
                }
                return res;
            } catch (...) { return "ERROR: Path not found: " + p.string(); }
        }
    ));

    // TOOL B: read_file
    tools->register_tool(std::make_unique<code_assistance::GenericTool>(
        "read_file",
        "Read the full text of a file from the workspace tree.",
        "{\"path\": \"string\"}",
        [](const std::string& args_json) -> std::string {
            try {
                auto j = nlohmann::json::parse(args_json);
                std::string path = j.value("path", "");
                std::ifstream f(path);
                if (!f.is_open()) return "ERROR: File not found: " + path;
                return std::string((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
            } catch (...) { return "ERROR: Invalid JSON arguments."; }
        }
    ));

    // TOOL C: web_search
    tools->register_tool(std::make_unique<code_assistance::GenericTool>(
        "web_search",
        "Search Google for documentation and high-concurrency patterns.",
        "{\"query\": \"string\"}",
        [](const std::string& args) { return code_assistance::web_search(args); }
    ));

    // 3. Initialize Executor
    auto executor = std::make_shared<code_assistance::AgentExecutor>(
        nullptr, ai, sub, tools
    );
    AgentServiceImpl service(executor);

    // 4. Start gRPC Server
    ServerBuilder builder;
    builder.AddListeningPort(server_address, grpc::InsecureServerCredentials());
    builder.RegisterService(&service);
    std::unique_ptr<Server> server(builder.BuildAndStart());
    
    spdlog::info("🚀 Agent gRPC Service ignited on {}", server_address);
    server->Wait();
    return 0;
}