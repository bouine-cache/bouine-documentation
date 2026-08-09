---
title: "Architecture"
weight: 4
description: "Comment bouine est structuré en interne : listeners, pipeline, stockage, moteur de cache, pools d'origines, clustering et observabilité."
---


## Conception en couches

bouine est structuré en 8 couches, chacune testable isolément.

{{< arch-diagram >}}

## Piles HTTP

Une seule implémentation HTTP :

- **`net/http`** — HTTP/1.1 + HTTP/2 (plan de données + administration)

L'API d'administration utilise `net/http.ServeMux`.

## Moteur de cache

La machine à états RFC 9111 est déterministe : les entrées sont `*http.Request`, l'`*Object` stocké et `now`. Les sorties sont `HIT`, `MISS`, `REVALIDATE`, `STALE_HIT` ou `BYPASS`.

### Clé de cache

Clé primaire : `xxhash64(scheme | host | path | sorted_query | method)`

Clé secondaire (Vary) : dérivée des en-têtes listés dans l'en-tête `Vary` de la réponse, ou de `cache.key.include_headers`.

### Éviction

- **SIEVE** — simple, performance proche de LRU-K, O(1) par opération

### CDN-Cache-Control (RFC 9211)

Lorsque l'origine envoie `CDN-Cache-Control`, il prend précédence sur `Cache-Control` pour toutes les décisions de cache partagé. Cela permet aux origines de définir des TTL différents pour les caches CDN vs navigateurs :

```http
Cache-Control: no-store
CDN-Cache-Control: max-age=3600
```

### Clés de substitution

Les origines peuvent étiqueter les réponses avec des clés de substitution pour une invalidation groupée :

```http
Surrogate-Key: product-456 category-shoes
Cache-Tag: product-456, category-shoes
```

bouine lit `Surrogate-Key`, `Cache-Tag` et `X-Cache-Tags` au moment du stockage et les rend disponibles pour l'invalidation via `POST /v1/ban{surrogate_key:"..."}`.

### Mise en cache négative

Les réponses 404, 405, 410, 501 peuvent être mises en cache pendant une durée configurable (`negative_ttl`).

### TTL avec gigue

Un aléa de ±N % est appliqué à chaque TTL pour empêcher les ruées d'expiration synchronisées.

## Clustering

bouine prend en charge deux modes de cohérence (voir [Clustering](/docs/configuration/cluster-modes/)) :

### Mode Strong (par défaut)

**Sharding** : hachage cohérent avec 256 nœuds virtuels par nœud réel. En cas de miss, le nœud demandeur vérifie le nœud propriétaire avant d'aller à l'origine.

### Mode Eventual

Chaque nœud est indépendant — pas de sharding, pas de récupération par pair. Les invalidations se propagent par gossip uniquement.

### Appartenance (tous modes)

`hashicorp/memberlist` pour le gossip. Les nœuds s'amorcent via le DNS du StatefulSet.

### Flux de récupération par pair (mode Strong uniquement)

{{< peer-fetch-diagram >}}

Latence ajoutée pour un hit par pair : ~0,3 ms (un saut HTTP/2 intra-cluster).

### Stale-while-revalidate (SWR)

Lorsqu'un objet entre dans sa fenêtre `stale-while-revalidate`, bouine :

1. Sert immédiatement l'objet périmé (pas d'attente côté client).
2. Déclenche une goroutine en arrière-plan (`bgRevalSem` limite la concurrence à 256) qui revalide conditionnellement avec l'origine.
3. La réponse de l'origine (200 ou 304) met à jour le hot store ; la prochaine requête obtient un `HIT` frais.

### Propagation de l'invalidation

| Opération | `strong` | `eventual` | `full` |
|---|---|---|---|
| **Purge** | Fan-out HTTP vers tous les pairs + gossip | Gossip uniquement (convergence 1–5 s) | Fan-out HTTP vers tous les pairs + gossip |
| **Ban** | Fan-out HTTP vers tous les pairs + gossip | Gossip uniquement | Fan-out HTTP vers tous les pairs + gossip |
| **Refresh** | Transmis au nœud propriétaire de la clé | Gossip uniquement | Fan-out HTTP vers tous les pairs |

### Protocole d'arrivée

Les pods réessayent l'arrivée toutes les 2 secondes pendant jusqu'à 60 secondes. Le succès nécessite `Members() > 1`. Le Service headless **doit** avoir `publishNotReadyAddresses: true`.

## Performance

| Benchmark | Résultat |
|---|---|
| `Evaluate_Hit` | 40 ns/op, 0 alloc |
| `HotStore_Get_Hit` | 5,4 ns/op, 0 alloc |
| `Handler_CacheHit` | 537 ns/op, 8 allocs |
| `BuildKey` (paramètres de requête) | 46 ns/op, 0 alloc |
| `SIEVE_Access` | 5,4 ns/op, 0 alloc |

Résultats des tests de charge (Docker, 3k RPS, nœud unique vs Varnish + nginx) :

| Scénario | bouine | nginx | varnish |
|---|---|---|---|
| Hit uniquement (cache chaud) | 166 µs moy | 166 µs moy | 177 µs moy |
| Tempête de miss (no-store) | 157 µs moy | dégradé | 166 µs moy |
| Mixte 60/15/10/5/5 | 230 µs moy | 22 ms moy† | 199 µs moy |

†La moyenne mixte élevée de nginx est due à la revalidation bloquante ; bouine et Varnish utilisent tous deux le rafraîchissement SWR en arrière-plan.
