---
title: "En-têtes de réponse"
weight: 93
description: "En-têtes de réponse HTTP ajoutés par bouine."
---

## X-Cache

Indique comment la réponse a été servie.

| Valeur | Description |
|-------|-------------|
| `HIT` | Servi depuis le cache (frais) |
| `MISS` | Récupéré depuis l'origine et mis en cache |
| `STALE` | Servi depuis le cache (stale, dans la fenêtre stale-while-revalidate ou stale-if-error) |
| `BYPASS` | Cache contourné (no-store, no-cache, cache désactivé pour la route, ou requête SSE) |
| `REVALIDATED` | Requête conditionnelle à l'origine a renvoyé 304, servi depuis le cache avec une fraîcheur mise à jour |

```bash
curl -sI http://localhost:8080/get | grep x-cache
# X-Cache: HIT
```

## Age

L'âge de l'objet en cache en secondes, calculé comme le temps écoulé depuis
l'en-tête `Date` de la réponse originale plus tout le temps passé dans les
forward proxies upstream. Mis à jour à chaque cache hit.

```bash
curl -sI http://localhost:8080/get | grep age
# Age: 42
```

## X-Cache-Source

Indique quel tier de stockage a servi la réponse.

| Valeur | Description |
|-------|-------------|
| `hot` | Servi depuis le hot tier en RAM (L0) |
| `warm` | Servi depuis le warm tier mmap (L1) |
| `peer` | Servi depuis un peer du cluster via peer fetch |
| `origin` | Récupéré depuis l'origine upstream — y compris tous les chemins BYPASS (fetch origine streamé, SSE, le fallback upstream-in-process) depuis v0.5.28 |
| _(vide)_ | Non servi depuis un tier de stockage : réponses synthétisées par bouine lui-même (le 504 only-if-cached, le 503 de shedding, le 502 sans upstream). Depuis v0.5.28, le label Prometheus `source` les rend sous la forme `bouine` au lieu de la chaîne vide. |

## Statuts d'erreur upstream (depuis v0.5.29)

Un fetch vers un pool upstream qui expire — timeout de dial, timeout
d'en-tête de réponse, ou deadline `cache.fetch_timeout` de la route —
est renvoyé au client comme `504 Gateway Timeout` (RFC 9110 §15.6.5)
avec le corps « upstream timeout » et l'attribution habituelle
`X-Cache` / `X-Cache-Source`. Tout autre échec upstream (refus, reset,
DNS) conserve `502 Bad Gateway`. La classification du timeout est la
même chaîne que porte le label reason de
`bouine_origin_connection_errors_total`, donc le statut sur le wire et
la métrique sont d'accord. Le 504 only-if-cached et le 503 de shedding
restent inchangés.

## X-Bouine-Route

Le label de route qui a correspondu à la requête. Utilisé par le tableau
de bord pour l'attribution par route et par le log d'accès. Ce n'est plus
un label Prometheus : depuis v0.5.8, les métriques RED du data plane
s'attribuent par `upstream_pool` (un petit ensemble borné par la
configuration) au lieu des noms de routes ; voir
[Supervision](/docs/operations/monitoring/#traffic-red).

## X-Bouine-Pool

L'upstream pool de la route servie. Défini par le routeur comme valeur
process-locale et consommé par le middleware de métriques comme label
Prometheus `upstream_pool` ; la forme entrante de l'en-tête est transférée
telle quelle. Les routes sans pool (statiques, catch-all) rapportent
`_default`.
