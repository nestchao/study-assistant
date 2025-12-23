# backend/cache_manager.py
"""
Industry-Standard Multi-Tier Caching System

Architecture:
    L1 (In-Memory) -> L2 (Redis) -> L3 (Database)
    
Features:
    - LRU eviction policy
    - TTL with jitter
    - Cache warming
    - Distributed locking
    - Metrics & monitoring
    - Graceful degradation
"""

import time
import hashlib
import pickle
import random
import logging
from typing import Any, Optional, Callable, Dict, Union
from collections import OrderedDict
from functools import wraps
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from threading import RLock
import redis
from redis.lock import Lock as RedisLock

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ============================================================================
# CACHE METRICS & MONITORING
# ============================================================================

@dataclass
class CacheMetrics:
    """Thread-safe cache metrics tracking"""
    hits: int = 0
    misses: int = 0
    evictions: int = 0
    errors: int = 0
    total_latency_ms: float = 0.0
    lock: RLock = field(default_factory=RLock)
    
    def record_hit(self, latency_ms: float = 0):
        with self.lock:
            self.hits += 1
            self.total_latency_ms += latency_ms
    
    def record_miss(self):
        with self.lock:
            self.misses += 1
    
    def record_eviction(self):
        with self.lock:
            self.evictions += 1
    
    def record_error(self):
        with self.lock:
            self.errors += 1
    
    @property
    def hit_rate(self) -> float:
        """Calculate cache hit rate"""
        total = self.hits + self.misses
        return (self.hits / total * 100) if total > 0 else 0.0
    
    @property
    def avg_latency_ms(self) -> float:
        """Calculate average cache latency"""
        return (self.total_latency_ms / self.hits) if self.hits > 0 else 0.0
    
    def get_stats(self) -> Dict[str, Any]:
        """Get comprehensive cache statistics"""
        with self.lock:
            total = self.hits + self.misses
            return {
                'hits': self.hits,
                'misses': self.misses,
                'evictions': self.evictions,
                'errors': self.errors,
                'total_requests': total,
                'hit_rate_percent': self.hit_rate,
                'avg_latency_ms': self.avg_latency_ms,
                'timestamp': datetime.utcnow().isoformat()
            }
    
    def reset(self):
        """Reset all metrics"""
        with self.lock:
            self.hits = 0
            self.misses = 0
            self.evictions = 0
            self.errors = 0
            self.total_latency_ms = 0.0


# ============================================================================
# L1 CACHE: IN-MEMORY LRU WITH TTL
# ============================================================================

