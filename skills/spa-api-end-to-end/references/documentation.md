# Documentation : quoi mettre à jour

La documentation se met à jour dans la même évolution que le code, jamais « plus tard ». Elle dit ce que le code ne montre pas ; ne pas raconter la modification.

| Élément | Où | Contenu à mettre à jour |
|---|---|---|
| Domaine | `domains/<nom>/<nom>.md` du dépôt `.github` | Règles métier, contrat API et SPA, points sensibles, date « État au ». Voir [gabarit](./domain-contract-template.md) |
| API métier | `README.md` du dépôt | Description, tableau endpoint → permission, proxies appelés, clés de configuration, tables Flyway, lancement local. Le détail de chaque endpoint est dans `@Operation` (et `@ApiResponse`) du contrôleur ou de l'interface `IApiXxx` |
| `api-proxy-*` | `README.md` du dépôt | Système encapsulé, endpoints exposés, clé `api.proxy-<x>.url`, client OAuth |
| Socle Maven | `README.md` du module modifié (un README par `pom.xml`) | Ce qui a été ajouté ou changé, version |
| Socle npm | `README.md` ou `docs/` du package modifié | Idem |
| SPA | `docs/README.md` | Vocabulaire et liste des pages |
| SPA | `docs/fonctionnalites/<page>.md` | Une page par fonctionnalité : but, parcours, permissions, appels API |
| SPA | `docs/domaine.md`, `docs/api.md`, `docs/architecture.md` | Règles métier côtés SPA, appels et contrat, structure |
| SPA | `docs/securite-roles.md` | Toute nouvelle permission, toute page ajoutée ou supprimée |
| SPA | `README.md` du dépôt | Description, lancement, variables `VITE_*` |
| Modèle sémantique | Descriptions TMDL | Colonnes et mesures ajoutées ou modifiées |

## Règles

- Une permission ajoutée apparaît dans `docs/securite-roles.md` de la SPA, dans le tableau endpoint → permission du README de l'API et dans le contrat de domaine, avec la même orthographe.
- Un paramètre de configuration ajouté apparaît dans la liste des clés de configuration du README de l'API.
- Une page supprimée emporte sa documentation.
- Un README créé n'est pas un document de synthèse de la session : il décrit l'état du dépôt.
