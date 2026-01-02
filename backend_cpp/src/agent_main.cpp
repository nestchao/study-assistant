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
#include "tools/FileSystemTools.hpp"

// Forward declare the web_search function
namespace code_assistance { 
    std::string web_search(const std::string& args_json, const std::string& api_key); 
}

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
        
        // 1. Initial Heartbeat
        ::code_assistance::AgentResponse init_res;
        init_res.set_phase("STARTUP");
        init_res.set_payload("Engine ignition sequence started...");
        writer->Write(init_res);

        spdlog::info("🛰️ Mission Received: {}", request->prompt());

        try {
            // 2. RUN THE LOOP & CAPTURE THE RESULT
            std::string final_answer = executor->run_autonomous_loop(*request, writer);

            // 3. SEND THE FINAL PAYLOAD (The missing step!)
            ::code_assistance::AgentResponse final_res;
            final_res.set_phase("final");
            final_res.set_payload(final_answer);
            writer->Write(final_res);

            spdlog::info("✅ Mission Successful. Final payload transmitted.");
            
        } catch (const std::exception& e) {
            spdlog::error("💥 Internal Engine Crash: {}", e.what());
            ::code_assistance::AgentResponse err_res;
            err_res.set_phase("ERROR");
            err_res.set_payload(e.what());
            writer->Write(err_res);
        }

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
    
    tools->register_tool(std::make_unique<code_assistance::ListDirTool>());
    tools->register_tool(std::make_unique<code_assistance::ReadFileTool>());

    // TOOL C: web_search
    // tools->register_tool(std::make_unique<code_assistance::GenericTool>(
    //     "web_search",
    //     "Search Google for documentation and high-concurrency patterns.",
    //     "{\"query\": \"string\"}",
    //     [keys](const std::string& args) { 
    //         // 🚀 THE FIX: Provide BOTH arguments (args and the key)
    //         return code_assistance::web_search(args, keys->get_serper_key()); 
    //     }
    // ));

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