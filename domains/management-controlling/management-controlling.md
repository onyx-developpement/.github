# Domaine management-controlling (P&L) : contrat transverse

État au 2026-11-19. Ce document décrit ce qui est vrai pour ce domaine ; la procédure générale est dans le skill `schema-change-end-to-end`. À mettre à jour quand le domaine évolue.

## Chaîne de données

| Étape | Où | Éléments |
|---|---|---|
| Base | dépôt `api-controle-gestion`, Flyway `src/main/resources/databases/migration/azure/postgresql/management-controlling/` | `pnl_common_label`, `pnl_common_label_code`, `pnl_deposit`, `pnl_deposit_line`, `pnl_sequence`, `subsidiary`, `pnl_subsidiary_currency`, `pnl_exchange_rate`, `pnl_subsidiary_label`, `debezium_signals` |
| Réplication | dépôt `debezium-cdc`, `connectors/management-controlling/application-{test,prod}.properties` | liste `debezium.source.table.include.list` ; signaux dans `public.debezium_signals` |
| Bronze vers silver | dépôt `configuration`, `spring-config/fabric/static/NB_BRONZE_TO_SILVER-management-controlling/application-{test,prod}.yaml` | `LH_SILVER`, schéma `management_controlling` : `PNL_COMMON_LABELS`, `PNL_DEPOSITS`, `PNL_DEPOSIT_LINES`, `PNL_SUBSIDIARY_LABELS`, `PNL_SEQUENCES`, `PNL_SUBSIDIARY_CURRENCIES`, `PNL_EXCHANGE_RATES` |
| Gold (configuration) | dépôt `configuration`, `spring-config/fabric/static/NB_GOLD_COMMON_DIMENSIONS/` et `NB_GOLD_COMMON_FACTS/` | `LH_GOLD_COMMON` : dimensions dans le schéma `dimensions`, faits dans `facts` ; chaque dimension a une table `_active` |
| Gold (moteur) | dépôt `WK_GOLD_COMMON`, `NOTEBOOK/NB_DIMENSIONS.Notebook` et `NB_FACTS.Notebook` | pilotés par les YAML ci-dessus |
| Modèle sémantique | dépôt `WK_GOLD_SEMANTIC_MODELS`, `SEMANTIC MODEL/SM_MANAGEMENT_CONTROLLING.SemanticModel` | Direct Lake sur `LH_GOLD_COMMON` |

Au moment de la rédaction, la configuration P&L est adaptée pour TEST uniquement ; les fichiers de production ne le sont pas. Le silver de production lit encore `eur_exchange_rate` (colonne supprimée de `pnl_deposit`) et ne réplique pas les tables de devises et de taux : l'adapter avant de déployer la migration en production.

## Tables Gold du P&L

- **Dimensions :** `DimPnlCommonLabel`, `DimPnlSequence`, `DimPnlHeader`, `DimPnlPresentation`, `DimPnlReferenceSelector`, `DimPnlSubsidiaryCurrency`, `DimPnlExchangeRate`, `DimPnlEffectiveExchangeRate`, `DimPnlPresentationCurrency`, `DimPnlErpSubsidiary`, `DimPnlErpAccountMapping`, et `DimSubsidiaryPnl` conservée pour le modèle sémantique (son `PnlType` est reconstitué par jointure entre en-tête et séquence).
- **Faits bruts :** `FactSubsidiaryPnlLine`, `FactSubsidiaryPnlLineThreeYearsPlan`, `FactErpPnlLine` (grand livre M3 rattaché aux filiales ERP).
- **Faits de présentation :** `FactPnlPresentationLine`, `FactPnlPresentationThreeYearsPlan`, `FactPnlPresentationLanding`.
- **Ordre de traitement :** dimensions de base (ordre 0), puis dimensions par requête (ordre 100, dont les taux effectifs) ; `DimPnlHeader` (dimension par requête) et `FactErpPnlLine` sont à l'ordre 50 : l'en-tête dépend des devises et des filiales ERP, les taux effectifs de l'en-tête ; faits de présentation (ordre 100), puis atterrissage (ordre 110), car il s'appuie sur les lignes mensuelles.
- **Montants :** les faits bruts portent le montant dans la devise du dépôt ; les faits de présentation portent `Amount` (devise du dépôt) et `ConvertedAmount` (avec `NumeratorConvertedAmount` et `DenominatorConvertedAmount` pour les pourcentages), par `RateType` (sauf le plan à trois ans) et `PresentationCurrency`.

