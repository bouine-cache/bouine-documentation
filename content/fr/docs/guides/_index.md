---
title: "Guides"
weight: 5
description: "Guides pas à pas pour migrer depuis Varnish ou NGINX, modèles d'intégration et planification de capacité."
---


- [Migration depuis Varnish](varnish-migration/) — comparaison côte à côte VCL vs YAML, parité purge/ban, correspondance d'observabilité, différences de comportement et FAQ.
- [Migration depuis NGINX](nginx-migration/) — mappez les directives `proxy_cache` NGINX vers la configuration bouine.
- [Exemples de proxy inverse](reverse-proxies/) — déployez bouine devant Caddy, Traefik, HAProxy et nginx.
- [Planification de capacité](capacity-planning/) — dimensionnez les niveaux hot et warm, choisissez le mode de cluster et les réplicas, validez sous charge.
- [Checklist de mise en production](production-checklist/) — vérifiez TLS, ressources, cluster, cache, observabilité et paramètres K8s avant la mise en service.
- [Compatibilité avec les service mesh](service-mesh/) — exécutez bouine aux côtés d'Istio, Linkerd et Cilium.
- [Benchmarks](benchmarks/) — méthodologie et résultats comparant bouine à Varnish, NGINX et Envoy sur des charges cache hit, miss et mixtes.
