---
title: "Sécurité"
weight: 3
description: "Signalement de sécurité, périmètre pris en charge, classes de vulnérabilités à fort impact et checklist de durcissement opérationnel pour bouine."
---


Signalez les problèmes de sécurité via le
[Signalement privé de vulnérabilités](https://github.com/bouine-cache/bouine/security/advisories/new)
de GitHub — cela crée un avis suivi et embargoé. Aucun alias e-mail de sécurité n'est
publié.

## Périmètre

- Binaire bouine
- Chart Helm
- Image conteneur
- SDK Go

## Exemples de problèmes à fort impact

- Cache poisoning qui fuit la réponse d'un utilisateur vers un autre
- HTTP request smuggling à travers le data plane
- Contournement de l'authentification de l'API d'administration
- Peer impersonation en mode cluster
- Path traversal dans le stockage de warm tier

## Checklist de durcissement

- Gardez le port d'administration privé ; exposez-le uniquement via le réseau interne ou mTLS.
- Utilisez la vérification TLS pour les upstreams.
- Exécutez les conteneurs en tant que non-root.
- Utilisez des NetworkPolicy pour les ports de cluster et d'administration.
- Surveillez les taux de purge/ban pour détecter les abus.
- Ne journalisez pas les corps de requête/réponse ni les identifiants.
