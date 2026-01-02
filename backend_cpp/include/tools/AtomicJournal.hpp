#pragma once
#include <filesystem>
#include <fstream>
#include <string>
#include <spdlog/spdlog.h>
#include "parser_elite.hpp"

namespace code_assistance {
namespace fs = std::filesystem;

class AtomicJournal {
public:
    // 🛡️ Creates a backup of the file before surgery
    static bool backup(const std::string& filePath) {
        fs::path p(filePath);
        fs::path journalPath = p.string() + ".synapse_journal";
        try {
            if (fs::exists(p)) {
                fs::copy(p, journalPath, fs::copy_options::overwrite_existing);
                return true;
            }
            // If file doesn't exist, it's a new file creation; backup not needed
            return true; 
        } catch (const std::exception& e) {
            spdlog::error("🚨 Journal Backup Failed: {}", e.what());
            return false;
        }
    }

    // ✅ Confirms the surgery was successful and deletes the backup
    static void commit(const std::string& filePath) {
        try {
            fs::remove(filePath + ".synapse_journal");
        } catch (...) {}
    }

    // 🔄 Restores the file to the state before the failed surgery
    static void rollback(const std::string& filePath) {
        fs::path journalPath = filePath + ".synapse_journal";
        if (fs::exists(journalPath)) {
            try {
                fs::copy(journalPath, filePath, fs::copy_options::overwrite_existing);
                fs::remove(journalPath);
                spdlog::warn("🔄 Rollback triggered for: {}", filePath);
            } catch (const std::exception& e) {
                spdlog::critical("💥 ROLLBACK FAILED: {}. Manual repair required!", e.what());
            }
        }
    }

    // 🚀 THE FIX: Integrated Surgery Logic
    static bool apply_surgery_safe(const std::string& path, const std::string& new_code) {
        if (!backup(path)) return false;

        if (new_code.empty()) {
            spdlog::error("🚨 Surgery resulted in empty payload. Rolling back.");
            rollback(path);
            return false;
        }

        std::ofstream out(path, std::ios::trunc);
        if (!out.is_open()) {
            rollback(path);
            return false;
        }

        out << new_code;
        out.close();

        // 🛰️ ELITE CHECK: In Phase 2, we call Tree-sitter here.
        // For now, we use basic validation.
        if (new_code.empty()) {
            spdlog::error("🚨 Surgery resulted in empty payload. Rolling back.");
            rollback(path);
            return false;
        }

        // 🛰️ AST VALIDATION
        elite::ASTBooster sensor;
        std::string ext = fs::path(path).extension().string();
        
        if (!sensor.validate_syntax(new_code, ext)) {
            spdlog::critical("🚨 SURGERY ABORTED: AI generated invalid syntax for {}. Rolling back!", path);
            rollback(path);
            return false;
        }

        commit(path);
        return true;
    }
};
}