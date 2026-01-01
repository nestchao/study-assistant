#include <tree_sitter/api.h>

// 🚀 ONLY wrap the scanner. The parser stays in its own C unit.
extern "C" {
    #include "../third_party/tree-sitter-cpp/src/scanner.c"
}