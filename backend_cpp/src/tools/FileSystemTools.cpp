#include "tools/FileSystemTools.hpp" // 🚀 THE CRITICAL MISSING LINK
#include <nlohmann/json.hpp>
#include <fstream>
#include <sstream>
#include <spdlog/spdlog.h>

namespace code_assistance {

namespace fs = std::filesystem;

ProjectFilter FileSystemTools::load_config(const std::string& root) {
    ProjectFilter filter;
    fs::path config_path = fs::path(root) / "config.json";
    
    if (fs::exists(config_path)) {
        try {
            std::ifstream f(config_path);
            auto j = nlohmann::json::parse(f);
            if (j.contains("allowed_extensions")) filter.allowed_extensions = j["allowed_extensions"].get<std::vector<std::string>>();
            if (j.contains("ignored_paths")) filter.ignored_paths = j["ignored_paths"].get<std::vector<std::string>>();
            if (j.contains("included_paths")) filter.included_paths = j["included_paths"].get<std::vector<std::string>>();
            
            // 🚀 LOG: Config Content
            spdlog::info("⚙️  Config Loaded: [Ext: {}] [Ignore: {}] [Incl: {}]", 
                filter.allowed_extensions.size(), filter.ignored_paths.size(), filter.included_paths.size());
        } catch (const std::exception& e) {
            spdlog::error("❌ Config Read Failed: {}", e.what());
        }
    } else {
        spdlog::warn("⚠️  No config.json found at {}. Using empty filter.", root);
    }
    return filter;
}

std::string FileSystemTools::list_dir_deep(const std::string& root, const std::string& sub, const ProjectFilter& filter, int max_depth) {
    fs::path base_root = fs::absolute(root).lexically_normal();
    fs::path target_path = (base_root / sub).lexically_normal();

    spdlog::info("🛰️  SCAN START | Target: {}", target_path.string());

    if (!fs::exists(target_path)) {
        spdlog::error("❌ TARGET MISSING: {}", target_path.string());
        return "ERROR: Path not found.";
    }

    std::stringstream ss;
    int found_count = 0;
    int skip_count = 0;

    try {
        auto iter_options = fs::directory_options::skip_permission_denied;
        for (const auto& entry : fs::recursive_directory_iterator(target_path, iter_options)) {
            fs::path current = entry.path();
            std::error_code ec;
            auto rel_to_root = fs::relative(current, base_root, ec);
            if (ec) continue;

            std::string rel_str = rel_to_root.generic_string();
            
            // 🚀 LOG: Every item the OS reveals
            spdlog::debug("🔍 Checking: {}", rel_str);

            // 1. Ignore Check
            bool ignored = false;
            for (const auto& i : filter.ignored_paths) {
                if (!i.empty() && rel_str.find(i) == 0) { ignored = true; break; }
            }

            // 2. Exception Check
            bool exception = false;
            for (const auto& i : filter.included_paths) {
                if (!i.empty() && rel_str.find(i) == 0) { exception = true; break; }
            }

            if (ignored && !exception) {
                spdlog::info("🚫 Ignored: {}", rel_str);
                skip_count++;
                continue;
            }

            // 3. Extension Check
            if (entry.is_regular_file()) {
                std::string ext = current.extension().string();
                if (!ext.empty()) ext = ext.substr(1);
                
                bool match = filter.allowed_extensions.empty();
                for (const auto& a : filter.allowed_extensions) {
                    if (ext == a) { match = true; break; }
                }

                if (!match && !exception) {
                    spdlog::info("✂️  Ext Mismatch: {} (ext: {})", rel_str, ext);
                    skip_count++;
                    continue;
                }
            }

            // 4. Success - Add to result
            found_count++;
            ss << (entry.is_directory() ? "📁 " : "📄 ") << rel_str << "\n";
        }
    } catch (const std::exception& e) {
        spdlog::error("💥 Scanner Crash: {}", e.what());
    }

    spdlog::info("🏁 SCAN COMPLETE | Found: {} | Filtered: {}", found_count, skip_count);
    return ss.str();
}

std::string FileSystemTools::read_file_safe(const std::string& root, const std::string& rel) {
    fs::path target = (fs::path(root) / rel).lexically_normal();
    spdlog::info("🔍 [I/O Probe] Attempting to read: {}", target.string());

    if (!fs::exists(target)) {
        spdlog::error("❌ [I/O Probe] Path not found: {}", target.string());
        return "ERROR: File not found at " + rel;
    }
    
    if (fs::file_size(target) > 1024 * 512) return "ERROR: File too large for direct read (>512KB).";

    std::ifstream f(target, std::ios::in | std::ios::binary);
    std::stringstream buffer;
    buffer << f.rdbuf();
    return buffer.str();
}

// 🔧 Tool Wrapper Implementations
std::string ListDirTool::execute(const std::string& args_json) {
    try {
        auto j = nlohmann::json::parse(args_json);
        std::string root = j.value("project_id", "");
        auto filter = FileSystemTools::load_config(root);
        return FileSystemTools::list_dir_deep(root, j.value("path", "."), filter, j.value("depth", 2));
    } catch (...) { return "ERROR: Invalid JSON parameters."; }
}

std::string ReadFileTool::execute(const std::string& args_json) {
    try {
        auto j = nlohmann::json::parse(args_json);
        return FileSystemTools::read_file_safe(j.value("project_id", ""), j.value("path", ""));
    } catch (...) { return "ERROR: Invalid JSON parameters."; }
}

} // namespace code_assistance