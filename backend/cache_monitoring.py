# backend/cache_monitoring.py
"""
Comprehensive cache monitoring and testing utilities
"""

import time
import random
from typing import Dict, List, Any
from dataclasses import dataclass
from datetime import datetime
import json


@dataclass
class CacheTestResult:
    """Results from a cache test"""
    test_name: str
    passed: bool
    latency_ms: float
    details: str
    timestamp: str = None
    
    def __post_init__(self):
        if not self.timestamp:
            self.timestamp = datetime.utcnow().isoformat()


class CacheMonitor:
    """
    Monitoring and diagnostic tools for cache system
    """
    
    def __init__(self, cache_manager):
        self.cache = cache_manager
        self.test_results: List[CacheTestResult] = []
    
    def run_health_check(self) -> Dict[str, Any]:
        """
        Comprehensive health check of the cache system.
        
        Returns:
            Health status report with diagnostics
        """
        print("\n" + "="*70)
        print("🏥 CACHE HEALTH CHECK")
        print("="*70)
        
        health = {
            'status': 'healthy',
            'timestamp': datetime.utcnow().isoformat(),
            'checks': {}
        }
        
        # Check 1: L1 Cache Availability
        print("\n1️⃣ Checking L1 Cache...")
        try:
            if self.cache.l1:
                test_key = f'health_check_{time.time()}'
                self.cache.l1.set(test_key, 'test_value')
                value = self.cache.l1.get(test_key)
                self.cache.l1.delete(test_key)
                
                if value == 'test_value':
                    print("   ✅ L1 Cache: HEALTHY")
                    health['checks']['l1'] = {
                        'status': 'healthy',
                        'current_size': len(self.cache.l1._cache),
                        'max_size': self.cache.l1.max_size
                    }
                else:
                    print("   ⚠️ L1 Cache: Data mismatch")
                    health['status'] = 'degraded'
                    health['checks']['l1'] = {'status': 'degraded'}
            else:
                print("   ⚠️ L1 Cache: Not configured")
                health['checks']['l1'] = {'status': 'disabled'}
        except Exception as e:
            print(f"   ❌ L1 Cache: ERROR - {e}")
            health['status'] = 'degraded'
            health['checks']['l1'] = {'status': 'error', 'error': str(e)}
        
        # Check 2: L2 Cache Availability
        print("\n2️⃣ Checking L2 Cache (Redis)...")
        try:
            if self.cache.l2 and self.cache.l2.available:
                test_key = f'health_check_{time.time()}'
                self.cache.l2.set(test_key, 'test_value')
                value = self.cache.l2.get(test_key)
                self.cache.l2.delete(test_key)
                
                if value == 'test_value':
                    print("   ✅ L2 Cache (Redis): HEALTHY")
                    
                    # Get Redis info
                    try:
                        info = self.cache.l2.client.info('memory')
                        health['checks']['l2'] = {
                            'status': 'healthy',
                            'used_memory_mb': info.get('used_memory', 0) / 1024 / 1024,
                            'max_memory_mb': info.get('maxmemory', 0) / 1024 / 1024 if info.get('maxmemory') else 'unlimited'
                        }
                    except:
                        health['checks']['l2'] = {'status': 'healthy'}
                else:
                    print("   ⚠️ L2 Cache: Data mismatch")
                    health['status'] = 'degraded'
                    health['checks']['l2'] = {'status': 'degraded'}
            else:
                print("   ⚠️ L2 Cache: Not available")
                health['checks']['l2'] = {'status': 'unavailable'}
        except Exception as e:
            print(f"   ❌ L2 Cache: ERROR - {e}")
            health['status'] = 'degraded'
            health['checks']['l2'] = {'status': 'error', 'error': str(e)}
        
        # Check 3: Performance Test
        print("\n3️⃣ Running Performance Test...")
        perf_result = self._performance_test()
        health['checks']['performance'] = perf_result
        
        # Final Status
        print("\n" + "="*70)
        if health['status'] == 'healthy':
            print("✅ OVERALL STATUS: HEALTHY")
        else:
            print("⚠️ OVERALL STATUS: DEGRADED (some checks failed)")
        print("="*70 + "\n")
        
        return health
    
    def _performance_test(self) -> Dict[str, Any]:
        """Test cache performance with timing"""
        test_key = f'perf_test_{time.time()}'
        test_value = {'data': 'x' * 1000}  # 1KB of data
        
        results = {}
        
        # Test L1 Write
        if self.cache.l1:
            start = time.time()
            self.cache.l1.set(test_key, test_value)
            l1_write_ms = (time.time() - start) * 1000
            results['l1_write_ms'] = round(l1_write_ms, 3)
            
            # Test L1 Read
            start = time.time()
            self.cache.l1.get(test_key)
            l1_read_ms = (time.time() - start) * 1000
            results['l1_read_ms'] = round(l1_read_ms, 3)
            
            self.cache.l1.delete(test_key)
            print(f"   L1: Write={l1_write_ms:.3f}ms, Read={l1_read_ms:.3f}ms")
        
        # Test L2 Write/Read
        if self.cache.l2 and self.cache.l2.available:
            start = time.time()
            self.cache.l2.set(test_key, test_value)
            l2_write_ms = (time.time() - start) * 1000
            results['l2_write_ms'] = round(l2_write_ms, 3)
            
            start = time.time()
            self.cache.l2.get(test_key)
            l2_read_ms = (time.time() - start) * 1000
            results['l2_read_ms'] = round(l2_read_ms, 3)
            
            self.cache.l2.delete(test_key)
            print(f"   L2: Write={l2_write_ms:.3f}ms, Read={l2_read_ms:.3f}ms")
        
        # Status
        if results.get('l1_read_ms', 0) < 1 and results.get('l2_read_ms', 0) < 5:
            results['status'] = 'excellent'
            print("   ✅ Performance: EXCELLENT")
        elif results.get('l1_read_ms', 0) < 2 and results.get('l2_read_ms', 0) < 10:
            results['status'] = 'good'
            print("   ✅ Performance: GOOD")
        else:
            results['status'] = 'poor'
            print("   ⚠️ Performance: POOR (may need tuning)")
        
        return results
    
    def run_stress_test(self, num_operations: int = 1000) -> Dict[str, Any]:
        """
        Stress test the cache with many operations.
        
        Args:
            num_operations: Number of operations to perform
        
        Returns:
            Stress test results
        """
        print(f"\n💪 Running stress test with {num_operations} operations...")
        
        start_time = time.time()
        
        # Generate test data
        for i in range(num_operations):
            key = f'stress_test_{i}'
            value = {'index': i, 'data': 'x' * random.randint(100, 1000)}
            
            # Write
            self.cache.set(key, value, ttl_l1=60, ttl_l2=120)
            
            # Read (should hit L1)
            self.cache.get(key)
            
            # Occasional deletes
            if i % 10 == 0:
                self.cache.delete(key)
        
        elapsed = time.time() - start_time
        ops_per_sec = num_operations / elapsed
        
        # Get final stats
        stats = self.cache.get_all_stats()
        
        result = {
            'total_operations': num_operations,
            'elapsed_seconds': round(elapsed, 2),
            'operations_per_second': round(ops_per_sec, 2),
            'final_hit_rate': stats.get('combined_hit_rate', 0),
            'l1_size': stats['tiers'].get('l1', {}).get('current_size', 0),
            'l1_evictions': stats['tiers'].get('l1', {}).get('evictions', 0)
        }
        
        print(f"   ✅ Completed in {elapsed:.2f}s ({ops_per_sec:.0f} ops/sec)")
        print(f"   Hit rate: {result['final_hit_rate']:.1f}%")
        
        return result
    
    def test_cache_invalidation(self) -> bool:
        """Test that cache invalidation works correctly"""
        print("\n🔄 Testing cache invalidation...")
        
        test_key = 'invalidation_test'
        
        # Set value
        self.cache.set(test_key, 'original_value')
        
        # Verify cached
        assert self.cache.get(test_key) == 'original_value'
        
        # Delete
        self.cache.delete(test_key)
        
        # Verify deleted
        result = self.cache.get(test_key)
        
        if result is None:
            print("   ✅ Invalidation works correctly")
            return True
        else:
            print(f"   ❌ Invalidation failed: got {result}")
            return False
    
    def test_ttl_expiration(self) -> bool:
        """Test that TTL expiration works"""
        print("\n⏰ Testing TTL expiration...")
        
        test_key = 'ttl_test'
        
        # Set with very short TTL
        self.cache.l1.set(test_key, 'expires_soon', ttl=1)
        
        # Should be cached immediately
        if self.cache.l1.get(test_key) != 'expires_soon':
            print("   ❌ Value not cached immediately")
            return False
        
        # Wait for expiration
        print("   ⏳ Waiting 2 seconds for expiration...")
        time.sleep(2)
        
        # Should be expired now
        result = self.cache.l1.get(test_key)
        
        if result is None:
            print("   ✅ TTL expiration works correctly")
            return True
        else:
            print(f"   ❌ TTL failed: value still exists ({result})")
            return False
    
    def test_tier_fallback(self) -> bool:
        """Test that tier fallback works (L1 -> L2 -> None)"""
        print("\n🔀 Testing tier fallback...")
        
        test_key = f'fallback_test_{time.time()}'
        test_value = 'tier_fallback_value'
        
        # Clear L1
        if self.cache.l1:
            self.cache.l1.clear()
        
        # Set in L2 only
        if self.cache.l2 and self.cache.l2.available:
            self.cache.l2.set(test_key, test_value)
            
            # Get via manager (should fallback to L2 and backfill L1)
            result = self.cache.get(test_key)
            
            if result != test_value:
                print(f"   ❌ L2 fallback failed: got {result}")
                return False
            
            # Check if L1 was backfilled
            if self.cache.l1:
                l1_result = self.cache.l1.get(test_key)
                if l1_result == test_value:
                    print("   ✅ Tier fallback and backfill work correctly")
                    return True
                else:
                    print("   ⚠️ Fallback works but backfill failed")
                    return False
        else:
            print("   ⚠️ L2 not available, skipping test")
            return True
    
    def generate_report(self) -> str:
        """Generate a comprehensive monitoring report"""
        health = self.run_health_check()
        stats = self.cache.get_all_stats()
        
        report = f"""
╔════════════════════════════════════════════════════════════════════╗
║              CACHE SYSTEM MONITORING REPORT                        ║
╚════════════════════════════════════════════════════════════════════╝

Timestamp: {datetime.utcnow().isoformat()}
Overall Status: {health['status'].upper()}

─────────────────────────────────────────────────────────────────────
📊 PERFORMANCE METRICS
─────────────────────────────────────────────────────────────────────
Combined Hit Rate: {stats.get('combined_hit_rate', 0):.1f}%

L1 Cache (In-Memory):
  • Hits: {stats['tiers'].get('l1', {}).get('hits', 0):,}
  • Misses: {stats['tiers'].get('l1', {}).get('misses', 0):,}
  • Hit Rate: {stats['tiers'].get('l1', {}).get('hit_rate_percent', 0):.1f}%
  • Avg Latency: {stats['tiers'].get('l1', {}).get('avg_latency_ms', 0):.3f}ms
  • Current Size: {stats['tiers'].get('l1', {}).get('current_size', 0):,} / {stats['tiers'].get('l1', {}).get('max_size', 0):,}
  • Evictions: {stats['tiers'].get('l1', {}).get('evictions', 0):,}

L2 Cache (Redis):
  • Status: {'Connected' if stats['tiers'].get('l2', {}).get('available') else 'Unavailable'}
  • Hits: {stats['tiers'].get('l2', {}).get('hits', 0):,}
  • Misses: {stats['tiers'].get('l2', {}).get('misses', 0):,}
  • Hit Rate: {stats['tiers'].get('l2', {}).get('hit_rate_percent', 0):.1f}%
  • Avg Latency: {stats['tiers'].get('l2', {}).get('avg_latency_ms', 0):.3f}ms

─────────────────────────────────────────────────────────────────────
🏥 HEALTH CHECKS
─────────────────────────────────────────────────────────────────────
"""
        for check_name, check_result in health['checks'].items():
            status_emoji = "✅" if check_result.get('status') in ['healthy', 'excellent', 'good'] else "⚠️"
            report += f"{status_emoji} {check_name.upper()}: {check_result.get('status', 'unknown').upper()}\n"
        
        report += "\n─────────────────────────────────────────────────────────────────────\n"
        
        return report


