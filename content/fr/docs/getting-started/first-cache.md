---
title: "Démarrage rapide"
weight: 2
description: "Démarrez un petit serveur d'origine, placez bouine devant celui-ci et vérifiez le comportement MISS puis HIT via les en-têtes et les métriques."
---


Démarrez un petit serveur d'origine :

```bash
mkdir -p /tmp/bouine-origin
printf 'hello from origin\n' > /tmp/bouine-origin/index.html
python3 -m http.server 3000 --directory /tmp/bouine-origin
```

Créez `config.yaml` :

```yaml
listen:
  http: ":8080"
  admin: ":9000"

storage:
  hot_max_bytes: 256Mo

upstream_pools:
  - name: origin
    targets: ["127.0.0.1:3000"]

routes:
  - match: { path_prefix: / }
    pool: origin
    cache:
      ttl_default: 60s
      stale_while_revalidate: 10s
      stale_if_error: 300s
```

Exécutez bouine :

```bash
bouine serve --config config.yaml --log-format json
```

Vérifiez la mise en cache :

```bash
curl -sI http://127.0.0.1:8080/ | grep X-Cache
# X-Cache: MISS

curl -sI http://127.0.0.1:8080/ | grep X-Cache
# X-Cache: HIT
```

Vérifiez la santé et les métriques :

```bash
curl -s http://127.0.0.1:9000/healthz
curl -s http://127.0.0.1:9000/readyz
curl -s http://127.0.0.1:9000/metrics | grep bouine_requests_total
```

## Que s'est-il passé ?

1. La première requête n'avait pas d'objet en cache → bouine a récupéré la réponse depuis l'origine et l'a stockée.
2. La deuxième requête a trouvé un objet frais dans le hot tier → bouine l'a servie immédiatement.
3. La réponse avait `X-Cache: HIT` et le journal d'accès incluait `cache_status=HIT`.

## Alternative : servir des fichiers sans serveur d'origine

bouine peut servir des fichiers directement depuis un répertoire local — pas besoin
d'exécuter un serveur HTTP distinct. Voir [Servir des fichiers statiques](/docs/configuration/static-files/)
pour la référence complète.

```bash
mkdir -p /tmp/bouine-static
printf 'hello from disk\n' > /tmp/bouine-static/index.html
```

Créez `config.yaml` :

```yaml
listen:
  http: ":8080"
  admin: ":9000"

routes:
  - match: { path_prefix: / }
    static:
      root: /tmp/bouine-static
      index: [index.html]
```

Exécutez bouine :

```bash
bouine serve --config config.yaml --log-format json
```

```bash
curl -sI http://127.0.0.1:8080/ | grep Content-Type
# Content-Type: text/html; charset=utf-8
```

Les routes statiques servent depuis le disque à chaque requête. Le cache de pages
de l'OS gère la mise en cache chaude en RAM. Pour activer la couche de cache de
bouine (pour la réplication en cluster ou l'éviction basée sur le TTL), définissez
`cache.enabled: true` sur la route.
