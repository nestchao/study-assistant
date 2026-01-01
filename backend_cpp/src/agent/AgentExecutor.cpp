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
    // 1. DYNAMIC TOOL DISCOVERY
    std::string tool_manifest = tool_registry_->get_manifest();
    spdlog::info("🛰️ Flight Manual size: {} bytes", tool_manifest.length());
    
    if (tool_manifest.length() < 200) {
        spdlog::error("🚨 CRITICAL: Tool Manifest is suspiciously small. AI will be blind!");
    }

    std::string internal_monologue = "";
    
    // 🚀 NEW: Track last tools to detect loops
    std::string last_tool_used = "";
    std::string second_to_last_tool = "";
    
    int max_steps = 10;
    
    for (int step = 0; step < max_steps; ++step) {
        // 2. THE FLIGHT MANUAL (Prompt) - 🚀 UPDATED WITH STRONGER TERMINATION EMPHASIS
        std::string prompt = 
            "### CRITICAL: YOU MUST USE FINAL_ANSWER WHEN DONE\n"
            "After EVERY tool observation, ask yourself: 'Do I now have enough information to answer?'\n"
            "If YES: Immediately call {\"tool\": \"FINAL_ANSWER\", \"parameters\": {\"answer\": \"your complete answer here\"}}\n"
            "DO NOT keep searching if you already have the answer!\n\n"
            
            "### YOUR TOOLS (The Flight Manual)\n"
            "You MUST call tools using this JSON format:\n"
            "```json\n"
            "{\"tool\": \"tool_name\", \"parameters\": {...}}\n"
            "```\n\n"
            "Available tools:\n" + tool_manifest + "\n\n"
            
            "### MISSION\n" + req.prompt() + "\n\n"
            
            "### CRITICAL PROTOCOL\n"
            "1. Efficiency is your primary metric.\n"
            "2. If an OBSERVATION provides the answer, you MUST use FINAL_ANSWER immediately.\n"
            "3. DO NOT repeat the same search query more than once.\n"
            "4. If a file is not found, use 'list_dir' to verify the path before giving up.\n\n"
            
            "### RULES\n"
            "1. If you need info, call a tool.\n"
            "2. If you have the answer, use FINAL_ANSWER.\n\n";
        
        // 🚀 NEW: Append conversation history with observations
        if (!internal_monologue.empty()) {
            prompt += "### PREVIOUS OBSERVATIONS:\n" + internal_monologue + "\n\n";
        }
        
        prompt += "NEXT ACTION (respond with JSON tool call):";

        std::string thought = ai_service_->generate_text(prompt);
        this->notify(writer, "THOUGHT", "Step " + std::to_string(step));
        spdlog::info("🧠 Step {}: AI generated a thought.", step);

        // 3. HARDENED JSON EXTRACTION
        nlohmann::json action = extract_json(thought);
        
        if (action.contains("tool")) {
            std::string tool_name = action["tool"];
            
            // 🚀 NEW: Loop detection logic
            if (tool_name == last_tool_used && tool_name == second_to_last_tool) {
                spdlog::warn("⚠️ LOOP DETECTED: Tool '{}' used 3 times in a row!", tool_name);
                internal_monologue += "\n\n[SYSTEM OVERRIDE: You've used the tool '" + tool_name + 
                                     "' three times consecutively. This suggests you're stuck in a loop. "
                                     "Either synthesize your findings with FINAL_ANSWER NOW, or try a different tool.]\n";
            }
            
            // 4. PREVENT TYPE_ERROR.302 (The "302" fix)
            nlohmann::json params = nlohmann::json::object();
            if (action.contains("parameters") && action["parameters"].is_object()) {
                params = action["parameters"];
            }
            params["project_id"] = req.project_id();

            // 5. CHECK FOR FINAL_ANSWER BEFORE DISPATCH
            if (tool_name == "FINAL_ANSWER") {
                std::string final_answer = params.value("answer", "No answer provided.");
                this->notify(writer, "FINAL", final_answer);
                spdlog::info("✅ Mission completed successfully at step {}", step);
                return final_answer;
            }

            // 6. HALLUCINATION CATCHER & TOOL EXECUTION
            std::string observation = tool_registry_->dispatch(tool_name, params);
            
            if (tool_name == "read_file" && !observation.starts_with("ERROR")) {
                try {
                    // Use full qualification: code_assistance::elite
                    code_assistance::elite::ASTBooster sensor; 
                    
                    std::string relative_path = params.value("path", "unknown");
                    
                    // 🛰️ Trigger structural analysis
                    // Note: CodeNode is in namespace code_assistance
                    std::vector<code_assistance::CodeNode> symbols = sensor.extract_symbols(relative_path, observation);
                    
                    this->notify(writer, "AST_SCAN", 
                        "X-Ray: Identified " + std::to_string(symbols.size()) + 
                        " symbols in [" + relative_path + "]");
                        
                    internal_monologue += "\n[SYSTEM: AST Scanner detected " + std::to_string(symbols.size()) + " symbols.]";
                    
                } catch (const std::exception& e) {
                    spdlog::warn("⚠️ AST Scanner bypassed: {}", e.what());
                }
            }
            // --- 🚀 END OF X-RAY INJECTION ---

            // 2. Format and append observation to monologue as usual
            std::string formatted_observation = "\n[CRITICAL DATA RECEIVED FROM " + tool_name + "]\n" + observation;
            
            internal_monologue += formatted_observation;

            // 🚀 UPDATE: Track tool usage for loop detection
            second_to_last_tool = last_tool_used;
            last_tool_used = tool_name;

            // 🚀 AUTO-LANDING: Remind AI to finish if it has enough data
            if (step >= 2) {
                internal_monologue += "\n(SYSTEM HINT: You have collected " + std::to_string(step + 1) + 
                                     " observations. If you can answer the mission goal, use FINAL_ANSWER now to complete efficiently.)\n";
            }

            this->notify(writer, "TOOL_EXEC", "Used " + tool_name);
            
        } else {
            // If AI didn't use a tool, check if it's trying to answer directly
            if (thought.find("FINAL_ANSWER") != std::string::npos || 
                thought.find("final answer") != std::string::npos) {
                spdlog::warn("⚠️ AI attempted direct answer without proper JSON format");
                this->notify(writer, "FINAL", thought);
                return thought;
            }
            
            internal_monologue += "\n[SYSTEM ERROR: You did not use a valid tool call. "
                                 "Please respond with ONLY a JSON object in this format: "
                                 "{\"tool\": \"tool_name\", \"parameters\": {...}}]\n";
            
            spdlog::warn("⚠️ Step {}: Invalid tool call format", step);
        }
    }

    // Mission timeout
    std::string timeout_msg = "Mission timed out after " + std::to_string(max_steps) + " steps without reaching FINAL_ANSWER.";
    this->notify(writer, "FINAL", timeout_msg);
    spdlog::error("❌ {}", timeout_msg);
    return timeout_msg;
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