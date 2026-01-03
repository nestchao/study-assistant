#include "proto/agent.grpc.pb.h" 
#include "agent/AgentExecutor.hpp"

namespace code_assistance {

class AgentServiceImpl final : public AgentService::Service {
    
    std::shared_ptr<AgentExecutor> executor;

public:
    // Constructor injection
    explicit AgentServiceImpl(std::shared_ptr<AgentExecutor> exec) : executor(exec) {}

    grpc::Status ExecuteTask(
        grpc::ServerContext* context, 
        const UserQuery* request, 
        grpc::ServerWriter<AgentResponse>* writer
    ) override {
        
        AgentResponse res;
        res.set_phase("STARTUP");
        res.set_payload("Agent Service Connected.");
        writer->Write(res);

        // 🚀 FIX 2: Correct Argument Count (2 Args)
        // Pass the request object (dereferenced) and the writer pointer
        std::string final_answer = executor->run_autonomous_loop(*request, writer);

        res.set_phase("FINAL");
        res.set_payload(final_answer);
        writer->Write(res);

        return grpc::Status::OK;
    }
};

} // namespace code_assistance