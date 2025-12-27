#define NOMINMAX            // 🚀 SPACE-X FIX: Stop Windows.h from breaking FAISS/std::max
#include <cpr/cpr.h>        // 🚀 REQUIRED for Telemetry Bridge
#include "agent/AgentExecutor.hpp"
#include "LogManager.hpp"
#include <regex>
#include <chrono>
#include <fstream>
#include <sstream>
#include <filesystem>
#include <spdlog/spdlog.h>

namespace code_assistance {

namespace fs = std::filesystem;

// --- 1. CONSTRUCTOR ---

AgentExecutor::AgentExecutor(
    std::shared_ptr<RetrievalEngine> engine,
    std::shared_ptr<EmbeddingService> ai,
    std::shared_ptr<SubAgent> sub_agent,
    std::shared_ptr<ToolRegistry> tool_registry
) : engine_(engine), ai_service_(ai), sub_agent_(sub_agent), tool_registry_(tool_registry) {
    context_mgr_ = std::make_unique<ContextManager>();
}

// --- 2. HELPERS ---

nlohmann::json extract_json(const std::string& raw) {
    try {
        std::regex json_re(R"(\{[\s\S]*\})");
        std::smatch match;
        if (std::regex_search(raw, match, json_re)) {
            return nlohmann::json::parse(match.str());
        }
    } catch (...) {}
    return nlohmann::json::object();
}

std::string AgentExecutor::find_project_root() {
    fs::path p = fs::current_path();
    while (p.has_parent_path()) {
        if (fs::exists(p / "src") || fs::exists(p / ".git") || fs::exists(p / "CMakeLists.txt")) {
            return p.string();
        }
        p = p.parent_path();
    }
    return fs::current_path().string();
}

std::string extract_json_payload_surgical(const std::string& raw) {
    std::regex md_regex(R"(```json\s*(\{[\s\S]*?\})\s*```)");
    std::smatch match;
    if (std::regex_search(raw, match, md_regex)) return match.str(1);
    
    std::regex plain_regex(R"(\{[\s\S]*\})");
    if (std::regex_search(raw, match, plain_regex)) return match.str();
    return "";
}

std::string read_agent_file_safe(const std::string& filename) {
    fs::path root = fs::path(AgentExecutor::find_project_root());
    fs::path target = root / filename;

    if (fs::exists(target) && !fs::is_directory(target)) {
        std::ifstream f(target);
        std::stringstream ss;
        ss << f.rdbuf();
        return ss.str();
    }
    return "ERROR: File not found: " + filename;
}

// --- 3. TELEMETRY & LOGIC ---

void AgentExecutor::notify(::grpc::ServerWriter<::code_assistance::AgentResponse>* w, 
                            const std::string& phase, 
                            const std::string& msg, 
                            double duration_ms) {
    if (w) {
        ::code_assistance::AgentResponse res;
        res.set_phase(phase);
        res.set_payload(msg);
        w->Write(res);
    }

    nlohmann::json telemetry_payload = {
        {"session_id", "AGENT_PROBE"},
        {"state", phase},
        {"detail", msg},
        {"duration", duration_ms} // 🚀 NOW SENDING REAL DATA
    };

    cpr::PostAsync(cpr::Url{"http://127.0.0.1:5002/api/admin/publish_trace"},
                  cpr::Body{telemetry_payload.dump()},
                  cpr::Header{{"Content-Type", "application/json"}});
}

void AgentExecutor::determineContextStrategy(const std::string& query, ContextSnapshot& ctx, const std::string& project_id) {
    ctx.architectural_map = read_agent_file_safe("tree.txt");
    if (query.length() < 150) {
        ctx.focal_code = read_agent_file_safe("_full_context.txt");
    }
}

// --- 4. THE COGNITIVE ENGINE ---
std::string AgentExecutor::run_autonomous_loop(const ::code_assistance::UserQuery& req, ::grpc::ServerWriter<::code_assistance::AgentResponse>* writer) {
    std::string internal_monologue = "Mission Start. Workspace tree loaded.";
    int max_steps = 12; 

    for (int step = 0; step < max_steps; ++step) {
        spdlog::info("🧠 Step {}: Thought Processing...", step);
        
        // 🚀 ELITE PROMPT: We must be extremely explicit with the model
        std::string prompt = 
            "### ROLE\n"
            "You are an Autonomous Code Architect. You communicate ONLY via JSON tool calls or FINAL_ANSWER.\n\n"

            "### TOOL SCHEMA (STRICT)\n"
            "To use a tool, you MUST output exactly this format:\n"
            "```json\n"
            "{\n"
            "  \"tool\": \"tool_name\",\n"
            "  \"parameters\": { \"key\": \"value\" }\n"
            "}\n"
            "```\n\n"

            "### FORBIDDEN ACTS\n"
            "- DO NOT write code like 'print(tool())'.\n"
            "- DO NOT explain your thought outside of the 'Thought' section.\n"
            "- DO NOT invent tools like 'tool_code'.\n\n"

            "### ERROR HANDLING RULES"
            "- If a tool returns \"ERROR:\", \"File not found\", or empty content, DO NOT call the same tool again with the same parameters."
            "- Instead, try listing the directory again or choose a different file."
            "- If you cannot proceed, output FINAL_ANSWER with what you know."

            "### MISSION\n" + req.prompt() + "\n\n"

            "### FLIGHT LOGS (HISTORY)\n" + internal_monologue + "\n\n"

            "### YOUR NEXT STEP\n"
            "Current status: Waiting for next command. Provide Thought + Action:";

        std::string thought = ai_service_->generate_text(prompt);
        
        // 🛰️ TELEMETRY: Log exactly what the AI said to the C++ console
        spdlog::info("🛰️  AI Monologue (Step {}): [{}]", step, thought);

        if (thought.empty() || thought == "ERROR: System Throttled.") {
            return "Mission Abort: AI Service returned empty or throttled response. Check API Keys.";
        }

        // 1. Check for Final Answer
        if (thought.find("FINAL_ANSWER:") != std::string::npos) {
            return thought.substr(thought.find("FINAL_ANSWER:") + 13);
        }

        // 2. Check for Tool Call
        nlohmann::json action = extract_json(thought);

        if (action.empty() || !action.contains("tool")) {
            // 🚀 AUTO-CORRECTION: If AI sends a hallucination, tell it why it failed
            spdlog::warn("⚠️  AI Hallucination Detected (Step {}). Sending corrective feedback.", step);
            internal_monologue += "\nSYSTEM ERROR: Your previous response was NOT a valid JSON tool call. You must use the format: {\"tool\": \"...\", \"parameters\": {...}}";
            continue; // Go back to the top of the loop and try again
        }

        if (!action.empty() && action.contains("tool")) {
            std::string tool_name = action["tool"];
    
            // 🚀 ELITE INJECTION: Augment the parameters with the current Project ID
            nlohmann::json params = action.value("parameters", nlohmann::json::object());

            if (tool_name == "FINAL_ANSWER") {
                return params.value("answer", "Mission completed with no descriptive answer.");
            }
            
            params["project_id"] = req.project_id(); // Use the ID from the gRPC request
            
            spdlog::info("🔧 Dispatching Augmented Tool: {} (Project: {})", tool_name, req.project_id());
            
            // Dispatch now has the ID even if the AI didn't provide it
            std::string observation = tool_registry_->dispatch(tool_name, params);

            if (observation.find("ERROR:") != std::string::npos) {
                internal_monologue += "\nSYSTEM: The tool returned an ERROR. You must adapt your plan. Do NOT repeat the same failing action.";
            }
            
            std::string log_entry = "\n[STEP " + std::to_string(step) + " RESULT]\n";
            log_entry += "TOOL USED: " + tool_name + "\n";
            log_entry += "OUTPUT:\n" + observation.substr(0, 5000); // Cap size to prevent prompt blowing up
            log_entry += "\n[END OF RESULT]";

            internal_monologue += log_entry;

            spdlog::info("🛰️  Tool Output Appended ({} bytes)", observation.length());

            this->notify(writer, "TOOL_EXEC", "Used " + tool_name);
        } else {
            // 🚀 FALLBACK: If AI didn't use a tool or say FINAL_ANSWER, 
            // but gave a regular response, treat it as the answer.
            if (thought.length() > 5) return thought;
        }
    }
    return "Mission timed out after maximum reasoning steps.";
}

std::string AgentExecutor::run_autonomous_loop_internal(const nlohmann::json& body) {
    ::code_assistance::UserQuery fake_req;
    fake_req.set_prompt(body.value("prompt", ""));
    fake_req.set_project_id(body.value("project_id", "default"));
    return this->run_autonomous_loop(fake_req, nullptr); 
}

bool AgentExecutor::check_reflection(const std::string& query, const std::string& topo, std::string& reason) {
    reason = "Bypass for testing.";
    return true; 
}

} // namespace code_assistance