class L1Cache:
    """
    Industry-standard in-memory LRU cache with TTL support.
    
    Features:
        - Thread-safe operations
        - TTL with automatic expiration
        - LRU eviction policy
        - Size-based eviction
        - Metrics tracking
    """
    
    def __init__(
        self, 
        max_size: int = 1000,
        default_ttl: int = 300,  # 5 minutes
        name: str = "L1"
    ):
        self.max_size = max_size
        self.default_ttl = default_ttl
        self.name = name
        
        # Core data structures
        self._cache: OrderedDict = OrderedDict()
        self._expiry: Dict[str, float] = {}
        self._lock = RLock()
        
        # Metrics
        self.metrics = CacheMetrics()
        
        logger.info(f"✅ {name} Cache initialized: max_size={max_size}, ttl={default_ttl}s")
    
    def _is_expired(self, key: str) -> bool:
        """Check if a key has expired"""
        if key not in self._expiry:
            return False
        return time.time() > self._expiry[key]
    
    def _evict_lru(self):
        """Evict the least recently used item"""
        if self._cache:
            evicted_key, _ = self._cache.popitem(last=False)
            self._expiry.pop(evicted_key, None)
            self.metrics.record_eviction()
            logger.debug(f"  🗑️ {self.name}: Evicted LRU key: {evicted_key}")
    
    def get(self, key: str) -> Optional[Any]:
        """
        Get value from cache with TTL check.
        
        Returns:
            Cached value or None if miss/expired
        """
        start_time = time.time()
        
        with self._lock:
            # Check if key exists
            if key not in self._cache:
                self.metrics.record_miss()
                logger.debug(f"  ❌ {self.name} MISS: {key}")
                return None
            
            # Check if expired
            if self._is_expired(key):
                del self._cache[key]
                del self._expiry[key]
                self.metrics.record_miss()
                self.metrics.record_eviction()
                logger.debug(f"  ⏰ {self.name} EXPIRED: {key}")
                return None
            
            # Move to end (mark as recently used)
            self._cache.move_to_end(key)
            value = self._cache[key]
            
            # Record hit
            latency_ms = (time.time() - start_time) * 1000
            self.metrics.record_hit(latency_ms)
            logger.debug(f"  ✅ {self.name} HIT: {key} ({latency_ms:.2f}ms)")
            
            return value
    
    def set(
        self, 
        key: str, 
        value: Any, 
        ttl: Optional[int] = None
    ):
        """
        Set value in cache with TTL.
        
        Args:
            key: Cache key
            value: Value to cache
            ttl: Time-to-live in seconds (uses default if None)
        """
        with self._lock:
            # Add TTL jitter (±10%) to prevent thundering herd
            actual_ttl = ttl or self.default_ttl
            jitter = random.uniform(0.9, 1.1)
            expiry_time = time.time() + (actual_ttl * jitter)
            
            # Evict if at capacity and key is new
            if key not in self._cache and len(self._cache) >= self.max_size:
                self._evict_lru()
            
            # Set value and expiry
            self._cache[key] = value
            self._cache.move_to_end(key)
            self._expiry[key] = expiry_time
            
            logger.debug(f"  💾 {self.name} SET: {key} (TTL: {actual_ttl:.1f}s)")
    
    def delete(self, key: str) -> bool:
        """Delete a key from cache"""
        with self._lock:
            if key in self._cache:
                del self._cache[key]
                self._expiry.pop(key, None)
                logger.debug(f"  🗑️ {self.name} DELETE: {key}")
                return True
            return False
    
    def clear(self):
        """Clear all cache entries"""
        with self._lock:
            self._cache.clear()
            self._expiry.clear()
            logger.info(f"  🧹 {self.name} CLEARED")
    
    def get_stats(self) -> Dict[str, Any]:
        """Get cache statistics"""
        with self._lock:
            stats = self.metrics.get_stats()
            stats.update({
                'cache_name': self.name,
                'current_size': len(self._cache),
                'max_size': self.max_size,
                'fill_rate_percent': (len(self._cache) / self.max_size * 100)
            })
            return stats


# ============================================================================
# L2 CACHE: REDIS DISTRIBUTED CACHE
# ============================================================================

