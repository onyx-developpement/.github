<#
.SYNOPSIS
    Déploie les fichiers copilot-instructions.md dans tous les dépôts GitHub
    de l'organisation onyx-developpement, selon l'équipe à laquelle ils appartiennent.

.DESCRIPTION
    - Equipe "SPA"          → instructions React SPA
    - Equipe "API Backend"  → instructions Spring WebFlux
    - Equipe "Data"         → instructions Microsoft Fabric

    Le fichier déployé = copilot-instructions/copilot-instructions.md (racine, commun)
    suivi du fichier spécifique à l'équipe.

    Les skills (skills/), hooks (hooks/) et contrats de domaine (domains/) sont déployés selon les topics des dépôts :
    - skills/deploy.json et hooks/deploy.json : { "nom": { "teams": ["spa"], "topics": ["api", "spa"] } }.
      Un dépôt est retenu s'il appartient à l'une des équipes listées (si `teams` est renseigné) ET porte au moins
      un des topics listés (si `topics` est renseigné). L'ancien format { "nom": ["spa"] } reste lu comme une liste d'équipes.
    - domains/<nom>/ : déployé dans .github/domains/ des dépôts portant le topic `domain-<nom>`, ou `domain-all` pour
      recevoir tous les domaines (dépôt de configuration, par exemple).
    Les dépôts sans équipe sont trouvés par leurs topics (lecture de tous les dépôts non archivés de l'organisation).
    Un fichier identique à celui du dépôt n'est pas réécrit (pas de commit inutile).
    Un fichier retiré d'une ressource, ou un topic retiré d'un dépôt, ne supprime rien dans les dépôts.

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
    Join-Path (Join-Path $PSScriptRoot "..") "copilot-instructions"
}
$script:RootTemplate = Join-Path $script:TemplateDir "copilot-instructions.md"
$script:SkillsDir = if ($Env:GITHUB_WORKSPACE) {
    Join-Path $Env:GITHUB_WORKSPACE "skills"
} else {
    Join-Path (Join-Path $PSScriptRoot "..") "skills"
}
$script:HooksDir = if ($Env:GITHUB_WORKSPACE) {
    Join-Path $Env:GITHUB_WORKSPACE "hooks"
} else {
    Join-Path (Join-Path $PSScriptRoot "..") "hooks"
}
$script:DomainsDir = if ($Env:GITHUB_WORKSPACE) {
    Join-Path $Env:GITHUB_WORKSPACE "domains"
} else {
    Join-Path (Join-Path $PSScriptRoot "..") "domains"
}

# ──────────────────────────────────────────────────────────────────────────────

function Write-GHALog {
    param([string] $Level, [string] $Message)
    if ($script:IsGHA) {
        Write-Host "::${Level}::${Message}"
    } elseif ($Level -eq 'warning') {
        Write-Warning $Message
    } elseif ($Level -eq 'error') {
        Write-Error $Message -ErrorAction Continue
    } else {
        Write-Host $Message
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
    param([string] $Repo, [string] $Content, [string] $TargetPath = $script:TargetFile)

    if ($WhatIf) {
        Write-Host "  [WhatIf] $Repo --> $TargetPath"
        return $true
    }

    $encoded     = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Content))
    $maxAttempts = 4

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        # SHA requis si le fichier existe déjà (sinon 409 Conflict)
        $existing = gh api "repos/$Repo/contents/$TargetPath" 2>$null | ConvertFrom-Json
        $sha      = if ($existing -and $existing.sha) { $existing.sha } else { $null }

        if ($existing -and $existing.content) {
            $current = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($existing.content -replace '\s', '')))
            if (($current -replace "`r`n", "`n").Trim() -eq ($Content -replace "`r`n", "`n").Trim()) {
                Write-Host "  [=] $Repo ($TargetPath inchange)"
                return $true
            }
        }

        $body = @{ message = $CommitMessage; content = $encoded }
        if ($sha) { $body.sha = $sha }

        $bodyJson = $body | ConvertTo-Json -Compress
        $out = $bodyJson | gh api "repos/$Repo/contents/$TargetPath" --method PUT --input - 2>&1

        if ($LASTEXITCODE -eq 0) {
            $verb = if ($sha) { "mis a jour" } else { "cree" }
            Write-Host "  [OK] $Repo ($TargetPath $verb)"
            return $true
        }

        # 409 "is at X but expected Y" : la branche a bougé entre la lecture et l'écriture → on relit puis on réessaie
        if ("$out" -match 'is at [0-9a-f]{40} but expected' -and $attempt -lt $maxAttempts) {
            Start-Sleep -Seconds (2 * $attempt)
            continue
        }

        Write-GHALog 'error' "[ERREUR] $Repo ($TargetPath) : $out"
        return $false
    }
    return $false
}

