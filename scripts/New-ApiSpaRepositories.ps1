#Requires -Version 5.1
<#
Phase 1 : cree les depots GitHub internes api-<name> et/ou spa-<name> (README, topics, equipe en ecriture).
Phase 2 : clone les depots, genere le squelette (archetype Maven api-archetype / npm create @nutriset/react-spa)
sur la branche yyyyMMdd-init, committe et pousse cette branche (pas main).
Phase 3 : cree les pipelines Azure DevOps (ci, cicd, deploy-definition si demande), le ruleset
require-ci-status-check et la PR yyyyMMdd-init -> main.
Phase 4 : ajoute les modules Terraform prod et test d'une application api-<name> et/ou spa-<name>
dans azure-infrastructure, sur la branche yyyyMMdd-<name> depuis origin/main, puis ouvre la PR.
-LinkApi : second run, une fois le premier applique. Ajoute les api_accesses de la SPA vers l'API
sur la branche yyyyMMdd-<name>-link (le client_id de l'API doit etre connu au plan).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z][a-z0-9-]*$')]
    [string]$Name,

    [ValidateSet('Api', 'Spa')]
    [string[]]$Only = @('Api', 'Spa'),

    [string]$InfraPath = 'C:\dev\git\TransverseSI\azure-infrastructure',

    [string]$GitHubOrg = 'onyx-developpement',

    [string]$ApiRoot = 'C:\dev\git\API Backend',

    [string]$SpaRoot = 'C:\dev\git\SPA',

    # Port local de l'API (defaut : plus grand port des .run des API existantes + 1).
    [ValidateRange(7000, 7999)]
    [int]$LocalPort,

    [string]$ArchetypeVersion = '2.0.0',

    # Cree le pipeline <api>-deploy-definition (API utilisee par d'autres API Java) ; demande si absent.
    [Nullable[bool]]$DefinitionPipeline,

    # Exposition Fortiweb (demandee si absente) :
    # PartoutSaufOT = internet compris (calque wfp), InterneSaufOT = defauts du module (calque proxy-m3),
    # OTUniquement = calque mes.
    [ValidateSet('PartoutSaufOT', 'InterneSaufOT', 'OTUniquement')]
    [string]$WafPreset,

    # Affiche les modifications sans rien ecrire ni committer.
    [switch]$DryRun,

    # Committe la branche sans push ni PR, et ne cree rien sur GitHub.
    [switch]$NoPublish,

    # Second run, apres l'apply du premier : ajoute les api_accesses de la SPA vers l'API (PR dediee).
    [switch]$LinkApi
)

$ErrorActionPreference = 'Stop'

$under = $Name -replace '-', '_'
$pascal = -join ($Name -split '-' | ForEach-Object { $_.Substring(0, 1).ToUpper() + $_.Substring(1) })
$branch = "$(Get-Date -Format yyyyMMdd)-$Name"
$initBranch = "$(Get-Date -Format yyyyMMdd)-init"
$tfRoot = Join-Path $InfraPath 'terraform\infra'
$environments = @(
    [pscustomobject]@{ Dir = 'sub-modern-apps-prod'; AspSuffix = '004' }
    [pscustomobject]@{ Dir = 'sub-modern-apps-test'; AspSuffix = '003' }
)
$kinds = @()
if ($Only -contains 'Api') { $kinds += 'api' }
if ($Only -contains 'Spa') { $kinds += 'spa' }
$utf8 = [Text.UTF8Encoding]::new($false)
$script:Changed = [System.Collections.Generic.List[string]]::new()
$script:WafIndex = [ordered]@{}

$apiTemplate = @'
module "api___UNDER__" {
  source = "../../../common/azure/linux-webapp"

  type              = "API"
  name              = "__NAME__"
  env               = var.env
  webapp_version    = "001"
  key_vault         = var.key_vault
  api_configuration = var.api_configuration
  resource_group    = var.resource_groups.__UNDER__
  waf_config_index  = __INDEX__

__WAF__

  webapp = {
    java_heap_size       = 100
    asp_id               = var.app_service_plans.asp_linux_france___ASP__.id
    outbound_subnet      = var.vnet.subnets.snet_asp_outbound
    application_insights = var.log_analytics_workspace.application_insights.appi_modern_apps
    private_dns_zone     = var.private_dns_zones.privatelink_azurewebsites_net.private_dns_zone
    inbound_subnet       = var.vnet.subnets.snet_inbound
  }

