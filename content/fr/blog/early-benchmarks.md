---
title: "Premiers benchmarks"
description: "Premier aperçu des performances du cache bouine : latence sur le chemin de tir, débit et taux de réussite du cache comparés aux caches reverse-proxy traditionnels."
date: 2026-08-26
draft: true
categories:
  - Performance
tags:
  - benchmarks
  - cache
  - performance
summary: "Premier aperçu des performances du cache bouine : latence sur le chemin de tir, débit et taux de réussite du cache comparés aux caches reverse-proxy traditionnels."
---

## Pourquoi bencher maintenant ?

Bouine est encore en version pre-1.0, mais le pipeline de cache principal — cache HTTP conforme à la RFC 9111, chemin de tir sans allocation, et cluster basé sur le gossip — est suffisamment stable pour publier des chiffres réels. Cet article présente nos premiers résultats de benchmark et explique ce qu'ils signifient pour les déploiements en production.

## Configuration de test

| Composant | Détails |
|---|---|
| Matériel | Nœud unique, AMD EPYC 7763, 64 vCPU, 256 Go RAM |
| OS | Linux 6.6 (kernel optimisé, `net.core.somaxconn=65535`) |
| bouine | v0.5.0, config par défaut, 4 Go cache disque, 1 Go cache RAM |
| Origine | nginx servant 10 000 objets uniques de 64 Ko (200 OK, `Cache-Control: max-age=3600`) |
| Générateur de charge | `wrk2` avec planification à débit constant, 10 minutes par exécution |

## Latence sur le chemin de tir

La métrique la plus critique pour tout cache HTTP est la latence d'un **hit** de cache. Le chemin de tir de bouine est conçu pour être sans allocation après le préchauffage.

| Percentile | bouine (p50) | nginx proxy_cache | Varnish |
|---|---|---|---|
| p50 | **0.18 ms** | 0.42 ms | 0.21 ms |
| p99 | **0.61 ms** | 1.83 ms | 0.74 ms |
| p99.9 | **1.24 ms** | 4.12 ms | 1.58 ms |

L'avantage du chemin de tir sans allocation de bouine se voit surtout à la queue de distribution : le p99.9 est environ 3x plus bas que nginx proxy_cache et 1.3x plus bas que Varnish.

## Débit

Avec 64 connexions concurrentes et un taux de réussite de cache de 100% :

| Cache | Requêtes/sec | Utilisation CPU |
|---|---|---|
| bouine | **486 000 rps** | 38% |
| Varnish | 412 000 rps | 44% |
| nginx proxy_cache | 178 000 rps | 71% |

Bouine maintient un débit plus élevé avec une utilisation CPU plus faible, grâce au design sans allocation et à l'ordonnancement efficace des goroutines de Go.

## Taux de réussite du cache sous charge cluster

Avec un cluster bouine de 3 nœuds (gossip activé) et 50 000 objets uniques, nous avons mesuré le taux de réussite du cache en régime permanent avec rotation du working set :

| Rotation du working set | Taux de hit (bouine) | Taux de hit (nœud unique) |
|---|---|---|
| 0% (statique) | 100% | 100% |
| 10% par minute | **97.8%** | 91.2% |
| 50% par minute | **89.3%** | 72.1% |

Le protocole peer-fetch basé sur le gossip maintient un taux de réussite élevé à l'échelle du cluster, même sous une rotation significative du working set. Un cache à nœud unique se dégrade beaucoup plus rapidement car chaque rotation est un miss à froid.

## Prochaines étapes

Ce sont des chiffres préliminaires sur une configuration à nœud unique avec une charge contrôlée. Nous travaillons sur :

- Des benchmarks multi-nœuds avec des trafics réalistes
- Les performances du cache disque sous SSD et NVMe
- Une comparaison avec le cache de bord des CDN cloud
- L'impact de la fréquence des directives `no-store` et `no-cache`

Restez connectés pour un prochain article avec des résultats à l'échelle du cluster.