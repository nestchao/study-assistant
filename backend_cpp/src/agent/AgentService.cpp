#include "proto/agent.grpc.pb.h" // Include the GENERATED header
#include "agent/AgentExecutor.hpp"

namespace code_assistance {

// Inherit from the GENERATED service class
class AgentServiceImpl final : public AgentService::Service {
    
    std::unique_ptr<AgentExecutor> executor;

    // Implementation of the "ExecuteTask" defined in the .proto
    grpc::Status ExecuteTask(
        grpc::ServerContext* context, 
        const UserQuery* request, 
        grpc::ServerWriter<AgentResponse>* writer
    ) override {
        
        // 1. Initial Telemetry
        AgentResponse res;
        res.set_phase("retrieving");
        writer->Write(res);

        // 2. High-Performance Logic (The Engine)
        // This calls the state-machine we discussed earlier
        std::string final_answer = executor->run_autonomous_loop(request->prompt(), request->session_id(), writer);

        // 3. Final Payload
        res.set_phase("final");
        res.set_payload(final_answer);
        writer->Write(res);

        return grpc::Status::OK;
    }
};

}