  oauth2 = {
    permission_scopes = {
      all = {
        enabled                    = true
        type                       = "Admin"
        admin_consent_display_name = "Api__PASCAL__.All"
        admin_consent_description  = "Api__PASCAL__.All"
        value                      = "Api__PASCAL__.All"
      }
    }
  }
}
'@

$spaTemplate = @'
module "spa___UNDER__" {
  source = "../../../common/azure/linux-webapp"

  type              = "SPA"
  name              = "__NAME__"
  env               = var.env
  webapp_version    = "001"
  resource_group    = var.resource_groups.__UNDER__
  waf_config_index  = __INDEX__

__WAF__

  webapp = {
    asp_id               = var.app_service_plans.asp_linux_france___ASP__.id
    outbound_subnet      = var.vnet.subnets.snet_asp_outbound
    application_insights = var.log_analytics_workspace.application_insights.appi_modern_apps
    private_dns_zone     = var.private_dns_zones.privatelink_azurewebsites_net.private_dns_zone
    inbound_subnet       = var.vnet.subnets.snet_inbound
  }

  oauth2 = {
    groups_to_assign   = var.apis.api___UNDER__.oauth2.app_roles_groups
    api_identifier_uri = var.apis.api___UNDER__.oauth2.identifier_uri
  }
}
'@

function Assert-Native([string]$What) {
    if ($LASTEXITCODE -ne 0) { throw "$What a echoue (code $LASTEXITCODE)" }
}

$wafPresets = [ordered]@{
    PartoutSaufOT = @{
        Label = 'Partout, internet compris, sauf OT (comme wfp)'
        Block = @'
  waf_ip_list = {
    groups = {
      all_sources = "allow_only"
    }
  }
'@
    }
    InterneSaufOT = @{
        Label = 'Interne sauf OT (comme proxy-m3 : defauts du module)'
        Block = ''
    }
    OTUniquement = @{
        Label = 'OT uniquement (comme mes : admin, serveurs OT et IT)'
        Block = @'
  waf_ip_list = {
    groups = {
      admin_bois_ricard         = "allow_only"
      serveurs_ot_bois_ricard   = "allow_only"
      pc_bois_du_roule          = "none"
      serveurs_it_bois_ricard   = "allow_only"
      serveurs_it_bois_du_roule = "allow_only"
      maromme                   = "none"
      rouen_st_maur             = "none"
      wifi_bois_ricard          = "none"
      zscaler_app_connectors    = "none"
      azure                     = "none"
      pc_bois_ricard            = "none"
    }
  }
'@
    }
}

function Read-WafPreset {
    $keys = @($wafPresets.Keys)
    for ($i = 0; $i -lt $keys.Count; $i++) { Write-Host "  $($i + 1). $($wafPresets[$keys[$i]].Label)" }
    while ($true) {
        $answer = Read-Host 'Exposition de l''application (numero)'
        $n = 0
        if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $keys.Count) { return $keys[$n - 1] }
        Write-Host 'Choix invalide.'
    }
}

# Sequence propre a chaque type : Fortiweb.ps1 decale l'index par type (Get-StartIndex -Type).
function Get-NextWafIndex([string]$Kind) {
    $indexes = foreach ($target in $environments) {
        $dir = Join-Path $tfRoot "$($target.Dir)\$Kind"
        if (Test-Path -LiteralPath $dir) {
            Select-String -Path (Join-Path $dir '*.tf') -Pattern 'waf_config_index\s*=\s*(\d+)' |
                ForEach-Object { [int]$_.Matches[0].Groups[1].Value }
        }
    }
    $max = ($indexes | Measure-Object -Maximum).Maximum
    if ($null -eq $max) { 0 } else { [int]$max + 1 }
}

function New-ModuleText([string]$Template, [string]$AspSuffix, [int]$Index) {
    $text = $Template.Replace('__UNDER__', $under).Replace('__PASCAL__', $pascal).Replace('__NAME__', $Name).Replace('__ASP__', $AspSuffix).Replace('__INDEX__', [string]$Index)
    if ($script:WafBlock) { $text = $text.Replace('__WAF__', $script:WafBlock) }
    else { $text = $text -replace '\r?\n\r?\n__WAF__', '' }
    (($text -replace "`r?`n", "`r`n") + "`r`n")
}

