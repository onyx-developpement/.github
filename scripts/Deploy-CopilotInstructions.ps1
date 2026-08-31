<#
.SYNOPSIS
    Déploie les fichiers copilot-instructions.md dans tous les dépôts GitHub
    de l'organisation onyx-developpement, selon l'équipe à laquelle ils appartiennent.

.DESCRIPTION
    - Equipe "SPA"          → instructions React SPA
    - Equipe "API Backend"  → instructions Spring WebFlux
    - Equipe "Data"         → instructions Microsoft Fabric

.PREREQUISITES
    - GitHub CLI (gh) installé et authentifié (gh auth login)
    - Droits admin ou maintainer sur les équipes de l'organisation

.EXAMPLE
    .\Deploy-CopilotInstructions.ps1
    .\Deploy-CopilotInstructions.ps1 -WhatIf          # simulation sans écriture
    .\Deploy-CopilotInstructions.ps1 -Team "api-backend"  # une seule équipe (slug = nom du sous-dossier)
#>

param(
    [switch] $WhatIf,

    # Slug de l'équipe = nom du sous-dossier dans copilot-instructions/ (ex: spa, api-backend, data)
    # Laisser vide pour traiter tous les sous-dossiers détectés automatiquement
    [string] $Team,

    [string] $CommitMessage = "chore: add GitHub Copilot instructions [skip ci]"
)

$ErrorActionPreference = "Stop"

# ─── GitHub Actions : lecture des inputs via variables d'environnement ─────────
$script:IsGHA = $Env:GITHUB_ACTIONS -eq 'true'

if ($script:IsGHA) {
    if ($Env:INPUT_WHATIF         -eq 'true') { $WhatIf        = $true }
    if ($Env:INPUT_TEAM)                      { $Team          = $Env:INPUT_TEAM }
    if ($Env:INPUT_COMMIT_MESSAGE)            { $CommitMessage = $Env:INPUT_COMMIT_MESSAGE }
}

# ─── Configuration ────────────────────────────────────────────────────────────
# GITHUB_REPOSITORY_OWNER est positionné automatiquement par le runner GitHub Actions
$script:Org        = if ($Env:GITHUB_REPOSITORY_OWNER) { $Env:GITHUB_REPOSITORY_OWNER } else { "onyx-developpement" }
$script:TargetFile = ".github/copilot-instructions.md"
# GITHUB_WORKSPACE pointe sur la racine du checkout dans GitHub Actions
$script:TemplateDir = if ($Env:GITHUB_WORKSPACE) {
    Join-Path $Env:GITHUB_WORKSPACE "copilot-instructions"
} else {
    Join-Path $PSScriptRoot ".." "copilot-instructions"
}

# ──────────────────────────────────────────────────────────────────────────────

function Write-GHALog {
    param([string] $Level, [string] $Message)
    if ($script:IsGHA) {
        Write-Output "::${Level}::${Message}"
    } elseif ($Level -eq 'warning') {
        Write-Warning $Message
    } elseif ($Level -eq 'error') {
        Write-Error $Message -ErrorAction Continue
    } else {
        Write-Output $Message
    }
}

function Get-TeamRepos {
    param([string] $Slug)
    $result = gh api "orgs/$script:Org/teams/$Slug/repos" --paginate --jq '.[] | select(.archived == false) | .full_name'
    if ($LASTEXITCODE -ne 0) {
        Write-GHALog 'warning' "Impossible de recuperer les depots du slug '$Slug'"
        return @()
    }
    # Garantir un tableau meme si 1 seul résultat
    return @($result)
}

