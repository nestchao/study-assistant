#include "parser_elite.hpp"
#include <tree_sitter/api.h>
#include <spdlog/spdlog.h>
#include <filesystem>
#include <fstream>

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
    std::vector<CodeNode> nodes;
    std::string ext = std::filesystem::path(path).extension().string();
    const TSLanguage* lang = get_lang(ext);
    
    if (!lang) return {};

    ts_parser_set_language(parser_, lang);
    TSTree* tree = ts_parser_parse_string(parser_, nullptr, content.c_str(), (uint32_t)content.length());
    TSNode root = ts_tree_root_node(tree);

    // 🚀 PHASE 2: Symbol Extraction (Surgical Search)
    // We walk the tree here. For now, we return 1 dummy node if syntax is valid 
    // to prove the sensor pipeline is connected.
    if (!ts_node_has_error(root)) {
        CodeNode info;
        info.name = "AST_VALIDATED_ROOT";
        info.type = "file";
        info.file_path = path;
        nodes.push_back(info);
    }
    
    ts_tree_delete(tree);
    return nodes;
}

} // namespace code_assistance::elite