#Requires -Version 5.1
<#
Phase 4 : ajoute les modules Terraform prod et test d'une application api-<name> et/ou spa-<name>
dans azure-infrastructure, sur la branche yyyyMMdd-<name> depuis origin/main, puis ouvre la PR.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z][a-z0-9-]*$')]
    [string]$Name,

    [ValidateSet('Api', 'Spa')]
    [string[]]$Only = @('Api', 'Spa'),

    [string]$InfraPath = 'C:\dev\git\TransverseSI\azure-infrastructure',

    # Exposition Fortiweb (demandee si absente) :
    # PartoutSaufOT = internet compris (calque wfp), InterneSaufOT = defauts du module (calque proxy-m3),
    # OTUniquement = calque mes.
    [ValidateSet('PartoutSaufOT', 'InterneSaufOT', 'OTUniquement')]
    [string]$WafPreset,

    # Affiche les modifications sans rien ecrire ni committer.
    [switch]$DryRun,

    # Committe la branche sans push ni PR.
    [switch]$NoPublish
)

$ErrorActionPreference = 'Stop'

$under = $Name -replace '-', '_'
$branch = "$(Get-Date -Format yyyyMMdd)-$Name"
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
$index = $null

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

function Get-NextWafIndex {
    $indexes = foreach ($target in $environments) {
        foreach ($kind in 'api', 'spa') {
            $dir = Join-Path $tfRoot "$($target.Dir)\$kind"
            if (Test-Path -LiteralPath $dir) {
                Select-String -Path (Join-Path $dir '*.tf') -Pattern 'waf_config_index\s*=\s*(\d+)' |
                    ForEach-Object { [int]$_.Matches[0].Groups[1].Value }
            }
        }
    }
    $max = ($indexes | Measure-Object -Maximum).Maximum
    if ($null -eq $max) { 0 } else { [int]$max + 1 }
}

function New-ModuleText([string]$Template, [string]$AspSuffix) {
    $text = $Template.Replace('__UNDER__', $under).Replace('__NAME__', $Name).Replace('__ASP__', $AspSuffix).Replace('__INDEX__', [string]$index)
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

# Exposition Fortiweb choisie avant toute modification
if (-not $WafPreset) { $WafPreset = Read-WafPreset }
$script:WafBlock = $wafPresets[$WafPreset].Block -replace "`r?`n", "`r`n"
Write-Host "Exposition Fortiweb : $($wafPresets[$WafPreset].Label)"

git -C $InfraPath fetch origin main --quiet
Assert-Native 'git fetch'

# Verifications et branche (hors DryRun : l'arbre doit etre propre, la branche part de origin/main)
if (-not $DryRun) {
    if (git -C $InfraPath status --porcelain) { throw "Arbre de travail non propre dans $InfraPath" }
    git -C $InfraPath checkout -b $branch origin/main
    Assert-Native 'git checkout'
}

# Module deja present : on arrete avant toute modification
$existing = @(foreach ($target in $environments) {
    foreach ($kind in $kinds) {
        $path = Join-Path $tfRoot "$($target.Dir)\$kind\$Name.modules.tf"
        if (Test-Path -LiteralPath $path) { $path }
    }
})
if ($existing.Count -gt 0) { throw "Module deja present : $($existing -join ', ')" }

$index = Get-NextWafIndex
Write-Host "Index WAF attribue : $index"

foreach ($target in $environments) {
    $root = Join-Path $tfRoot $target.Dir

    Add-ToBlock -Path (Join-Path $root 'apps-resource-groups\locals.tf') -OpenPattern '^  resource_groups = \{$' -CloseLine '  }' `
        -Entries @("    $under = {", '      version = "001"', '    }') -SkipIfMatch "^    $under = \{$"

    if ($Only -contains 'Api') {
        Add-ToBlock -Path (Join-Path $root 'api\locals.tf') -OpenPattern '^  apps = \[$' -CloseLine '  ]' -CommaSeparated `
            -Entries @("    module.api_$under,") -SkipIfMatch "^\s+module\.api_$under,?$"
        Add-ToBlock -Path (Join-Path $root 'api\locals.tf') -OpenPattern '^  apis = \{$' -CloseLine '  }' `
            -Entries @("    api_$under = module.api_$under") -SkipIfMatch "^\s+api_$under\s*="
        Write-Change (Join-Path $root "api\$Name.modules.tf") (New-ModuleText $apiTemplate $target.AspSuffix)
    }

    if ($Only -contains 'Spa') {
        Add-ToBlock -Path (Join-Path $root 'spa\locals.tf') -OpenPattern '^  apps = \[$' -CloseLine '  ]' -CommaSeparated `
            -Entries @("    module.spa_$under,") -SkipIfMatch "^\s+module\.spa_$under,?$"
        Write-Change (Join-Path $root "spa\$Name.modules.tf") (New-ModuleText $spaTemplate $target.AspSuffix)
    }
}

if ($DryRun) {
    Write-Host '[DryRun] Termine, aucune modification ecrite.'
    return
}

$fileList = @($script:Changed | Sort-Object -Unique)
if (Get-Command terraform -ErrorAction SilentlyContinue) {
    terraform fmt @fileList | Out-Null
}

git -C $InfraPath add -A
Assert-Native 'git add'
git -C $InfraPath commit -m "feat(infra): ajoute les modules Terraform $Name"
Assert-Native 'git commit'

if ($NoPublish) {
    Write-Host "Branche $branch committee localement (NoPublish : ni push ni PR)."
    return
}

git -C $InfraPath push -u origin $branch
Assert-Native 'git push'

Push-Location $InfraPath
try {
    $body = "Modules Terraform prod et test pour $Name (types : $($Only -join ', ')), index WAF $index, exposition Fortiweb : $($wafPresets[$WafPreset].Label)."
    $prUrl = gh pr create --base main --head $branch --title "feat(infra): modules Terraform $Name" --body $body
    Assert-Native 'gh pr create'
    Write-Host "PR : $prUrl"
}
finally {
    Pop-Location
}
