---
title: "Configuration"
weight: 2
description: "Référence de configuration YAML de bouine : listeners, stockage, pools d'origines, routes, cache, cluster, TLS et observation."
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

- [Politique de cache](cache-policy/) — sélection TTL, override, stale-while-revalidate, mise en cache négative, gigue, clés de cache.
- [Modes de cluster](cluster-modes/) — strong, eventual, full ; Service headless ; gossip.
- [Chart Helm](helm/) — valeurs configurables du chart Helm.
- [Servir des fichiers statiques](static-files/) — servir des fichiers depuis le disque sans serveur d'origine.
- [Stockage](storage/) — niveaux hot (RAM) et warm (mmap), éviction SIEVE.
- [TLS](tls/) — terminaison TLS, mTLS entre pairs, certificats.
- [Fonctionnalités expérimentales](experimental/) — fonctionnalités opt-in susceptibles de changer.

## Rechargement de configuration

bouine prend en charge le rechargement de configuration à chaud via l'API d'administration :

```bash
curl -X POST http://127.0.0.1:9000/v1/config/reload \
  -H "Authorization: Bearer ${BOUINE_ADMIN_TOKEN}"
```

Si le nouveau fichier de configuration est invalide, l'ancienne configuration reste en vigueur.

## Référence des champs

### `listen`

| Champ | Par défaut | Description |
|------|---------|-------------|
| `http` | `":8080"` | Adresse du listener HTTP/1.1 + HTTP/2 |
| `https` | — | Adresse du listener HTTPS (H1 + H2) |
| `admin` | `":9000"` | Adresse du serveur d'administration |

### `storage`

| Champ | Par défaut | Description |
|------|---------|-------------|
| `hot_max_bytes` | `1GiB` | Taille maximale du tier hot en RAM |
| `warm_dir` | — | Répertoire du tier warm (mmap) |
| `warm_max_bytes` | — | Taille maximale du tier warm sur disque |

### `upstream_pools[]`

| Champ | Description |
|------|-------------|
| `name` | Nom du pool, référencé par `routes[].pool` |
| `targets[]` | Liste des adresses des serveurs d'origine |
| `health.active` | Health check actif (path, interval, timeout, unhealthy_threshold) |
| `health.passive` | Health check passif (consecutive_5xx, eject_for) |

### `routes[]`

| Champ | Description |
|------|-------------|
| `match.path_prefix` | Correspondance par préfixe de chemin |
| `match.host` | Correspondance par hôte |
| `match.methods` | Correspondance par méthodes HTTP |
| `pool` | Nom du pool d'upstream |
| `cache.ttl_default` | TTL par défaut si l'origine n'envoie pas d'en-têtes de fraîcheur |
| `cache.ttl_override` | Surcharge le TTL interne de bouine |
| `cache.stale_while_revalidate` | Durée pendant laquelle le contenu périmé est servi pendant la revalidation |
| `cache.stale_if_error` | Durée pendant laquelle le contenu périmé est servi en cas d'erreur d'origine |
| `cache.negative_ttl` | TTL pour les réponses d'erreur cachables |
| `cache.jitter_percent` | Pourcentage d'aléa appliqué au TTL |
| `cache.enabled` | Active ou désactive le cache pour cette route (par défaut: true) |

### `cluster`

| Champ | Description |
|------|-------------|
| `enabled` | Active le clustering |
| `mode` | `strong`, `eventual`, ou `full` |
| `join[]` | Liste des adresses seed pour le gossip |
| `tls` | Configuration mTLS pour la communication entre pairs |

### `tls`

| Champ | Description |
|------|-------------|
| `certs[]` | Liste des certificats (cert_file + key_file) |
| `min_version` | Version TLS minimale (par défaut: 1.2) |

### `cloudflare`

| Champ | Description |
|------|-------------|
| `zone_id` | ID de zone Cloudflare |
| `api_token` | Jeton API Cloudflare (permission Cache Purge) |
| `async` | Mode asynchrone (par défaut: true) |
| `propagate` | Quelles opérations propager (purge, ban, refresh) |

### `tracing`

| Champ | Description |
|------|-------------|
| `endpoint` | Point de terminaison OTLP (format `host:port`, pas URL) |
| `service_name` | Nom du service pour les traces (par défaut: "bouine") |
| `sampling_rate` | Taux d'échantillonnage (0.0 à 1.0) |

### `admin`

| Champ | Description |
|------|-------------|
| `token` | Jeton bearer pour l'authentification de l'API d'administration |
