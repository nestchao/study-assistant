#include "parser_elite.hpp"
#include <tree_sitter/api.h>
#include <spdlog/spdlog.h>
#include <filesystem>
#include <fstream>
#include <stack>

// 🚀 LINK THE EMBEDDED GRAMMARS (Must be global scope)
extern "C" {
    const TSLanguage* tree_sitter_cpp();
    const TSLanguage* tree_sitter_python();
    const TSLanguage* tree_sitter_typescript();
}

namespace code_assistance::elite {

ASTBooster::ASTBooster() {
    parser_ = ts_parser_new();
}

ASTBooster::~ASTBooster() {
    if (parser_) ts_parser_delete(parser_);
}

const TSLanguage* ASTBooster::get_lang(const std::string& ext) {
    if (ext == ".cpp" || ext == ".hpp" || ext == ".h") return tree_sitter_cpp();
    if (ext == ".py") return tree_sitter_python();
    if (ext == ".ts" || ext == ".js") return tree_sitter_typescript();
    return nullptr;
}

bool ASTBooster::validate_syntax(const std::string& content, const std::string& extension) {
    const TSLanguage* lang = get_lang(extension);
    if (!lang) return true;

    ts_parser_set_language(parser_, lang);
    TSTree* tree = ts_parser_parse_string(parser_, nullptr, content.c_str(), (uint32_t)content.length());
    
    TSNode root = ts_tree_root_node(tree);
    bool has_error = ts_node_has_error(root);
    
    ts_tree_delete(tree);
    return !has_error;
}

std::vector<CodeNode> ASTBooster::extract_symbols(const std::string& path, const std::string& content) {
    std::vector<CodeNode> found_nodes;
    std::string ext = std::filesystem::path(path).extension().string();
    const TSLanguage* lang = get_lang(ext);
    
    if (!lang) return {};

    ts_parser_set_language(parser_, lang);
    TSTree* tree = ts_parser_parse_string(parser_, nullptr, content.c_str(), (uint32_t)content.length());
    TSNode root = ts_tree_root_node(tree);

    // 🚀 THE ELITE FIX: Non-recursive stack-based tree traversal (Memory Efficient)
    std::stack<TSNode> stack;
    stack.push(root);

    while (!stack.empty()) {
        TSNode node = stack.top();
        stack.pop();

        std::string type = ts_node_type(node);

        // 🎯 TARGETING THE SKELETON: Logic-bearing nodes
        if (type == "function_definition" || type == "class_specifier" || 
            type == "method_definition" || type == "function_item") {
            
            CodeNode symbol;
            symbol.file_path = path;
            symbol.type = type;
            
            // Extract Symbol Name (Surgical Extraction)
            // Usually the 'identifier' node is a child of these types
            uint32_t children = ts_node_child_count(node);
            for (uint32_t i = 0; i < children; i++) {
                TSNode child = ts_node_child(node, i);
                if (std::string(ts_node_type(child)) == "identifier" || 
                    std::string(ts_node_type(child)) == "type_identifier") {
                    
                    uint32_t start = ts_node_start_byte(child);
                    uint32_t end = ts_node_end_byte(child);
                    symbol.name = content.substr(start, end - start);
                    break;
                }
            }
            
            if (!symbol.name.empty()) {
                found_nodes.push_back(symbol);
            }
        }

        // Add children to stack for continued exploration
        uint32_t count = ts_node_child_count(node);
        for (uint32_t i = 0; i < count; i++) {
            stack.push(ts_node_child(node, i));
        }
    }
    
    ts_tree_delete(tree);
    spdlog::info("🛰️  AST X-Ray Complete: Found {} logical symbols in {}", found_nodes.size(), path);
    return found_nodes;
}

} // namespace code_assistance::elite