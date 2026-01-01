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
#include "parser_elite.hpp" 

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
        // Find the first '{' and the last '}'
        size_t first = raw.find('{');
        size_t last = raw.rfind('}');
        
        if (first != std::string::npos && last != std::string::npos && last > first) {
            std::string clean_json = raw.substr(first, last - first + 1);
            return nlohmann::json::parse(clean_json);
        }
    } catch (const std::exception& e) {
        spdlog::warn("⚠️ Failed to parse AI JSON: {}", e.what());
    }
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
    auto mission_start_time = std::chrono::steady_clock::now();
    
    // 1. Initial Setup
    std::string tool_manifest = tool_registry_->get_manifest();
    std::string internal_monologue = "";
    std::string last_tool_used = "";
    std::string second_to_last_tool = "";
    
    // 🚀 THE TELEMETRY BUCKET: Capture the very last generation for logging
    code_assistance::GenerationResult last_gen; 
    std::string final_output = "Mission Timed Out.";
    
    int max_steps = 10;
    
    for (int step = 0; step < max_steps; ++step) {
        // 2. PROMPT CONSTRUCTION (Decisive Landing Logic)
        std::string prompt = 
            "### ROLE: Synapse Autonomous Pilot\n"
            "### TOOLS\n" + tool_manifest + "\n\n"
            "### MISSION\n" + req.prompt() + "\n\n"
            "### PROTOCOL\n"
            "1. Format calls as JSON: {\"tool\": \"name\", \"parameters\": {...}}\n"
            "2. If the answer is in the history, use FINAL_ANSWER immediately.\n"
            "3. Efficiency = Success. Do not repeat failed steps.\n";

        if (!internal_monologue.empty()) {
            prompt += "\n### HISTORY & OBSERVATIONS\n" + internal_monologue;
        }
        prompt += "\nNEXT ACTION:";

        // 🚀 THE BRAIN: Use the Elite Generator (Token-Aware)
        last_gen = ai_service_->generate_text_elite(prompt);
        
        if (!last_gen.success) {
            this->notify(writer, "ERROR", "AI Service Unreachable");
            return "ERROR: AI Service Failure";
        }

        std::string thought = last_gen.text;
        this->notify(writer, "THOUGHT", "Step " + std::to_string(step));
        spdlog::info("🧠 Step {}: AI Thinking ({} tokens)", step, last_gen.total_tokens);

        // 3. JSON EXTRACTION & VALIDATION
        nlohmann::json action = extract_json(thought);
        
        if (action.contains("tool")) {
            std::string tool_name = action["tool"];
            
            // Loop Detection
            if (tool_name == last_tool_used && tool_name == second_to_last_tool) {
                internal_monologue += "\n[SYSTEM: Loop detected. Change strategy or use FINAL_ANSWER.]";
            }

            // 4. CHECK FOR FINAL_ANSWER
            if (tool_name == "FINAL_ANSWER") {
                final_output = action["parameters"].value("answer", "No answer provided.");
                this->notify(writer, "FINAL", final_output);
                goto mission_complete; // 🚀 Jump to logging and exit
            }

            // 5. TOOL DISPATCH
            nlohmann::json params = action.value("parameters", nlohmann::json::object());
            params["project_id"] = req.project_id();

            std::string observation = tool_registry_->dispatch(tool_name, params);
            
            // 🛰️ SENSOR: AST X-Ray (Only for successful reads)
            if (tool_name == "read_file" && !observation.starts_with("ERROR")) {
                code_assistance::elite::ASTBooster sensor;
                auto symbols = sensor.extract_symbols(params.value("path", ""), observation);
                this->notify(writer, "AST_SCAN", "Identified " + std::to_string(symbols.size()) + " symbols.");
                internal_monologue += "\n[AST DATA: " + std::to_string(symbols.size()) + " symbols detected]";
            }

            internal_monologue += "\n[STEP " + std::to_string(step) + " RESULT FROM " + tool_name + "]\n" + observation;
            
            second_to_last_tool = last_tool_used;
            last_tool_used = tool_name;
            this->notify(writer, "TOOL_EXEC", "Used " + tool_name);
            
        } else {
            // Handle non-JSON attempts
            if (thought.find("FINAL_ANSWER") != std::string::npos) {
                final_output = thought;
                goto mission_complete;
            }
            internal_monologue += "\n[SYSTEM: Error - Your last response was not valid JSON.]";
        }
    }

mission_complete:
    // 🚀 THE TELEMETRY BRIDGE: Executed ONCE per mission
    auto mission_end_time = std::chrono::steady_clock::now();
    double total_ms = std::chrono::duration<double, std::milli>(mission_end_time - mission_start_time).count();

    code_assistance::InteractionLog log;
    log.timestamp = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    log.project_id = req.project_id();
    log.user_query = req.prompt();
    log.ai_response = final_output;
    log.duration_ms = total_ms;
    log.prompt_tokens = last_gen.prompt_tokens;
    log.completion_tokens = last_gen.completion_tokens;
    log.total_tokens = last_gen.total_tokens;

    // 1. Save to local process memory
    code_assistance::LogManager::instance().add_log(log);

    // 2. Radio back to Dashboard (Port 5002)
    nlohmann::json packet = {
        {"timestamp", log.timestamp},
        {"project_id", log.project_id},
        {"user_query", log.user_query},
        {"ai_response", log.ai_response},
        {"duration_ms", log.duration_ms},
        {"prompt_tokens", log.prompt_tokens},
        {"completion_tokens", log.completion_tokens},
        {"total_tokens", log.total_tokens}
    };

    cpr::PostAsync(cpr::Url{"http://127.0.0.1:5002/api/admin/publish_log"},
                  cpr::Body{packet.dump()},
                  cpr::Header{{"Content-Type", "application/json"}});

    spdlog::info("✅ Mission Logged. Fuel consumed: {} tokens.", log.total_tokens);
    return final_output;
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