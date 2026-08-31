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

## Format de réponse préféré

Code TypeScript complet avec imports. Inclure les types explicitement. Pas de `any`.
