#include <string>
#include <cpr/cpr.h>
#include <nlohmann/json.hpp>
#include <spdlog/spdlog.h>

namespace code_assistance {

// 🚀 FIXED: Standard function definition instead of a lambda variable
std::string web_search(const std::string& args_json) {
    try {
        auto j_args = nlohmann::json::parse(args_json);
        std::string query = j_args.value("query", "");

        spdlog::info("🌐 WebSearchTool: Searching for '{}'", query);

        auto r = cpr::Get(cpr::Url{"https://google.serper.dev/search"},
                 cpr::Header{{"X-API-KEY", "YOUR_API_KEY"}}, // Replace with your key
                 cpr::Parameters{{"q", query}});

        return r.text;
    } catch (const std::exception& e) {
        return "ERROR: WebSearch failed: " + std::string(e.what());
    }
}

} // namespace code_assistance