---
title: "Storage tiers"
weight: 3
description: "Understand bouine's hot and warm storage tiers, SIEVE eviction, capacity planning, and operational tuning."
---

bouine uses a two-tier storage architecture: a fast in-memory **hot tier** and an optional disk-backed **warm tier**.

## Hot tier (RAM)

The primary cache store. Every cache hit is served from here.

```yaml
storage:
  hot_max_bytes: 2GiB
```

| Field | Default | Description |
|-------|---------|-------------|
| `hot_max_bytes` | — (required) | Maximum RAM for cached objects. See [size units](/docs/configuration/#size-units). |

### How SIEVE works

SIEVE maintains a FIFO queue with a single "visited" bit per entry. On eviction, it scans from the tail, evicts the first unvisited entry, and marks visited entries as unvisited. This gives recently-accessed objects a second chance without the overhead of LRU pointer updates.

### Monitoring

| Metric | Description |
|--------|-------------|
| `bouine_hot_store_bytes` | Current bytes used |
| `bouine_hot_store_entries` | Object count |
| `bouine_hot_store_evictions_total` | Eviction counter |

When `bouine_hot_store_bytes / hot_max_bytes > 0.9` for an extended period, consider increasing `hot_max_bytes` or reviewing whether low-value objects are consuming cache space.

## Warm tier (disk)

An optional mmap-backed tier for objects evicted from the hot tier. Enables much larger effective cache sizes without proportional RAM costs.

```yaml
storage:
  warm_dir: /var/lib/bouine
  warm_max_bytes: 50GiB
```

| Field | Default | Description |
|-------|---------|-------------|
| `warm_dir` | `""` | Directory for mmap segment files. Empty disables the warm tier. |
| `warm_max_bytes` | `""` | Maximum disk usage for warm-tier segments. |

### When to enable

- Your working set exceeds available RAM.
- You want to reduce origin load during cold starts (warm tier persists across restarts).
- You can tolerate slightly higher tail latency for warm-tier reads vs. hot-tier reads.

### Kubernetes volume

The Helm chart provisions a PersistentVolumeClaim per StatefulSet replica:

```yaml
warmVolume:
  enabled: true
  size: 50Gi
  storageClass: ""   # uses cluster default
```

### Behavior

- Objects evicted from the hot tier are written to warm-tier segments.
- On a hot-tier miss, the warm tier is checked before going to origin.
- Warm-tier reads promote the object back to the hot tier.
- Segment files are compacted periodically to reclaim space from deleted entries.

## Sizing guidelines

| Deployment | `hot_max_bytes` | `warm_dir` | Notes |
|-----------|-----------------|-----------|-------|
| Dev / testing | `256MiB` | disabled | Minimal footprint |
| Small API cache | `512MiB`–`2GiB` | optional | Most APIs have small working sets |
| Large content site | `2GiB`–`8GiB` | `50GiB`+ | Images and static assets benefit from warm tier |
| CDN edge PoP | `4GiB`–`16GiB` | `100GiB`+ | Maximize hit rate at the edge |

### Cluster mode impact

| Mode | Memory per node |
|------|----------------|
| `strong` | working set ÷ N (sharded) |
| `eventual` | 1–N× (depends on traffic overlap) |

## Configuration not reloadable

Storage settings (`hot_max_bytes`, `warm_dir`, `warm_max_bytes`) require a restart to take effect.