class L2Cache:
    """
    Industry-standard Redis-based distributed cache.
    
    Features:
        - Distributed caching
        - Atomic operations
        - Connection pooling
        - Automatic serialization
        - Distributed locking
        - Graceful degradation
    """
    
    def __init__(
        self,
        host: str = 'localhost',
        port: int = 6379,
        db: int = 0,
        password: Optional[str] = None,
        default_ttl: int = 3600,  # 1 hour
        name: str = "L2",
        max_connections: int = 50
    ):
        self.default_ttl = default_ttl
        self.name = name
        self.metrics = CacheMetrics()
        
        # Connection pool for better performance
        self.pool = redis.ConnectionPool(
            host=host,
            port=port,
            db=db,
            password=password,
            max_connections=max_connections,
            decode_responses=False  # We'll handle serialization
        )
        
        try:
            self.client = redis.Redis(connection_pool=self.pool)
            self.client.ping()
            self.available = True
            logger.info(f"✅ {name} Cache (Redis) connected: {host}:{port}")
        except redis.ConnectionError as e:
            self.client = None
            self.available = False
            logger.warning(f"⚠️ {name} Cache (Redis) unavailable: {e}")
    
    def _serialize(self, value: Any) -> bytes:
        """Serialize Python object to bytes"""
        return pickle.dumps(value, protocol=pickle.HIGHEST_PROTOCOL)
    
    def _deserialize(self, data: bytes) -> Any:
        """Deserialize bytes to Python object"""
        return pickle.loads(data)
    
    def get(self, key: str) -> Optional[Any]:
        """Get value from Redis cache"""
        if not self.available:
            self.metrics.record_miss()
            return None
        
        start_time = time.time()
        
        try:
            data = self.client.get(key)
            
            if data is None:
                self.metrics.record_miss()
                logger.debug(f"  ❌ {self.name} MISS: {key}")
                return None
            
            value = self._deserialize(data)
            latency_ms = (time.time() - start_time) * 1000
            self.metrics.record_hit(latency_ms)
            logger.debug(f"  ✅ {self.name} HIT: {key} ({latency_ms:.2f}ms)")
            
            return value
            
        except Exception as e:
            self.metrics.record_error()
            logger.error(f"  ❌ {self.name} ERROR: {e}")
            return None
    
    def set(
        self, 
        key: str, 
        value: Any, 
        ttl: Optional[int] = None
    ):
        """Set value in Redis cache with TTL"""
        if not self.available:
            return
        
        try:
            # Add jitter to TTL
            actual_ttl = ttl or self.default_ttl
            jitter = random.uniform(0.9, 1.1)
            final_ttl = int(actual_ttl * jitter)
            
            # Serialize and set
            data = self._serialize(value)
            self.client.setex(key, final_ttl, data)
            
            logger.debug(f"  💾 {self.name} SET: {key} (TTL: {final_ttl}s)")
            
        except Exception as e:
            self.metrics.record_error()
            logger.error(f"  ❌ {self.name} SET ERROR: {e}")
    
    def delete(self, key: str) -> bool:
        """Delete a key from Redis"""
        if not self.available:
            return False
        
        try:
            deleted = self.client.delete(key)
            logger.debug(f"  🗑️ {self.name} DELETE: {key}")
            return deleted > 0
        except Exception as e:
            self.metrics.record_error()
            logger.error(f"  ❌ {self.name} DELETE ERROR: {e}")
            return False
    
    def clear(self, pattern: str = "*"):
        """Clear keys matching pattern"""
        if not self.available:
            return
        
        try:
            keys = self.client.keys(pattern)
            if keys:
                self.client.delete(*keys)
            logger.info(f"  🧹 {self.name} CLEARED: {len(keys)} keys")
        except Exception as e:
            self.metrics.record_error()
            logger.error(f"  ❌ {self.name} CLEAR ERROR: {e}")
    
    def get_lock(
        self, 
        lock_name: str, 
        timeout: int = 10,
        blocking: bool = True
    ) -> RedisLock:
        """
        Get a distributed lock from Redis.
        
        Use this to prevent cache stampede:
            with cache.get_lock('my_resource'):
                # Only one process can execute this
                expensive_operation()
        """
        if not self.available:
            raise RuntimeError("Redis not available for locking")
        
        return self.client.lock(
            lock_name,
            timeout=timeout,
            blocking=blocking,
            blocking_timeout=timeout
        )
    
    def get_stats(self) -> Dict[str, Any]:
        """Get Redis cache statistics"""
        stats = self.metrics.get_stats()
        stats['cache_name'] = self.name
        stats['available'] = self.available
        
        if self.available:
            try:
                info = self.client.info('stats')
                stats.update({
                    'redis_total_commands': info.get('total_commands_processed', 0),
                    'redis_keyspace_hits': info.get('keyspace_hits', 0),
                    'redis_keyspace_misses': info.get('keyspace_misses', 0),
                })
            except:
                pass
        
        return stats


# ============================================================================
# MULTI-TIER CACHE MANAGER
# ============================================================================

