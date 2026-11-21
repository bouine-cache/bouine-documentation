---
title: "Configuration"
weight: 2
description: "Référence de configuration YAML de bouine : listeners, stockage, origin pools, routes, cache, cluster, TLS et observabilité."
---

bouine est configuré via un fichier YAML passé avec `--config`. Les variables d'environnement sont développées (`${VAR}`, `${VAR:-default}`) avant le décodage.

```yaml
listen:
  http: ":8080"
  https: ":443"
  admin: ":9000"

storage:
  hot_max_bytes: 1GiB

upstream_pools:
  - name: app
    targets: ["app.default.svc:8080"]
    health:
      active:
        path: /healthz
        interval: 10s

routes:
  - match: { path_prefix: /api/ }
    pool: app
    cache:
      ttl_default: 60s
      stale_while_revalidate: 10s
      stale_if_error: 300s
```

## Pages dans cette section

- [Politique de cache](cache-policy/) — sélection TTL, override, stale-while-revalidate, mise en cache négative, jitter, clés de cache.
- [Streaming et réponses live](streaming/) — SSE, misses en streaming, shedding de fetch slots et limites mémoire.
- [Modes de cluster](cluster-modes/) — strong, eventual ; Service headless ; gossip ; vérification et dépannage.
- [Chart Helm](helm/) — valeurs configurables du chart Helm.
- [Servir des fichiers statiques](static-files/) — servir des fichiers depuis le disque sans serveur d'origine.
- [Stockage](storage/) — niveaux hot (RAM) et warm (mmap), éviction SIEVE.
- [TLS](tls/) — terminaison TLS, mTLS entre pairs, certificats.
- [Fonctionnalités expérimentales](experimental/) — fonctionnalités opt-in susceptibles de changer.
- [Référence de configuration YAML](/docs/reference/config/) — référence champ par champ exhaustive de chaque clé de premier niveau.

## Nouveautés v0.6

- **`listen.max_connections`** — plafond par défaut relevé de 4096 à **65536** (v0.6.0) ; les refus à l'accept sont comptés par `bouine_conn_rejections_total`.
- **Chemin rapide H1 toujours actif** (v0.6.0, ADR-0069) : `experimental.h1_fast_path` et `h1_fast_peer_path` sont retirés (clés ignorées, avis au démarrage), `experimental.h1_reactor` est **supprimé** (erreur de parsing stricte — retirez la clé).
- **`routes[].cache.max_fetch_concurrency`** — défaut intégré relevé de 32 à **256** (v0.6.0).
- **`cluster.peer_fetch_concurrency`** — défaut relevé de 16 à **64** (v0.6.0).
- **`health.passive`** — `eject_for` non défini = fenêtre de restauration intégrée de 30 s (v0.6.1) ; les 5xx ne comptent vers l'éjection qu'après une fenêtre de succès de 5 s (v0.6.0) ; `consecutive_5xx` et `eject_for` modifiables à chaud par pool (v0.6.0).
- **Configuration à chaud** (v0.6.0) : `bouine config get/set/diff`, `bouine config reload` (expérimental, `experimental.config_reload`), `GET|POST /v1/config/hot`, `POST /v1/config/reload` — voir [Configuration à chaud](/docs/reference/config/#hot-configuration).
- **Nouvelles commandes CLI / API** (v0.6.0) : `bouine status`, `bouine explain`, `bouine keys find/top/recent`, `GET /v1/status`, `GET /v1/explain`, `GET /v1/keys/*` — voir [CLI](/docs/reference/cli/) et [API](/docs/reference/api/).
- **`Set-Login`** rejoint `Set-Cookie` dans toutes les portes de stockage et le strip (v0.6.0) ; les réponses à état client ne sont plus servies à un second client via le collapse (ADR-0067).
- **Collapse des miss froid sans include_headers** onto one fill flight, served from the store (ADR-0066, v0.6.0).
- **Plafond de bans** relevé de 1024 à **4096**, registration O(1) et bans surrogate appliqués via un ensemble lock-free (v0.6.0).

La référence champ par champ exhaustive (listen, storage, cluster, routes, upstream pools, métriques, admin, tracing, cloudflare, expérimental) se trouve dans la [référence de configuration YAML](/docs/reference/config/).

