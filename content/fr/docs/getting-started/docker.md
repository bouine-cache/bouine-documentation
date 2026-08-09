---
title: "Docker"
weight: 3
description: "Exécutez l'image Docker officielle de bouine, montez une configuration personnalisée et construisez des images multi-architectures rapides localement."
---


## Exécuter l'image officielle

```bash
docker run --rm \
  -p 8080:80 \
  -p 9000:9000 \
  bouinecache/bouine:latest
```

## Monter un fichier de configuration

```bash
docker run --rm \
  -p 8080:80 \
  -p 9000:9000 \
  -v "$PWD/config.yaml:/etc/bouine/config.yaml:ro" \
  bouinecache/bouine:latest
```

## Construire localement

Sur Apple Silicon ciblant un cluster Linux amd64 :

```bash
docker buildx build --platform linux/amd64 \
  -t bouinecache/bouine:latest \
  --push .
```

Pour des tests locaux sur votre machine :

```bash
docker build -t bouine:dev .
docker run --rm -p 8080:80 -p 9000:9000 bouine:dev
```

Le Dockerfile utilise `BUILDPLATFORM`/`TARGETARCH` pour que Go effectue une compilation croisée native au lieu d'exécuter le compilateur sous QEMU.
