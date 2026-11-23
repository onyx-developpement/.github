---
name: spa-api-end-to-end
description: "Créer ou faire évoluer une fonctionnalité de SPA React et l'API métier Spring qui la porte, de bout en bout : écran, route, permission, endpoint, DTO propres à la SPA, orchestration des api-proxy-*, paramètres en configuration ou en base, socles npm et Maven, domaine métier et contrat de domaine, documentation. À utiliser pour ajouter une page, un écran, un endpoint, un paramètre métier, une permission, appeler un autre système via un proxy, créer une nouvelle SPA ou une nouvelle API métier, ou quand une fonctionnalité manque dans un socle partagé. Mots-clés : nouvelle fonctionnalité, nouvelle page, nouvelle SPA, nouvelle API, api-proxy, configuration, Key Vault, paramétrage métier, frontend-config, domaine, contrat de domaine, socle, @nutriset/react, commons, permission, documentation."
---

# SPA et API métier de bout en bout

Une fonctionnalité de SPA ne se limite jamais à la SPA : l'API métier doit presque toujours évoluer avec elle, et le domaine métier doit rester documenté. Ce skill sert de fil conducteur ; le détail de chaque couche est dans les instructions du dépôt concerné.

Pour un changement de table ou de colonne (Flyway, Debezium, Gold, modèle sémantique), utiliser le skill `schema-change-end-to-end` : ce skill lui délègue la chaîne de données à l'étape 8.

## Étape 0 : création ou évolution ?

| Situation | Procédure |
|---|---|
| Fonctionnalité nouvelle ou évolution dans une SPA et une API qui existent | Étapes 1 à 11 |
| Nouvelle SPA, nouvelle API métier ou nouvel `api-proxy` | Lire d'abord la [checklist de création](./references/creation-checklist.md) : tout ce qui est manuel (dépôts, topics, app registration, Terraform, pipelines) est à lister pour l'utilisateur, puis étapes 1 à 11 |

Demander à l'utilisateur de confirmer la situation si elle n'est pas évidente.

## Étape 1 : rattacher au domaine métier

1. Chercher dans `.github/domains/` du dépôt (déposé par topic `domain-<nom>`) le domaine concerné ; à défaut, dans le dépôt `.github` de l'organisation.
2. **Domaine existant :** le lire avant de concevoir (règles métier, contrat API et SPA, points sensibles). Il sera mis à jour à l'étape 10.
3. **Domaine inexistant :** proposer son nom à l'utilisateur et créer `domains/<nom>/<nom>.md` depuis le [gabarit](./references/domain-contract-template.md), ainsi que `workspaces/<nom>.code-workspace` (chemins relatifs, tous les dépôts du domaine plus `.github`). Rappeler que les dépôts doivent porter le topic `domain-<nom>` pour recevoir le contrat : action manuelle.

## Étape 2 : cartographier l'impact

Produire un tableau d'impact, couche par couche, et le présenter avant de coder :

| Couche | Dépôt | Modifié / non concerné / à faire par un tiers |
|---|---|---|
| Socle npm | `npm-nutriset-react-packages` | |
| Socles Maven | `maven-fr.nutriset.*` | |
| `api-proxy-*` | un dépôt par proxy | |
| Configuration | `configuration` | |
| Base (Flyway) | dépôt de l'API métier | |
| API métier | dépôt de l'API métier | |
| SPA | dépôt de la SPA | |
| Chaîne de données | `debezium-cdc`, `configuration`, `WK_GOLD_*` | |
| Contrat de domaine et documentation | `.github`, README, `docs/` | |

## Étape 3 : plan par phases

Un plan est obligatoire avant toute création ou modification, sauf modification triviale d'un seul fichier : règles communes « Plan, modèle et contexte ». Phases habituelles : socles et proxies, configuration et base, API, SPA, chaîne de données, documentation.

## Étape 4 : décisions à poser à l'utilisateur

Ne pas trancher seul, poser la question avec les options :

