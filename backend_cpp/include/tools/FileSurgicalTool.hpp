#pragma once
#include <fstream>
#include <filesystem>
#include "tools/ToolRegistry.hpp"
#include "tools/AtomicJournal.hpp" // The safety logic we designed earlier

namespace code_assistance {

class FileSurgicalTool : public ITool {
public:
    ToolMetadata get_metadata() override {
        return {
            "apply_edit",
            "Surgically writes code to a file. Requires a full content overwrite for safety. "
            "Input: {'path': 'string', 'content': 'string'}",
            "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"}},\"required\":[\"path\",\"content\"]}"
        };
    }

    std::string execute(const std::string& args_json) override {
        try {
            auto j = nlohmann::json::parse(args_json);
            std::string raw_path = j.value("path", "");
            std::string content = j.value("content", "");

            // 1. Resolve Path Safety
            std::filesystem::path target = std::filesystem::absolute(raw_path);
            
            // 2. Atomic Backup (The Safety Hull)
            if (!AtomicJournal::backup(target.string())) {
                return "ERROR: Failed to create safety journal. Write aborted.";
            }

            // 3. Perform Write
            std::ofstream f(target, std::ios::trunc);
            if (!f.is_open()) return "ERROR: Cannot open file for surgery.";
            f << content;
            f.close();

            // 4. Verification (Simulated for Phase I)
            // In Phase II, we will run Tree-sitter here.
            AtomicJournal::commit(target.string());
            
            spdlog::info("🏗️ Surgery Successful: {}", target.string());
            return "SUCCESS: File updated. Atomic journal cleared.";

        } catch (const std::exception& e) {
            return "ERROR: Surgery failed: " + std::string(e.what());
        }
    }
};
}