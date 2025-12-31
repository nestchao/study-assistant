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
        auto j = nlohmann::json::parse(args_json);
        std::string project_root = j.value("project_id", ""); // Absolute path passed via gRPC
        std::string relative_path = j.value("path", "");
        std::string new_content = j.value("content", "");

        std::filesystem::path full_path = std::filesystem::path(project_root) / relative_path;

        // 🚀 SAFETY CHECK: Atomic Backup
        if (!AtomicJournal::backup(full_path.string())) {
            return "ERROR: Failed to secure file backup. Surgery aborted.";
        }

        std::ofstream out(full_path, std::ios::trunc);
        if (!out) return "ERROR: Access denied to " + relative_path;
        
        out << new_content;
        out.close();

        // 🚀 COMMIT: In Phase II, this is where we'd run a Syntax Check
        AtomicJournal::commit(full_path.string());
        
        return "SUCCESS: Applied edits to " + relative_path + ". Backup cleared.";
    }
};
}