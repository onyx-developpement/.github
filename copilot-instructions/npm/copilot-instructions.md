# GitHub Copilot Instructions — Socle React Nutriset

Monorepo des packages npm servant de socle aux SPA React Nutriset, publiés sur le feed Azure
Artifacts `nutriset-transverse`. La documentation technique se trouve dans
[`docs/`](../docs/README.md) — **la lire avant toute modification de l'API publique**.

Ce dépôt est une **bibliothèque**, pas une application : chaque modification est vue par toutes les
SPA consommatrices. Privilégier systématiquement la rétrocompatibilité et le paramétrage à
l'ajout de comportement implicite.

## Stack technique

- **React 19** en `peerDependencies` — jamais en `dependencies`
- **TypeScript** (mode strict, décorateurs legacy activés)
- **Vite 8** en *library mode* pour le bundle, **`tsc`** pour les déclarations
- UI : **Fluent UI** (`@fluentui/react-components`, `@fluentui/react-icons`, `@fluentui/react-nav`)
- Authentification : **MSAL** (`@azure/msal-browser`, `@azure/msal-react`)
- Tests : **Vitest** + **React Testing Library**
- Lint : **oxlint**
- npm workspaces (pas de pnpm, pas de Lerna, pas de Changesets)

## Architecture

```
docs/                          ← documentation technique (à tenir à jour)
azure-pipelines/
└── pipeline-cicd.yml          ← wrapper extends vers pipelines-assets
packages/
├── react/                     ← @nutriset/react
│   ├── src/
│   │   ├── index.ts           ← réexporte core + layout
│   │   ├── core/              ← point d'entrée ./core
│   │   │   ├── config/        ← initCore, ConfigurationProperties
│   │   │   ├── msal/          ← instances MSAL, scopes, cache de jetons
│   │   │   ├── rest/          ← RestClient + décorateurs
│   │   │   ├── auth/          ← useAuthBootstrap
│   │   │   └── SocleProvider.tsx
│   │   ├── layout/            ← point d'entrée ./layout
│   │   └── test/setup.ts
│   ├── tsconfig.json          ← typecheck des sources
│   ├── tsconfig.build.json    ← émission des .d.ts
│   └── tsconfig.node.json     ← typecheck de vite.config.ts
└── create-react-spa/          ← @nutriset/create-react-spa
    ├── index.js               ← CLI, Node natif, aucune dépendance
    └── template/              ← squelette d'application généré
```

### Ce qui a sa place dans le socle

| Critère | Exemple |
| --- | --- |
| Technique et transverse | Authentification, client REST, configuration, chrome applicatif |
| Réutilisable par au moins deux SPA | Layout, indicateur d'étapes générique |
| Sans règle métier | Aucun libellé, statut ou workflow propre à une application |

Tout ce qui porte du vocabulaire métier reste dans l'application consommatrice.

## Règles de conception

Ces règles sont non négociables : chacune corrige un défaut constaté.

1. **Aucun accès à `import.meta.env`.** Ces valeurs sont résolues à la compilation de la
   *bibliothèque*, donc vides chez le consommateur. Toute configuration passe par `initCore`.
2. **Aucune dépendance au routeur.** Les composants exposent `selectedPath`, `onNavigate` et
   `children` ; l'application garde le contrôle de son routeur.
3. **Aucun accès au service métier du consommateur.** Un composant qui a besoin d'une donnée
   applicative la reçoit par une prop de type fonction (ex. `getUserPhoto`).
4. **Aucune valeur métier codée en dur.** Titre, entrées de menu, icônes et libellés sont des props.
5. **Instance unique des contextes.** React et React DOM sont des `peerDependencies` ; Fluent UI et
   MSAL sont des `dependencies` afin d'être transitives, mais restent externalisées au build pour
   que npm les dédoublonne.
6. **Rien n'est bundlé.** `rollupOptions.external` exclut toutes les dépendances.

## Conventions de code

- Nommage : PascalCase pour composants et types, camelCase pour variables/fonctions,
  UPPER_SNAKE_CASE pour constantes
- Un composant par fichier, le fichier porte le nom du composant
- Toujours typer explicitement les props (interface `{Composant}Props`) et **les exporter**
- Préférer `interface` pour les props, `type` pour les unions/intersections
- Pas de `any`
- Libellés, messages et commentaires en français
- Styliser avec `makeStyles` + `tokens`. Griffel interdit les raccourcis CSS (`borderColor`,
  `borderWidth`, `borderStyle`…) : utiliser `shorthands.*`
- Une icône passée en prop est typée `ReactElement`, pas `ReactNode` : les emplacements Fluent
  (`Slot<'span'>`) n'acceptent pas l'union complète de `ReactNode`

## API publique

- Un fichier `index.ts` par point d'entrée liste explicitement les exports ; pas de `export *`
  depuis un module de feature
