---
title: "Streaming et réponses live"
weight: 2
description: "Comment bouine streame les corps de réponse, sert les Server-Sent Events et shedde la charge excessive quand l'origine est lente."
---

bouine ne bufferise jamais un corps de réponse quand ce n'est pas nécessaire.
Cette page documente les trois comportements de streaming et les deux
protections de surcharge qui y interagissent.

## Server-Sent Events (SSE)

bouine sert les Server-Sent Events comme des **flux live de bout en bout**.
Une requête annonçant `Accept: text/event-stream` (le contrat client WHATWG
— ce qu'envoient les navigateurs, `EventSource` et les SDK d'IA) est servie
en flux non bufferisé, jamais mise en cache, et jamais fusionnée par
singleflight sur le flux d'un autre client.

```yaml
routes:
  - match: { path_prefix: /chat/ }
    pool: llm
    cache:
      ttl_default: 60s
```

Aucune configuration au niveau de la route n'est requise : l'en-tête
`Accept` est le contrat. Le SSE basé sur POST (la forme dominante des API
d'IA — un corps de requête suivi d'une réponse streamée) fonctionne de la
même façon, et ses sémantiques d'[invalidation par méthode d'écriture](../cache-policy/#write-method-invalidation-postputdelete)
sont préservées : une réponse 2xx/3xx purge l'entrée de cache concernée au
moment des en-têtes, pas après le corps (interminable).

### Contrat de service SSE

| Comportement | Détail |
|---|---|
| `X-Cache` | `BYPASS` — la lecture du cache est entièrement ignorée |
| Stockage | Jamais stocké |
| Singleflight | Jamais fusionné ; chaque client reçoit son propre fetch origin |
| Slot de fetch | Libéré au moment des en-têtes — un flux live ne consomme pas de slot `max_fetch_concurrency` |
| Flush | Chaque événement est flushé au client dès son arrivée |
| Budget de lecture origin | Budget d'inactivité de 10 minutes, réinitialisé à chaque événement — un flux actif n'est jamais coupé par l'horloge |
| Budget d'écriture client | Basé sur l'inactivité (5 min réarmés par écriture sur le fast path H1, 1 h absolu sans lui) |

Les deux dernières lignes sont la propriété clé : un flux dont l'origine
continue d'envoyer des événements reste ouvert indéfiniment, tandis qu'un
pair mort ou un client qui cesse de lire est quand même coupé.

### SSE non annoncé

Une origine peut répondre `Content-Type: text/event-stream` à une requête
qui n'avait pas annoncé l'en-tête `Accept`. Ces réponses sont quand même
streamées sans bufferisation, mais elles sont **bornées par le
`fetch_timeout` de la route** (le deadline de lecture de la connexion
origin était armé avant que la réponse soit connue comme un flux). Corrigez
le client pour envoyer l'en-tête ; n'augmentez pas `fetch_timeout`. Les
requêtes concurrentes non annoncées pour la même URL ne sont pas fusionnées
sur un seul flux — rien n'est bufferisé, donc il n'y a pas de résultat
partageable.

### Réglage des routes SSE

- **Flux d'événements épars** (écarts > 10 min sans heartbeat) : ne changez
  rien. L'origine doit envoyer des heartbeats (commentaires SSE), sinon le
  flux est coupé après le budget d'inactivité de 10 minutes et les clients
  se reconnectent.
- **Nombreux flux simultanés** : chaque flux occupe une connexion client et
  une connexion origin pendant toute sa durée. Augmentez
  `upstream_pools[].connect.max_connections` (défaut 64) sur les pools qui
  desservent des routes SSE lourdes, et `listen.max_connections` pour le
  data plane. `max_fetch_concurrency` n'a **pas** besoin d'être augmenté —
  les flux libèrent leur slot au moment des en-têtes.
- **Origines bloquées** : un fetch annoncé dont l'origine accepte la
  connexion mais n'envoie jamais d'en-têtes immobilise un slot de fetch
  pendant le budget d'inactivité de 10 minutes (au lieu de
  `response_header_timeout`). Seules les requêtes annonçant explicitement
  une intention de flux prennent ce chemin.

### Modes de défaillance

| Symptôme | Cause |
|---|---|
| Le flux se termine après ~10 min de silence | Budget d'inactivité atteint — l'origine a cessé d'envoyer sans heartbeat |
| Le flux se termine à exactement `fetch_timeout` | Le client n'a pas envoyé `Accept: text/event-stream` (chemin non annoncé) |
| Le flux se termine à 1 h avec le fast path désactivé | Comportement attendu sur le chemin fasthttp standard ; activez `experimental.h1_fast_path` ou comptez sur la reconnexion des clients |
| `503 + Retry-After` au démarrage du flux | File de fetch pleine pendant `fetch_wait_timeout` — augmentez `max_fetch_concurrency` ou investiguez la latence origin |

## Miss en streaming

Les misses cachables sont streamés au client pendant que le corps est teed
vers le stockage en arrière-plan, si bien que le client n'attend pas le
corps complet avant le premier octet. Les buffers de tee sont plafonnés :

- Par flux : `max_response_bytes` (le fetch est interrompu avec 502 au-delà).
- Par route : `max_streaming_buffer_bytes` — le total des octets détenus
  dans les buffers tee actifs des misses concurrents de la route. Quand le
  plafond est atteint, les nouveaux misses cachables retombent en
  bufferisation synchrone (le client attend le corps complet). Le défaut
  dérive de GOMEMLIMIT (7 %), avec un plancher intégré de 64 Mio.
  Surveillez `bouine_streaming_buffer_bytes` et
  `bouine_streaming_fallback_total` pour voir la pression.

## Shedding des fetch origin

Les origines lentes sont le mode de défaillance classique d'un reverse
proxy : les goroutines de requête se mettent en attente d'un slot de
fetch, s'accumulent sans limite, et le pod entre dans un livelock sans
recouvrement. bouine shedde à la place.

Quand un miss au premier plan ne peut pas acquérir un slot de fetch origin
(borné par `max_fetch_concurrency` par route) dans `fetch_wait_timeout`
(défaut 100 ms, max validé 1 s) :

1. Un **objet périmé dans le périmètre est servi périmé** (style RFC 5861), ou
2. le client reçoit **503 + `Retry-After: 1`** — distinct du mapping 502
   des échecs d'origine.

Les followers singleflight et des flux en cours se déparquent avec le
résultat sheddé du leader. Le compteur `bouine_fetch_shed_total` expose le
taux de shedding pour l'alerting.

```yaml
routes:
  - match: { path_prefix: / }
    pool: app
    cache:
      max_fetch_concurrency: 32
      fetch_wait_timeout: 100ms
```

La borne d'attente sert à absorber les rafales sous la seconde dans la
file de fetch, pas à faire la queue pendant une surcharge soutenue :
quand le taux d'arrivée dépasse le taux de vidange, aucune attente finie
ne vide la file, et une borne plus longue ne fait que retenir les
goroutines (et leurs connexions) plus longtemps avant de les shedder.
Augmentez `max_fetch_concurrency` ou scalez horizontalement plutôt que
d'augmenter `fetch_wait_timeout`.