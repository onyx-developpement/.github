# Couche SPA (React, TypeScript strict, Vite, Fluent UI, Vitest)

## Où chercher

- `src/model/*.model.ts` : types des DTO et des requêtes. Un type qui reflète une réponse API doit suivre le contrat de l'API.
- `src/service/ApiControleGestion.ts` : classe décorée qui décrit les appels (méthode HTTP, paramètres de requête). Un paramètre renommé côté API l'est ici aussi, avec `@QueryParam`.
- `src/service/BusinessService.ts` : couche métier, construit les DTO envoyés à l'API.
- `src/service/MockApiControleGestion.ts` : données et règles de contrôle simulées. Elles doivent suivre le contrat réel (identifiants, validations, messages), sinon la SPA se comporte autrement en local.
- `src/pages/**` : écrans qui lisent ou écrivent le champ. Chercher le nom du champ et le nom de ses dérivés (étiquettes, filtres, tris, colonnes de grille).
- `docs/` : documents de sécurité et de rôles, à mettre à jour si une page ou une permission disparaît.

## Règles

- Un champ rendu optionnel dans un type pour éviter de modifier tous les objets de test ou de stub doit l'être parce que l'API peut réellement l'omettre, pas par commodité. Sinon le rendre obligatoire et corriger les appelants.
- Une requête de mise à jour qui remplace l'état existant renseigne toujours explicitement chaque champ : un oubli ferait perdre la valeur.
- Une erreur API a la forme `{ status, error: { message } }` : réutiliser l'utilitaire existant d'extraction du premier message plutôt que de le réécrire.
- Une page supprimée entraîne la suppression de sa route, de son entrée de menu, de ses icônes devenues inutilisées et de sa documentation.

## Vérifications

- `npx tsc -b` : les erreurs de type révèlent les appelants oubliés.
- `npx vitest run` : ajouter un test sur toute fonction pure introduite ou modifiée (arbres, calculs, validations).
- `npx oxlint src` : ne pas corriger les avertissements existants hors périmètre, ne pas en ajouter.
