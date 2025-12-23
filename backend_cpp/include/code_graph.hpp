#pragma once

#include <string>
#include <vector>
#include <unordered_set>
#include <unordered_map>
#include <memory>
#include <nlohmann/json.hpp>

namespace code_assistance {

struct CodeNode {
    std::string id;
    std::string name;
    std::string content;
    std::string docstring;
    std::string file_path;
    std::string type;
    std::unordered_set<std::string> dependencies;
    std::vector<float> embedding;
    std::unordered_map<std::string, double> weights;
    std::string ai_summary;
    double ai_quality_score = 0.5;

    nlohmann::json to_json() const;
    static CodeNode from_json(const nlohmann::json& j);
};

class CodeParser {
public:
    // Simple regex-based parser
    static std::vector<CodeNode> extract_nodes_from_file(const std::string& file_path, const std::string& content);
};

class CodeGraph {
public:
    void add_node(std::shared_ptr<CodeNode> node);
    void calculate_static_weights();

private:
    std::vector<std::shared_ptr<CodeNode>> all_nodes_;
    std::unordered_map<std::string, std::shared_ptr<CodeNode>> name_to_node_map_;
};

} // namespace code_assistance