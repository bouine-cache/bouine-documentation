---
title: "Guide du code"
weight: 2
description: "Carte des packages bouine orientée contributeur, couches, bonnes premières tâches et règles pour modifier le comportement de cache en toute sécurité."
---


## Carte des packages

| Package | Couche | Rôle |
|---|---:|---|
| `internal/server` | L1 | HTTP/1.1, TLS, correspondance de routes |
| `internal/storage` | L2 | Hot store, niveau tiède, WAL, SIEVE |
| `internal/cache` | L3 | Machine à états RFC 9111 et handler |
| `internal/origin` | L4 | Pools amont, health checks, transport avec hedging |
| `internal/cluster` | L5 | gossip memberlist, anneau de hachage, peer fetch |
| `internal/admin` | L6 | API HTTP d'administration |
| `internal/observability` | L7 | Métriques, journaux, journal d'accès |

| `pkg/api` | public | Wire types partagés par le SDK et l'admin |
| `pkg/bouineapi` | public | SDK Go |

## Bonnes premières tâches

- Ajouter un test de l'API d'administration.
- Ajouter un cas de test tabulaire au moteur de cache.
- Améliorer une page de runbook.
- Ajouter un benchmark pour un hot path avant de le modifier.

## Avant de modifier le comportement de cache

1. Ajoutez un test unitaire dans `internal/cache`.
2. Exécutez `make conformance`.
3. Exécutez `make bench` si le changement touche le code du hit path.
4. Mettez à jour la documentation si le comportement visible par l'opérateur change.
