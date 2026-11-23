# Où vit chaque paramètre

## Dépôt `configuration` (valeurs par environnement)

- API Spring : `spring-config/spring/static/<app>/application-{dev,test,prod}.yml`. Une clé ajoutée l'est dans les trois environnements.
- Le dossier `generated/` est géré par Terraform : ne pas le modifier à la main.
- Ne jamais mettre une valeur d'environnement dans `src/main/resources` de l'API ni dans le code.
- Production : ses valeurs sont propres, à traiter seulement sur demande explicite de l'utilisateur ; le signaler dans le compte rendu si elle reste à faire.

## Secrets

- Stockés dans Key Vault, référencés `${nom}` dans le fichier de configuration.
- Jamais en clair dans la configuration, le code, un test ou un `.env`.
- Créer le secret dans Key Vault est une action manuelle à lister pour l'utilisateur.

## Permissions

- Déclarées dans `spring.security.oauth2.resourceserver.authorization.roles` de chaque environnement.
- L'API refuse de démarrer si une permission n'est accordée à aucun rôle : ajouter la permission à la configuration avant de déployer l'API.
- Les rôles Entra ID (app roles) se créent dans l'app registration : action manuelle (voir la checklist de création).

## URL d'un proxy

`api.proxy-<x>.url` dans `static/application-{env}.yml` ; l'interface `IApiProxyXxx` y renvoie par `urlConfigKey`.

## Paramètre géré par les utilisateurs métier

Ne va pas en configuration : il se modifie sans déploiement ni développeur.

- Table dédiée créée par migration Flyway.
- Endpoints de lecture et d'écriture dans l'API métier, protégés par une permission (demander : réutiliser ou créer).
- Écran dans la SPA, derrière `RequirePermission`, avec entrée de menu.
- Valeurs initiales dans la migration seulement si elles sont stables et identiques dans tous les environnements.
- Si la donnée alimente Fabric, la table entre dans la chaîne de données (`schema-change-end-to-end`).

## Configuration de la SPA

- Les fichiers `.env.*` ne portent que `VITE_API_URL`.
- Tout le reste (paramètres MSAL, autres valeurs d'environnement) vient de `GET {VITE_API_URL}/frontend-config`, servi par l'API depuis le dépôt `configuration`.
- Une nouvelle valeur utile à la SPA avant connexion s'ajoute à la configuration de l'API et à ce endpoint, pas à un `.env`.
- Aucun secret côté client.