# Dépôts non archivés de l'organisation avec leurs topics (nom complet -> topics) ; le dépôt .github, source des déploiements, est exclu
function Get-OrgRepos {
    $repos = @{}
    $lines = gh api "orgs/$script:Org/repos?per_page=100&type=all" --paginate --jq '.[] | select(.archived == false) | {name: .full_name, topics: (.topics // [])} | tojson'
    if ($LASTEXITCODE -ne 0) {
        Write-GHALog 'warning' "Impossible de lister les depots de l'organisation"
        return $repos
    }
    foreach ($line in @($lines)) {
        $repo = $line | ConvertFrom-Json
        if ($repo.name -eq "$script:Org/.github") { continue }
        $repos[$repo.name] = @($repo.topics)
    }
    return $repos
}

# Sélecteur d'une entrée de manifeste : liste d'équipes (ancien format) ou { "teams": [...], "topics": [...] }.
# Quand les deux sont renseignés, l'équipe ET au moins un des topics doivent correspondre.
function Test-Selector {
    param($Selector, [string[]] $Teams, [string[]] $Topics)

    if ($Selector -is [System.Array]) {
        $teamList  = @($Selector)
        $topicList = @()
    } else {
        $teamList  = @($Selector.teams)
        $topicList = @($Selector.topics)
    }
    $teamList  = @($teamList  | Where-Object { $_ })
    $topicList = @($topicList | Where-Object { $_ })

    if ($teamList.Count -eq 0 -and $topicList.Count -eq 0) { return $false }
    if ($teamList.Count  -gt 0 -and -not ($teamList  | Where-Object { $Teams  -contains $_ })) { return $false }
    if ($topicList.Count -gt 0 -and -not ($topicList | Where-Object { $Topics -contains $_ })) { return $false }
    return $true
}

# Fichiers d'un dossier de ressources (skills, hooks) retenus pour un dépôt, selon <Root>/deploy.json.
# Avec -IncludeName, le nom de la ressource est ajouté au chemin cible ; sinon les fichiers sont déposés à plat sous <TargetRoot>.
function Get-ManifestFiles {
    param([string] $Root, [string] $TargetRoot, [switch] $IncludeName, [string[]] $Teams, [string[]] $Topics)

    $manifestPath = Join-Path $Root "deploy.json"
    if (-not (Test-Path $manifestPath)) { return @() }

    $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $files    = @()
    foreach ($entry in $manifest.PSObject.Properties) {
        if (-not (Test-Selector -Selector $entry.Value -Teams $Teams -Topics $Topics)) { continue }
        $dir = Join-Path $Root $entry.Name
        if (-not (Test-Path $dir)) {
            Write-GHALog 'warning' "Ressource introuvable : $dir"
            continue
        }
        # Chemin normalise (sans ..) pour que le calcul du chemin relatif concorde avec FullName
        $dir    = (Resolve-Path $dir).Path
        $prefix = if ($IncludeName) { "$TargetRoot/$($entry.Name)" } else { $TargetRoot }
        foreach ($file in Get-ChildItem $dir -Recurse -File) {
            $relative = $file.FullName.Substring($dir.Length + 1) -replace '\\', '/'
            $files += [pscustomobject]@{
                Target  = "$prefix/$relative"
                Content = (Get-Content $file.FullName -Raw -Encoding UTF8).TrimEnd() + "`n"
            }
        }
    }
    return $files
}

# Contrats de domaine : domains/<nom>/ est déposé dans .github/domains/ des dépôts portant le topic domain-<nom> ou domain-all
function Get-DomainFiles {
    param([string[]] $Topics)

    if (-not (Test-Path $script:DomainsDir)) { return @() }

    $files = @()
    foreach ($dir in Get-ChildItem $script:DomainsDir -Directory) {
        if (($Topics -notcontains "domain-$($dir.Name)") -and ($Topics -notcontains 'domain-all')) { continue }
        foreach ($file in Get-ChildItem $dir.FullName -Recurse -File) {
            $relative = $file.FullName.Substring($dir.FullName.Length + 1) -replace '\\', '/'
            $files += [pscustomobject]@{
                Target  = ".github/domains/$relative"
                Content = (Get-Content $file.FullName -Raw -Encoding UTF8).TrimEnd() + "`n"
            }
        }
    }
    return $files
}