# Flask routes for monitoring
def setup_monitoring_routes(app, cache_manager):
    """
    Add monitoring endpoints to Flask app.
    
    Usage:
        from cache_monitoring import setup_monitoring_routes
        setup_monitoring_routes(app, cache_manager)
    """
    monitor = CacheMonitor(cache_manager)
    
    @app.route('/admin/cache/health', methods=['GET'])
    def cache_health():
        """Health check endpoint"""
        health = monitor.run_health_check()
        return json.dumps(health, indent=2), 200, {'Content-Type': 'application/json'}
    
    @app.route('/admin/cache/stats', methods=['GET'])
    def cache_stats():
        """Detailed statistics endpoint"""
        stats = cache_manager.get_all_stats()
        return json.dumps(stats, indent=2), 200, {'Content-Type': 'application/json'}
    
    @app.route('/admin/cache/report', methods=['GET'])
    def cache_report():
        """Human-readable report"""
        report = monitor.generate_report()
        return report, 200, {'Content-Type': 'text/plain; charset=utf-8'}
    
    @app.route('/admin/cache/stress-test', methods=['POST'])
    def cache_stress_test():
        """Run stress test (admin only)"""
        num_ops = int(request.args.get('operations', 1000))
        result = monitor.run_stress_test(num_ops)
        return json.dumps(result, indent=2), 200, {'Content-Type': 'application/json'}
    
    @app.route('/admin/cache/clear', methods=['POST'])
    def cache_clear():
        """Clear all caches (admin only, use with caution)"""
        cache_manager.clear_all()
        return json.dumps({'success': True, 'message': 'All caches cleared'}), 200


