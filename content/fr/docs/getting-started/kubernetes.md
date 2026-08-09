---
title: "Kubernetes"
weight: 4
description: "Déployez bouine sur Kubernetes avec Helm, configurez le gossip StatefulSet, vérifiez la découverte des pairs et effectuez des rolling updates."
---


## Ajouter le dépôt de charts

bouine publie un dépôt de charts Helm à l'adresse **`https://charts.bouine.org`**,
indexé sur [Artifact Hub](https://artifacthub.io/packages/search?repo=bouine).
Le chart récupère l'image `bouinecache/bouine` depuis Docker Hub par défaut.

```bash
helm repo add bouine https://charts.bouine.org
helm repo update
helm search repo bouine
```

```text
NAME            CHART VERSION   APP VERSION     DESCRIPTION
bouine/bouine   0.1.0           0.1.0           Cloud-native HTTP cache in Go ...
```

## Démarrage rapide Helm

```bash
helm install bouine bouine/bouine \
  --namespace bouine --create-namespace \
  --set "config.upstream_pools[0].name=app" \
  --set "config.upstream_pools[0].targets[0]=app.default.svc:8080" \
  --set "config.routes[0].pool=app"
```

Cela déploie un StatefulSet avec clustering par gossip, un Service headless pour
la découverte des pairs et un PodDisruptionBudget.

Pour installer depuis un checkout local au lieu du dépôt, pointez Helm vers
le répertoire du chart :

```bash
helm install bouine deploy/helm/bouine --namespace bouine --create-namespace ...
```

Consultez la [référence du chart Helm](/docs/configuration/helm/) pour toutes les valeurs configurables.

## Prérequis du StatefulSet

Pour un clustering multi-pods, utilisez un StatefulSet et un Service headless avec `publishNotReadyAddresses: true`. Voir [Clustering → Service headless](/docs/configuration/cluster-modes/#headless-service-kubernetes) pour le manifeste complet.

## Jeton d'administration (exigence multi-pods)

Tous les pods **doivent partager le même `admin.token`**. Voir [Authentification](/docs/operations/authentication/) pour les instructions de configuration.

## Mise à l'échelle

```bash
kubectl scale statefulset/bouine -n bouine --replicas=3
kubectl exec bouine-0 -n bouine -- /bouine cluster peers
```

## Mises à jour progressives

```bash
kubectl rollout restart statefulset/bouine -n bouine
kubectl rollout status statefulset/bouine -n bouine
```

bouine se marque comme not-ready pendant l'arrêt et quitte proprement le cluster gossip. Voir [Opérations Kubernetes](/docs/operations/kubernetes/) pour les procédures de rolling update sans 5xx.
