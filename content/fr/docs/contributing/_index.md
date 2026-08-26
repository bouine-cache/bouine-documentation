---
title: "Contribuer"
weight: 6
description: "Guide du contributeur couvrant la configuration locale, le flux de développement, le format des commits, les vérifications de pull request et les standards du projet."
---


Merci d'améliorer bouine. Ce projet valorise l'exactitude, la performance et la clarté opérationnelle.

## Pages

- [Guide du code](codebase/) — carte des packages et bonnes premières tâches.
- [Sécurité](security/) — signalement de vulnérabilités et notes de durcissement.

## Prérequis

- Go 1.27+
- `pre-commit` (`pip install pre-commit` ou `brew install pre-commit`)
- Docker (pour les tests d'intégration)

## Configuration

```bash
git clone https://github.com/bouine-cache/bouine.git
cd bouine
make hooks
make all
```

## Flux de travail

1. **S'orienter** — lisez `PLAN.md` et la documentation des packages pertinents.
2. **Planifier** — décidez des tests avant le code.
3. **Implémenter** — le plus petit changement utile.
4. **Vérifier** — `make all` ; `make bench` si vous touchez L1–L6.
5. **Documenter** — mettez à jour les runbooks ou la documentation de configuration lorsque le comportement change.

## Format des commits

```text
feat(cache): add negative caching for 404 responses
fix(cluster): retry join until actual peers discovered
docs(runbook): document cluster join retry
```

Préfixes autorisés : `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`.

## Checklist de PR

- [ ] `pre-commit run --all-files` passe
- [ ] `make all` passe
- [ ] Tests ajoutés ou mis à jour
- [ ] Pas de régression des cache-tests pour les changements de cache
- [ ] Pas de régression des benchmarks pour les changements du hot path
- [ ] Pas de secrets, jetons ou noms d'hôtes de production
