#pragma once
#include <string>
#include <vector>
#include "code_graph.hpp"
#include "retrieval_engine.hpp"

namespace code_assistance {

class SubAgent {
public:
    SubAgent() = default;

    /**
     * Converts raw E-Algorithm nodes into a high-density Topology Map (T-Map).
     * Rejects: Raw code dumps.
     * Accepts: Hierarchical context (Full Code -> Signatures -> Relationship Map).
     */
    std::string generate_topology(const std::vector<RetrievalResult>& nodes);

private:
    // Helper to extract just the def/class lines (Surgical Extraction)
    std::string extract_signatures(const std::string& code);
    
    // Categorizes nodes based on path and type
    std::string get_node_category(const std::shared_ptr<CodeNode>& node);
};

} // namespace code_assistance