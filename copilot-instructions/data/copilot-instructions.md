# GitHub Copilot Instructions — Data (Microsoft Fabric)

## Stack technique

- **Microsoft Fabric** (workspaces, lakehouses, pipelines, notebooks)
- **PySpark** pour les notebooks Fabric
- **Delta Lake** comme format de stockage (tables Delta)
- **OneLake** comme couche de stockage unifiée

## Conventions notebooks PySpark

- Première cellule : imports et configuration Spark
- Utiliser des **fonctions** pour structurer le code, pas de scripts monolithiques
- Documenter chaque cellule avec une cellule Markdown avant
- Nommage des DataFrames : `df_{entité}_{étape}` (ex: `df_orders_raw`, `df_orders_clean`)

## Conventions SQL

- Nommage : `snake_case` pour tables et colonnes
- Toujours inclure les colonnes de traçabilité : `created_at`, `updated_at`, `source_system`
- Préférer des vues pour l'exposition des données Gold (pas de duplication physique inutile)
- Utiliser des commentaires sur les colonnes (`COMMENT`) pour documenter le sens métier

- Documenter les règles de qualité attendues en cellule Markdown

## Sécurité

- Ne jamais stocker de credentials dans les notebooks — utiliser les **Key Vault** ou les connexions Fabric

## Format de réponse préféré

Code PySpark complet. Inclure les imports. Signaler les hypothèses faites sur le schéma des données.
