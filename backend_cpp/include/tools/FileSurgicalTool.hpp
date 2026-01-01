// backend_cpp/include/tools/FileSurgicalTool.hpp
#pragma once
#include "tools/ToolRegistry.hpp"
#include "tools/AtomicJournal.hpp"
#include <fstream>

namespace code_assistance {

class FileSurgicalTool : public ITool {
public:
    ToolMetadata get_metadata() override {
        return {
            "apply_edit",
            "Overwrites a file with new content. Use ONLY after verifying logic via read_file.",
            "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"}},\"required\":[\"path\",\"content\"]}"
        };
    }

    std::string execute(const std::string& args_json) override {
        try {
            // 1. Parse Payload
            auto j = nlohmann::json::parse(args_json);
            std::string project_root = j.value("project_id", ""); 
            std::string relative_path = j.value("path", "");
            std::string new_content = j.value("content", "");

            // 2. Resolve Flight Path
            if (project_root.empty() || relative_path.empty()) {
                return "ERROR: Mission abort - Invalid project root or file path provided.";
            }

            std::filesystem::path full_path = std::filesystem::path(project_root) / relative_path;

            // 🚀 THE UPGRADE: Execute Atomic Surgery
            // This single call handles: Backup -> Write -> Validation -> (Commit OR Rollback)
            bool success = AtomicJournal::apply_surgery_safe(full_path.string(), new_content);

            if (success) {
                spdlog::info("🏗️ Surgery Successful: {}", full_path.string());
                return "SUCCESS: Applied edits to " + relative_path + ". Atomic journal cleared and integrity verified.";
            } else {
                spdlog::error("💥 Surgery Failed: {}", full_path.string());
                return "ERROR: Surgery failed for " + relative_path + ". Rollback performed to preserve codebase integrity.";
            }

        } catch (const std::exception& e) {
            return "ERROR: Surgical Tool Engine Stall: " + std::string(e.what());
        }
    }
};
}