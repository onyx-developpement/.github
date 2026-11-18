# Couche base et API (Spring WebFlux, R2DBC, Flyway)

## Migration Flyway

- Dossier : `src/main/resources/databases/migration/azure/postgresql/<clé-base>/`, fichiers `V<n>__<Description>.sql`.
- Appliquer les règles Flyway du `copilot-instructions.md` du dépôt : peu de scripts, et demander avant de modifier un script appliqué, de regrouper ou de renuméroter. Demander aussi si les scripts précédents de l'évolution sont déjà appliqués en test ou en production.
- Changement de clé ou de colonne : ajouter la colonne nullable, reprendre les données par `UPDATE ... FROM`, poser `NOT NULL` et la clé étrangère, recréer les index qui dépendent de l'ancienne colonne, puis supprimer l'ancienne colonne.
- Terminer la migration par un commentaire `-- Rollback :` décrivant le retour arrière.
- Un `UPDATE` de masse dans une migration émet un événement de changement par ligne côté Debezium : c'est voulu quand les lignes doivent être rejouées dans le silver.

## Code Java

Suivre les conventions du dépôt (`copilot-instructions.md`). Points propres à une évolution de schéma :

- **Entité** (`repository/model`) : le nom du champ suit le nom de colonne en `snake_case` (`pnlSequenceId` pour `pnl_sequence_id`).
- **DTO** (`definition`) : un DTO sert en entrée et en sortie. Un champ en lecture seule reste ignoré à l'écriture côté mapper. Retirer les imports de validation devenus inutiles.
- **Mapper MapStruct** : `@BeanMapping(ignoreByDefault = true)`, un `@Mapping` par champ. Ajouter le champ dans les mappings lecture et écriture, et ne pas l'ajouter dans la mise à jour si la valeur est figée.
- **Repository** : requêtes `@Query` avec le nom de colonne SQL, méthodes dérivées avec le nom du champ. Chercher aussi les contrôles d'utilisation (« existe-t-il des lignes qui référencent... ») dans les services d'autres référentiels.
- **Interface de définition et contrôleur** : un paramètre de requête renommé doit l'être dans l'interface `IApiXxx`, le contrôleur, le service et les tests.
- Chercher toutes les occurrences avec le nom de colonne, le nom du champ et les noms de méthodes dérivées (`existsByXxx`, `findByXxx`).

## Tests

- Services : Mockito en mode strict. Un nouveau repository injecté demande un stub, ou `lenient`.
- Surcharger un stub défini dans `setUp` : utiliser `doReturn(...).when(mock).méthode(...)`, car un `when(...)` rappelle le stub existant et peut échouer.
- `findById` est ambigu (entier et publisher) : utiliser `any(Integer.class)`.
- Mappers : un test par sens de conversion, y compris les valeurs nulles.
- Commande : `mvn -P app-dependencies,webapp test`. Sous PowerShell, mettre les propriétés `-D` entre guillemets.
- Le test d'intégration du contrôleur peut échouer pour une raison antérieure (404) : le vérifier sur la branche d'origine avant de s'en inquiéter, et le signaler dans le compte rendu sans le masquer.