function Write-Change([string]$Path, [string]$Text) {
    $script:Changed.Add($Path)
    if ($DryRun) {
        Write-Host "[DryRun] Creation $Path"
        Write-Host $Text
        return
    }
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Test-GitHubRepo([string]$FullName) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = gh api "repos/$FullName" --silent 2>&1 | Out-String } finally { $ErrorActionPreference = $previous }
    if ($LASTEXITCODE -eq 0) { return $true }
    if ($out -match 'HTTP 404') { return $false }
    throw "Verification de $FullName impossible : $out"
}

# Idempotent : cree le depot s'il manque, puis force equipe (push) et topics.
function Initialize-GitHubRepo {
    param([string]$Repo, [string]$TeamSlug, [string[]]$Topics)
    $full = "$GitHubOrg/$Repo"
    $exists = Test-GitHubRepo $full
    if ($DryRun) {
        $state = if ($exists) { 'existe deja' } else { 'a creer (internal, README)' }
        Write-Host "[DryRun] GitHub $full : $state ; equipe $TeamSlug=push ; topics $($Topics -join ',')"
        return
    }
    if ($exists) {
        Write-Host "[Ignore] Depot $full deja present"
        # Depot vide : sans commit initial, la branche main et la PR d'init sont impossibles
        $isEmpty = gh repo view $full --json isEmpty -q '.isEmpty'
        Assert-Native "lecture de $full"
        if ($isEmpty -eq 'true') {
            $content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("# $Repo`n"))
            gh api -X PUT "repos/$full/contents/README.md" -f message='chore: README initial' -f content=$content --silent
            Assert-Native "README initial de $full"
            Write-Host "[GitHub] Depot $full vide : README initial ajoute sur la branche par defaut"
        }
    }
    else {
        gh repo create $full --internal --add-readme | Out-Null
        Assert-Native "gh repo create $full"
        Write-Host "[GitHub] Depot $full cree"
    }

    gh api -X PUT "orgs/$GitHubOrg/teams/$TeamSlug/repos/$full" -f permission=push --silent
    Assert-Native "attribution de l'equipe $TeamSlug sur $full"
    $permission = gh api "orgs/$GitHubOrg/teams/$TeamSlug/repos/$full" -H 'Accept: application/vnd.github.v3.repository+json' -q '.role_name'
    Assert-Native "verification de l'equipe $TeamSlug sur $full"
    if ($permission -notin 'write', 'maintain', 'admin') { throw "L'equipe $TeamSlug n'a pas l'acces en ecriture sur $full (role : $permission)" }

    $payload = @{ names = $Topics } | ConvertTo-Json -Compress
    $payload | gh api -X PUT "repos/$full/topics" --input - --silent
    Assert-Native "topics de $full"
    Write-Host "[GitHub] $full : equipe $TeamSlug ($permission), topics $($Topics -join ',')"
}

function Get-NextLocalPort {
    $ports = Get-ChildItem -Path (Join-Path $ApiRoot '*\.run\*.xml') -ErrorAction SilentlyContinue |
        Select-String -Pattern 'server\.port=(7\d{3})' |
        ForEach-Object { [int]$_.Matches[0].Groups[1].Value }
    $max = ($ports | Measure-Object -Maximum).Maximum
    if ($null -eq $max) { 7001 } else { [int]$max + 1 }
}

