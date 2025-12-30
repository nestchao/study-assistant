#pragma once
#include <filesystem>
#include <fstream>
#include <string>

namespace code_assistance {
namespace fs = std::filesystem;

class AtomicJournal {
public:
    static bool backup(const std::string& filePath) {
        fs::path p(filePath);
        fs::path journalPath = p.string() + ".synapse_journal";
        try {
            if (fs::exists(p)) {
                fs::copy(p, journalPath, fs::copy_options::overwrite_existing);
                return true;
            }
        } catch (...) {}
        return false;
    }

    static void commit(const std::string& filePath) {
        fs::remove(filePath + ".synapse_journal");
    }

    static void rollback(const std::string& filePath) {
        fs::path journalPath = filePath + ".synapse_journal";
        if (fs::exists(journalPath)) {
            fs::copy(journalPath, filePath, fs::copy_options::overwrite_existing);
            fs::remove(journalPath);
        }
    }
};
}