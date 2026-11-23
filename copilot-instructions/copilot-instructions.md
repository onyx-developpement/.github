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
- Ne jamais pousser, réécrire l'historique ni supprimer une branche sans demande explicite
- Ne jamais modifier la production (configuration, fichiers, déploiement) sans demande explicite, et le signaler dans le compte rendu

### Méthode de travail de Copilot

- Ne faire que ce qui est demandé. Quand un choix de conception engage un contrat ou un droit (nom ou forme d'un champ d'API, permission, migration de base, clé d'une dimension), poser la question avec les options plutôt que de trancher
- Vérifier avant d'affirmer : lancer les tests, le typage ou le lint du dépôt concerné, et dire explicitement ce qui n'a pas été exécuté (notebooks Fabric, chemins Delta, tests d'intégration déjà en échec). Ne jamais conclure « pas de régression » sans preuve
- Un échec de test antérieur à la modification se signale tel quel : ne pas le corriger hors périmètre, ne pas le masquer
- Modifier un fichier avec les outils d'édition, jamais par redirection ni commande de terminal. Une ancre de remplacement doit être unique et ne pas englober l'en-tête d'un bloc voisin ; après une série d'éditions, relancer la compilation ou une recherche pour s'assurer que tout s'est appliqué
- Ne pas lancer en parallèle une édition et la commande qui la vérifie : elle lirait l'état d'avant
- Relire un fichier avant de le modifier à nouveau : l'utilisateur ou un formateur a pu le changer entre deux demandes
- Les recherches du workspace ne voient pas les dépôts voisins non ouverts : les lire en lecture seule avec le terminal, ou demander un workspace multi-racine
- Une évolution qui traverse plusieurs dépôts (base, API, SPA, réplication, Gold, modèle sémantique) suit le skill `schema-change-end-to-end`
- Créer ou faire évoluer une SPA et son API métier (fonctionnalité, écran, paramétrage, rattachement à un domaine métier) suit le skill `spa-api-end-to-end`
- Un fichier de domaine (`domains/`) se modifie uniquement dans le dépôt `.github`, jamais dans les copies des autres dépôts : la GitHub Action les y déploie. Une fois l'action passée, un `git pull` dans le dépôt concerné suffit à récupérer la copie à jour
- Fichiers temporaires dans un dossier temporaire hors du dépôt, supprimés en fin de tâche ; le signaler si la suppression échoue
- Pas de document Markdown de synthèse non demandé. Un commentaire dit ce que le code ne montre pas, en une ligne, sans raconter la modification
- Terminer par un compte rendu court : ce qui a changé, ce qui reste à faire à la main (déploiement, production, réplication), ce qui n'a pas été vérifié

### Plan, modèle et contexte

- Tout chantier commence par un **plan** validé avant la première modification, sauf un changement trivial limité à un seul fichier. Le plan découpe le travail en phases et indique pour chacune le modèle et la taille de contexte
- Choix du modèle :
  - **Opus** : conception, contrat d'API ou de données, arbitrage, débogage difficile
  - **Sonnet** : implémentation (y compris sur plusieurs dépôts) et tests
  - **Haiku** : documentation de textes déjà arrêtés, renommages mécaniques, montées de version
- Choix du contexte : le plus petit qui suffit à la phase ; ouvrir une nouvelle session ou compacter plutôt que de traîner l'historique des phases précédentes
- **Fin de phase** : annoncer qu'elle est terminée, indiquer le modèle et le contexte de la phase suivante, demander à l'utilisateur de changer de modèle et de lancer `/compact` (ou d'ouvrir une nouvelle session), et fournir le résumé de l'état à reprendre. Ne pas enchaîner la phase suivante avant sa réponse
- Une tâche de documentation pure qui ne demande pas de comprendre le code se propose en une phrase dans une nouvelle session avec Haiku ; en cas de refus, continuer dans la session courante
- Lire un fichier par plage de lignes, pas en entier ; ne pas relire un fichier déjà lu et inchangé
- Borner toute sortie de terminal (`-First`, `Select-String`, colonnes utiles) ; ne jamais afficher un diff, un log ou une trace complets
- Pour une exploration large (plusieurs fichiers ou dépôts), déléguer à un sous-agent qui ne renvoie qu'un résumé
