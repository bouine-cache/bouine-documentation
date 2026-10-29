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
- [Modes de cluster](cluster-modes/) — strong, eventual ; Service headless ; gossip.
- [Chart Helm](helm/) — valeurs configurables du chart Helm.
- [Servir des fichiers statiques](static-files/) — servir des fichiers depuis le disque sans serveur d'origine.
- [Stockage](storage/) — niveaux hot (RAM) et warm (mmap), éviction SIEVE.
- [TLS](tls/) — terminaison TLS, mTLS entre pairs, certificats.
- [Fonctionnalités expérimentales](experimental/) — fonctionnalités opt-in susceptibles de changer.

## Nouveautés v0.6

- **`listen.max_connections`** — plafond par défaut relevé de 4096 à **65536** (v0.6.0) ; les refus à l'accept sont comptés par `bouine_conn_rejections_total`.
- **Chemin rapide H1 toujours actif** (v0.6.0, ADR-0069) : `experimental.h1_fast_path` et `h1_fast_peer_path` sont retirés (clés ignorées, avis au démarrage), `experimental.h1_reactor` est **supprimé** (erreur de parsing stricte — retirez la clé).
- **`routes[].cache.max_fetch_concurrency`** — défaut intégré relevé de 32 à **256** (v0.6.0).
- **`cluster.peer_fetch_concurrency`** — défaut relevé de 16 à **64** (v0.6.0).
- **`health.passive`** — `eject_for` non défini = fenêtre de restauration intégrée de 30 s (v0.6.1) ; les 5xx ne comptent vers l'éjection qu'après une fenêtre de succès de 5 s (v0.6.0) ; `consecutive_5xx` et `eject_for` modifiables à chaud par pool (v0.6.0).
- **Configuration à chaud** (v0.6.0) : `bouine config get/set/diff`, `bouine config reload` (expérimental, `experimental.config_reload`), `GET|POST /v1/config/hot`, `POST /v1/config/reload` — voir [Configuration à chaud](#hot-configuration).
- **Nouvelles commandes CLI / API** (v0.6.0) : `bouine status`, `bouine explain`, `bouine keys find/top/recent`, `GET /v1/status`, `GET /v1/explain`, `GET /v1/keys/*` — voir [CLI](/docs/reference/cli/) et [API](/docs/reference/api/).
- **`Set-Login`** rejoint `Set-Cookie` dans toutes les portes de stockage et le strip (v0.6.0) ; les réponses à état client ne sont plus servies à un second client via le collapse (ADR-0067).
- **Collapse des miss froid sans include_headers** onto one fill flight, served from the store (ADR-0066, v0.6.0).
- **Plafond de bans** relevé de 1024 à **4096**, registration O(1) et bans surrogate appliqués via un ensemble lock-free (v0.6.0).

## Référence des champs

### `listen`

| Champ | Par défaut | Description |
|------|---------|-------------|
| `http` | `":8080"` | Adresse du listener HTTP/1.1 |
| `https` | — | Adresse du listener HTTPS (H1) |
| `admin` | `":9000"` | Adresse du serveur d'administration |
| `max_connections` | `0` | Nombre maximal de connexions data-plane simultanées (0 = défaut intégré **65536 depuis v0.6.0**, précédemment 4096 ; 0 désactive le plafond). Protège contre l'épuisement des FD. Les connexions keep-alive inactives occupent aussi un slot : dimensionnez pour toute la population cliente qu'un seul front CDN produit, pas seulement le pic de concurrence ; chaque connexion acceptée épingle ~32 KiB, donc 65536 connexions épinglent au plus ~2 GiB — réduisez sur les petits pods. Les connexions au-delà de la limite reçoivent un `503 + Connection: close` instantané à l'accept, compté exactement par `bouine_conn_rejections_total` (le log warn est limité à une ligne par 10 s par listener). |
| `idle_timeout` | `120s` | Timeout keep-alive des connexions data-plane inactives. Avec un proxy amont (upstream) en face, gardez son timeout keep-alive inactif **en dessous** de cette valeur pour que le proxy ferme les connexions inactives en premier. |
| `tcp_quickack` | `true` (Linux) | Active TCP_QUICKACK sur les connexions acceptées pour réduire la latence (no-op sur les autres plateformes) |
| `tcp_fast_open` | `false` | Active le TCP Fast Open côté serveur sur les listeners data-plane (Linux uniquement, no-op ailleurs). **Défaut passé de activé à désactivé en v0.5.29** — les déploiements qui comptaient sur l'ancien défaut doivent le mettre à `true` explicitement. Avec un cookie TFO mis en cache par le noyau, les octets de requête partent dans le SYN du client : un RTT économisé sur chaque nouvelle connexion. |
| `read_timeout` | `30s` | Durée maximale de lecture de l'en-tête et du corps d'une requête (depuis v0.5.9). C'est la défense anti-slowloris — ce n'est **pas** un deadline de bout en bout (les fetch origin sont bornés par `fetch_timeout`). À augmenter pour des clients mobiles lents ou de gros uploads. Doit rester sous le filet de sécurité de 5 minutes du data-plane. |

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
| `match.host` | Correspondance par hôte (vide = tous). Depuis v0.5.27 un `*.` initial effectue une correspondance par suffixe ancrée sur la frontière de label : `*.staging.example.com` couvre tout l'arbre de sous-domaines, jamais l'hôte nu |
| `match.path` | Motif RE2 ancré appliqué au chemin de requête, query exclue, ex. `^/[a-z]{2}-[a-z]{2}/l/campaign-.*$` (depuis v0.5.27). Mutuellement exclusif avec `path_prefix` ; motifs non ancrés, regex invalides, > 512 B et octets de contrôle rejetés ; compilés une seule fois au démarrage. Une route ultérieure entièrement couverte par une route antérieure (hôte, chemin, méthodes) est du dead config : rapportée en Error au boot, le boot continue |
| `match.methods` | Correspondance par méthodes HTTP |
| `pool` | Nom du upstream pool |
| `cache.ttl_default` | TTL par défaut si l'origine n'envoie pas d'en-têtes de fraîcheur |
| `cache.ttl_override` | Override le TTL interne de bouine. Depuis v0.5.29 l'override ne s'applique qu'aux réponses de succès et de redirection (statut < 400) — les réponses d'erreur stockables suivent l'échelle de TTL du negative caching (fraîcheur explicite de l'origine > `negative_ttl` > heuristique > `ttl_default`) au lieu d'être épinglées fraîches pour toute la durée de l'override |
| `cache.stale_while_revalidate` | Durée pendant laquelle le contenu périmé est servi pendant la revalidation |
| `cache.stale_if_error` | Durée pendant laquelle le contenu périmé est servi en cas d'erreur d'origine |
| `cache.negative_ttl` | TTL pour les réponses d'erreur cachables. Depuis v0.5.22 accepte aussi une map par statut — `negative_ttl: {404: 1m, 5xx: 10s, 410: 0}` (codes exacts 400–599, classes `4xx`/`5xx`, un code exact prime sur sa classe, `0` désactive ce statut) — qui prime sur `ttl_default`/fraîcheur heuristique pour les statuts couverts. Voir [Mise en cache négative](cache-policy/#negative-caching). |
| `cache.jitter_percent` | Pourcentage aléatoire appliqué au TTL |
| `cache.enabled` | Active ou désactive le cache pour cette route (par défaut: true) |
| `cache.bypass_on_cookie` | Si `true`, toute requête portant un en-tête `Cookie` non vide ne touche jamais le cache sur cette route : ni lookup, ni stockage, ni partage de fetch en cours — elle est proxiée vers l'origine (`X-Cache: BYPASS`). L'équivalent Varnish `return (pass)` pour `req.http.Cookie` ; conçu pour les routes SSR personnalisées (depuis v0.5.26). Voir [Cookie bypass](cache-policy/#cookie-bypass-since-v0526). |
| `cache.bypass_on_cookie_names` | Noms de cookies qui contournent entièrement le cache pour une requête qui en porte l'un d'eux — même contrat que `bypass_on_cookie`, limité aux noms listés (depuis v0.5.27). Les requêtes ne portant que des cookies non listés participent au cache selon RFC 9111. Correspondance insensible à la casse sur le token de nom, dans chaque position et sur chaque ligne `Cookie` répétée. Plafond 16 noms ; mutuellement exclusif avec `bypass_on_cookie`. Voir [Cookie-name bypass](cache-policy/#cookie-name-bypass-since-v0527). |
| `cache.bypass_on_user_agent` | Motifs glob `*` d'User-Agent qui contournent entièrement le cache (depuis v0.5.27) : la requête est proxiée vers l'origine avec `X-Cache: BYPASS`. Correspondance insensible à la casse sur la chaîne UA complète ; `*` est le seul joker ; un motif exact correspond à la chaîne entière (`*Bot*` pour une sous-chaîne). Plafond 16 entrées / 256 o. À déclarer une fois via `route_defaults.cache.bypass_on_user_agent`. Voir [User-Agent bypass](cache-policy/#user-agent-bypass-since-v0527). |
| `cache.key.cookie_presence` | Noms de cookies dont la **présence** (jamais la valeur) ajoute un bit de clé chacun à la clé de variante Vary (depuis v0.5.27) — pour les origines qui rendent un contenu différent selon l'existence d'un cookie de consentement. Plafond 16 noms (jusqu'à 2^N combinaisons) ; mutuellement exclusif avec les deux boutons de bypass ; identique sur tous les nœuds du cluster. Voir [Cookie presence keying](cache-policy/#cookie-presence-keying-since-v0527). |
| `cache.max_fetch_concurrency` | Nombre maximal de fetch origin simultanés pour cette route (défaut **256 depuis v0.6.0**, précédemment 32) |
| `cache.max_variants` | Plafond de variantes Vary distinctes stockées par clé primaire pour cette route (défaut intégré 1024, depuis v0.5.25 ; négatif rejeté, le plafond ne peut pas être désactivé ; `vary_cap_hits_total` s'incrémente quand il est atteint) |
| `cache.fetch_timeout` | Timeout origin par route (en-tête + corps). Sans valeur explicite, la route hérite de `connect.response_header_timeout` du pool (défaut 30s) ; avec une valeur, elle est appliquée telle quelle — une route peut dépasser le réglage du pool (sémantique depuis v0.5.11) |
| `cache.fetch_wait_timeout` | Durée d'attente d'un slot de fetch avant shedding (défaut 100ms, max 1s) : objet périmé servi si disponible, sinon 503 + `Retry-After: 1` |
| `request.forwarded` | Injection d'en-têtes d'identité client sur les fetchs vers l'origine (depuis v0.5.27) : `X-Forwarded-For` (ajoute l'adresse du peer immédiat de bouine, jamais de réécriture), `X-Forwarded-Proto` (le schéma reçu), `X-Forwarded-Host` (le Host reçu) et `Via: 1.1 bouine` (RFC 9110 §7.6.3). Quatre formes YAML : `standard` (les quatre en-têtes), une liste de tokens (`[client_ip, proto]`), l'opt-out (`false`/`none`), ou le mapping complet avec `max_append` (défaut 5, plage 1–64). Jamais sur le chemin de hit, jamais dans la clé de cache. Exige un pool ; mutuellement exclusif avec les `header_set` visant les mêmes en-têtes. À déclarer une fois via `route_defaults.request.forwarded`. Voir la section « En-têtes forwarded » ci-dessous |

### `route_defaults`

Déclare une fois des blocs par route au lieu de les répéter sur chaque route (depuis v0.5.27). Fusionnés dans chaque route avant validation ; seuls les deux blocs ayant des sémantiques de fusion définies sont acceptés — tout autre champ est rejeté au décodage.

```yaml
route_defaults:
  request:
    forwarded: standard        # hérité par toute route qui n'opte pas out
  cache:
    bypass_on_user_agent: ["*ShoppingFeedBot*"]
```

- **`request.forwarded`** : une route sans bloc `forwarded` hérite du défaut en entier ; un preset ou une liste de tokens **remplace** les drapeaux du défaut (seul `max_append` retombe dessus) ; la forme mapping fait un **OU** champ par champ ; `false`/`none` désactive pour la route. Les routes statiques ignorent le défaut hérité.
- **`cache.bypass_on_user_agent`** : chaque route sans liste propre hérite du défaut en entier ; la liste propre d'une route la **remplace** (jamais une union) ; une liste vide explicite (`[]`) désactive pour la route ; les routes statiques n'héritent de rien.

### `cluster`

| Champ | Description |
|------|-------------|
| `enabled` | Active le clustering |
| `mode` | `strong` ou `eventual` |
| `join[]` | Liste des adresses seed pour le gossip |
| `peer_max_idle_conn_duration` | Durée de vie des connexions peer inactives (défaut 120s). Doit rester **en dessous** de `admin.idle_timeout` (défaut 300s) — la validation de config rejette toute combinaison explicite qui viole cet ordre |
| `peer_fetch_concurrency` | RPC peer-fetch/put simultanés par nœud (plage 1–128, depuis v0.5.11 ; **défaut relevé à 64 en v0.6.0** — après 16 depuis v0.5.29 et 4 avant — car un pool trop petit fait attendre les peer hits derrière des fetchs en cours et ajoute de la latence de queue en mode strong). En mode strong la plupart des hits sont des peer hits : à augmenter avec `peer_max_conns_per_host` sous charge |
| `peer_tcp_fast_open` | Active le TCP Fast Open sortant (`TCP_FASTOPEN_CONNECT`) sur les dials peer — peer fetch/put et broadcast d'invalidation (depuis v0.5.29, défaut désactivé). Opt-in, Linux 4.11+ uniquement ; les dials bouine↔bouine utilisent TFO de bout en bout quand le côté répondant active aussi `listen.tcp_fast_open`. Advisory : un dial n'échoue jamais à cause de lui |
| `ban_ttl` | Durée de rétention des bans d'invalidation avant élagage par le reaper (défaut 24h, ≥ 1s si défini, depuis v0.5.20 ; **modifiable à chaud depuis v0.6.0** via `bouine config set cluster.ban_ttl 45m`) |
| `tls` | Configuration mTLS pour la communication entre peers |

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

### `metrics`

| Champ | Description |
|------|-------------|
| `traffic_classes` | Jusqu'à 8 populations de trafic nommées, appariées par motifs d'hôte (depuis v0.5.27). Ajoute un label `traffic_class` toujours présent sur `bouine_requests_total`, `bouine_request_duration_seconds` et `bouine_response_bytes_total`, plus un attribut `traffic_class` dans les logs d'accès. Chaque classe : un nom unique en minuscules (`unclassified` est réservé — le fallback) et jusqu'à 64 motifs d'hôte (hôte exact, `*.` initial ou `.*`/`*` final). L'ordre de déclaration est la précédence (premier match gagnant) ; une classe ultérieure entièrement masquée par une classe antérieure est rapportée en Error au boot, le boot continue. Voir [Supervision → traffic classes](/docs/operations/monitoring/#traffic-classes) |

```yaml
metrics:
  traffic_classes:
    - name: checkout
      hosts: ["checkout.example.com"]
    - name: marketing
      hosts: ["*.example.com"]   # correspondance par suffixe sur la frontière de label
```

### `admin`

| Champ | Description |
|------|-------------|
| `token` | Jeton bearer pour l'authentification de l'API d'administration |
| `idle_timeout` | Timeout keep-alive des connexions du serveur d'admin (défaut 300s), y compris les RPC peer du cluster (`/v1/peer/*`). Gardez `cluster.peer_max_idle_conn_duration` en dessous de cette valeur. |

## En-têtes forwarded

`routes[].request.forwarded` (depuis v0.5.27) injecte des en-têtes
d'identité client sur les requêtes **vers l'origine uniquement** — miss,
proxy invalidant (POST/PUT/DELETE), bypass, revalidation, streaming/SSE
et fetchs en arrière-plan. Le chemin de hit n'est pas touché, et ces
en-têtes n'entrent jamais dans la clé de cache ni dans les en-têtes de
requête stockés.

| En-tête | Token | Comportement |
|---|---|---|
| `X-Forwarded-For` | `client_ip` | Ajoute l'adresse du peer immédiat de bouine (l'edge) à la chaîne portée — les entrées existantes ne sont jamais réécrites |
| `X-Forwarded-Proto` | `proto` | **Fixé** au schéma sur lequel bouine a reçu la requête — pas celui utilisé vers l'origine |
| `X-Forwarded-Host` | `host` | **Fixé** au Host reçu par bouine ; indique à une origine multi-hôtes quel nom a été demandé — à apparier avec `connect.preserve_host` |
| `Via` | `via` | Ajoute `1.1 bouine` selon RFC 9110 §7.6.3 |

Quatre formes YAML :

```yaml
request:
  forwarded: standard           # les quatre en-têtes, une ligne
  forwarded: [client_ip, proto]  # exactement ces en-têtes
  forwarded: false              # opt-out explicite (tue un route_default)
  forwarded:                    # mapping complet, champ par champ
    client_ip: true
    proto: true
    max_append: 10              # plafond de chaîne, défaut 5 (plage 1–64)
```

Les chaînes XFF et `Via` sont plafonnées à `max_append` entrées (les plus
récentes — les plus à droite — sont conservées) et au budget de 8 KiB par
en-tête. Les fetchs en arrière-plan (revalidation SWR, refresh-before-expiry,
recharge après shed) injectent proto/host/`Via` mais n'ajoutent jamais
`X-Forwarded-For` — il n'y a pas de peer vivant, et rejouer l'adresse du
demandeur original attribuerait l'identité d'un utilisateur à un refresh
anonyme. `forwarded` exige un pool (rejeté sur les routes statiques).

## TCP Fast Open

bouine prend en charge TCP Fast Open sur trois surfaces, toutes
**désactivées par défaut depuis v0.5.29** (précédemment, un
`listen.tcp_fast_open` non défini signifiait « activé sur Linux ») :

| Surface | Clé | Direction |
|---|---|---|
| Listeners data-plane | `listen.tcp_fast_open` | TFO côté serveur sur les accepts |
| Dials origine | `upstream_pools[].connect.tcp_fast_open` | `TCP_FASTOPEN_CONNECT` côté client, par pool |
| Dials peer | `cluster.peer_tcp_fast_open` | `TCP_FASTOPEN_CONNECT` sur peer fetch/put et broadcast d'invalidation |

Avec un cookie TFO mis en cache par le noyau, les premiers octets de
requête partent dans le paquet SYN — un RTT complet économisé sur chaque
nouvelle connexion. L'option est advisory : des peers ou origines sans TFO
côté serveur n'émettent jamais de cookie et le dial retombe silencieusement
sur le handshake habituel, donc il n'y a aucun coût à l'activer. Linux
uniquement (4.11+ côté client ; no-op ailleurs) ; le noyau est sondé une
fois au démarrage. Les dials bouine↔bouine utilisent TFO de bout en bout
quand les deux côtés l'activent — `cluster.peer_tcp_fast_open` côté
appelant, `listen.tcp_fast_open` côté répondant — et les noyaux des peers
doivent avoir `net.ipv4.tcp_fastopen` avec le bit serveur.

> **Note de mise à jour (v0.5.29) :** les déploiements qui comptaient sur
> l'ancien défaut côté listener doivent définir `listen.tcp_fast_open: true`
> explicitement après la mise à niveau.

## Configuration à chaud

Depuis v0.6.0, deux surfaces d'exécution existent en complément du redémarrage :

- **Boutons de configuration à chaud** (`bouine config get/set/diff`, `GET|POST /v1/config/hot`) : modifient des champs réellement appliquables à chaud sur un démon en cours d'exécution. Boutons actuels : `cluster.ban_ttl`, `url_ring_sample_rate`, et par pool `pool:<name>.health.passive.consecutive_5xx` / `pool:<name>.health.passive.eject_for`. Les overrides runtime sont éphémères (perdus au redémarrage, dérive visible via `bouine config diff`) et `bouine config set` se propage à tous les peers vivants en mode strong (`POST /v1/peer/config/hot`).
- **`bouine config reload` / `POST /v1/config/reload`** (expérimental, derrière `experimental.config_reload`) : ré-applique un fichier de config à un démon en cours, applique le sous-ensemble à chaud, et rapporte applied / unchanged / NEEDS RESTART.

```bash
bouine config get
bouine config set cluster.ban_ttl 45m
bouine config set cluster.ban_ttl 45m --dry-run
bouine config diff
bouine config reload --file /etc/bouine/config.yaml
```
