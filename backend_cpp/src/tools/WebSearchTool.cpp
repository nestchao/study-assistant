#include "tools/ToolRegistry.hpp"
#include <cpr/cpr.h>
#include <nlohmann/json.hpp>
#include <spdlog/spdlog.h>
#include <string>

namespace code_assistance {

// 🚀 THE FIX: This is the specific function the Linker is missing
std::string web_search(const std::string& args_json, const std::string& api_key) {
    if (api_key.empty()) return "ERROR: Web-Oculus API key not configured.";
    
    try {
        auto j_args = nlohmann::json::parse(args_json);
        std::string query = j_args.value("query", "");

        if (query.empty()) return "ERROR: Search query is empty.";

        spdlog::info("🛰️ Web-Oculus: Searching live web for '{}'", query);

        // Using Serper.dev for high-speed orbital lookups
        // Replace with your actual API key or move to KeyManager
        auto r = cpr::Post(
            cpr::Url{"https://google.serper.dev/search"},
            cpr::Header{
                {"X-API-KEY", api_key}, // 🚀 Using injected key
                {"Content-Type", "application/json"}
            },
            cpr::Body{nlohmann::json({{"q", query}, {"num", 4}}).dump()}
        );

        if (r.status_code != 200) {
            return "ERROR: Web provider unreachable. Status: " + std::to_string(r.status_code);
        }

        auto raw_res = nlohmann::json::parse(r.text);
        std::string compiled_results = "### WEB SEARCH RESULTS FOR: " + query + "\n";

        if (raw_res.contains("organic")) {
            for (auto& item : raw_res["organic"]) {
                compiled_results += "- **" + item.value("title", "No Title") + "**\n";
                compiled_results += "  Snippet: " + item.value("snippet", "") + "\n";
                compiled_results += "  Link: " + item.value("link", "") + "\n\n";
            }
        }

        return compiled_results;

    } catch (const std::exception& e) {
        return "ERROR: Web Search Engine Stall: " + std::string(e.what());
    }
}

} // namespace code_assistance