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
    .\Deploy-CopilotInstructions.ps1 -Team "API Backend"  # une seule équipe
#>

param(
    [switch] $WhatIf,

    [ValidateSet("SPA", "API Backend", "Data")]
    [string] $Team,

    [string] $CommitMessage = "chore: add GitHub Copilot instructions [skip ci]"
)

$ErrorActionPreference = "Stop"

# ─── Configuration ────────────────────────────────────────────────────────────
$script:Org        = "onyx-developpement"
$script:TargetFile = ".github/copilot-instructions.md"
$script:TemplateDir = Join-Path $PSScriptRoot "copilot-instructions"

$script:TeamConfig = @(
    @{ TeamName = "SPA";         TeamSlug = "spa";          Template = Join-Path $script:TemplateDir "spa\copilot-instructions.md" }
    @{ TeamName = "API Backend"; TeamSlug = "api-backend";  Template = Join-Path $script:TemplateDir "api-backend\copilot-instructions.md" }
    @{ TeamName = "Data";        TeamSlug = "data";          Template = Join-Path $script:TemplateDir "data\copilot-instructions.md" }
)
# ──────────────────────────────────────────────────────────────────────────────

function Get-TeamRepos {
    param([string] $Slug)
    $result = gh api "orgs/$script:Org/teams/$Slug/repos" --paginate --jq '.[] | select(.archived == false) | .full_name'
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "  Impossible de recuperer les depots du slug '$Slug'"
        return @()
    }
    # Garantir un tableau meme si 1 seul résultat
    return @($result)
}

function Deploy-ToRepo {
    param([string] $Repo, [string] $TemplatePath)

    if ($WhatIf) {
        Write-Output "  [WhatIf] $Repo --> $script:TargetFile"
        return
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
    } else {
        Write-Warning "  [ERREUR] $Repo : $out"
    }
}

# ─── Main ─────────────────────────────────────────────────────────────────────
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "gh CLI introuvable." }

$configs = if ($Team) { $script:TeamConfig | Where-Object { $_.TeamName -eq $Team } } else { $script:TeamConfig }

foreach ($config in $configs) {
    Write-Output ""
    Write-Output "=== Equipe : $($config.TeamName) (slug: $($config.TeamSlug)) ==="

    if (-not (Test-Path $config.Template)) {
        Write-Warning "Template introuvable : $($config.Template)"
        continue
    }

    $repos = Get-TeamRepos -Slug $config.TeamSlug

    Write-Output "  $($repos.Count) depot(s) trouve(s)"

    foreach ($repo in $repos) {
        Deploy-ToRepo -Repo $repo -TemplatePath $config.Template
    }
}

Write-Output ""
Write-Output "Deploiement termine."