# Standalone test runner
if __name__ == '__main__':
    from cache_manager import CacheManager
    
    print("\n🧪 CACHE SYSTEM TEST SUITE")
    print("="*70)
    
    # Initialize cache
    cache_mgr = CacheManager()
    monitor = CacheMonitor(cache_mgr)
    
    # Run all tests
    tests = [
        ('Health Check', lambda: monitor.run_health_check()),
        ('Cache Invalidation', lambda: monitor.test_cache_invalidation()),
        ('TTL Expiration', lambda: monitor.test_ttl_expiration()),
        ('Tier Fallback', lambda: monitor.test_tier_fallback()),
        ('Stress Test (1000 ops)', lambda: monitor.run_stress_test(1000))
    ]
    
    results = []
    for test_name, test_func in tests:
        try:
            result = test_func()
            results.append((test_name, True))
        except Exception as e:
            print(f"\n❌ {test_name} FAILED: {e}")
            results.append((test_name, False))
    
    # Summary
    print("\n" + "="*70)
    print("📊 TEST SUMMARY")
    print("="*70)
    
    passed = sum(1 for _, success in results if success)
    total = len(results)
    
    for test_name, success in results:
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"{status} - {test_name}")
    
    print(f"\n{'='*70}")
    print(f"Results: {passed}/{total} tests passed ({passed/total*100:.0f}%)")
    print("="*70)
    
    # Generate report
    print("\n" + monitor.generate_report())