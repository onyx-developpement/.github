# Socles npm et Maven : corriger au bon endroit

Un besoin technique transverse, sans règle métier, qui manque dans un socle se corrige dans le socle, pas par un contournement dans l'application. Une règle métier reste dans l'application.

## Socle npm `@nutriset/react`

- Dépôt : `C:\dev\git\NPM\npm-nutriset-react-packages` (workspaces).
- Contient uniquement du code technique, transverse et sans règle métier (MSAL, autorisation, appels REST, composants génériques).
- Montée de version : `npm version <patch|minor|major> --workspaces --include-workspace-root`.
- La publication est automatique au push sur `main` : le push est fait par l'utilisateur.
- Consommateurs : mettre à jour la dépendance dans leur `package.json` (la SPA est en `^1.3.0` au moment de la rédaction) une fois la version publiée, puis relancer `npx tsc -b` et `npx vitest run`.

## Socles Maven

Dépôts dans `C:\dev\git\Maven\` : `maven-fr.nutriset.api`, `maven-fr.nutriset.spring`, `maven-fr.nutriset.components`, `maven-fr.nutriset.common`, `maven-fr.nutriset.repositories`.

| Besoin | Où |
|---|---|
| Parent des API (`fr.nutriset:api`, 2.3.x) | `maven-fr.nutriset.api` |
| Modèles partagés entre API (BOM `fr.nutriset.components:components`, module `commons`) | `maven-fr.nutriset.components` |
| Autres briques techniques | le socle correspondant ; si le choix n'est pas évident, demander |

- Semver strict : correction compatible = patch, ajout compatible = minor, rupture = major.
- Une règle Maven du dépôt : un README par `pom.xml`. Mettre à jour le README du module modifié.
- Consommateurs : monter le parent ou le BOM dans le `pom.xml` de chaque API concernée, une fois la version publiée.
- Tester avec `mvn -P app-dependencies,webapp test` dans le socle puis dans le consommateur.

## Proxy

Un endpoint manquant dans un `api-proxy-*` se corrige dans le proxy (nouvelle version), pas dans l'API métier. Voir [orchestration et modèles](./orchestration-et-modeles.md).

## Ordre

1. Modifier le socle, ses tests et son README.
2. Monter sa version.
3. Indiquer à l'utilisateur de commiter, publier (push sur `main` pour npm, pipeline pour Maven) et d'attendre la disponibilité.
4. Monter la version chez les consommateurs.

Tant que la version n'est pas publiée, le consommateur ne peut pas la résoudre : le lister comme action manuelle bloquante.