- Dans `src/index.ts`, les réexports désignent le fichier et non le dossier :
  `export * from './core/index'`. Un réexport de dossier n'est pas résolu par les consommateurs en
  `moduleResolution: "bundler"`, et `skipLibCheck: true` masque l'erreur : le symptôme est un
  « has no exported member » incompréhensible côté application
- Tout type utilisé dans une signature publique doit être exporté

## Build et packaging

- `npm run build` = `typecheck` → `vite build` → `tsc -p tsconfig.build.json`
- Les déclarations sont générées par **`tsc`** (`emitDeclarationOnly`, `rootDir: src`,
  `outDir: dist`). Ne pas réintroduire `vite-plugin-dts` : en multi-entrées il produit des
  déclarations vides avec `rollupTypes`, et ignore `entryRoot` sans lui
- `tsc` s'exécute **après** `vite build`, qui vide `dist/`
- Le champ `exports` déclare `types` avant `import` ; toute nouvelle entrée doit y être ajoutée,
  ainsi que dans `build.lib.entry`
- Vérifier le paquet avant publication : `npx publint` et
  `npx @arethetypeswrong/cli --pack . --profile esm-only`. La résolution `bundler` doit être verte ;
  `node16` n'est pas supportée et c'est assumé

## Versionnement et publication

- Publication automatique sur chaque commit `main` par le pipeline, qui ignore une version déjà
  présente sur le feed. Publier revient donc à monter la version
- Semver strict, le socle étant en `1.x` :

  | Changement | Version |
  | --- | --- |
  | Correction sans impact sur l'API | patch |
  | Nouvel export, nouvelle prop **optionnelle** | mineure |
  | Renommage, suppression, prop devenue obligatoire, changement de comportement par défaut | **majeure** |

- Les deux packages sont versionnés ensemble : `npm version <version> --workspaces --include-workspace-root`
- `@nutriset/create-react-spa` dérive la version du socle qu'il injecte dans le template de sa
  propre version

## Tests

- Tester le comportement observable, pas l'implémentation
- Utiliser `screen.getByRole`, `screen.getByText` (pas `getByTestId` en priorité)
- Nommage : `{Composant}.test.tsx`, à côté du composant
- Envelopper le rendu dans un `FluentProvider`
- `src/test/setup.ts` contient deux correctifs à conserver :
  - `globalThis.NodeFilter` est repositionné depuis `window` — l'environnement jsdom de Vitest ne le
    recopie pas, alors que tabster (focus management de Fluent UI) l'y attend
  - `afterEach(cleanup)` — l'auto-cleanup de Testing Library n'est actif qu'avec `globals: true`
- `tabster` est épinglé par `overrides` : ne pas retirer sans vérifier l'interopérabilité ESM

## CLI et template

- `packages/create-react-spa/index.js` n'utilise que des modules Node natifs : aucune dépendance
- Les fichiers du template commençant par un point sont stockés préfixés par `_` (`_gitignore`,
  `_env.test`…) : npm les exclurait sinon du tarball publié. Le mapping est dans `DOTFILES`
- Les valeurs variables sont des jetons `{{nom}}` substitués à la copie
- Aucun `.npmrc` n'est généré : le registre est configuré au niveau utilisateur en local, et fourni
  par `pipelines-assets` en CI
- Toute évolution de l'API du socle qui change l'amorçage doit être répercutée dans
  `template/src/App.tsx`

## Documentation

La documentation vit dans `docs/` et est **technique** : elle décrit l'API publique, ses contrats et
ses pièges, pour qu'un développeur ou un assistant IA puisse utiliser le socle sans lire ses sources.

```
docs/
├── README.md              ← index, principes de conception, matrice des points d'entrée
├── core.md                ← référence de @nutriset/react/core
├── layout.md              ← référence de @nutriset/react/layout
└── create-react-spa.md    ← CLI de génération et contenu du template
```

### Quand la mettre à jour

Toute modification de l'API publique impose de mettre à jour la documentation **dans le même
commit** : nouvel export, nouvelle prop, changement de valeur par défaut, changement de contrat,
dépréciation.

### Comment l'écrire

- Une section par symbole exporté, avec sa signature TypeScript exacte
- Un tableau des paramètres et des props : nom, type, valeur par défaut, description
- Décrire le **contrat** : ce que la fonction garantit, ce qu'elle exige de l'appelant, ce qu'elle
  fait en cas d'erreur
- Donner un exemple d'utilisation minimal et compilable pour chaque point d'entrée
- Documenter explicitement les pièges et les raisons des choix non évidents — c'est ce qui évite
  qu'ils soient défaits par une prochaine modification
- Indiquer les effets de bord : redirection pleine page, écriture en `localStorage`, appel réseau au
  montage

## Format de réponse préféré

Code TypeScript complet avec imports. Inclure les types explicitement. Pas de `any`.
