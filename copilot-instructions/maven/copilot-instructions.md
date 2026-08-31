# GitHub Copilot Instructions — Packages Maven (Transverse SI)

## Rôle de ces dépôts

Ces dépôts produisent des **librairies Maven internes** réutilisées par les équipes SPA (BFF) et API Backend.
Le groupId de chaque artefact est préfixé `maven-` (ex : `maven-fr.nutriset.spring`).

## Stack technique

- **Java 17** (LTS)
- **Spring Boot 3.x** (auto-configuration, starters)
- **Maven** multi-module si le package regroupe plusieurs fonctionnalités distinctes
- Pas de couche web propre : les dépendants apportent leur runtime (WebFlux ou Web MVC)

## Structure d'un dépôt multi-module

```
<package-root>/
├── README.md                   ← documentation du package (voir ci-dessous)
├── pom.xml                     ← POM parent (gestion des versions, plugins communs)
├── <module-a>/
│   ├── README.md               ← documentation du module A
│   └── src/
└── <module-b>/
    ├── README.md               ← documentation du module B
    └── src/
```

## Conventions de code

- Nommage : camelCase pour variables/méthodes, PascalCase pour classes, UPPER_SNAKE_CASE pour constantes
- **Services** : interface préfixée `I` et suffixe `Service` (ex : `ITokenService`), implémentation avec suffixe uniquement (ex : `TokenService`)
- **Repositories** : même convention — interface `ITokenRepository`, implémentation `TokenRepository`
- Les classes de configuration Spring portent le suffixe `AutoConfiguration` ou `Configuration`
- Les propriétés de configuration externalisées utilisent une classe `@ConfigurationProperties` suffixée `Properties`
- Un fichier par classe/interface (pas de regroupement de plusieurs types dans un même fichier)

## Documentation obligatoire

> **Règle fondamentale** : chaque répertoire contenant un `pom.xml` doit avoir son propre `README.md`. Cette règle s'applique **récursivement à tous les niveaux** de l'arborescence multi-module, y compris les sous-modules de sous-modules (ex : `azure/servicebus/`, `azure/redis/`, etc.).

### README.md à la racine du dépôt (ou du module parent)

Doit contenir **dans cet ordre** :

1. **Description** — rôle fonctionnel du package en 2-3 phrases
2. **Modules** — tableau listant chaque module, son artefact Maven et son rôle (si multi-module)
3. **Prérequis** — version Java, Spring Boot, éventuelles dépendances système
4. **Installation** — coordonnées Maven à copier dans un `pom.xml` consommateur
5. **Configuration** — toutes les propriétés `@ConfigurationProperties` avec valeur par défaut et description
6. **Utilisation** — tableau de liens vers le README de chaque module (pas d'exemples de code dans le README racine)
7. **Contribuer** — procédure de build local, tests, versioning (`MAJOR.MINOR.PATCH`)

### README.md à la racine de chaque module / sous-module (tous niveaux)

Doit contenir **dans cet ordre** :

1. **Description** — rôle du module dans le package
2. **Dépendances** — artefacts Maven requis (scope, version)
3. **Auto-configuration** — classe(s) `AutoConfiguration` exposées et conditions d'activation
4. **API publique** — liste des beans/interfaces exposés avec description courte
5. **Configuration** — (`@ConfigurationProperties`) est documentée dans le README de **chaque module**, pas dans le README racine — les propriétés sont spécifiques à chaque module.
5. **Configuration** — propriétés spécifiques au module (clé, type, valeur par défaut)
6. **Exemples** — snippets d'utilisation

> Toujours maintenir **tous** ces fichiers README à jour lors de tout ajout, suppression ou modification d'API publique, de module ou de sous-module.

## Gestion des versions et compatibilité

- Suivre le **versioning sémantique** strict (SemVer) : breaking change → MAJOR, nouvelle fonctionnalité → MINOR, correctif → PATCH
- Déclarer les versions des dépendances dans le POM parent via `<dependencyManagement>`
- Ne pas exposer de dépendances transitives inutiles (`<scope>provided</scope>` ou `<optional>true</optional>` autant que possible)

## Tests

- Tests unitaires : **JUnit 5** + **Mockito**
- Tests d'intégration Spring : `@SpringBootTest` avec un contexte minimal (`classes = {MaClasseAutoConfiguration.class}`)
- Nommage : `{ClasseTestée}Test.java` pour unitaires, `{ClasseTestée}IT.java` pour intégration
- Couverture minimale sur la logique métier exposée dans l'API publique

## Sécurité

- Aucun secret, credential ou clé en dur dans le code ou les ressources
- Valider les paramètres en entrée des beans publics avec Bean Validation (`@Valid`, `@NotNull`, etc.)

## Format de réponse préféré

Toujours proposer du code complet et compilable, pas de pseudo-code. Inclure les imports et la configuration Maven nécessaires.
