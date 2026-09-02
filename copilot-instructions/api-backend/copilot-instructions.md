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
  - L'interface de définition porte le préfixe `I` (ex : `IApiFinance`)
  - Un fichier par DTO, **au même niveau que l'interface** (pas de sous-packages)
  - Tous les DTOs ont le suffixe `DTO` (majuscules, ex : `MailOutlookDTO`, `PipelineDTO`)
  - Les DTOs sont utilisés pour les corps de requête **et** de réponse des opérations GET, PUT, POST
  - Un même DTO peut servir à la fois pour la requête et la réponse (champs non renseignés ignorés à la sérialisation)
- **Contrôleurs** : dans le package `controller`, l'implémentation porte le suffixe `Controller` (ex : `ApiFinanceController`)
- Toujours annoter les endpoints avec `@Operation` (Springdoc OpenAPI)

## Appels vers des APIs externes (RestClient proxy)

Le framework `fr.nutriset.spring.core` (hérité via `fr.nutriset.api`) fournit un proxy RestClient qui crée automatiquement des beans à partir d'interfaces annotées `@RestResource` + `IRestResource`.

**Pattern pour appeler une API externe :**

- Créer une interface `IApiXxx` dans `repository/` annotée `@RestResource(urlConfigKey = "api.xxx.url")` + `IRestResource`, avec les endpoints Spring MVC (`@GetMapping`, `@PostMapping`, etc.) et les types exacts de l'API cible
- Les modèles de requête/réponse de l'API externe sont dans `repository/model/` avec `@Getter @Setter` Lombok
- Pour l'authentification custom, utiliser `specificWebClientConfigs = { XxxWebClientConfig.class }` dans `@RestResource`
  - `XxxWebClientConfig implements SpecificRestResourceWebClientConfig` — ajoute un filtre au `WebClient.Builder`
  - Le filtre d'auth implémente `ExchangeFilterFunction` et ajoute le header `Authorization`
- Le **service** injecte directement l'interface proxy `IApiXxx` — **pas de repository intermédiaire** pour les appels vers des APIs externes
- Le package `repository/` ne contient que l'interface proxy `IApiXxx` et son sous-package `model/`. Les repositories R2DBC (persistance BDD) sont la seule exception légitimant un repository wrapper.

**Exemple (MS Fabric) :**
```
config/FabricClientConfig.java         → ClientSecretCredential bean
config/FabricAuthenticationFilter.java → ExchangeFilterFunction (Bearer token OAuth2)
config/FabricWebClientConfig.java      → SpecificRestResourceWebClientConfig
repository/IApiMsFabric.java           → interface proxy @RestResource
repository/model/                      → modèles de l'API MS Fabric
service/PipelineService.java           → injecte IApiMsFabric directement
```



- Utiliser les composants communs fournis par les packages Maven internes (préfixe `maven-`)
- Ne pas réimplémenter ce qui existe dans ces packages (gestion des erreurs, sécurité, logging, etc.)
- Vérifier d'abord dans les packages communs avant d'ajouter une dépendance externe

## DTOs et modèles

- Utiliser **Lombok** sur tous les DTOs et modèles : `@Getter` et `@Setter`
- **Pas de constructeurs** dans les DTOs (ni all-args, ni no-args explicites)
- Lombok est hérité transitvement via le parent `fr.nutriset:api` → `fr.nutriset:common` — **ne pas le redéclarer dans le `pom.xml`**

## Mappers (MapStruct)

- Toute conversion entre un modèle (`repository/model/`) et un DTO (`definition/`) passe obligatoirement par un **mapper MapStruct**
- Les mappers sont dans le package `mapper/` avec le suffixe `Mapper` (ex : `PipelineMapper`)
- Annotation obligatoire : `@Mapper(componentModel = MappingConstants.ComponentModel.SPRING)`
- Injection par constructeur dans les services, comme n'importe quel bean Spring
- MapStruct est hérité transitvement via `fr.nutriset:api` → `fr.nutriset:common` — **ne pas le redéclarer dans le `pom.xml`**
- Utiliser en priorité les annotations MapStruct : `@Mapping`, `@Mappings`, `@BeanMapping`, `expression`, `ignore`, etc.
- Utiliser `@BeanMapping(ignoreByDefault = true)` plutôt que des `@Mapping(ignore = true)` individuels — seuls les champs explicitement mappés sont renseignés

**Exemple :**
```java
@Mapper(componentModel = MappingConstants.ComponentModel.SPRING)
public interface PipelineMapper {
    @BeanMapping(ignoreByDefault = true)
    @Mapping(target = "location",      expression = "java(responseEntity.getHeaders().getFirst(...))")
    @Mapping(target = "jobInstanceId", expression = "java(extractLastSegment(...))")
    PipelineDTO toRunPipelineResponse(ResponseEntity<Void> responseEntity);

    default String extractLastSegment(String location) { ... }
}
```

## Configuration (Spring Config Server)

Toute la configuration des applications est externalisée dans le dépôt `onyx-developpement/configuration`. **Ne jamais mettre de configuration dans `src/main/resources/`** (ni `application.yml`, ni `application-{env}.yml`).

### Structure du dépôt `configuration`

```
spring-config/spring/
├── static/                          ← configuration manuelle (à éditer)
│   ├── application.yml              ← config commune à toutes les apps
│   ├── application-{dev,test,prod}.yml  ← config commune par environnement
│   └── <app-name>/
│       ├── application-dev.yml      ← config spécifique à l'app, env dev
│       ├── application-test.yml
│       └── application-prod.yml
└── generated/                       ← généré par Terraform IaC (ne pas éditer)
    ├── application-{test,prod}.yml  ← variables d'infra communes (KV endpoint, Redis, etc.)
    └── <app-name>/
        ├── application-test.yml     ← client IDs, noms de managed identity, etc.
        └── application-prod.yml
```

### Règles

- **Config commune** (URLs inter-apps, Service Bus topics, etc.) → `static/application-{env}.yml` à la racine
- **Config spécifique** à une app → `static/<app-name>/application-{env}.yml`
- **Variables IaC** (client IDs, client secrets d'enregistrement Azure AD, endpoints infra) → `generated/` — générées automatiquement par Terraform, **ne jamais éditer manuellement**
- **Secrets** → stockés dans Azure Key Vault, référencés dans la config via `${nom-du-secret}` (minuscules avec tirets)

**Exemple de référence à un secret Key Vault :**
```yaml
fabric:
  pipelines:
    etl-commandes:
      workspace-id: ${fabric-etl-commandes-workspace-id}
      item-id: ${fabric-etl-commandes-item-id}
```

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
