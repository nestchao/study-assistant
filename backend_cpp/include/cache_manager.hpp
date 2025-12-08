#pragma once

#include <unordered_map>
#include <list>
#include <mutex>
#include <optional>
#include <chrono>
#include <vector>
#include <string>

namespace code_assistance {

template<typename Key, typename Value>
class LRUCache {
public:
    explicit LRUCache(size_t max_size, std::chrono::seconds ttl = std::chrono::seconds(300))
        : max_size_(max_size), ttl_(ttl) {}

    std::optional<Value> get(const Key& key) {
        std::lock_guard<std::mutex> lock(mutex_);
        
        auto it = cache_map_.find(key);
        if (it == cache_map_.end()) {
            return std::nullopt;
        }
        
        // Check expiry
        auto now = std::chrono::steady_clock::now();
        if (now > it->second.expiry_time) {
            auto lru_key = *(it->second.list_it);
            cache_list_.erase(it->second.list_it);
            cache_map_.erase(it);
            return std::nullopt;
        }
        
        // Move to front (most recently used)
        cache_list_.splice(cache_list_.begin(), cache_list_, it->second.list_it);
        
        return it->second.value;
    }

    void set(const Key& key, const Value& value) {
        std::lock_guard<std::mutex> lock(mutex_);
        
        auto now = std::chrono::steady_clock::now();
        auto expiry = now + ttl_;
        
        auto it = cache_map_.find(key);
        if (it != cache_map_.end()) {
            // Update existing
            it->second.value = value;
            it->second.expiry_time = expiry;
            cache_list_.splice(cache_list_.begin(), cache_list_, it->second.list_it);
        } else {
            // Add new
            if (cache_map_.size() >= max_size_) {
                // Evict LRU
                auto lru_key = cache_list_.back();
                cache_list_.pop_back();
                cache_map_.erase(lru_key);
            }
            
            cache_list_.push_front(key);
            cache_map_[key] = {value, cache_list_.begin(), expiry};
        }
    }

    void clear() {
        std::lock_guard<std::mutex> lock(mutex_);
        cache_map_.clear();
        cache_list_.clear();
    }

    size_t size() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return cache_map_.size();
    }

private:
    struct CacheEntry {
        Value value;
        typename std::list<Key>::iterator list_it;
        std::chrono::steady_clock::time_point expiry_time;
    };

    size_t max_size_;
    std::chrono::seconds ttl_;
    std::list<Key> cache_list_;
    std::unordered_map<Key, CacheEntry> cache_map_;
    mutable std::mutex mutex_;
};

class CacheManager {
public:
    CacheManager() 
        : embedding_cache_(1000, std::chrono::seconds(3600)),
          result_cache_(500, std::chrono::seconds(300)) {}

    // Cache embeddings
    std::optional<std::vector<float>> get_embedding(const std::string& text) {
        return embedding_cache_.get(text);
    }

    void set_embedding(const std::string& text, const std::vector<float>& embedding) {
        embedding_cache_.set(text, embedding);
    }

    // Cache retrieval results
    std::optional<std::string> get_result(const std::string& query) {
        return result_cache_.get(query);
    }

    void set_result(const std::string& query, const std::string& result) {
        result_cache_.set(query, result);
    }

    void clear_all() {
        embedding_cache_.clear();
        result_cache_.clear();
    }

private:
    LRUCache<std::string, std::vector<float>> embedding_cache_;
    LRUCache<std::string, std::string> result_cache_;
};

} // namespace code_assistance