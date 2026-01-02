#include "tools/ToolRegistry.hpp"
#include "embedding_service.hpp"

namespace code_assistance {

class VisionTool : public ITool {
    std::shared_ptr<EmbeddingService> ai_;
public:
    VisionTool(std::shared_ptr<EmbeddingService> ai) : ai_(ai) {}

    ToolMetadata get_metadata() override {
        return {
            "analyze_vision",
            "Analyzes a screenshot (terminal errors, UI bugs). Input: {'prompt': 'string', 'image_data': 'base64_string'}",
            "{\"type\":\"object\",\"properties\":{\"prompt\":{\"type\":\"string\"},\"image_data\":{\"type\":\"string\"}}}"
        };
    }

    std::string execute(const std::string& args_json) override {
        auto j = nlohmann::json::parse(args_json);
        std::string prompt = j.value("prompt", "What is wrong with this image?");
        std::string base64 = j.value("image_data", "");

        if (base64.empty()) return "ERROR: No image data received.";

        // 🛰️ Call the Vision Booster
        auto res = ai_->analyze_vision(prompt, base64);
        return res.success ? res.analysis : "ERROR: Vision Engine Stall.";
    }
};
}