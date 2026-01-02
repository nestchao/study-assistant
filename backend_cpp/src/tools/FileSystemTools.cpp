#include "tools/FileSystemTools.hpp"
#include <nlohmann/json.hpp>
#include <fstream>
#include <sstream>
#include <spdlog/spdlog.h>

namespace code_assistance {

namespace fs = std::filesystem;

// 🚀 THE ELITE HELPER: Segment-based path comparison (Mirroring Sync Logic)
bool is_inside_path(const fs::path& child, const fs::path& parent) {
    if (parent.empty()) return false;
    auto c = child.lexically_normal();
    auto p = parent.lexically_normal();
    auto it_c = c.begin();
    for (auto it_p = p.begin(); it_p != p.end(); ++it_p) {
        if (it_c == c.end() || *it_c != *it_p) return false;
        ++it_c;
    }
    return true;
}

ProjectFilter FileSystemTools::load_config(const std::string& root) {
    ProjectFilter filter;
    // 🚀 THE FIX: Look inside the .study_assistant folder for the config
    fs::path config_path = fs::path(root) / ".study_assistant" / "config.json";
    
    if (!fs::exists(config_path)) {
        // Fallback to root
        config_path = fs::path(root) / "config.json";
    }

    if (fs::exists(config_path)) {
        try {
            std::ifstream f(config_path);
            auto j = nlohmann::json::parse(f);
            filter.allowed_extensions = j.value("allowed_extensions", std::vector<std::string>{});
            filter.ignored_paths = j.value("ignored_paths", std::vector<std::string>{});
            filter.included_paths = j.value("included_paths", std::vector<std::string>{});
            spdlog::info("⚙️  Config Synced: {} ignores, {} exceptions.", 
                         filter.ignored_paths.size(), filter.included_paths.size());
        } catch (...) { spdlog::error("❌ Config corrupted at {}", config_path.string()); }
    }
    return filter;
}

std::string FileSystemTools::list_dir_deep(const std::string& root, const std::string& sub, const ProjectFilter& filter, int max_depth) {
    fs::path base_root = fs::absolute(root).lexically_normal();
    fs::path target_path = (base_root / sub).lexically_normal();

    // 🛡️ Geofence Guard
    if (base_root.relative_path().empty()) return "ERROR: Security - Root scan blocked.";

    std::stringstream ss;
    ss << "🛰️ SCANNING WORKSPACE: " << base_root.generic_string() << "\n";

    try {
        for (const auto& entry : fs::recursive_directory_iterator(target_path, fs::directory_options::skip_permission_denied)) {
            fs::path current = entry.path();
            fs::path rel_path = fs::relative(current, base_root);
            
            // 🚀 THE MIRROR LOGIC: Ignore vs Exception
            bool is_ignored = false;
            for (const auto& p : filter.ignored_paths) {
                if (is_inside_path(rel_path, fs::path(p))) { is_ignored = true; break; }
            }

            bool is_exception = false;
            for (const auto& p : filter.included_paths) {
                if (is_inside_path(rel_path, fs::path(p))) { is_exception = true; break; }
            }

            bool is_bridge = false;
            for (const auto& p : filter.included_paths) {
                if (is_inside_path(fs::path(p), rel_path)) { is_bridge = true; break; }
            }

            if (entry.is_directory()) {
                // Enter if not ignored OR if it's a bridge to an exception
                if (is_ignored && !is_bridge && !is_exception) continue; 
            } else {
                // Collect file if not ignored OR if it's an explicit exception
                if (is_ignored && !is_exception) continue;
                
                // Extension Filter
                std::string ext = current.extension().string();
                if (!ext.empty()) ext = ext.substr(1);
                bool ext_match = filter.allowed_extensions.empty();
                for (const auto& a : filter.allowed_extensions) if (ext == a) { ext_match = true; break; }
                
                if (!ext_match && !is_exception) continue;
            }

            // Depth calculation relative to the scan start
            auto depth_rel = fs::relative(current, target_path);
            int depth = std::distance(depth_rel.begin(), depth_rel.end());
            if (depth > max_depth) continue;

            for (int i = 0; i < depth - 1; ++i) ss << "  ";
            ss << (entry.is_directory() ? "📁 " : "📄 ") << rel_path.generic_string() << "\n";
        }
    } catch (const std::exception& e) { spdlog::error("💥 Scanner fail: {}", e.what()); }

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