class CacheManager:
    """
    Industry-standard multi-tier cache manager.
    
    Read path:  L1 -> L2 -> Database -> Backfill L2 -> Backfill L1
    Write path: Invalidate L1 -> Invalidate L2 -> Write Database
    
    Features:
        - Automatic tier management
        - Cache warming
        - Stampede prevention
        - Decorator support
        - Comprehensive metrics
    """
    
    def __init__(
        self,
        l1_config: Optional[Dict] = None,
        l2_config: Optional[Dict] = None,
        enable_l1: bool = True,
        enable_l2: bool = True
    ):
        # Initialize L1 (In-Memory)
        self.l1 = None
        if enable_l1:
            config = l1_config or {}
            self.l1 = L1Cache(**config)
        
        # Initialize L2 (Redis)
        self.l2 = None
        if enable_l2:
            config = l2_config or {}
            self.l2 = L2Cache(**config)
        
        logger.info("✅ CacheManager initialized")
    
    def get(self, key: str) -> Optional[Any]:
        """
        Get value from cache with automatic tier fallback.
        
        Read path: L1 -> L2 -> None
        Backfills higher tiers on cache hit.
        """
        # Try L1
        if self.l1:
            value = self.l1.get(key)
            if value is not None:
                return value
        
        # Try L2
        if self.l2:
            value = self.l2.get(key)
            if value is not None:
                # Backfill L1
                if self.l1:
                    self.l1.set(key, value)
                return value
        
        return None
    
    def set(
        self, 
        key: str, 
        value: Any, 
        ttl_l1: Optional[int] = None,
        ttl_l2: Optional[int] = None
    ):
        """
        Set value in all cache tiers.
        
        Write path: L1 + L2 (parallel)
        """
        if self.l1:
            self.l1.set(key, value, ttl_l1)
        
        if self.l2:
            self.l2.set(key, value, ttl_l2)
    
    def delete(self, key: str):
        """Delete key from all cache tiers"""
        if self.l1:
            self.l1.delete(key)
        
        if self.l2:
            self.l2.delete(key)
    
    def get_or_set(
        self,
        key: str,
        factory: Callable[[], Any],
        ttl_l1: Optional[int] = None,
        ttl_l2: Optional[int] = None,
        use_lock: bool = True
    ) -> Any:
        """
        Get from cache or compute and cache the result.
        
        Includes stampede prevention via distributed locking.
        
        Args:
            key: Cache key
            factory: Function to compute value if cache miss
            ttl_l1: L1 TTL override
            ttl_l2: L2 TTL override
            use_lock: Use distributed lock to prevent stampede
        """
        # Try cache first
        value = self.get(key)
        if value is not None:
            return value
        
        # Cache miss - need to compute
        lock_name = f"lock:{key}"
        
        if use_lock and self.l2 and self.l2.available:
            # Use distributed lock
            try:
                with self.l2.get_lock(lock_name, timeout=10):
                    # Double-check cache (another process might have filled it)
                    value = self.get(key)
                    if value is not None:
                        return value
                    
                    # Compute value
                    logger.debug(f"  🔨 Computing value for: {key}")
                    value = factory()
                    
                    # Cache it
                    self.set(key, value, ttl_l1, ttl_l2)
                    
                    return value
            except Exception as e:
                logger.error(f"  ❌ Lock error for {key}: {e}")
                # Fallback to computing without lock
                value = factory()
                self.set(key, value, ttl_l1, ttl_l2)
                return value
        else:
            # No locking available
            value = factory()
            self.set(key, value, ttl_l1, ttl_l2)
            return value
    
    def warm(self, keys_and_factories: Dict[str, Callable]):
        """
        Warm cache with pre-computed values.
        
        Args:
            keys_and_factories: Dict mapping cache keys to factory functions
        """
        logger.info(f"  🔥 Warming cache with {len(keys_and_factories)} entries...")
        
        for key, factory in keys_and_factories.items():
            try:
                value = factory()
                self.set(key, value)
                logger.debug(f"    ✅ Warmed: {key}")
            except Exception as e:
                logger.error(f"    ❌ Failed to warm {key}: {e}")
        
        logger.info(f"  ✅ Cache warming complete")
    
    def get_all_stats(self) -> Dict[str, Any]:
        """Get comprehensive statistics from all cache tiers"""
        stats = {
            'timestamp': datetime.utcnow().isoformat(),
            'tiers': {}
        }
        
        if self.l1:
            stats['tiers']['l1'] = self.l1.get_stats()
        
        if self.l2:
            stats['tiers']['l2'] = self.l2.get_stats()
        
        # Calculate combined hit rate
        total_hits = 0
        total_requests = 0
        
        for tier_stats in stats['tiers'].values():
            total_hits += tier_stats.get('hits', 0)
            total_requests += tier_stats.get('total_requests', 0)
        
        stats['combined_hit_rate'] = (
            (total_hits / total_requests * 100) if total_requests > 0 else 0.0
        )
        
        return stats
    
    def clear_all(self):
        """Clear all cache tiers"""
        if self.l1:
            self.l1.clear()
        
        if self.l2:
            self.l2.clear()
        
        logger.info("  🧹 All caches cleared")


