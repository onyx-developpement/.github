# GitHub Copilot Instructions — Data (Microsoft Fabric)

## Stack technique

- **Microsoft Fabric** (workspaces, lakehouses, pipelines, notebooks)
- **PySpark** pour les notebooks de transformation
- **Python 3.10+** dans les notebooks Fabric
- **SQL** (T-SQL / Spark SQL) pour les requêtes et vues
- **Delta Lake** comme format de stockage (tables Delta)
- **OneLake** comme couche de stockage unifiée

## Architecture medallion (Bronze / Silver / Gold)

- **Bronze** : données brutes ingérées telles quelles depuis les sources
- **Silver** : données nettoyées, typées, dédupliquées — 1 table = 1 entité métier
- **Gold** : données agrégées, dénormalisées, prêtes pour la consommation **Power BI** (DirectLake ou import)
- Ne jamais écrire dans Bronze depuis Silver ou Gold
- Toujours utiliser `MERGE` (upsert) en Silver pour gérer l'idempotence

## Conventions notebooks PySpark

- Première cellule : imports et configuration Spark
- Paramétrer les notebooks (widgets `dbutils.widgets` / Fabric parameters) — pas de valeurs en dur
- Utiliser des **fonctions** pour structurer le code, pas de scripts monolithiques
- Documenter chaque cellule avec une cellule Markdown avant
- Nommage des DataFrames : `df_{entité}_{étape}` (ex: `df_orders_raw`, `df_orders_clean`)
- Écrire en Delta avec `overwrite` ou `merge` selon le besoin — jamais `append` sans contrôle de doublons

## Conventions SQL

- Nommage : `snake_case` pour tables et colonnes
- Toujours inclure les colonnes de traçabilité : `created_at`, `updated_at`, `source_system`
- Préférer des vues pour l'exposition des données Gold (pas de duplication physique inutile)
- Utiliser des commentaires sur les colonnes (`COMMENT`) pour documenter le sens métier

## Pipelines Fabric

- Paramétrer tous les pipelines (dates, environnement, etc.)
- Gérer les erreurs avec des activités `If Condition` + notification en cas d'échec
- Journaliser les exécutions dans une table de log Delta (`bronze.pipeline_logs`)
- Respecter l'idempotence : un pipeline peut être relancé sans effet de bord

## Tests & qualité des données

- Ajouter des contrôles de qualité après chaque étape (count != 0, pas de nulls sur les clés, etc.)
- Documenter les règles de qualité attendues en cellule Markdown

## Sécurité

- Ne jamais stocker de credentials dans les notebooks — utiliser les **Key Vault** ou les connexions Fabric
- Restreindre les accès OneLake par rôle (workspace roles, item permissions)
- Ne pas exposer les données brutes (Bronze) aux utilisateurs finaux

## Format de réponse préféré

Code PySpark ou SQL complet. Inclure les imports. Signaler les hypothèses faites sur le schéma des données.