# Idempotent : ignore si la branche init existe deja sur origin.
function Initialize-Scaffold {
    param([ValidateSet('api', 'spa')][string]$Kind)
    $repo = "$Kind-$Name"
    $full = "$GitHubOrg/$repo"
    $root = if ($Kind -eq 'api') { $ApiRoot } else { $SpaRoot }
    $dest = Join-Path $root $repo
    if ($DryRun) {
        Write-Host "[DryRun] Scaffold $full dans $dest : branche $initBranch, port local $LocalPort, commit et push"
        return
    }

    if (-not (Test-Path -LiteralPath $dest)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        gh repo clone $full $dest
        Assert-Native "clone de $full"
    }
    elseif (git -C $dest status --porcelain) {
        throw "Arbre de travail non propre dans $dest"
    }
    git -C $dest fetch origin --quiet
    Assert-Native "git fetch $repo"
    if (git -C $dest ls-remote --heads origin $initBranch) {
        Write-Host "[Ignore] Branche $initBranch deja presente sur $full"
        return
    }
    git -C $dest checkout -b $initBranch origin/main
    Assert-Native "git checkout $repo"

    $tmp = Join-Path ([IO.Path]::GetTempPath()) "scaffold-$repo-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        Push-Location $tmp
        try {
            if ($Kind -eq 'api') {
                mvn archetype:generate -B '-DarchetypeGroupId=fr.nutriset' '-DarchetypeArtifactId=api-archetype' "-DarchetypeVersion=$ArchetypeVersion" '-DgroupId=fr.nutriset' "-DartifactId=$repo" '-Dversion=1.0' "-DlocalPort=$LocalPort"
                Assert-Native 'mvn archetype:generate'
            }
            else {
                npm create '@nutriset/react-spa@latest' -- $repo --yes --api-path "api-$Name" --local-port $LocalPort
                Assert-Native 'npm create @nutriset/react-spa'
            }
        }
        finally { Pop-Location }
        $generated = Join-Path $tmp $repo
        if (-not (Test-Path -LiteralPath $generated)) { throw "Squelette introuvable : $generated" }
        robocopy $generated $dest /E /XD node_modules .git /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy a echoue (code $LASTEXITCODE)" }
        # Le lockfile doit etre committe : on relance l'installation si celle du generateur a echoue
        if ($Kind -eq 'spa' -and -not (Test-Path -LiteralPath (Join-Path $dest 'package-lock.json'))) {
            Push-Location $dest
            try {
                npm install
                Assert-Native 'npm install (authentification Azure Artifacts requise : npx vsts-npm-auth -config $env:USERPROFILE\.npmrc)'
            }
            finally { Pop-Location }
        }
    }
    finally {
        $ErrorActionPreference = $previous
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    git -C $dest add -A
    Assert-Native "git add $repo"
    git -C $dest commit -m "feat: squelette initial $repo"
    Assert-Native "git commit $repo"
    git -C $dest push -u origin $initBranch
    Assert-Native "git push $repo"
    Write-Host "[Scaffold] $full : branche $initBranch poussee"
}

function Add-ToBlock {
    param(
        [string]$Path,
        [string]$OpenPattern,
        [string]$CloseLine,
        [string[]]$Entries,
        [string]$SkipIfMatch,
        [switch]$CommaSeparated
    )
    $lines = [System.Collections.Generic.List[string]]::new([string[]](Get-Content -LiteralPath $Path -Encoding UTF8))
    if ($lines.Exists([Predicate[string]]{ param($l) $l -match $SkipIfMatch })) {
        Write-Host "[Ignore] Deja present dans $Path : $($Entries[0].Trim())"
        return
    }
    $open = -1
    for ($i = 0; $i -lt $lines.Count -and $open -lt 0; $i++) { if ($lines[$i] -match $OpenPattern) { $open = $i } }
    if ($open -lt 0) { throw "Bloc introuvable dans ${Path} : $OpenPattern" }
    $close = -1
    for ($i = $open + 1; $i -lt $lines.Count -and $close -lt 0; $i++) { if ($lines[$i] -eq $CloseLine) { $close = $i } }
    if ($close -lt 0) { throw "Fin de bloc introuvable dans $Path" }
    if ($CommaSeparated -and $close - 1 -gt $open -and $lines[$close - 1] -notmatch ',$') {
        $lines[$close - 1] += ','
    }
    $lines.InsertRange($close, [string[]]$Entries)
    $script:Changed.Add($Path)
    if ($DryRun) {
        Write-Host "[DryRun] Modification $Path"
        $Entries | ForEach-Object { Write-Host "  + $_" }
        return
    }
    [IO.File]::WriteAllText($Path, (($lines -join "`r`n") + "`r`n"), $utf8)
}

