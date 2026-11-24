---
name: new-api-spa
description: "Créer une nouvelle paire de dépôts api-<nom> / spa-<nom> de bout en bout : dépôts GitHub, squelette (archetype Maven, npm create @nutriset/react-spa), pipelines Azure DevOps, ruleset, modules Terraform dans azure-infrastructure et pull requests. À utiliser pour démarrer une nouvelle application, une nouvelle API ou une nouvelle SPA. Mots-clés : nouvelle API, nouvelle SPA, nouveau projet, scaffold, création de dépôt, Fortiweb, WAF, pipeline."
---

# Création d'une paire api-<nom> / spa-<nom>

Le script `scripts/New-ApiSpaRepositories.ps1` enchaîne : dépôts GitHub, squelette, pipelines ADO, ruleset, PR d'init, modules Terraform (prod et test) et PR infra.

## Procédure

1. Demander le nom (minuscules, chiffres, tirets, commence par une lettre). Ne jamais le deviner.
2. Demander ce qui est à créer : API, SPA ou les deux (`-Only Api|Spa`).
3. Demander l'exposition Fortiweb si elle n'est pas donnée : `PartoutSaufOT`, `InterneSaufOT` ou `OTUniquement` (`-WafPreset`).
4. Demander si l'API est utilisée par d'autres API Java (`-DefinitionPipeline $true|$false`).
5. Lancer d'abord un essai à blanc et en montrer le résultat :

   ```powershell
   .\scripts\New-ApiSpaRepositories.ps1 -Name <nom> -WafPreset <preset> -DryRun
   ```

6. Demander confirmation, puis lancer sans `-DryRun`.
7. Afficher les URLs des PR du résumé final.

## Prérequis

- `gh auth login` avec SSO autorisé sur l'organisation (si `GH_TOKEN` est défini dans l'environnement, le retirer pour la session).
- Authentification Azure Artifacts pour npm, et accès Azure DevOps.
- Clone local de `azure-infrastructure` à jour et à arbre propre (le script change de branche).

## Options utiles

- `-NoPublish` : commit local de la partie infra, sans push ni PR, et sans toucher à GitHub.
- `-InfraPath`, `-ApiRoot`, `-SpaRoot` : chemins des clones.

## Après l'exécution

- Relire et merger les PR : init api/spa, puis infra.
- OAuth2 : l'API expose le scope `Api<Nom>.All` et la SPA est liée à `var.apis.api_<nom>` (avec `-Only Spa`, l'API doit déjà exister dans `azure-infrastructure`). Ajouter les `app_roles` de l'API si besoin.
- Vérifier que les pipelines ADO utilisent `main` et que le ruleset `require-ci-status-check` est actif.