## Règles métier à respecter

- **Réel alimenté par l'ERP :** le réel des filiales `E100000` (division B00), `E150000` (C00), `E200000` et `E250000` (A00, réparties par centre comptable dans `DimPnlErpSubsidiary`) vient du grand livre M3 (`FactGeneralLedger`), pas des dépôts de la SPA. `DimPnlHeader` porte un en-tête par filiale ERP et année : séquence `REAL`, version `ERP-<année>`, dernière version, devise fonctionnelle saisie dans la SPA, identifiant négatif (`-(numéro de filiale × 10000 + année)`) pour ne jamais rencontrer celui d'un dépôt. Sans devise fonctionnelle dans la SPA, la filiale n'a pas d'en-tête.
- `FactErpPnlLine` reprend les comptes de classe 6 et 7 : montant `ThirdPartyCurrencyAmount` signé par `DimPnlErpAccountMapping` (mapping provisoire par préfixe de compte, le plus long l'emporte), écriture de clôture d'exercice exclue (`AccountingText` commençant par `CLOTURE EXERCICE`). Une ligne non reprise porte `RejectionReason` : `ACCOUNT_NOT_MAPPED`, `NO_HEADER` ou `CURRENCY_MISMATCH` (devise tiers différente de la devise fonctionnelle de la SPA).
- `FactPnlPresentationLine` ajoute les lignes ERP retenues et ignore les dépôts `REAL` de la SPA des filiales ERP, qui restent en base. L'API refuse tout dépôt `REAL` d'une filiale dont `realDepositBlocked` est vrai.
- Un dépôt (`pnl_deposit`) référence sa séquence par `pnl_sequence_id` (clé de `pnl_sequence`). Le code de séquence (`BUDGET`, `REAL`, `SPRING_FORECAST`, `SUMMER_FORECAST`, `FALL_FORECAST`, `THREE_YEARS_PLAN`) reste la clé naturelle, mais n'est plus stocké dans le dépôt.
- Une séquence porte `REAL_MONTH_COUNT`, `COMPARISON_MONTH_COUNT`, `IS_LANDING` et `IS_ANNUAL`. Les lignes d'un plan à trois ans sont annuelles, sans mois ; l'année du dépôt est l'année de référence N.
- La dernière version est un marqueur `IS_LATEST_VERSION`, unique par (filiale, séquence, année), posé depuis l'application. Sans séquence sélectionnée, la lecture retient `BUDGET`.
- Les lignes calculées (totaux, marges, pourcentages) sont des libellés communs marqués `IS_CALCULATED`, avec un code obligatoire et sans enfant. Elles ne reçoivent jamais de montant : leurs formules sont dans le Gold (`calculated_lines` de `FactPnlPresentationLine` et du plan à trois ans). Une ligne en pourcentage stocke numérateur et dénominateur ; le ratio se calcule à la lecture sur l'agrégat.
- Les libellés communs ont une hiérarchie de trois niveaux au plus. Le code de présentation est le code du libellé, ou `LABEL_<id>` s'il n'en a pas.
- Les montants de coûts sont saisis en positif ; les formules les soustraient.
- Les devises sont paramétrées par filiale (`pnl_subsidiary_currency`, une ligne par filiale) : devise transactionnelle, devise fonctionnelle (celle des dépôts, imposée par l'API) et deux devises de présentation (EUR et USD par défaut). Un dépôt porte sa devise (`currency_code`) et n'a plus de taux de change.
- Les taux (`pnl_exchange_rate`) sont mensuels, en base EUR (1 EUR = taux × devise), avec un taux moyen et un taux de clôture. `subsidiary_id` vide : taux commun ; renseigné : taux spécifique à la filiale, prioritaire. L'API refuse un dépôt dont un taux manque (devise du dépôt et devises de présentation hors EUR, 12 mois de l'année, N+1 à N+3 pour un plan annuel) et la suppression d'un taux dont un dépôt dépend.
- Conversion dans le Gold : `AVERAGE` = taux moyen du mois ; `CLOSING` = taux de clôture du mois pour la séquence `REAL`, taux moyen pour les autres ; `CONSTANT` = moyenne annuelle des taux moyens de l'année précédente (absent s'il manque un mois). Le plan à trois ans utilise la moyenne annuelle. Un montant dont un taux manque n'est pas produit : les lignes calculées le compteraient à 0 sinon.
- L'atterrissage d'une séquence `IS_LANDING` prend les mois réels (jusqu'à `RealMonthCount`) dans la dernière version de `REAL`, et les mois suivants dans la dernière version de la séquence. La séquence réelle est identifiée par son code `REAL`.

## Contrat API et SPA

- Dépôts : `api-controle-gestion` (API Spring) et `spa-controle-gestion-react`.
- `DepositDTO.pnlSequenceId` (entier) ; filtre `GET /pnl/deposits?pnlSequenceId=`.
- `PnlSequenceDTO` expose `id` en lecture seule ; routes `/pnl/sequences` (création, modification, suppression par code).
- `CommonLabelDTO` : `calculated`, `percentage`, `accentuated`.
- `PUT /pnl/deposits/{uuid}/latest-version` pose le marqueur de dernière version.
- Permissions : `common-label-codes:write` pour les séquences et les libellés calculés, `deposit:lock` pour la dernière version, `real-deposit-source:write` pour le blocage du réel d'une filiale.
- `SubsidiaryDTO.realDepositBlocked` (colonne `subsidiary.real_deposit_blocked`) ; `PUT /pnl/subsidiaries/{id}/real-deposits/block` et `/allow`.
- `DepositDTO` ne porte plus de taux de change. Devises d'une filiale : `GET`/`PUT /pnl/subsidiaries/{id}/currencies` (`SubsidiaryCurrencyDTO`). Taux communs : `GET /pnl/exchange-rates?currencyCode=&year=`, `PUT /pnl/exchange-rates/{code}/{year}`. Taux spécifiques : `GET`/`PUT /pnl/subsidiaries/{id}/exchange-rates[/{code}/{year}]`. Taux manquants d'une filiale : `GET /pnl/subsidiaries/{id}/exchange-rates/missing?pnlSequenceId=&year=` (`MissingExchangeRateDTO`). Lecture : `deposit:read` ; écriture : `subsidiaries:write`.

## Points sensibles

- **Clés de substitution :** `xxhash64` des colonnes de `merge_key`. `PnlHeader_SK` et `SubsidiaryPnl_SK` sont égaux parce que les deux dimensions ont la même clé `PnlDepositId`. Changer une `merge_key` change toutes les SK.
- **Ajout d'un lookup :** les faits chargés en upsert incrémental gardent des SK nulles sur les lignes antérieures. Prévoir un rechargement complet.
- **Nouvelle table répliquée :** l'ajouter à la liste Debezium ne reprend pas ses lignes existantes ; lancer un snapshot incrémental via `debezium_signals`.
- **Colonne supprimée côté base :** l'ancienne colonne reste dans le silver avec des valeurs nulles ; le Gold ne doit plus la lire.
- **Séquences absentes du silver :** `FactPnlPresentationLanding` perd les lignes réelles et `DimPnlScenario` du modèle ne propose qu'une séquence.
- **Modèle sémantique :** une table de partition « calculée » ne peut pas devenir Direct Lake dans la même synchronisation Git. Il faut supprimer les tables concernées (et les mesures qui en dépendent), synchroniser, puis les restaurer et synchroniser de nouveau. Le modèle garde les noms de tables et de mesures pour ne pas casser les rapports.
- **Relations du modèle :** seul `FactPnlPresentationLanding` est relié à `DimPnlScenario`. Les comparaisons lisent `FactPnlPresentationLine` filtré par `DimSubsidiaryPnl_active[PnlType]` et `[VersionCode]`, ou par `DimPnlHeader_active[IsLatestVersion]` pour `LATEST`.
- **Conversion côté modèle :** `PnlRateTypeSelector` (table calculée) et `PnlPresentationCurrencySelector` sont déconnectés ; les mesures `Selected Rate Type` et `Selected Presentation Currency` retiennent `AVERAGE` et `EUR` sans choix unique, et filtrent `RateType` et `PresentationCurrency` des faits. `Actual N-1` et `YN-1` restent au taux moyen quand `CONSTANT` est choisi. Les faits sont reconstruits en entier : un taux modifié se répercute à la prochaine exécution des faits.
