# GitHub Copilot Instructions — SPA Contrôle de Gestion

Application React de dépôt et de traitement des fichiers P&L (Profit & Loss) des filiales.
La documentation fonctionnelle détaillée se trouve dans [`docs/`](../docs/README.md) — **la lire avant
toute modification d'une page existante**.

## Stack technique

- **React 19** — composants fonctionnels uniquement
- **TypeScript** (mode strict, décorateurs legacy activés)
- **Vite 8** (bundler) + **react-router-dom 7** (data router)
- **`@nutriset/react`** — socle applicatif interne publié sur Azure Artifacts : configuration,
  authentification MSAL, client REST décoré, layout Fluent UI
- Gestion d'état : mécanismes natifs React — `useState`, `useContext` (pas de librairie externe)
- UI : **Fluent UI** (`@fluentui/react-components`, `@fluentui/react-icons`)
- Lecture de fichiers Excel : `xlsx` et `@extend-ai/react-xlsx` (viewer WASM)
- Tests : **Vitest** + **React Testing Library**
- Lint : **oxlint**

## Architecture & patterns

Structure hybride « pages feature-sliced ». L'infrastructure technique (MSAL, REST, layout) n'est
**pas** dans ce dépôt : elle vient du socle `@nutriset/react`.

```
docs/              ← documentation fonctionnelle (à tenir à jour)
src/
├── components/    ← composants partagés à l'application
├── model/         ← DTO et constantes métier (pnl.model.ts)
├── service/       ← déclaration de l'API REST et service métier
├── menu.tsx       ← entrées du menu de navigation
├── App.tsx        ← amorçage du socle + déclaration des routes
└── pages/
    ├── depot/
    ├── filiales/
    ├── historique/
    ├── libelles-communs/
    └── mappings/
```

### Ce que fournit le socle

| Import | Rôle |
| --- | --- |
| `initCore({ apiUrl, basePath, dev, useMocks })` | Injecte la configuration ; appelé **une fois** au niveau module dans `App.tsx`, avant tout rendu |
| `useAuthBootstrap()` | Charge le config server, initialise MSAL, gère la redirection Entra ID ; retourne `{ msal, ready, error, getToken }` |
| `SocleProvider` | `FluentProvider` + `MsalProvider` + écran de chargement / d'erreur |
| `AppLayout` | Topbar + menu + zone de contenu ; router-agnostique (`sections`, `selectedPath`, `onNavigate`, `children`) |
| `RestClient`, `@RequestMapping`, `@GetMapping`… | Client REST par décorateurs |
| `ConfigurationProperties`, `getCoreOptions()` | Accès à la configuration chargée |

Le socle ne lit pas `import.meta.env` : toute variable d'environnement lui est passée via `initCore`.

### Règles

- Les appels HTTP ne se font que depuis `service/`, jamais dans un composant
- Un endpoint = une méthode décorée dans `ApiControleGestion`, exposée via `BusinessService`
- Les composants consomment les données via `useService()`
- Custom hooks pour la logique réutilisable (préfixe `use`)
- Ne pas réimplémenter dans l'application ce que le socle fournit déjà — si le socle doit évoluer,
  le signaler plutôt que de contourner

## Conventions de code

- Nommage : PascalCase pour composants et types, camelCase pour variables/fonctions,
  UPPER_SNAKE_CASE pour constantes
- Un composant par fichier, le fichier porte le nom du composant
- Toujours typer explicitement les props (interface `{Composant}Props`)
- Préférer `interface` pour les props, `type` pour les unions/intersections
- Pas de `any` — typer toutes les réponses API et les états
- Libellés, messages et commentaires en français

## Composants UI

- Utiliser exclusivement les composants **Fluent UI** — ne pas créer de composant custom si Fluent UI
  en fournit un équivalent
- Utiliser `@fluentui/react-icons` pour les icônes
- Styliser avec `makeStyles` + `tokens` ; pas de styles inline qui court-circuitent le design system
- `makeStyles` (Griffel) interdit les raccourcis CSS (`borderColor`, `borderWidth`…) : utiliser
  `shorthands.*`

## Tests

- Tester le comportement, pas l'implémentation
- Utiliser `screen.getByRole`, `screen.getByText` (pas `getByTestId` en priorité)
- Nommage : `{Composant}.test.tsx`, à côté du composant

## Sécurité

- Ne jamais utiliser `dangerouslySetInnerHTML` sans sanitisation
- Authentification via **MSAL**, encapsulée par le socle — ne jamais manipuler un token dans un
  composant ; les tokens s'obtiennent via le `getToken` passé au `ServiceProvider`
- Variables d'environnement via `import.meta.env.VITE_*`, jamais de secrets côté client
- La configuration Entra ID est lue au démarrage depuis `GET {VITE_API_URL}/frontend-config`

## Documentation

La documentation fonctionnelle vit dans `docs/` et sert autant aux développeurs qu'aux assistants IA :
elle doit permettre de comprendre l'application **sans lire le code**.

```
docs/
├── README.md                    ← index, vocabulaire métier, parcours principaux
├── architecture.md              ← couches, amorçage, authentification, configuration
├── domaine.md                   ← DTO, types P&L, règles transverses
├── api.md                       ← endpoints REST consommés
└── fonctionnalites/
    └── {page}.md                ← une fiche par page de l'application
```

### Quand la mettre à jour

Toute modification qui change le comportement observable de l'application impose de mettre à jour la
documentation **dans le même commit** : nouvelle page, nouvelle action, nouvelle règle de validation,
nouveau statut, nouvel endpoint, changement de parcours utilisateur.

### Comment l'écrire

- Décrire le **comportement métier**, pas l'implémentation : pas de nom de `useState`, pas d'extrait
  de JSX, pas de détail de style
- Citer en revanche les noms exacts des routes, méthodes de `BusinessService`, types et constantes :
  ce sont les points d'ancrage qui permettent de relier la documentation au code
- Privilégier les tableaux et les listes numérotées aux paragraphes
- Rendre les états et transitions explicites : « à l'étape N, le bouton X est actif si … »
- Énumérer exhaustivement les valeurs possibles (types P&L, mois attendus, colonnes affichées)
- Documenter les cas d'erreur et le message vu par l'utilisateur
- Une fiche par page, structurée de la même façon : *But métier*, *Parcours utilisateur*, *Actions*,
  *Règles métier*, *Cas d'erreur*, *Appels service*
- Lier les fiches entre elles avec des liens relatifs

## Format de réponse préféré

Code TypeScript complet avec imports. Inclure les types explicitement. Pas de `any`.