function Initialize-AdoPipelines {
    param([ValidateSet('api', 'spa')][string]$Kind)
    $repo = "$Kind-$Name"
    $project = if ($Kind -eq 'api') { 'API Backend' } else { 'SPA' }
    $orgUrl = 'https://dev.azure.com/nutriset'
    $serviceConnectionId = '5a964410-440c-44eb-8cf2-9b02b478a2e1'
    $repoUrl = "https://github.com/$GitHubOrg/$repo"
    $pipelines = @(
        @{ Suffix = 'ci'; Yaml = 'pipeline-ci.yml'; StripPrTrigger = $false }
        @{ Suffix = 'cicd'; Yaml = 'pipeline-cicd.yml'; StripPrTrigger = $true }
    )
    if ($Kind -eq 'api' -and $DefinitionPipeline) {
        $pipelines += @{ Suffix = 'deploy-definition'; Yaml = 'pipeline-deploy-definition.yml'; StripPrTrigger = $false }
    }

    if ($DryRun) {
        Write-Host "[DryRun] ADO '$project' : pipelines $(($pipelines | ForEach-Object { "$repo-$($_.Suffix)" }) -join ', ') (branche $initBranch puis defaut main)"
        Write-Host "[DryRun] GitHub $repo : ruleset require-ci-status-check ($repo-ci) et PR $initBranch -> main"
        return
    }

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $token = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv
        Assert-Native 'az account get-access-token (az login requis)'
        $headers = @{ Authorization = "Bearer $token" }
        $proj = az devops project show --organization $orgUrl --project $project | ConvertFrom-Json
        Assert-Native "az devops project show $project"

        foreach ($p in $pipelines) {
            $pName = "$repo-$($p.Suffix)"
            $found = az pipelines list --organization $orgUrl --project $proj.id --name $pName | ConvertFrom-Json
            if (@($found).Count -gt 0) { Write-Host "[Ignore] Pipeline $pName existe deja"; continue }

            $created = az pipelines create --organization $orgUrl --project $proj.id --name $pName `
                --branch $initBranch --repository $repoUrl --yaml-path "azure-pipelines/$($p.Yaml)" `
                --repository-type github --service-connection $serviceConnectionId `
                --skip-first-run --folder-path $repo | ConvertFrom-Json
            Assert-Native "az pipelines create $pName"

            # Les YAML ne sont pas encore sur main : la branche par defaut est basculee apres creation
            $defUri = "$orgUrl/$($proj.id)/_apis/build/definitions/$($created.id)?api-version=7.1"
            $def = Invoke-RestMethod -Uri $defUri -Headers $headers -Method Get
            $def.repository.defaultBranch = 'refs/heads/main'
            if ($p.StripPrTrigger) {
                $def.triggers = @($def.triggers | Where-Object { $_.triggerType -ne 'pullRequest' })
            }
            Invoke-RestMethod -Uri $defUri -Headers $headers -Method Put -Body ($def | ConvertTo-Json -Depth 30) `
                -ContentType 'application/json; charset=utf-8' | Out-Null
            Write-Host "[OK] Pipeline $pName cree"
        }

        # Ruleset : check "<repo>-ci" obligatoire sur main ; l'integration copilot-instructions-deployer pousse sans PR
        $rulesetName = 'require-ci-status-check'
        $body = [ordered]@{
            name = $rulesetName; target = 'branch'; enforcement = 'active'
            bypass_actors = @([ordered]@{ actor_id = 4806262; actor_type = 'Integration'; bypass_mode = 'always' })
            conditions = [ordered]@{ ref_name = [ordered]@{ include = @('refs/heads/main'); exclude = @() } }
            rules = @([ordered]@{
                type = 'required_status_checks'
                parameters = [ordered]@{
                    required_status_checks = @([ordered]@{ context = "$repo-ci" })
                    strict_required_status_checks_policy = $false
                }
            })
        }
        $tmpFile = Join-Path $env:TEMP "ruleset-$repo-$(Get-Random).json"
        [IO.File]::WriteAllText($tmpFile, ($body | ConvertTo-Json -Depth 20), $utf8)
        $rulesets = gh api "repos/$GitHubOrg/$repo/rulesets" | ConvertFrom-Json
        $rulesetId = @($rulesets | Where-Object { $_.name -eq $rulesetName })[0].id
        if ($rulesetId) { $null = gh api -X PUT "repos/$GitHubOrg/$repo/rulesets/$rulesetId" --input $tmpFile 2>&1 }
        else { $null = gh api -X POST "repos/$GitHubOrg/$repo/rulesets" --input $tmpFile 2>&1 }
        $rc = $LASTEXITCODE
        Remove-Item $tmpFile -ErrorAction SilentlyContinue
        if ($rc -ne 0) { throw "Ruleset $rulesetName ($repo) en echec" }
        Write-Host "[OK] Ruleset $rulesetName ($repo-ci)"

        # PR init -> main
        $open = gh pr list -R "$GitHubOrg/$repo" --head $initBranch --state open --json url | ConvertFrom-Json
        if (@($open).Count -gt 0) {
            Write-Host "[Ignore] PR deja ouverte : $($open[0].url)"
            $script:PullRequests.Add($open[0].url)
        }
        else {
            $url = gh pr create -R "$GitHubOrg/$repo" --head $initBranch --base main `
                --title "feat: squelette initial $repo" --body "Squelette genere par New-ApiSpaRepositories.ps1."
            Assert-Native "gh pr create $repo"
            Write-Host "[OK] PR : $url"
            $script:PullRequests.Add(($url | Select-Object -Last 1))
        }
    }
    finally { $ErrorActionPreference = $previous }
}

$script:PullRequests = [System.Collections.Generic.List[string]]::new()

function Publish-InfraPullRequest {
    param([string]$Head = $branch, [string]$Title, [string]$Body)
    if (-not $Title) { $Title = "feat(infra): modules Terraform $Name" }
    if (-not $Body) {
        $Body = "Modules Terraform prod et test pour $Name (types : $($Only -join ', ')), index WAF $(($script:WafIndex.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" }) -join ', '), exposition Fortiweb : $($wafPresets[$WafPreset].Label)."
    }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location $InfraPath
    try {
        $open = gh pr list --head $Head --state open --json url | ConvertFrom-Json
        Assert-Native "gh pr list $Head"
        if ($open) {
            Write-Host "[Ignore] PR deja ouverte : $($open[0].url)"
            $script:PullRequests.Add($open[0].url)
            return
        }
        $url = gh pr create --base main --head $Head --title $Title --body $Body
        Assert-Native 'gh pr create azure-infrastructure'
        $url = $url | Select-Object -Last 1
        Write-Host "[OK] PR : $url"
        $script:PullRequests.Add($url)
    }
    finally {
        Pop-Location
        $ErrorActionPreference = $previous
    }
}

# Second run : le client_id de l'API n'est connu qu'apres l'apply du premier, d'ou une PR dediee
function Invoke-LinkApi {
    $linkBranch = "$branch-link"
    $marker = "^(\s*)api_identifier_uri\s*=\s*var\.apis\.api_$under\.oauth2\.identifier_uri\s*$"
    $accesses = @(
        '    api_accesses = [{'
        "      api_client_id = var.apis.api_$under.oauth2.application.client_id"
        "      scope_ids     = [var.apis.api_$under.oauth2.permission_scopes[`"all`"].scope_id]"
        '    }]'
    )
    $relPaths = @($environments | ForEach-Object { "terraform/infra/$($_.Dir)/spa/$Name.modules.tf" })

    git -C $InfraPath fetch origin main --quiet
    Assert-Native 'git fetch'
    $todo = @(foreach ($rel in $relPaths) {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $lines = @(git -C $InfraPath show "origin/main:$rel" 2>$null) } finally { $ErrorActionPreference = $previous }
        if ($LASTEXITCODE -ne 0) { throw "$rel absent de origin/main : merger et appliquer d'abord la PR infra de $Name" }
        if ($lines -match '^\s*api_accesses\s*=') { Write-Host "[Ignore] api_accesses deja present dans $rel"; continue }
        if (-not ($lines -match $marker)) { throw "api_identifier_uri vers api_$under introuvable dans $rel" }
        $rel
    })
    if ($todo.Count -eq 0) { return }

    if ($DryRun) {
        foreach ($rel in $todo) {
            Write-Host "[DryRun] Modification $rel"
            $accesses | ForEach-Object { Write-Host "  + $_" }
        }
        return
    }

    $remoteBranch = git -C $InfraPath ls-remote --heads origin $linkBranch
    Assert-Native 'git ls-remote'
    if (-not $remoteBranch) {
        if (git -C $InfraPath status --porcelain) { throw "Arbre de travail non propre dans $InfraPath" }
        git -C $InfraPath checkout --quiet -b $linkBranch origin/main
        Assert-Native 'git checkout'
        foreach ($rel in $todo) {
            $path = Join-Path $InfraPath $rel
            $out = foreach ($line in [IO.File]::ReadAllLines($path)) {
                $line
                if ($line -match $marker) { $accesses }
            }
            [IO.File]::WriteAllText($path, (($out -join "`r`n") + "`r`n"), $utf8)
        }
        git -C $InfraPath add -- $todo
        Assert-Native 'git add'
        git -C $InfraPath commit --quiet -m "feat(infra): lie la SPA $Name a l'API $Name (api_accesses)"
        Assert-Native 'git commit'
        if ($NoPublish) {
            Write-Host "Branche $linkBranch committee localement (NoPublish : ni push ni PR)."
            return
        }
        git -C $InfraPath push -u origin $linkBranch
        Assert-Native 'git push'
    }
    Publish-InfraPullRequest -Head $linkBranch -Title "feat(infra): api_accesses spa-$Name vers api-$Name" `
        -Body "Second run : la SPA $Name obtient l'acces au scope Api$pascal.All de l'API $Name, maintenant creee par l'apply precedent."
}

if ($LinkApi) {
    Invoke-LinkApi
    Write-Host ''
    Write-Host "=== Liaison SPA -> API $Name $(if ($DryRun) { '(DryRun)' }) ===" -ForegroundColor Cyan
    $script:PullRequests | ForEach-Object { Write-Host "  $_" }
    return
}

# Exposition Fortiweb choisie avant toute modification
if (-not $WafPreset) { $WafPreset = Read-WafPreset }
$script:WafBlock = $wafPresets[$WafPreset].Block -replace "`r?`n", "`r`n"
Write-Host "Exposition Fortiweb : $($wafPresets[$WafPreset].Label)"

# SPA seule : le bloc oauth2 reference var.apis.api_<nom>, l'API doit deja exister dans l'infra
if ($Only -notcontains 'Api') {
    git -C $InfraPath fetch origin main --quiet
    Assert-Native 'git fetch'
    foreach ($target in $environments) {
        $locals = git -C $InfraPath show "origin/main:terraform/infra/$($target.Dir)/api/locals.tf"
        Assert-Native "lecture de $($target.Dir)/api/locals.tf"
        if (-not ($locals -match "^\s+api_$under\s*=")) {
            throw "api_$under absent de $($target.Dir)/api/locals.tf sur origin/main : la SPA ne peut pas lier son bloc oauth2"
        }
    }
}

# Phase 1 : depots GitHub
if ($NoPublish) {
    Write-Host '[Ignore] NoPublish : aucun depot GitHub cree.'
}
else {
    if ($Only -contains 'Api') { Initialize-GitHubRepo -Repo "api-$Name" -TeamSlug 'api-backend' -Topics @('api') }
    if ($Only -contains 'Spa') { Initialize-GitHubRepo -Repo "spa-$Name" -TeamSlug 'spa' -Topics @('spa', 'react') }
}

# Phase 2 : squelette sur la branche init
if (-not $NoPublish) {
    if (-not $LocalPort) { $LocalPort = Get-NextLocalPort }
    Write-Host "Port local de l'API : $LocalPort"
    if ($Only -contains 'Api') { Initialize-Scaffold -Kind api }
    if ($Only -contains 'Spa') { Initialize-Scaffold -Kind spa }
}

# Phase 3 : pipelines Azure DevOps, ruleset et PR d'init
if (-not $NoPublish) {
    if ($Only -contains 'Api' -and $null -eq $DefinitionPipeline) {
        $DefinitionPipeline = (Read-Host "L'API sera-t-elle utilisee par d'autres API Java ? (o/N)") -match '^[oOyY]'
    }
    if ($Only -contains 'Api') { Initialize-AdoPipelines -Kind api }
    if ($Only -contains 'Spa') { Initialize-AdoPipelines -Kind spa }
}

function Initialize-Infra {
    git -C $InfraPath fetch origin main --quiet
    Assert-Native 'git fetch'

    # Modules deja sur origin/main : rien a faire ; presence partielle : arret
    $paths = @(foreach ($target in $environments) {
        foreach ($kind in $kinds) { "terraform/infra/$($target.Dir)/$kind/$Name.modules.tf" }
    })
    $onMain = @($paths | Where-Object { git -C $InfraPath ls-tree --name-only origin/main -- $_ })
    if ($onMain.Count -eq $paths.Count) {
        Write-Host "[Ignore] Modules Terraform deja presents sur origin/main."
        return
    }
    if ($onMain.Count -gt 0) { throw "Modules partiellement presents sur origin/main : $($onMain -join ', ')" }

    # Branche deja creee par un run precedent : reprise du push et de la PR
    $remoteBranch = git -C $InfraPath ls-remote --heads origin $branch
    Assert-Native 'git ls-remote'
    git -C $InfraPath rev-parse --verify --quiet "refs/heads/$branch" | Out-Null
    $localBranch = $LASTEXITCODE -eq 0
    if ($remoteBranch -or $localBranch) {
        if ($DryRun -or $NoPublish) {
            Write-Host "[Ignore] Branche $branch deja existante dans azure-infrastructure (reprise push/PR hors DryRun/NoPublish)."
            return
        }
        if (-not $remoteBranch) {
            git -C $InfraPath push -u origin $branch
            Assert-Native 'git push'
        }
        Publish-InfraPullRequest
        return
    }

    # DryRun : lecture d'un worktree temporaire sur origin/main (le clone n'est pas touche)
    $workPath = $InfraPath
    if ($DryRun) {
        $workPath = Join-Path ([IO.Path]::GetTempPath()) "infra-dryrun-$Name-$(Get-Random)"
        git -C $InfraPath worktree add --detach --quiet $workPath origin/main
        Assert-Native 'git worktree add'
    }
    else {
        if (git -C $InfraPath status --porcelain) { throw "Arbre de travail non propre dans $InfraPath" }
        git -C $InfraPath checkout --quiet -b $branch origin/main
        Assert-Native 'git checkout'
    }

    try {
        $script:tfRoot = Join-Path $workPath 'terraform\infra'
        foreach ($kind in $kinds) {
            $script:WafIndex[$kind] = Get-NextWafIndex $kind
            Write-Host "Index WAF $kind attribue : $($script:WafIndex[$kind])"
        }

        foreach ($target in $environments) {
            $root = Join-Path $tfRoot $target.Dir

            Add-ToBlock -Path (Join-Path $root 'apps-resource-groups\locals.tf') -OpenPattern '^  resource_groups = \{$' -CloseLine '  }' `
                -Entries @("    $under = {", '      version = "001"', '    }') -SkipIfMatch "^    $under = \{$"

            if ($Only -contains 'Api') {
                Add-ToBlock -Path (Join-Path $root 'api\locals.tf') -OpenPattern '^  apps = \[$' -CloseLine '  ]' -CommaSeparated `
                    -Entries @("    module.api_$under,") -SkipIfMatch "^\s+module\.api_$under,?$"
                Add-ToBlock -Path (Join-Path $root 'api\locals.tf') -OpenPattern '^  apis = \{$' -CloseLine '  }' `
                    -Entries @("    api_$under = module.api_$under") -SkipIfMatch "^\s+api_$under\s*="
                Write-Change (Join-Path $root "api\$Name.modules.tf") (New-ModuleText $apiTemplate $target.AspSuffix $script:WafIndex.api)
            }

            if ($Only -contains 'Spa') {
                Add-ToBlock -Path (Join-Path $root 'spa\locals.tf') -OpenPattern '^  apps = \[$' -CloseLine '  ]' -CommaSeparated `
                    -Entries @("    module.spa_$under,") -SkipIfMatch "^\s+module\.spa_$under,?$"
                Write-Change (Join-Path $root "spa\$Name.modules.tf") (New-ModuleText $spaTemplate $target.AspSuffix $script:WafIndex.spa)
            }
        }
    }
    finally {
        if ($DryRun) {
            git -C $InfraPath worktree remove --force $workPath
            Assert-Native 'git worktree remove'
        }
    }

    if ($DryRun) {
        Write-Host '[DryRun] Phase 4 terminee, aucune modification ecrite.'
        return
    }

    $fileList = @($script:Changed | Sort-Object -Unique)
    if (Get-Command terraform -ErrorAction SilentlyContinue) {
        terraform fmt @fileList | Out-Null
    }

    git -C $InfraPath add -A
    Assert-Native 'git add'
    git -C $InfraPath commit --quiet -m "feat(infra): ajoute les modules Terraform $Name"
    Assert-Native 'git commit'

    if ($NoPublish) {
        Write-Host "Branche $branch committee localement (NoPublish : ni push ni PR)."
        return
    }

    git -C $InfraPath push -u origin $branch
    Assert-Native 'git push'
    Publish-InfraPullRequest
}

# Phase 4 : modules Terraform dans azure-infrastructure
Initialize-Infra

# Phase 5 : resume final
Write-Host ''
Write-Host "=== Resume $Name $(if ($DryRun) { '(DryRun)' }) ===" -ForegroundColor Cyan
if ($script:PullRequests.Count -gt 0) {
    Write-Host 'Pull requests :'
    $script:PullRequests | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
}
elseif (-not $DryRun) {
    Write-Host 'Aucune pull request creee.'
}
Write-Host 'A faire manuellement :'
Write-Host '  - Relire et merger les PR (init api/spa, puis infra).'
if ($Only -contains 'Api') {
    Write-Host "  - OAuth2 : scope Api$pascal.All genere ; ajouter les app_roles de l'API si necessaire."
}
if ($Only -contains 'Spa') {
    Write-Host "  - Apres merge et apply de la PR infra : relancer avec -Name $Name -LinkApi pour ajouter les api_accesses de la SPA."
}
Write-Host '  - Verifier les pipelines ADO (defaultBranch main) et le ruleset require-ci-status-check.'
