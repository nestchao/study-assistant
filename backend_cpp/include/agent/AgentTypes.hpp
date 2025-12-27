#pragma once
#include <string>
#include <vector>
#include "retrieval_engine.hpp"

namespace code_assistance {

struct ContextSnapshot {
    std::vector<RetrievalResult> raw_nodes;
    std::string architectural_map;
    std::string search_results;
    std::string history;
    std::vector<std::string> experiences;
    std::string focal_code; // 🚀 ADDED
};

}