#pragma once
#include <windows.h>
#include <psapi.h>
#include <pdh.h>
#include <mutex>
#include <thread>
#include <atomic>
#include <chrono>

#pragma comment(lib, "pdh.lib")

namespace code_assistance {

struct TelemetryData {
    // System
    double cpu_usage = 0.0;
    size_t ram_usage_mb = 0;
    size_t ram_total_mb = 0;
    
    // Application Latency
    double vector_latency_ms = 0.0;
    double embedding_latency_ms = 0.0;
    double llm_generation_ms = 0.0; // <--- NEW
    
    // AI Throughput
    int output_token_count = 0;     // <--- NEW
    double tokens_per_second = 0.0; // <--- NEW
    int graph_nodes_scanned = 0; 
};

class SystemMonitor {
public:
    // Global Atomic Metrics
    inline static std::atomic<double> global_vector_latency_ms{0.0};
    inline static std::atomic<double> global_embedding_latency_ms{0.0};
    inline static std::atomic<double> global_llm_generation_ms{0.0}; // <--- NEW
    inline static std::atomic<int> global_output_tokens{0};          // <--- NEW
    inline static std::atomic<int> global_graph_nodes_scanned{0};

    SystemMonitor() : stop_thread_(false) {
        PdhOpenQuery(NULL, NULL, &cpuQuery);
        PdhAddCounter(cpuQuery, TEXT("\\Processor(_Total)\\% Processor Time"), NULL, &cpuCounter);
        PdhCollectQueryData(cpuQuery);
        monitor_thread_ = std::thread(&SystemMonitor::poll_routine, this);
    }

    ~SystemMonitor() {
        stop_thread_ = true;
        if (monitor_thread_.joinable()) monitor_thread_.join();
        PdhCloseQuery(cpuQuery);
    }

    TelemetryData get_latest_snapshot() {
        std::lock_guard<std::mutex> lock(data_mutex_);
        return current_data_;
    }

private:
    PDH_HQUERY cpuQuery;
    PDH_HCOUNTER cpuCounter;
    TelemetryData current_data_;
    std::mutex data_mutex_;
    std::thread monitor_thread_;
    std::atomic<bool> stop_thread_;

    void poll_routine() {
        while (!stop_thread_) {
            TelemetryData snapshot;

            // 1. OS Metrics
            PDH_FMT_COUNTERVALUE counterVal;
            PdhCollectQueryData(cpuQuery);
            PdhGetFormattedCounterValue(cpuCounter, PDH_FMT_DOUBLE, NULL, &counterVal);
            snapshot.cpu_usage = counterVal.doubleValue;

            PROCESS_MEMORY_COUNTERS_EX pmc;
            if (GetProcessMemoryInfo(GetCurrentProcess(), (PROCESS_MEMORY_COUNTERS*)&pmc, sizeof(pmc))) {
                snapshot.ram_usage_mb = pmc.PrivateUsage / 1024 / 1024;
            }
            
            MEMORYSTATUSEX memInfo;
            memInfo.dwLength = sizeof(MEMORYSTATUSEX);
            GlobalMemoryStatusEx(&memInfo);
            snapshot.ram_total_mb = memInfo.ullTotalPhys / 1024 / 1024;

            // 2. Read Global Atomics
            snapshot.vector_latency_ms = global_vector_latency_ms.load();
            snapshot.embedding_latency_ms = global_embedding_latency_ms.load();
            snapshot.llm_generation_ms = global_llm_generation_ms.load();
            snapshot.output_token_count = global_output_tokens.load();
            snapshot.graph_nodes_scanned = global_graph_nodes_scanned.load();

            // 3. Derived Metric: TPS (Tokens Per Second)
            if (snapshot.llm_generation_ms > 0) {
                snapshot.tokens_per_second = (snapshot.output_token_count / snapshot.llm_generation_ms) * 1000.0;
            } else {
                snapshot.tokens_per_second = 0.0;
            }

            {
                std::lock_guard<std::mutex> lock(data_mutex_);
                current_data_ = snapshot;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
        }
    }
};
}