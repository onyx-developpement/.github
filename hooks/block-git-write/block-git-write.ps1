# Bloque les commandes Git qui écrivent dans l'historique ou les branches : seul le développeur les lance.
# Lit l'événement preToolUse sur stdin ; renvoie un refus sur stdout, ou {} pour ne rien décider.
$ErrorActionPreference = 'Stop'

try {
    $event = [Console]::In.ReadToEnd() | ConvertFrom-Json

    $toolName = if ($event.toolName) { $event.toolName } else { $event.tool_name }
    $toolArgs = if ($null -ne $event.toolArgs) { $event.toolArgs } else { $event.tool_input }

    # Les autres outils (édition de fichiers) peuvent citer ces commandes dans leur contenu sans les exécuter
    if ($toolName -notmatch '^(bash|powershell|run_in_terminal|send_to_terminal)$') {
        Write-Output '{}'
        exit 0
    }

    $commandText = if ($toolArgs -is [string]) { $toolArgs } else { $toolArgs | ConvertTo-Json -Compress -Depth 5 }

    $segment = '[^;&|\r\n]*?'
    $forbidden = "(?i)\bgit\b$segment\s(commit|push|rebase)\b" +
        "|\bgit\b$segment\sreset\s+--hard\b" +
        "|\bgit\b$segment\sbranch\s+(-D|-d|--delete)\b"

    if ($commandText -match $forbidden) {
        $decision = @{
            permissionDecision       = 'deny'
            permissionDecisionReason = 'Commits, pushes, rebases et suppressions de branche sont reserves au developpeur. Indiquez-lui la commande a lancer.'
        }
        Write-Output ($decision | ConvertTo-Json -Compress)
        exit 0
    }

    Write-Output '{}'
    exit 0
}
catch {
    # Une entrée illisible ne doit pas bloquer tous les outils : aucune décision
    Write-Output '{}'
    exit 0
}