# ─── Main ─────────────────────────────────────────────────────────────────────
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "gh CLI introuvable." }

# GH_TOKEN est utilisé automatiquement par gh CLI (secrets.COPILOT_DEPLOY_TOKEN dans le workflow)
# GITHUB_TOKEN est le fallback natif GitHub Actions
if (-not $Env:GH_TOKEN -and -not $Env:GITHUB_TOKEN) {
    Write-GHALog 'warning' "Ni GH_TOKEN ni GITHUB_TOKEN n'est defini. L'authentification gh pourrait echouer."
}

# Découverte des slugs : soit le paramètre $Team (liste séparée par des virgules), soit tous les sous-dossiers de $script:TemplateDir
if ($Team) {
    $slugs = @($Team -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
} else {
    $slugs = @(Get-ChildItem -Path $script:TemplateDir -Directory | Select-Object -ExpandProperty Name)
}

if ($slugs.Count -eq 0) { throw "Aucun sous-dossier trouve dans : $script:TemplateDir" }

if (-not (Test-Path $script:RootTemplate)) { throw "Fichier racine introuvable : $script:RootTemplate" }
$rootContent = (Get-Content $script:RootTemplate -Raw -Encoding UTF8).TrimEnd()

$summary   = [System.Collections.Generic.List[string]]::new()
$totalOK   = 0
$totalFail = 0

if ($script:IsGHA) { $summary.Add("| Depot | Equipe | Statut |") ; $summary.Add("|---|---|---|") }

$teamsOfRepo = @{}

foreach ($slug in $slugs) {
    $template = Join-Path (Join-Path $script:TemplateDir $slug) "copilot-instructions.md"

    if ($script:IsGHA) { Write-Output "::group::Equipe : $slug" }
    else               { Write-Output ""; Write-Output "=== Equipe : $slug ===" }

    if (-not (Test-Path $template)) {
        Write-GHALog 'warning' "Template introuvable : $template"
        if ($script:IsGHA) { Write-Output "::endgroup::" }
        continue
    }

    $teamContent = (Get-Content $template -Raw -Encoding UTF8).TrimEnd()
    $content     = "$rootContent`n`n---`n`n$teamContent`n"

    $repos = Get-TeamRepos -Slug $slug
    Write-Output "  $($repos.Count) depot(s) trouve(s)"

    foreach ($repo in $repos) {
        if (-not $teamsOfRepo.ContainsKey($repo)) { $teamsOfRepo[$repo] = @() }
        $teamsOfRepo[$repo] += $slug
        $ok = Deploy-ToRepo -Repo $repo -Content $content
        if ($script:IsGHA) {
            $icon = if ($ok) { ':white_check_mark:' } else { ':x:' }
            $summary.Add("| $repo | $slug | $icon |")
        }
        if ($ok) { $totalOK++ } else { $totalFail++ }
    }

    if ($script:IsGHA) { Write-Output "::endgroup::" }
}

Write-Output ""
Write-Output "=== Skills, hooks et domaines (equipes et topics) ==="

foreach ($repo in ((Get-OrgRepos).GetEnumerator() | Sort-Object Name)) {
    $repoName = $repo.Name
    $teams    = if ($teamsOfRepo.ContainsKey($repoName)) { @($teamsOfRepo[$repoName]) } else { @() }

    # Avec -Team, seuls les depots des equipes traitees sont concernes
    if ($Team -and $teams.Count -eq 0) { continue }

    $topics = @($repo.Value)
    $files  = @(Get-ManifestFiles -Root $script:SkillsDir -TargetRoot '.github/skills' -IncludeName -Teams $teams -Topics $topics) +
              @(Get-ManifestFiles -Root $script:HooksDir  -TargetRoot '.github/hooks' -Teams $teams -Topics $topics) +
              @(Get-DomainFiles -Topics $topics)
    if ($files.Count -eq 0) { continue }

    $ok = $true
    foreach ($file in $files) {
        if (-not (Deploy-ToRepo -Repo $repoName -Content $file.Content -TargetPath $file.Target)) { $ok = $false }
    }
    if ($script:IsGHA) {
        $icon = if ($ok) { ':white_check_mark:' } else { ':x:' }
        $summary.Add("| $repoName | topics | $icon |")
    }
    if ($ok) { $totalOK++ } else { $totalFail++ }
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

if ($totalFail -gt 0) { exit 1 }
exit 0
