# GitHub Copilot Instructions — Data (Microsoft Fabric)

## Stack technique

- **Microsoft Fabric** (workspaces, lakehouses, pipelines, notebooks)
- **PySpark** pour les notebooks Fabric
- **Delta Lake** comme format de stockage (tables Delta)
- **OneLake** comme couche de stockage unifiée

## Pilotage par configuration

- Les notebooks Gold et bronze→silver sont pilotés par des fichiers YAML du dépôt de configuration (`spring-config/fabric/static/<notebook>/application-{env}.yaml`). Modifier d'abord la configuration ; ne modifier un notebook que si le moteur ne sait pas faire ce qu'il faut.
- Un chemin partagé d'un notebook (lookups, déduplication, watermark, écriture) touche toutes les tables : évaluer l'impact sur les résultats et sur la durée, annoncer le risque et proposer un plan de test sur le workspace de test avant le commit.
- Les calculs métier (totaux, marges, pourcentages) se font dans le Gold, par configuration, jamais dans la SPA, l'API ni le modèle sémantique. Une ligne en pourcentage stocke numérateur et dénominateur ; le ratio se calcule à la lecture sur l'agrégat.
- Les clés de substitution sont un hachage de `merge_key` : ne pas changer `merge_key` d'une dimension existante sans accord, cela change toutes ses SK.
- Une source externe (non maîtrisée) n'est jamais modifiée ni suggérée comme à modifier : on ne change que la transformation.

## Conventions notebooks PySpark

- Première cellule : imports et configuration Spark
- Utiliser des **fonctions** pour structurer le code, pas de scripts monolithiques
- Documenter chaque cellule avec une cellule Markdown avant
- Nommage des DataFrames : `df_{entité}_{étape}` (ex: `df_orders_raw`, `df_orders_clean`)
- Les notebooks Fabric sont des fichiers `notebook-content.py` à éditer comme du texte, sans les exécuter : indiquer qu'aucune exécution Delta n'a été faite

## Tests des requêtes

- Une requête SQL de configuration se rejoue en local avec PySpark sur des jeux de données `VALUES` (pas de lecture Delta). L'environnement jetable est supprimé ensuite.
- Le contenu d'une table silver ou Gold se contrôle par requête en lecture seule (`SHOW TABLES`, `DESCRIBE TABLE`) ; ne jamais lancer de requête qui modifie des données sans demande explicite.

## Conventions SQL

- Nommage : `snake_case` pour tables et colonnes
- Toujours inclure les colonnes de traçabilité : `created_at`, `updated_at`, `source_system`
- Préférer des vues pour l'exposition des données Gold (pas de duplication physique inutile)
- Utiliser des commentaires sur les colonnes (`COMMENT`) pour documenter le sens métier

- Documenter les règles de qualité attendues en cellule Markdown

## Documentation

- Le contrat du domaine métier (dépôt `.github`, `domains/`) est la référence : toute modification de la chaîne de données ou des tables Gold y est reportée dans le même chantier
- Mettre à jour le README du dépôt ou du workspace s'il existe
- Chaque colonne et chaque mesure du modèle sémantique (TMDL) porte une description métier

## Sécurité

- Ne jamais stocker de credentials dans les notebooks — utiliser les **Key Vault** ou les connexions Fabric

## Format de réponse préféré

Code PySpark complet. Inclure les imports. Signaler les hypothèses faites sur le schéma des données.
