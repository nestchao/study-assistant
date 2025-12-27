#pragma once
#include <string>
#include <vector>
#include <map>
#include <functional>
#include <memory>
#include <nlohmann/json.hpp>
#include <spdlog/spdlog.h>
#include "LogManager.hpp"

namespace code_assistance {

struct ToolMetadata {
    std::string name;
    std::string description;
    std::string parameter_schema; 
};

class ITool {
public:
    virtual ~ITool() = default;
    virtual ToolMetadata get_metadata() = 0;
    virtual std::string execute(const std::string& args_json) = 0;
};

class GenericTool : public ITool {
    ToolMetadata meta_;
    std::function<std::string(const std::string&)> action_;
public:
    GenericTool(std::string name, std::string desc, std::string schema, 
                std::function<std::string(const std::string&)> action)
        : action_(action) {
        meta_ = {name, desc, schema};
    }
    ToolMetadata get_metadata() override { return meta_; }
    std::string execute(const std::string& args) override { return action_(args); }
};

class ToolRegistry {
private:
    std::map<std::string, std::unique_ptr<ITool>> tools_;
public:
    void register_tool(std::unique_ptr<ITool> tool) {
        spdlog::info("🛰️ Payload Integrated: {}", tool->get_metadata().name);
        tools_[tool->get_metadata().name] = std::move(tool);
    }

    // 🚀 FIX: Required by AgentExecutor for building the System Prompt
    nlohmann::json get_manifest_json() const {
        auto manifest = nlohmann::json::array();
        for (const auto& [name, tool] : tools_) {
            auto meta = tool->get_metadata();
            manifest.push_back({
                {"name", meta.name},
                {"description", meta.description},
                {"parameters", meta.parameter_schema}
            });
        }
        return manifest;
    }

    // 🚀 FIX: Required by AgentExecutor for executing actions
    std::string dispatch(const std::string& name, const nlohmann::json& args) {
        if (tools_.count(name)) {
            auto start = std::chrono::high_resolution_clock::now();
            
            // Convert JSON args to string for the tool's execution
            std::string res = tools_[name]->execute(args.dump());
            
            auto end = std::chrono::high_resolution_clock::now();
            double duration = std::chrono::duration<double, std::milli>(end - start).count();

            LogManager::instance().add_trace({"AGENT", "", "TOOL_EXEC", name, duration});
            return res;
        }
        return "ERROR: Tool '" + name + "' not found.";
    }

    // Legacy support
    std::string get_manifest() const {
        return get_manifest_json().dump(2);
    }
};
}