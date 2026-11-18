# Couches de données : Debezium, bronze→silver, Gold, modèle sémantique

Les noms de dossiers ci-dessous sont ceux du domaine management-controlling. Ils servent d'exemple : transposer à `<domaine>`.

## Dépôts

| Couche | Dépôt | Fichiers à chercher |
|---|---|---|
| Réplication | `TransverseSI` | `debezium-cdc/connectors/<domaine>/application-{test,prod}.properties` |
| Bronze vers silver | `TransverseSI` | `configuration/spring-config/fabric/static/NB_BRONZE_TO_SILVER-<domaine>/application-{test,prod}.yaml` |
| Gold (configuration) | `TransverseSI` | `configuration/spring-config/fabric/static/NB_GOLD_COMMON_DIMENSIONS/` et `NB_GOLD_COMMON_FACTS/` |
| Gold (moteur) | `WK_GOLD_COMMON` | `NOTEBOOK/NB_DIMENSIONS.Notebook`, `NB_FACTS.Notebook` (fichiers `notebook-content.py`) |
| Modèle sémantique | `WK_GOLD_SEMANTIC_MODELS` | `SEMANTIC MODEL/SM_<NOM>.SemanticModel/definition/` (tables, mesures, relations) |

La configuration d'abord, les notebooks seulement si le moteur ne sait pas faire ce qu'il faut.

## Debezium

- La liste des tables est `debezium.source.table.include.list` (noms `public.<table>` en minuscules). Une nouvelle table y est ajoutée dans chaque environnement concerné.
- Une colonne ajoutée à une table déjà répliquée circule automatiquement, mais les lignes existantes ne portent la nouvelle valeur qu'après un événement de changement ou un snapshot.
- Une table ajoutée à la liste a besoin d'un snapshot incrémental (table `public.debezium_signals`) pour reprendre ses lignes existantes.
- L'ajout dans la liste est une action manuelle de l'utilisateur dans beaucoup de cas : la signaler dans le compte rendu.

## Bronze vers silver

- Chaque table est décrite par `target` (schéma silver, nom en majuscules), `source` (schéma bronze, nom en minuscules) et `columns` (`source` en minuscules vers `target` en majuscules).
- Une colonne ajoutée : une entrée de plus dans `columns`. Une colonne supprimée côté source : retirer l'entrée ; l'ancienne colonne reste dans le silver avec des valeurs nulles, ce qui est sans danger tant que le Gold ne la lit plus.
- Une table abandonnée : retirer son entrée, la table silver devient orpheline ; proposer sa suppression sans la décider.
- Les types sont lus selon les métadonnées du lakehouse bronze : vérifier qu'elles décrivent bien les nouvelles colonnes.
- Contrôle en lecture seule du résultat : `SHOW TABLES IN <schéma>` puis `DESCRIBE TABLE <schéma>.<table>` sur le lakehouse silver.

## Gold

- **Clé de substitution** : hachage `xxhash64` des colonnes de `merge_key`. Changer `merge_key` change les SK. Garder la même clé métier pour conserver les SK existantes.
- **Dimensions** : `column_mapping` de la colonne silver vers la colonne Gold. Une dimension peut aussi venir d'une requête (`source.views` + `source.query`) : elle est reconstruite en entier à chaque exécution (SCD1), sa clé doit être unique dans le résultat, et `order` règle son rang de traitement.
- **Tables `_active`** : les faits et les dimensions de requête lisent les tables `_active` (lignes supprimées exclues).
- **Faits** : `lookups` (jointure sur la clé métier pour retrouver la SK), `computed_columns`, `post_filter`. Une clé de jointure renommée doit l'être dans tous les lookups imbriqués : chercher le nom de colonne dans tout le fichier.
- **Dimension héritée** : si le modèle sémantique lit encore une colonne supprimée de la source, la dériver par jointure sur les dimensions amont (`order` supérieur) plutôt que de casser le modèle.
- **Ordre** : une dimension ou un fait de requête s'exécute après ceux dont il dépend (`order`, 0 par défaut).
- **Test local des requêtes** : sans accès au lakehouse, rejouer la requête SQL sur des `VALUES` avec PySpark en local (environnement jetable, supprimé ensuite). Les tables Delta ne sont pas lisibles sans réseau Fabric.

## Modèle sémantique (TMDL)

- Chercher le nom de colonne dans `tables/*.tmdl`, `relationships.tmdl` et les mesures (`DimXxx[Colonne]`).
- Si la couche Gold garde le même nom de colonne et le même type, rien à modifier.
- Une colonne renommée ou supprimée : modifier la colonne, `sourceColumn`, les relations et chaque mesure qui la cite.
- Synchronisation Git de Fabric : une table dont la partition passe de « calculée » à Direct Lake est refusée dans la même synchronisation. Prévoir deux commits : supprimer ces tables et tout ce qui en dépend (tables de mesures, relations), synchroniser ; puis restaurer l'état cible (par exemple avec `git revert`) et synchroniser de nouveau.

## Environnements

- Modifier et valider le test d'abord.
- Les fichiers de production sont séparés. Les reporter uniquement sur demande explicite, et dire dans le compte rendu qu'ils n'ont pas été traités sinon.