function Deploy-ToRepo {
    param([string] $Repo, [string] $TemplatePath)

    if ($WhatIf) {
        Write-Output "  [WhatIf] $Repo --> $script:TargetFile"
        return $true
    }

    $content        = Get-Content $TemplatePath -Raw -Encoding UTF8
    $encoded        = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))

    # SHA requis si le fichier existe déjà (sinon 409 Conflict)
    $existing = gh api "repos/$Repo/contents/$script:TargetFile" 2>$null | ConvertFrom-Json
    $sha      = if ($existing -and $existing.sha) { $existing.sha } else { $null }

    $body = @{ message = $CommitMessage; content = $encoded }
    if ($sha) { $body.sha = $sha }

    $bodyJson = $body | ConvertTo-Json -Compress
    $out = $bodyJson | gh api "repos/$Repo/contents/$script:TargetFile" --method PUT --input - 2>&1

    if ($LASTEXITCODE -eq 0) {
        $verb = if ($sha) { "mis a jour" } else { "cree" }
        Write-Output "  [OK] $Repo ($verb)"
        return $true
    } else {
        Write-GHALog 'error' "[ERREUR] $Repo : $out"
        return $false
    }
}

# ─── Main ─────────────────────────────────────────────────────────────────────
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "gh CLI introuvable." }

# GH_TOKEN est utilisé automatiquement par gh CLI (secrets.COPILOT_DEPLOY_TOKEN dans le workflow)
# GITHUB_TOKEN est le fallback natif GitHub Actions
if (-not $Env:GH_TOKEN -and -not $Env:GITHUB_TOKEN) {
    Write-GHALog 'warning' "Ni GH_TOKEN ni GITHUB_TOKEN n'est defini. L'authentification gh pourrait echouer."
}

# Découverte des slugs : soit le paramètre $Team, soit tous les sous-dossiers de $script:TemplateDir
if ($Team) {
    $slugs = @($Team)
} else {
    $slugs = @(Get-ChildItem -Path $script:TemplateDir -Directory | Select-Object -ExpandProperty Name)
}

if ($slugs.Count -eq 0) { throw "Aucun sous-dossier trouve dans : $script:TemplateDir" }

$summary   = [System.Collections.Generic.List[string]]::new()
$totalOK   = 0
$totalFail = 0

if ($script:IsGHA) { $summary.Add("| Depot | Equipe | Statut |") ; $summary.Add("|---|---|---|") }

foreach ($slug in $slugs) {
    $template = Join-Path $script:TemplateDir $slug "copilot-instructions.md"

    if ($script:IsGHA) { Write-Output "::group::Equipe : $slug" }
    else               { Write-Output ""; Write-Output "=== Equipe : $slug ===" }

    if (-not (Test-Path $template)) {
        Write-GHALog 'warning' "Template introuvable : $template"
        if ($script:IsGHA) { Write-Output "::endgroup::" }
        continue
    }

    $repos = Get-TeamRepos -Slug $slug
    Write-Output "  $($repos.Count) depot(s) trouve(s)"

    foreach ($repo in $repos) {
        $ok = Deploy-ToRepo -Repo $repo -TemplatePath $template
        if ($script:IsGHA) {
            $icon = if ($ok) { ':white_check_mark:' } else { ':x:' }
            $summary.Add("| $repo | $slug | $icon |")
        }
        if ($ok) { $totalOK++ } else { $totalFail++ }
    }

    if ($script:IsGHA) { Write-Output "::endgroup::" }
}

Write-Output ""
Write-Output "Deploiement termine. OK=$totalOK  ERREURS=$totalFail"

# ─── GitHub Actions Step Summary ──────────────────────────────────────────────
if ($script:IsGHA -and $Env:GITHUB_STEP_SUMMARY) {
    try {
        $md  = [System.Collections.Generic.List[string]]::new()
        $md.Add("## Deploiement Copilot Instructions")
        $md.Add("")
        $md.Add("- **Organisation** : $script:Org")
        $md.Add("- **WhatIf** : $WhatIf")
        $md.Add("- **Depots mis a jour** : $totalOK  |  **Erreurs** : $totalFail")
        $md.Add("")
        $md.AddRange($summary)
        $md | Add-Content -Path $Env:GITHUB_STEP_SUMMARY -Encoding utf8
    } catch {
        Write-GHALog 'warning' "Impossible d'ecrire le step summary : $_"
    }
}

exit ($totalFail -gt 0 ? 1 : 0)
