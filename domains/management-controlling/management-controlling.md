# Domaine management-controlling (P&L) : contrat transverse

État au 2026-11-18. Ce document décrit ce qui est vrai pour ce domaine ; la procédure générale est dans le skill `schema-change-end-to-end`. À mettre à jour quand le domaine évolue.

## Chaîne de données

| Étape | Où | Éléments |
|---|---|---|
| Base | dépôt `api-controle-gestion`, Flyway `src/main/resources/databases/migration/azure/postgresql/management-controlling/` | `pnl_common_label`, `pnl_common_label_code`, `pnl_deposit`, `pnl_deposit_line`, `pnl_sequence`, `subsidiary`, `subsidiary_currency`, `pnl_subsidiary_label`, `debezium_signals` |
| Réplication | dépôt `debezium-cdc`, `connectors/management-controlling/application-{test,prod}.properties` | liste `debezium.source.table.include.list` ; signaux dans `public.debezium_signals` |
| Bronze vers silver | dépôt `configuration`, `spring-config/fabric/static/NB_BRONZE_TO_SILVER-management-controlling/application-{test,prod}.yaml` | `LH_SILVER`, schéma `management_controlling` : `PNL_COMMON_LABELS`, `PNL_DEPOSITS`, `PNL_DEPOSIT_LINES`, `PNL_SUBSIDIARY_LABELS`, `PNL_SEQUENCES` |
| Gold (configuration) | dépôt `configuration`, `spring-config/fabric/static/NB_GOLD_COMMON_DIMENSIONS/` et `NB_GOLD_COMMON_FACTS/` | `LH_GOLD_COMMON` : dimensions dans le schéma `dimensions`, faits dans `facts` ; chaque dimension a une table `_active` |
| Gold (moteur) | dépôt `WK_GOLD_COMMON`, `NOTEBOOK/NB_DIMENSIONS.Notebook` et `NB_FACTS.Notebook` | pilotés par les YAML ci-dessus |
| Modèle sémantique | dépôt `WK_GOLD_SEMANTIC_MODELS`, `SEMANTIC MODEL/SM_MANAGEMENT_CONTROLLING.SemanticModel` | Direct Lake sur `LH_GOLD_COMMON` |

Au moment de la rédaction, la configuration P&L est adaptée pour TEST uniquement ; les fichiers de production ne le sont pas.

## Tables Gold du P&L

- **Dimensions :** `DimPnlCommonLabel`, `DimPnlSequence`, `DimPnlHeader`, `DimPnlPresentation`, `DimPnlReferenceSelector`, et `DimSubsidiaryPnl` conservée pour le modèle sémantique (son `PnlType` est reconstitué par jointure entre en-tête et séquence).
- **Faits bruts :** `FactSubsidiaryPnlLine`, `FactSubsidiaryPnlLineThreeYearsPlan`.
- **Faits de présentation :** `FactPnlPresentationLine`, `FactPnlPresentationThreeYearsPlan`, `FactPnlPresentationLanding`.
- **Ordre de traitement :** dimensions de base (ordre 0), puis dimensions par requête (ordre 100) ; faits de présentation (ordre 100), puis atterrissage (ordre 110), car il s'appuie sur les lignes mensuelles.

## Règles métier à respecter

- Un dépôt (`pnl_deposit`) référence sa séquence par `pnl_sequence_id` (clé de `pnl_sequence`). Le code de séquence (`BUDGET`, `REAL`, `SPRING_FORECAST`, `SUMMER_FORECAST`, `FALL_FORECAST`, `THREE_YEARS_PLAN`) reste la clé naturelle, mais n'est plus stocké dans le dépôt.
- Une séquence porte `REAL_MONTH_COUNT`, `COMPARISON_MONTH_COUNT`, `IS_LANDING` et `IS_ANNUAL`. Les lignes d'un plan à trois ans sont annuelles, sans mois ; l'année du dépôt est l'année de référence N.
- La dernière version est un marqueur `IS_LATEST_VERSION`, unique par (filiale, séquence, année), posé depuis l'application. Sans séquence sélectionnée, la lecture retient `BUDGET`.
- Les lignes calculées (totaux, marges, pourcentages) sont des libellés communs marqués `IS_CALCULATED`, avec un code obligatoire et sans enfant. Elles ne reçoivent jamais de montant : leurs formules sont dans le Gold (`calculated_lines` de `FactPnlPresentationLine` et du plan à trois ans). Une ligne en pourcentage stocke numérateur et dénominateur ; le ratio se calcule à la lecture sur l'agrégat.
- Les libellés communs ont une hiérarchie de trois niveaux au plus. Le code de présentation est le code du libellé, ou `LABEL_<id>` s'il n'en a pas.
- Les montants de coûts sont saisis en positif ; les formules les soustraient.
- L'atterrissage d'une séquence `IS_LANDING` prend les mois réels (jusqu'à `RealMonthCount`) dans la dernière version de `REAL`, et les mois suivants dans la dernière version de la séquence. La séquence réelle est identifiée par son code `REAL`.

## Contrat API et SPA

- Dépôts : `api-controle-gestion` (API Spring) et `spa-controle-gestion-react`.
- `DepositDTO.pnlSequenceId` (entier) ; filtre `GET /pnl/deposits?pnlSequenceId=`.
- `PnlSequenceDTO` expose `id` en lecture seule ; routes `/pnl/sequences` (création, modification, suppression par code).
- `CommonLabelDTO` : `calculated`, `percentage`, `accentuated`.
- `PUT /pnl/deposits/{uuid}/latest-version` pose le marqueur de dernière version.
- Permissions : `common-label-codes:write` pour les séquences et les libellés calculés, `deposit:lock` pour la dernière version.

## Points sensibles

- **Clés de substitution :** `xxhash64` des colonnes de `merge_key`. `PnlHeader_SK` et `SubsidiaryPnl_SK` sont égaux parce que les deux dimensions ont la même clé `PnlDepositId`. Changer une `merge_key` change toutes les SK.
- **Ajout d'un lookup :** les faits chargés en upsert incrémental gardent des SK nulles sur les lignes antérieures. Prévoir un rechargement complet.
- **Nouvelle table répliquée :** l'ajouter à la liste Debezium ne reprend pas ses lignes existantes ; lancer un snapshot incrémental via `debezium_signals`.
- **Colonne supprimée côté base :** l'ancienne colonne reste dans le silver avec des valeurs nulles ; le Gold ne doit plus la lire.
- **Séquences absentes du silver :** `FactPnlPresentationLanding` perd les lignes réelles et `DimPnlScenario` du modèle ne propose qu'une séquence.
- **Modèle sémantique :** une table de partition « calculée » ne peut pas devenir Direct Lake dans la même synchronisation Git. Il faut supprimer les tables concernées (et les mesures qui en dépendent), synchroniser, puis les restaurer et synchroniser de nouveau. Le modèle garde les noms de tables et de mesures pour ne pas casser les rapports.
- **Relations du modèle :** seul `FactPnlPresentationLanding` est relié à `DimPnlScenario`. Les comparaisons lisent `FactPnlPresentationLine` filtré par `DimSubsidiaryPnl_active[PnlType]` et `[VersionCode]`, ou par `DimPnlHeader_active[IsLatestVersion]` pour `LATEST`.
