# Checklist de création (SPA, API métier, proxy)

Rien de ceci ne se fait depuis le code : c'est une liste d'actions manuelles à remettre à l'utilisateur, avec ce que Copilot a préparé. Vérifier chaque ligne dans les dépôts voisins existants avant d'affirmer (un dépôt récent du même type sert de référence).

## Commun

| Action | Qui |
|---|---|
| Créer le dépôt dans l'organisation, branche `main` | Utilisateur |
| Poser les topics : technique (`api`, `spa`, `config`...) et `domain-<nom>` (ou `domain-all`) | Utilisateur |
| Vérifier que le slug d'équipe reçoit les instructions et skills (`Deploy-CopilotInstructions.ps1`, `deploy.json`) | Utilisateur |
| Ajouter le dépôt au `workspaces/<domaine>.code-workspace` du dépôt `.github` | Copilot, dans `.github` |
| Créer ou compléter le contrat `domains/<nom>/<nom>.md` | Copilot, dans `.github` |
| Pipelines Azure DevOps (`azure-pipelines/pipeline-ci.yml`, `pipeline-cicd.yml`) : copier un dépôt du même type | Copilot prépare, utilisateur crée le pipeline |

## Nouvelle API métier

| Action | Qui |
|---|---|
| Générer le projet avec le parent `fr.nutriset:api` (version courante) et le package `fr.nutriset.api<nom>` ; le filtre du pipeline impose `fr/nutriset/api*/definition` | Copilot |
| Port local : 7001 à 7025 sont pris, `api-mes` = 7026 ; choisir le suivant libre ; port de debug = port moins 2000 | Copilot propose, utilisateur valide |
| App registration Entra ID et app roles (`ApiControleGestion.*` pour l'existant) | Utilisateur |
| Terraform (dossier `generated/` du dépôt `configuration`) : ressources de l'application | Utilisateur |
| Fichiers `spring-config/spring/static/<app>/application-{dev,test,prod}.yml` : permissions, URL des proxies, clés ; secrets dans Key Vault | Copilot prépare les fichiers, utilisateur crée les secrets |
| Endpoint `GET /frontend-config` pour la SPA | Copilot |
| Base de données et Flyway : clé de base, dossier `databases/migration/azure/postgresql/<clé>/` | Copilot, base créée par l'utilisateur |
| README structuré (voir [documentation](./documentation.md)) | Copilot |

## Nouvelle SPA

| Action | Qui |
|---|---|
| Générer depuis le gabarit de la SPA existante : React 19, TypeScript strict, Vite, Fluent UI, `@nutriset/react` | Copilot |
| `.env.*` : seulement `VITE_API_URL` | Copilot |
| App registration SPA (redirections, accès à l'API) | Utilisateur |
| Permissions : `GET /api/me`, `RequirePermission`, `docs/securite-roles.md` | Copilot |
| Mode maquette (`MockApiControleGestion`) | Copilot |
| `docs/` et README | Copilot |

## Nouvel `api-proxy-<x>`

| Action | Qui |
|---|---|
| Dépôt et projet : parent `fr.nutriset:api`, package `fr.nutriset.apiproxy<x>` | Copilot |
| Interface `definition/IApiProxyXxx` avec `@RestResource(urlConfigKey="api.proxy-<x>.url", aadOAuthClientRegistrationId=…)` | Copilot |
| Pour M3 : interfaces `mvxapim3/definition/<PGM>MI.java` ; beaucoup de transactions manquent, vérifier avant usage | Copilot |
| Inscription OAuth et droits côté système externe et Entra ID | Utilisateur |
| URL dans `static/application-{env}.yml` de chaque API consommatrice | Copilot |
| Publication de l'artefact `fr.nutriset:api-proxy-<x>` avant consommation | Utilisateur |

## Fin de création

Lister dans le compte rendu chaque ligne « Utilisateur » restante, avec le dépôt ou le portail concerné, et signaler ce qui n'a pas pu être vérifié (pipeline, Terraform, secrets).