# ============================================================================
# DECORATOR FOR AUTOMATIC CACHING
# ============================================================================

def cached(
    cache_manager: CacheManager,
    key_prefix: str = "",
    ttl_l1: int = 300,
    ttl_l2: int = 3600,
    key_builder: Optional[Callable] = None
):
    """
    Decorator for automatic function result caching.
    
    Usage:
        @cached(cache_mgr, key_prefix="user", ttl_l1=60, ttl_l2=300)
        def get_user(user_id: str):
            return db.get_user(user_id)
    
    Args:
        cache_manager: CacheManager instance
        key_prefix: Prefix for cache keys
        ttl_l1: L1 cache TTL
        ttl_l2: L2 cache TTL
        key_builder: Custom function to build cache key from args
    """
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            # Build cache key
            if key_builder:
                cache_key = key_builder(*args, **kwargs)
            else:
                # Default: hash function name + args
                arg_str = f"{args}_{kwargs}"
                arg_hash = hashlib.md5(arg_str.encode()).hexdigest()[:8]
                cache_key = f"{key_prefix}:{func.__name__}:{arg_hash}"
            
            # Use get_or_set with stampede prevention
            return cache_manager.get_or_set(
                key=cache_key,
                factory=lambda: func(*args, **kwargs),
                ttl_l1=ttl_l1,
                ttl_l2=ttl_l2
            )
        
        return wrapper
    return decorator


# ============================================================================
# GLOBAL CACHE INSTANCE (Singleton Pattern)
# ============================================================================

# Initialize with environment-based configuration
_cache_manager: Optional[CacheManager] = None

def get_cache_manager() -> CacheManager:
    """Get or create the global cache manager instance"""
    global _cache_manager
    
    if _cache_manager is None:
        _cache_manager = CacheManager(
            l1_config={
                'max_size': 1000,
                'default_ttl': 300,
                'name': 'L1-Global'
            },

# When to increase max_size:
# You have lots of RAM available
# Your data items are small (<10KB each)
# You want higher hit rates

# When to decrease default_ttl:
# Your data changes frequently
# You need fresher data
# Memory pressure is high

            l2_config={
                'host': 'localhost',
                'port': 6379,
                'default_ttl': 3600,
                'name': 'L2-Global'
            }

# When to increase max_connections:
# High concurrent request volume
# Many background workers
# Experiencing connection timeouts

# When to increase default_ttl:
# Data rarely changes
# Database queries are very expensive
# You can tolerate stale data

        )
    
    return _cache_manager


# Export main classes and functions
__all__ = [
    'CacheManager',
    'L1Cache',
    'L2Cache',
    'CacheMetrics',
    'cached',
    'get_cache_manager'
]