# GitHub Copilot Instructions — SPA React

## Stack technique

- **React 18+**
- **TypeScript** (strict mode activé)
- **Vite** (bundler)
- Gestion d'état : mécanismes natifs React — `useState`, `useContext` (pas de librairie externe)
- UI : **Fluent UI** (`@fluentui/react-components`, `@fluentui/react-icons`, `@fluentui/react-nav`)
- Tests : **Vitest** + **React Testing Library**

## Architecture & patterns

Structure hybride "pages feature-sliced" :

```
src/
├── components/   ← composants partagés
├── engine/       ← infrastructure technique (MSAL, appels REST...)
├── layout/       ← structure visuelle de l'application
├── model/        ← modèles de données / types partagés
├── service/      ← services métier et appels API
└── pages/
    ├── depot/        ← composants propres à cette page
    ├── filiales/
    ├── historique/
    └── ...
```

- Composants fonctionnels uniquement — pas de class components
- Custom hooks pour la logique réutilisable (préfixe `use`)
- Les appels API se font depuis `service/` ou `engine/`, jamais directement dans les composants

## Conventions de code

- Nommage : PascalCase pour composants et types, camelCase pour variables/fonctions, UPPER_SNAKE_CASE pour constantes
- Un composant par fichier, le fichier porte le nom du composant
- Toujours typer explicitement les props (interface `{Composant}Props`)
- Préférer `interface` pour les props, `type` pour les unions/intersections
- Utiliser `const` et arrow functions pour les composants
- Pas de `any` — typer toutes les réponses API et les états

## Composants UI

- Utiliser exclusivement les composants **Fluent UI** (`@fluentui/react-components`) — ne pas créer de composant custom si Fluent UI en fournit un équivalent
- Utiliser `@fluentui/react-icons` pour les icônes
- Respecter le thème Fluent UI — pas de styles CSS inline qui court-circuitent le design system

## Tests

- Tester le comportement, pas l'implémentation
- Utiliser `screen.getByRole`, `screen.getByText` (pas `getByTestId` en priorité)
- Nommage : `{Composant}.test.tsx`

## Sécurité

- Ne jamais utiliser `dangerouslySetInnerHTML` sans sanitisation
- Authentification via **MSAL** (géré dans `engine/`) — ne pas manipuler les tokens directement dans les composants
- Variables d'environnement via `import.meta.env.VITE_*`, jamais de secrets côté client

## Autorisation (rôles et permissions)

Détail : `docs/securite-roles.md`. Plan côté API : `docs/plan-securite-api.md`.

- Les **rôles Entra ID** (`ApiControleGestion.*`) n'existent que côté API. La SPA ne les lit **jamais** : pas de décodage de jeton, pas de comparaison de nom de rôle, pas de mapping rôle → fonctionnalité.
- La SPA raisonne uniquement en **permissions** (`deposit:read`, `deposit:write`, `common-labels:write`, `common-label-codes:write`, `subsidiaries:write`), calculées par l'API et reçues via `GET /api/me` (`service.getMe()`). Le catalogue et le mapping rôle → permission sont gérés dans la configuration de l'API.
- Le moteur d'autorisation vient du socle `@nutriset/react` : ne pas le réimplémenter ni l'envelopper dans l'application.

| Besoin | Outil |
| --- | --- |
| Verrouiller une route | `<RequirePermission permission="…">` autour de la page, dans `App.tsx` |
| Masquer une entrée de menu | champ `permission` de l'entrée dans `menu.tsx`, filtré par `filterNavSections(MENU, can)` |
| Masquer ou désactiver une action dans une page | `useCan('…')` |
| Lire l'état des droits | `useAuthorization()` (`ready`, `failed`, `can`) |

Règles :

- **Tout ajout, quel qu'il soit** (fonctionnalité, page, route, entrée de menu, action, bouton, formulaire, appel API, etc.) : demander systématiquement à l'utilisateur, avant d'implémenter, s'il faut **réutiliser une permission existante** (si l'une est pertinente, la proposer explicitement) ou **en créer une nouvelle**. Ne jamais trancher seul, y compris quand l'ajout semble mineur.
- **Toute nouvelle page ou action sensible** doit porter sa permission à deux endroits : l'entrée de menu *et* la route. Masquer le menu seul ne protège rien, l'URL reste atteignable.
- Une route sans verrou est un oubli, pas un choix : toute page métier est enveloppée dans `RequirePermission`.
- **Ne jamais décider avant `ready`** : `can()` renvoie `false` pendant le chargement, ce qui ne signifie pas « refusé ». `RequirePermission` gère déjà cet état ; dans un composant, vérifier `ready` avant d'afficher un refus.
- Un échec de `GET /api/me` n'accorde **aucune** permission. Ne jamais ajouter de repli permissif (« en cas d'erreur, tout autoriser »).
- Les noms de permissions sont des chaînes libres : une coquille compile mais refuse l'accès sans erreur. Les recopier exactement depuis `docs/securite-roles.md` et mettre ce document à jour à chaque nouvelle permission.
- Ces verrous sont **cosmétiques**. L'autorisation effective est celle que l'API applique sur chaque route : toute nouvelle permission côté SPA suppose le verrou correspondant côté API (voir `docs/plan-securite-api.md`).
- Mode maquette (`useMocks`) : `MockApiControleGestion.getMe()` accorde toutes les permissions. Pour tester un parcours restreint, modifier la liste renvoyée par ce mock.

## Format de réponse préféré

Code TypeScript complet avec imports. Inclure les types explicitement. Pas de `any`.
