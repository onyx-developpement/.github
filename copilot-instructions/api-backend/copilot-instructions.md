# GitHub Copilot Instructions — API Backend (Spring WebFlux)

## Stack technique

- **Java 17** (LTS)
- **Spring Boot 3.x**
- **Spring WebFlux** (programmation réactive, Project Reactor)
- **PostgreSQL** + driver R2DBC réactif
- **Maven** (gestion des dépendances)
- **Packages Maven internes** : groupId préfixé `maven-`, fournis par l'équipe Transverse SI

## Architecture & patterns

- Architecture en couches classique : `definition` (interfaces API) → `controller` (implémentations) → `service` → `repository`
- Reactive streams : utiliser `Mono<T>` et `Flux<T>` de Project Reactor — **ne jamais bloquer** (pas de `.block()`)
- Endpoints avec `@RestController` + `@GetMapping` / `@PostMapping` / etc.
- Repositories réactifs : `ReactiveCrudRepository` ou `R2dbcRepository`

## Conventions de code

- Nommage : camelCase pour variables/méthodes, PascalCase pour classes, UPPER_SNAKE_CASE pour constantes
- **Services** : interface préfixée `I` et suffixe `Service` (ex : `IFinanceService`), implémentation avec suffixe uniquement (ex : `FinanceService`)
- **Repositories** : même convention — interface `IFinanceRepository`, implémentation `FinanceRepository`
- **Définition d'API** : dans le package `definition`
  - Un fichier par DTO
  - Une interface par domaine contenant les mappings Spring (ex : `IApiFinance`)
- **Contrôleurs** : dans le package `controller`, l'implémentation porte le suffixe `Controller` (ex : `ApiFinanceController`)
- Les DTOs ont le suffixe `Dto` (request) ou `Response` (response)
- Toujours annoter les endpoints avec `@Operation` (Springdoc OpenAPI)

## Packages internes (Transverse SI)

- Utiliser les composants communs fournis par les packages Maven internes (préfixe `maven-`)
- Ne pas réimplémenter ce qui existe dans ces packages (gestion des erreurs, sécurité, logging, etc.)
- Vérifier d'abord dans les packages communs avant d'ajouter une dépendance externe

## Gestion des erreurs

- Utiliser `onErrorResume`, `onErrorMap`, `onErrorReturn` dans les chaînes réactives
- Utiliser la classe `RestError` définie dans le package `maven-fr.nutriset.spring` pour formater les réponses d'erreur
- Ne jamais exposer de stack traces dans les réponses API

## Tests

- Tests unitaires : **JUnit 5** + **Mockito** + `StepVerifier` (Reactor Test) pour les flux réactifs
- Tests d'intégration : `@SpringBootTest` avec `WebTestClient`
- Nommage : `{ClasseTestée}Test.java` pour unitaires, `{ClasseTestée}IT.java` pour intégration

## Sécurité

- Valider toutes les entrées avec Bean Validation (`@Valid`, `@NotNull`, etc.)
- Secrets via variables d'environnement, jamais en dur dans le code

## Format de réponse préféré

Toujours proposer du code complet et compilable, pas de pseudo-code. Inclure les imports nécessaires.
