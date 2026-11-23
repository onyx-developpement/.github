# Orchestration des proxies et emplacement des modèles

## Qui appelle qui

```
SPA  ->  API métier  ->  api-proxy-<x>  ->  système externe (M3, Jira...)
```

- La SPA n'appelle que son API métier, jamais un proxy ni un système externe.
- L'API métier orchestre : elle appelle un ou plusieurs proxies, applique les règles métier et renvoie à la SPA un DTO adapté.
- Un proxy encapsule un système externe et ne porte pas de règle métier.

## Appeler un proxy depuis l'API métier

1. Ajouter la dépendance Maven `fr.nutriset:api-proxy-<x>` (version publiée).
2. Injecter l'interface `definition/IApiProxyXxx` du proxy ; elle porte `@RestResource(urlConfigKey="api.proxy-<x>.url", aadOAuthClientRegistrationId=…)`.
3. Déclarer l'URL `api.proxy-<x>.url` dans `static/application-{env}.yml` du dépôt `configuration`, pour chaque environnement.
4. Le client OAuth (`aadOAuthClientRegistrationId`) suppose une inscription et un rôle côté Entra ID : action manuelle à lister.
5. Si l'endpoint ou le champ nécessaire manque dans le proxy, le proxy évolue (nouvelle version, voir [socles et versions](./socles-et-versions.md)).

Le motif `repository/IApiXxx` n'est valable que pour un proxy qui appelle une application externe ; ce n'est pas la façon d'appeler un autre proxy de l'organisation.

## Où va chaque modèle

| Modèle | Emplacement |
|---|---|
| DTO exposé à la SPA | `definition` de l'API métier, propre à la SPA. Jamais un DTO de proxy ou de `commons` renvoyé tel quel |
| Modèle partagé entre plusieurs API | `fr.nutriset.components:commons` (module `commons` du BOM : `client`, `contact`, `currency`, `order`, `mail`, `workflow`...) |
| Partie spécifique à une API | `definition` de cette API, même si elle étend un modèle de `commons` |
| Type TypeScript d'un DTO | `src/model` de la SPA, aligné sur le DTO de l'API métier |
| Modèle d'un système externe | Dans le proxy qui l'encapsule |

- Un modèle partagé qui manque dans `commons` s'y ajoute (nouvelle version du BOM) plutôt que de se dupliquer dans deux API.
- Le mapping entre un modèle de proxy ou de `commons` et le DTO de la SPA se fait dans l'API métier (mapper MapStruct).
- Les modèles JSON de la SPA ne remontent pas dans `commons` : ils sont propres à la SPA.

## Erreurs

Une erreur d'un proxy est traduite par l'API métier en erreur à la forme attendue par la SPA (`{ status, error: { message } }`) ; ne pas laisser fuiter le message ou la structure du système externe.
