# GitHub Copilot Instructions — Organisation onyx-developpement

## Valeurs communes

- Code lisible avant tout : nommer les choses selon leur intention métier
- Revues de code systématiques — le code doit être compréhensible sans commentaire
- Sécurité by design : OWASP Top 10, pas de secrets dans le code, validation des entrées
- Tests automatisés obligatoires sur la logique métier

## Conventions transversales

### Branching

- Convention de nommage des branches : `yyyyMMdd-<nom-feature-ou-fix>` (ex: `20260831-ajout-endpoint-commandes`)
- La branche principale est `main`

### Langue

- **Code** (nommage variables, fonctions, classes, méthodes) : **anglais**
- **Commentaires** et **messages de commit** : **français**

### CI / Merge

- Le pipeline CI doit être **vert** avant tout merge dans `main`

### Git

- Ne jamais faire de commit automatiquement : les commits doivent toujours être initiés explicitement par le développeur

> Pour les instructions spécifiques à votre type de dépôt, voir le fichier `.github/copilot-instructions.md` du dépôt.
