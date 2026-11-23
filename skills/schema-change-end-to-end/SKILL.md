---
name: schema-change-end-to-end
description: "Faire évoluer une table ou une colonne de bout en bout : migration Flyway, API Spring (entité, DTO, mapper, repository), SPA React (modèle, services, mock), Debezium, bronze vers silver, Gold (dimensions, faits, notebooks) et modèle sémantique. À utiliser pour ajouter, renommer, supprimer ou changer le type d'une colonne ou d'une table, remplacer une clé (code par identifiant), ajouter une table à répliquer, ou quand la source est externe et que seule la transformation est modifiable. Mots-clés : changement de schéma, migration, Flyway, Debezium, include list, bronze, silver, gold, DimXxx, FactXxx, TMDL, DTO, contrat API, impact."
---

# Évolution d'un schéma de bout en bout

Une modification de table traverse plusieurs dépôts. Les oublis viennent presque toujours de la chaîne, pas du code : table absente de Debezium, configuration de production non reportée, modèle sémantique qui lit encore l'ancienne colonne.

Pour une nouvelle fonctionnalité (écran, endpoint, paramètre, permission) et non une évolution de schéma, suivre le skill `spa-api-end-to-end` ; il renvoie ici pour la chaîne de données.

## Quand utiliser ce skill

- Ajout, renommage, suppression ou changement de type d'une colonne.
- Nouvelle table à répliquer, ou remplacement d'une clé (ex. un code par un identifiant).
- Une source externe change et seule la transformation peut s'adapter.

## Étape 0 : qui maîtrise la source ?

Poser la question avant toute modification si elle n'est pas évidente.

| Source | Ce qu'on peut modifier | Procédure |
|---|---|---|
| Base portée par une de nos API (Flyway) | Toute la chaîne | Suivre les étapes 1 à 5 |
| Source externe (M3, Jira, outil tiers...) | Uniquement la transformation : bronze→silver, Gold, modèle sémantique | Lire [source externe](./references/source-externe.md), ne jamais proposer de modifier la source |

Dans le second cas, l'API et la SPA ne sont concernées que si elles exposent ou consomment la donnée transformée. Elles s'adaptent alors à ce que la transformation produit, jamais l'inverse.

## Étape 1 : cartographier l'impact avant d'éditer

1. Chercher la colonne ou la table dans chaque dépôt de la chaîne (voir [couches de données](./references/couche-donnees.md), [API](./references/couche-api.md), [SPA](./references/couche-spa.md)). Pour le P&L ou tout autre domaine, lire d'abord le contrat du domaine dans `.github/domains/` du dépôt, s'il existe : il est déposé dans les dépôts portant le topic `domain-<nom>`.
2. Le workspace multi-racine `workspaces/management-controlling.code-workspace` du dépôt `.github` couvre les dépôts de la chaîne.
3. Produire un tableau d'impact par couche : modifié, non concerné, ou à faire par un tiers. Le présenter à l'utilisateur avant de coder s'il y a un changement de contrat.

## Étape 2 : plan par phases

Un plan est obligatoire avant toute modification, sauf évolution triviale d'un seul fichier : règles communes « Plan, modèle et contexte ». Phases habituelles : base et API, SPA, chaîne de données (Debezium, silver, Gold, modèle sémantique), documentation.

## Étape 3 : décider du contrat et de la compatibilité

- Changement de contrat API (champ renommé ou supprimé, paramètre de requête) : demander à l'utilisateur s'il l'expose tel quel ou s'il garde l'ancien contrat avec une traduction côté API. Ne pas décider seul.
- Suppression de colonne : si une couche aval lit encore l'ancienne colonne (Gold, modèle sémantique), prévoir une dérivation par jointure plutôt qu'une rupture.
- Rappeler l'ordre de déploiement : base, API, SPA, Debezium, bronze→silver, Gold, modèle sémantique.

## Étape 4 : exécuter couche par couche

Dans cet ordre, en validant chaque couche avant la suivante :

1. **Base (Flyway)** : règles Flyway du dépôt (peu de scripts, demander avant de modifier un script appliqué ou de regrouper). Voir [API](./references/couche-api.md).
2. **API** : entité, DTO, mapper, repository, service, tests.
3. **SPA** : modèle, couches de service, mock, pages, tests.
4. **Debezium** : liste des tables, snapshot des lignes existantes.
5. **Bronze→silver** : correspondance des colonnes, types.
6. **Gold** : dimensions, faits, clés de jointure.
7. **Modèle sémantique** : colonnes et mesures qui lisent le Gold.
8. **Environnements** : test d'abord ; la production a ses propres fichiers de configuration, à traiter seulement sur demande explicite.

## Étape 5 : documenter

Dans la même évolution que le code. Détail et règles dans la référence « documentation » du skill `spa-api-end-to-end`.

- **Contrat de domaine** (`domains/<nom>/<nom>.md` du dépôt `.github`, jamais dans les copies) : mettre à jour *Chaîne de données*, *Tables Gold*, *Contrat API et SPA*, *Points sensibles* et la date « État au ».
- **API** : `README.md` (tables Flyway, endpoints et DTO modifiés).
- **SPA** : `docs/api.md`, `docs/domaine.md` et la page de `docs/fonctionnalites/` concernée.
- **Modèle sémantique** : descriptions TMDL des colonnes et mesures modifiées.

## Règles à ne jamais enfreindre

- Ne rien inventer sur un schéma externe : vérifier par lecture (voir [source externe](./references/source-externe.md)).

## Vérifications avant de conclure

- API et SPA : lancer les vérifications du dépôt touché, celles de ses instructions (tests, typage, lint).
- Silver : vérifier les tables et colonnes avec une requête en lecture seule sur le lakehouse (`SHOW TABLES IN <schéma>`, `DESCRIBE TABLE <schéma>.<table>`).
- Requêtes SQL des YAML Gold : les rejouer sur un petit jeu de données avec PySpark en local.

## Compte rendu final

Terminer par :

1. Le tableau d'impact par couche (modifié / non concerné / à faire par un tiers).
2. Les actions manuelles restantes (ex. ajout dans Debezium, snapshot, production, déploiement).
3. La documentation mise à jour (contrat de domaine, README, `docs/`, TMDL).
4. Ce qui n'a pas pu être vérifié (tests d'intégration en échec avant la modification, chemins Delta non exécutés...).
5. La mention explicite qu'aucun commit n'a été fait.
