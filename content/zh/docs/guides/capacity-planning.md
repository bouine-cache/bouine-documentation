---
title: "容量规划"
weight: 4
description: "Size bouine for your workload: estimate hot and warm tier capacity, choose cluster mode and replica count, and plan for growth."
---

## Step 1: Estimate your working set

The **working set** is the total size of responses that need to stay cached for acceptable hit rates.

```
working_set ≈ unique_cacheable_urls × avg_response_size
```

| Workload | Typical working set |
|----------|-------------------|
| REST API (100k endpoints, 2 KiB avg) | ~200 MiB |
| E-commerce catalog (1M products, 5 KiB avg) | ~5 GiB |
| Static site / CDN (50k assets, 50 KiB avg) | ~2.5 GiB |
| Media-heavy site (10k pages, 200 KiB avg) | ~2 GiB |

If you cannot estimate, start with 2 GiB and monitor `bouine_hot_store_bytes / bouine_hot_store_max_bytes`. If it stays above 0.9 consistently, double `hot_max_bytes`.

## Step 2: Choose cluster mode and replicas

| Mode | Memory per node | When to use |
|------|----------------|-------------|
| `strong` (default) | working_set ÷ N | Most deployments — memory efficient, one copy per key |
| `eventual` | ~working_set (each node independent) | Geo-distributed, CDN edge |
| `full` | working_set × 1 (every node has all keys) | Small clusters (2–5), maximum hit rate |

**Replica count guidelines:**

| Concern | Recommendation |
|---------|---------------|
| High availability | ≥ 3 replicas (survives 1 node loss with PDB `minAvailable: 2`) |
| Memory efficiency | More replicas = less RAM per node in `strong` mode |
| Gossip overhead | Keep under ~50 nodes for manageable gossip traffic |

## Step 3: Size the hot tier

```
hot_max_bytes = working_set ÷ N × 1.2   (strong mode, with 20% headroom)
hot_max_bytes = working_set × 1.2        (eventual mode)
```

The 20% headroom prevents constant eviction pressure. SIEVE eviction works best when the cache is not permanently full.

## Step 4: Size the warm tier (optional)

Enable the warm tier when your working set exceeds affordable RAM:

```
warm_max_bytes = working_set - hot_max_bytes + headroom
```

The warm tier holds objects evicted from the hot tier on disk (mmap). Reads from the warm tier are slower than RAM but far faster than an origin fetch.

```yaml
storage:
  hot_max_bytes: 2GiB
  warm_dir: /var/lib/bouine
  warm_max_bytes: 50GiB
```

## Step 5: Set resource limits

The Helm chart defaults are a reasonable starting point:

```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2
    memory: 4Gi

goMemLimit: "3GiB"    # ~75% of memory limit
goGC: "100"
```

The `GOMEMLIMIT` should be ~75% of `resources.limits.memory`. This gives the Go runtime room for GC while keeping the hot tier resident.

| Memory limit | `goMemLimit` | `hot_max_bytes` |
|-------------|-------------|-----------------|
| 2 Gi | 1.5GiB | 1GiB |
| 4 Gi | 3GiB | 2GiB |
| 8 Gi | 6GiB | 4GiB |
| 16 Gi | 12GiB | 8GiB |

## Step 6: Validate under load

Run the benchmark suite against your target configuration:

```bash
# Single-node load test
bash bench/loadtest/scenarios/1_hit_only/run.sh

# Rolling update test (verifies zero 5xx)
bash bench/loadtest/scenarios/4.5_rolling_update/run.sh
```

### Key metrics to watch

| Metric | Healthy range | Action if out of range |
|--------|-------------|----------------------|
| `bouine_hot_store_bytes / bouine_hot_store_max_bytes` | < 0.9 | Increase `hot_max_bytes` |
| `bouine_sieve_evictions_total` (rate) | Low, stable | If spiking, cache is undersized |
| `bouine_requests_total{cache_result="HIT"}` / total | > 0.8 for static content | Check TTLs, working set size |
| `bouine_peer_fetch_duration_seconds` p99 | < 5 ms | Check cluster network health |


## Example: e-commerce deployment

```yaml
# 3-node strong-mode cluster for a 5 GiB product catalog
replicaCount: 3

config:
  cluster:
    enabled: true
    mode: strong

  storage:
    hot_max_bytes: 2GiB     # 5 GiB ÷ 3 × 1.2 ≈ 2 GiB per node
    warm_dir: /var/lib/bouine
    warm_max_bytes: 20GiB

resources:
  limits:
    memory: 4Gi

goMemLimit: "3GiB"
```
