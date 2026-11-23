# Gabarit du contrat de domaine

Copier ce gabarit dans `domains/<nom>/<nom>.md` du dépôt `.github`, puis le remplir. Le modèle à suivre est `domains/management-controlling/management-controlling.md`. Supprimer une section qui ne s'applique pas (un domaine sans chaîne de données n'a pas de section « Chaîne de données »), ne pas la laisser vide.

Les dépôts qui portent le topic `domain-<nom>` reçoivent ce fichier dans leur dossier `.github/domains/` ; ne jamais le modifier ailleurs que dans `.github`.

## Contenu

```markdown
# Domaine <nom> : contrat transverse

État au AAAA-MM-JJ. Ce document décrit ce qui est vrai pour ce domaine ; les procédures générales sont dans les skills `spa-api-end-to-end` et `schema-change-end-to-end`. À mettre à jour quand le domaine évolue.

## Dépôts du domaine

| Rôle | Dépôt |
|---|---|
| SPA | `<spa-...>` |
| API métier | `<api-...>` |
| Proxies appelés | `<api-proxy-...>` |
| Configuration | `configuration` (`spring-config/spring/static/<app>/`) |
| Données | `debezium-cdc`, `WK_GOLD_*` (si le domaine alimente Fabric) |

## Chaîne de données

(Seulement si le domaine alimente Fabric.) Tableau Étape / Où / Éléments : base, réplication, bronze vers silver, Gold (configuration et moteur), modèle sémantique.

## Tables Gold

(Seulement si le domaine alimente Fabric.) Dimensions, faits, ordre de traitement, règles de montants.

## Règles métier à respecter

Une puce par règle, énoncée comme une contrainte vérifiable : ce que l'API refuse, ce que la SPA masque, ce que le Gold calcule. Ne pas décrire le code, décrire la règle.

## Contrat API et SPA

- DTO exposés à la SPA et leurs champs notables.
- Endpoints : méthode, route, permission requise.
- Permissions du domaine et rôle qui les porte.
- Paramètres gérés par les utilisateurs métier : table, endpoints, écran.
- Appels aux proxies : quel proxy, pour quelle donnée.

## Points sensibles

Ce qui casse silencieusement : ordre de déploiement, rechargement complet nécessaire, état de la production différent du test, dépendance cachée entre deux couches.
```

## Règle de mise à jour

- Une fonctionnalité qui change une règle, un endpoint, une permission, un DTO ou la chaîne de données met à jour la section correspondante et la date « État au ».
- Un écart connu entre test et production figure dans « Points sensibles » tant qu'il existe.
