#include "code_graph.hpp"
#include <regex>
#include <numeric>
#include <filesystem> 

namespace code_assistance {

namespace fs = std::filesystem; 

using json = nlohmann::json;

std::string sanitize_utf8(const std::string& str) {
    std::string safe_str;
    for (unsigned char c : str) {
        if (c < 128) {
            safe_str += c;
        } else {
            // Simple replacement for non-ASCII/invalid chars to prevent JSON crash
            // You can implement full UTF-8 validation here if needed
            safe_str += "?"; 
        }
    }
    return safe_str;
}

json CodeNode::to_json() const {
    return json{
        {"id", sanitize_utf8(id)},
        {"name", sanitize_utf8(name)},
        {"content", sanitize_utf8(content)}, // <--- CRITICAL FIX
        {"docstring", sanitize_utf8(docstring)},
        {"file_path", sanitize_utf8(file_path)},
        {"type", type},
        {"dependencies", dependencies},
        {"embedding", embedding},
        {"weights", weights},
        {"ai_summary", sanitize_utf8(ai_summary)},
        {"ai_quality_score", ai_quality_score}
    };
}

CodeNode CodeNode::from_json(const json& j) {
    CodeNode node;
    node.id = j.at("id");
    node.name = j.at("name");
    node.content = j.at("content");
    node.docstring = j.at("docstring");
    node.file_path = j.at("file_path");
    node.type = j.at("type");
    node.dependencies = j.value("dependencies", std::unordered_set<std::string>{});
    node.embedding = j.value("embedding", std::vector<float>{});
    node.weights = j.value("weights", std::unordered_map<std::string, double>{});
    node.ai_summary = j.value("ai_summary", "");
    node.ai_quality_score = j.value("ai_quality_score", 0.5);
    return node;
}


std::vector<CodeNode> CodeParser::extract_nodes_from_file(const std::string& file_path, const std::string& content) {
    std::vector<CodeNode> nodes;
    
    // Regex for functions (def, function) and classes
    std::regex def_regex(R"((?:def|class|function)\s+([a-zA-Z0-9_]+))");
    auto words_begin = std::sregex_iterator(content.begin(), content.end(), def_regex);
    auto words_end = std::sregex_iterator();

    for (std::sregex_iterator i = words_begin; i != words_end; ++i) {
        std::smatch match = *i;
        std::string name = match[1].str();
        
        CodeNode node;
        node.name = name;
        node.file_path = file_path;
        node.id = file_path + "::" + name;
        node.content = "// Definition for " + name + " in " + file_path;
        node.type = "unknown"; // Simplified
        node.weights = {{"structural", 0.5}, {"complexity", 0.5}};
        nodes.push_back(node);
    }

    // Always add the whole file as a node
    fs::path p(file_path);
    CodeNode file_node;
    file_node.name = p.filename().string();
    file_node.file_path = file_path;
    file_node.id = file_path;
    file_node.content = content;
    file_node.type = "file";
    file_node.weights = {{"structural", 0.5}, {"complexity", std::min(1.0, content.length() / 1000.0)}};
    nodes.push_back(file_node);

    return nodes;
}

void CodeGraph::add_node(std::shared_ptr<CodeNode> node) {
    all_nodes_.push_back(node);
    name_to_node_map_[node->name] = node;
}

void CodeGraph::calculate_static_weights() {
    std::unordered_map<std::string, int> incoming_calls;
    for (const auto& node : all_nodes_) {
        for (const auto& dep : node->dependencies) {
            incoming_calls[dep]++;
        }
    }

    int max_calls = 1;
    for (const auto& pair : incoming_calls) {
        if (pair.second > max_calls) {
            max_calls = pair.second;
        }
    }

    for (auto& node : all_nodes_) {
        int calls = incoming_calls.count(node->name) ? incoming_calls[node->name] : 0;
        node->weights["structural"] = 0.3 + (0.7 * (static_cast<double>(calls) / max_calls));
    }
}

} // namespace code_assistance