- **Permission :** réutiliser une permission existante (en proposer une pertinente) ou en créer une. À chaque ajout, y compris mineur.
- **Contrat d'API :** nom et forme d'un champ ou d'un paramètre, compatibilité avec l'ancien contrat.
- **Flyway :** modifier, regrouper ou renuméroter un script appliqué.
- **Chaîne de données :** la fonctionnalité doit-elle alimenter Debezium et Fabric ? Si oui, déléguer à `schema-change-end-to-end` à l'étape 8.
- **Fonctionnalité manquante dans un socle :** corriger le socle (étape 6) ou contourner.

## Étape 5 : classer chaque paramètre

Pour chaque valeur que la fonctionnalité introduit, décider où elle vit, avec [configuration](./references/configuration.md) :

| Nature | Où |
|---|---|
| Valeur technique propre à un environnement (URL, délai, identifiant) | Dépôt `configuration`, jamais en dur ni dans `src/main/resources` |
| Secret | Key Vault, référencé `${nom}` dans la configuration |
| Valeur gérée par les utilisateurs métier | Table en base (Flyway) avec endpoints CRUD, permission d'écriture et écran SPA |
| Valeur lue par la SPA avant connexion | `GET /frontend-config` de l'API ; la SPA ne porte que `VITE_API_URL` |

## Étape 6 : socles npm et Maven

Un besoin technique transverse sans règle métier qui manque dans un socle se corrige dans le socle, pas dans l'application : voir [socles et versions](./references/socles-et-versions.md) (modification, semver, montée de version chez les consommateurs, publication par l'utilisateur).

## Étape 7 : où va chaque appel et chaque modèle

La SPA n'appelle que son API métier. L'API métier orchestre les `api-proxy-*`. Les DTO exposés à la SPA sont propres à la SPA ; les modèles partagés entre API vont dans `fr.nutriset.components:commons`. Détail dans [orchestration et modèles](./references/orchestration-et-modeles.md).

## Étape 8 : exécuter dans cet ordre

Valider chaque couche avant la suivante :

1. **Socles** (npm, Maven) et **proxies** : version publiée avant d'être consommée.
2. **Configuration** : dépôt `configuration`, les permissions avant l'API (elle refuse de démarrer si une permission n'est accordée à aucun rôle, dans les trois environnements). Production seulement sur demande explicite.
3. **Base** : migration Flyway des tables de paramétrage.
4. **API métier** : entité, DTO propres à la SPA, mapper, service, appel des proxies, contrôleur et permissions, tests. Voir la couche API du skill `schema-change-end-to-end`.
5. **SPA** : modèle, `ApiControleGestion`, `BusinessService`, mock, page, route verrouillée par `RequirePermission`, entrée de menu, tests. Voir la couche SPA du skill `schema-change-end-to-end`.
6. **Chaîne de données** si décidée à l'étape 4 : suivre `schema-change-end-to-end` à partir de son étape 1.

## Étape 9 : documenter

Systématique, voir [documentation](./references/documentation.md) : README de l'API (et des proxies, socles), `docs/` de la SPA, contrat de domaine.

## Étape 10 : mettre à jour le contrat de domaine

Dans le dépôt `.github` uniquement : règles métier, contrat API et SPA (endpoints, permissions, DTO), points sensibles, chaîne de données si elle change. Mettre à jour la date « État au ».

## Règles à ne jamais enfreindre

- Ne jamais publier un socle : c'est le développeur qui le fait.

## Étape 11 : vérifier et conclure

- Lancer les vérifications de chaque dépôt touché, celles de ses instructions (tests, typage, lint).

Compte rendu final :

1. Tableau d'impact par couche.
2. Actions manuelles restantes (topics, app roles, Terraform, publication des socles, configuration de production, déploiement, réplication).
3. Documentation mise à jour (contrat de domaine, README, `docs/`).
4. Ce qui n'a pas pu être vérifié.
5. Mention explicite qu'aucun commit n'a été fait.
