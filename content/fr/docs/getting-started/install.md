---
title: "Installation"
weight: 1
description: "Installez bouine depuis Docker Hub, les binaires de releases GitHub ou les sources, et comprenez les prérequis de chaque méthode."
---


## Docker

Le moyen le plus rapide d'exécuter bouine est l'image Docker :

```bash
docker pull bouinecache/bouine:latest
docker run --rm -p 8080:80 -p 9000:9000 bouinecache/bouine:latest
```

L'image par défaut inclut une configuration minimale dans `/etc/bouine/config.yaml` afin que le conteneur démarre sans montage de volume.

> **Pour la production**
>
> Montez votre propre configuration dans `/etc/bouine/config.yaml`, ou utilisez le chart Helm pour que Kubernetes gère la ConfigMap.

## Releases GitHub

Téléchargez le dernier binaire de release depuis [GitHub Releases](https://github.com/bouine-cache/bouine/releases). La commande ci-dessous est présélectionnée pour votre système d'exploitation et votre architecture CPU — changez d'onglet si vous avez besoin d'une cible différente :

{{< install-binary >}}

La commande en une ligne résout automatiquement la dernière version, elle ne devient donc jamais obsolète. Les binaires sont publiés pour :

| OS | Architectures |
|---|---|
| Linux | `amd64`, `arm64` |
| macOS | `amd64`, `arm64` |
| Windows | `amd64`, `arm64` |

> **Vérifier le téléchargement**
>
> Chaque release est livrée avec `SHA256SUMS` (avec une signature cosign `SHA256SUMS.sig` et un certificat `SHA256SUMS.pem`). Vérifiez la somme de contrôle après le téléchargement si vous avez besoin d'une garantie sur la supply chain.

## Depuis les sources

```bash
git clone https://github.com/bouine-cache/bouine.git
cd bouine
make build
./bin/bouine version
```

Prérequis :

- Go 1.26+
- `golangci-lint` si vous souhaitez exécuter `make lint`
- Docker si vous souhaitez builder des images ou exécuter des tests d'intégration
