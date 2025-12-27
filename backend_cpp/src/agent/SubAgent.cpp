#include "agent/SubAgent.hpp"
#include <sstream>
#include <regex>

namespace code_assistance {

std::string SubAgent::generate_topology(const std::vector<RetrievalResult>& nodes) {
    std::stringstream topo;
    topo << "### PROJECT ARCHITECTURAL TOPOLOGY (T-MAP)\n";

    for (size_t i = 0; i < nodes.size(); ++i) {
        const auto& cand = nodes[i];
        
        // TIER 1: Focal Points (Top 3) - Provide Full implementation context
        if (i < 3) {
            topo << "[TIER: IMPLEMENTATION] FILE: " << cand.node->file_path 
                 << " | NODE: " << cand.node->name << "\n"
                 << cand.node->content << "\n---\n";
        } 
        // TIER 2: Structural Context (Next 12) - Provide only "The What"
        else if (i < 15) {
            topo << "[TIER: STRUCTURE] FILE: " << cand.node->file_path 
                 << " | NODE: " << cand.node->name << " (Type: " << cand.node->type << ")\n"
                 << "  AI_SUMMARY: " << cand.node->ai_summary << "\n"
                 << "  SIGNATURES:\n" << extract_signatures(cand.node->content) << "\n";
        }
        // TIER 3: Ambient Context (The rest) - Provide only "The Connectivity"
        else {
            topo << "[TIER: TOPOLOGY] " << cand.node->file_path << " -> " << cand.node->name 
                 << " (Ref: " << cand.node->dependencies.size() << " deps)\n";
        }

        // Hard stop to prevent prompt overflow (SpaceX limit check)
        if (topo.str().length() > 250000) break; 
    }

    return topo.str();
}

std::string SubAgent::extract_signatures(const std::string& code) {
    std::string signatures;
    std::istringstream stream(code);
    std::string line;
    
    // Regex for Python/TS/JS/C++ signatures
    // Reject: Comments and logic. Accept: Headers.
    std::regex sig_re(R"(^\s*(def|class|async def|export|function|void|int|auto|struct|interface)\s+([a-zA-Z0-9_]+))");

    while (std::getline(stream, line)) {
        if (std::regex_search(line, sig_re)) {
            signatures += "    " + line + " ...\n";
        }
    }
    return signatures.empty() ? "    (Utility/Script Logic)" : signatures;
}

} // namespace code_assistance