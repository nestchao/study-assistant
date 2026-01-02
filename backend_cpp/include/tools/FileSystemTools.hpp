#pragma once
#include <string>
#include <vector>
#include <filesystem>
#include "tools/ToolRegistry.hpp"

namespace code_assistance {

// 🛰️ Flight Manifest Structure
struct ProjectFilter {
    std::vector<std::string> allowed_extensions;
    std::vector<std::string> ignored_paths;
    std::vector<std::string> included_paths;
};

class FileSystemTools {
public:
    // 🚀 THE FIX: Static helper to load project-specific rules
    static ProjectFilter load_config(const std::string& root_path);
    
    // 🛰️ Recursive Scanner with Filtering
    static std::string list_dir_deep(
        const std::string& root_path, 
        const std::string& sub_path, 
        const ProjectFilter& filter, 
        int max_depth = 2
    );

    // 🛡️ Safe Reader
    static std::string read_file_safe(const std::string& root_path, const std::string& relative_path);
};

// 🔧 Tool Registry Wrappers
class ListDirTool : public ITool {
public:
    ToolMetadata get_metadata() override {
        return {"list_dir", "Lists files recursively with filters. Input: {'path': 'string', 'depth': number}", 
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"depth\":{\"type\":\"number\"}}}"};
    }
    std::string execute(const std::string& args_json) override;
};

class ReadFileTool : public ITool {
public:
    ToolMetadata get_metadata() override {
        return {"read_file", "Reads file content safely. Input: {'path': 'string'}", 
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}}}"};
    }
    std::string execute(const std::string& args_json) override;
};

} // namespace code_assistance