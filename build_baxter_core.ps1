################################################################################
# build_baxter_core.ps1
# Creates _BaxterCore.json sub-workflow and updates Orchestrator + JobRunner
################################################################################

Set-StrictMode -Off
$ErrorActionPreference = "Stop"
$workflowDir = "c:\Users\maxva\Repositories\local-ai-system\n8n\workflows"

# ── IDs ──────────────────────────────────────────────────────────────────────
$CORE_WORKFLOW_ID   = "baxtercore2025v1"
$CORE_START_ID      = "bc000001-0000-0000-0000-000000000001"
$CORE_SETVARS_ID    = "bc000001-0000-0000-0000-000000000002"
$CORE_SETOUTPUT_ID  = "bc000001-0000-0000-0000-000000000003"
$ORC_CALLCORE_ID    = "bc000001-0000-0000-0000-000000000004"
$JR_CALLCORE_ID     = "bc000001-0000-0000-0000-000000000005"
$JR_VAULTNAV_ID     = "bc000001-0000-0000-0000-000000000006"

# ── Load files ────────────────────────────────────────────────────────────────
Write-Host "Loading workflow files..."
$orcRaw = Get-Content "$workflowDir\c-Baxter-v2-Orchestrator-v8.json" -Raw -Encoding UTF8
$jrRaw  = Get-Content "$workflowDir\5-JobRunner.json" -Raw -Encoding UTF8
$orcObj = $orcRaw | ConvertFrom-Json
$jrObj  = $jrRaw  | ConvertFrom-Json

# ── Shared node list ──────────────────────────────────────────────────────────
$sharedNames = @(
  'LlamaCpp Main','Simple Memory','Agent',
  'GetSchema','ExecQuery',
  'Wikipedia','Research Agent','DuckDuckGo','WeatherAPI',
  'LlamaCpp Research','Memory RS',
  'Qdrant Vector Store','Embeddings Ollama',
  'LlamaCpp PM','Project Manager','Memory PM',
  'GetTasks','GetSubtasks','UpsertTask','UpsertSubtask',
  'GetReminders','UpsertReminders','GetProjects','UpsertProject',
  'LlamaCpp Calendar','CalendarManager','MemoryCalendar',
  'GetEvents','CreateEvent','UpdateEvent','DeleteEvent',
  'NewsTool','CreateTask','GetTaskStatus','UpdateProfile',
  'ReadVaultNote','SearchVault','WriteVaultNote'
)

# Extract shared nodes from ORC (preserving all params, credentials, positions)
$sharedNodes = $orcObj.nodes | Where-Object { $_.name -in $sharedNames }
Write-Host "Extracted $($sharedNodes.Count) shared nodes from Orchestrator"

# Note: Agent node systemMessage will be patched via string replacement after serialization
# (PSCustomObject doesn't allow adding new properties directly)

# ── New nodes for BaxterCore ──────────────────────────────────────────────────
$startJson = @"
{
  "id": "$CORE_START_ID",
  "name": "Start",
  "type": "n8n-nodes-base.executeWorkflowTrigger",
  "typeVersion": 1,
  "position": [240, 400],
  "parameters": {}
}
"@

$setVarsCode = 'const inp = $input.first().json;\nreturn {\n  systemPrompt: inp.systemPrompt ?? \"\",\n  RequestInput: { input: inp.userMessage ?? \"\" },\n  ChannelInformation: {\n    ChannelID: inp.channelId ?? null,\n    MessageID: inp.messageId ?? null\n  },\n  InputType: inp.inputType ?? \"text\"\n};'

$setVarsJson = @"
{
  "id": "$CORE_SETVARS_ID",
  "name": "SetVars",
  "type": "n8n-nodes-base.code",
  "typeVersion": 2,
  "position": [460, 400],
  "parameters": {
    "jsCode": "$setVarsCode"
  }
}
"@

# SetOutput: same logic as ORC SetOutput but reads from SetVars (same name, fine)
# We include full cleanResponse logic. Output mimics old SetOutput shape for compat.
$setOutputCode = 'let vars = $(''SetVars'').first().json;\nlet rawOutput = $(''Agent'').first().json.output ?? \"\";\n\nconst cleanResponse = (input) => {\n    if (!input || typeof input !== \"string\") return \"\";\n    let output = input.replace(/\\\\n/g, \"\\n\");\n    output = output.replace(/<think>[\\s\\S]*?<\\/think>/gi, \"\");\n    output = output.replace(/<think>[\\s\\S]*/gi, \"\");\n    output = output.replace(/<\\|channel>thought[\\s\\S]*?<channel\\|>/gi, \"\");\n    output = output.replace(/<\\|channel>thought[\\s\\S]*/gi, \"\");\n    output = output.trim();\n    const matches = [...output.matchAll(/RESPONSE:\\s*/g)];\n    if (matches.length > 0) {\n        const last = matches[matches.length - 1];\n        const extracted = output.slice(last.index + last[0].length).trim();\n        if (extracted.length > 0) return extracted.slice(0, 3000) + (extracted.length > 3000 ? \"...\" : \"\");\n    }\n    const reasoningPatterns = [\n        /^(okay|ok|alright|right|so|well)[,\\s]/i,/^let me\\s/i,\n        /^i(''ll| will| need to| should| must| can| am going to)\\s/i,\n        /^i(''ve| have) (retrieved|fetched|found|got|collected)/i,\n        /^now i(''ll| need| should| will| can)/i,\n        /^(first|now|next|then|finally)[,\\s]/i,\n        /^the user[\\s(wants|asked|needs)]/i,\n        /^they (want|asked|need|said)/i,\n        /^(looking at|checking|reviewing|analyzing|considering)/i,\n        /^(since|given that|because|as)\\s/i,\n        /^(therefore|thus|so|hence)\\s/i,\n        /^my (response|answer|plan|approach)/i,\n        /^let me (format|organize|structure|present|summarize|summarise)/i,\n        /^here(''s| is) (a summary|the|what)/i,\n        /^this (seems|looks|appears|is a)/i,\n        /^it (seems|looks|appears)/i,\n        /^(OUTPUT:|##OUTPUT|Start your final answer|\\/no_think)/i,\n    ];\n    const lines = output.split(\"\\n\").map(l => l.trim()).filter(Boolean);\n    const responseLines = lines.filter(l => !reasoningPatterns.some(p => p.test(l)));\n    const result = (responseLines.length > 0 ? responseLines : [lines[lines.length - 1] || \"\"]).join(\"\\n\").trim();\n    return result.slice(0, 3000) + (result.length > 3000 ? \"...\" : \"\");\n};\n\nlet response = cleanResponse(rawOutput);\nif (!response || response.trim().length === 0) {\n    response = \"Sorry, I ran into an issue formulating a response. Please try again.\";\n}\n\nreturn {\n    ...vars,\n    AgentOutput: {\n        response,\n        model: null,\n        tokens: { prompt: null, completion: null, total: null },\n        metadata: {}\n    }\n};'

$setOutputJson = @"
{
  "id": "$CORE_SETOUTPUT_ID",
  "name": "SetOutput",
  "type": "n8n-nodes-base.code",
  "typeVersion": 2,
  "position": [1800, 400],
  "parameters": {
    "jsCode": "$setOutputCode"
  }
}
"@

# ── Serialize shared nodes (positions kept from ORC) ──────────────────────────
# We serialize nodes to JSON individually and join them
$sharedNodesJson = ($sharedNodes | ForEach-Object {
    $_ | ConvertTo-Json -Depth 20 -Compress
}) -join ",`n"

# Assemble full nodes array as raw JSON
$nodesArrayJson = "[$startJson,$setVarsJson,$sharedNodesJson,$setOutputJson]"

# Patch Agent node: replace BuildSystemPrompt reference with SetVars.systemPrompt
$searchStr = [regex]::Escape("\u0027BuildSystemPrompt\u0027).first().json.systemPrompt")
$replaceStr = "\u0027SetVars\u0027).first().json.systemPrompt"
$nodesArrayJson = [System.Text.RegularExpressions.Regex]::Replace($nodesArrayJson, $searchStr, $replaceStr)

# Validate nodes JSON parses
$nodesArrayJson | ConvertFrom-Json | Out-Null
Write-Host "Nodes array valid ($($sharedNodes.Count + 3) nodes)"

# ── Build connections as raw JSON (nested array safe) ─────────────────────────
$connectionsJson = @'
{
  "Start": { "main": [[{"node": "SetVars", "type": "main", "index": 0}]] },
  "SetVars": { "main": [[{"node": "Agent", "type": "main", "index": 0}]] },
  "Agent": { "main": [[{"node": "SetOutput", "type": "main", "index": 0}]] },
  "LlamaCpp Main": { "ai_languageModel": [[{"node": "Agent", "type": "ai_languageModel", "index": 0}]] },
  "Simple Memory": { "ai_memory": [[{"node": "Agent", "type": "ai_memory", "index": 0}]] },
  "GetSchema": { "ai_tool": [[{"node": "Agent", "type": "ai_tool", "index": 0}]] },
  "ExecQuery": { "ai_tool": [[{"node": "Agent", "type": "ai_tool", "index": 0}]] },
  "Qdrant Vector Store": { "ai_tool": [[{"node": "Agent", "type": "ai_tool", "index": 0}]] },
  "Research Agent": { "ai_tool": [[{"node": "Agent", "type": "ai_tool", "index": 0}]] },
  "Project Manager": { "ai_tool": [[{"node": "Agent", "type": "ai_tool", "index": 0}]] },
  "CalendarManager": { "ai_tool": [[{"node": "Agent", "type": "ai_tool", "index": 0}]] },
  "NewsTool": { "ai_tool": [[{"node": "Agent", "type": "ai_tool", "index": 0}]] },
  "CreateTask": { "ai_tool": [[{"node": "Agent", "type": "ai_tool", "index": 0}]] },
  "GetTaskStatus": { "ai_tool": [[{"node": "Agent", "type": "ai_tool", "index": 0}]] },
  "UpdateProfile": { "ai_tool": [[{"node": "Agent", "type": "ai_tool", "index": 0}]] },
  "ReadVaultNote": { "ai_tool": [[{"node": "Agent", "type": "ai_tool", "index": 0}]] },
  "SearchVault": { "ai_tool": [[{"node": "Agent", "type": "ai_tool", "index": 0}]] },
  "WriteVaultNote": { "ai_tool": [[{"node": "Agent", "type": "ai_tool", "index": 0}]] },
  "Wikipedia": { "ai_tool": [[{"node": "Research Agent", "type": "ai_tool", "index": 0}]] },
  "DuckDuckGo": { "ai_tool": [[{"node": "Research Agent", "type": "ai_tool", "index": 0}]] },
  "WeatherAPI": { "ai_tool": [[{"node": "Research Agent", "type": "ai_tool", "index": 0}]] },
  "LlamaCpp Research": { "ai_languageModel": [[{"node": "Research Agent", "type": "ai_languageModel", "index": 0}]] },
  "Memory RS": { "ai_memory": [[{"node": "Research Agent", "type": "ai_memory", "index": 0}]] },
  "GetTasks": { "ai_tool": [[{"node": "Project Manager", "type": "ai_tool", "index": 0}]] },
  "GetSubtasks": { "ai_tool": [[{"node": "Project Manager", "type": "ai_tool", "index": 0}]] },
  "UpsertTask": { "ai_tool": [[{"node": "Project Manager", "type": "ai_tool", "index": 0}]] },
  "UpsertSubtask": { "ai_tool": [[{"node": "Project Manager", "type": "ai_tool", "index": 0}]] },
  "GetReminders": { "ai_tool": [[{"node": "Project Manager", "type": "ai_tool", "index": 0}]] },
  "UpsertReminders": { "ai_tool": [[{"node": "Project Manager", "type": "ai_tool", "index": 0}]] },
  "GetProjects": { "ai_tool": [[{"node": "Project Manager", "type": "ai_tool", "index": 0}]] },
  "UpsertProject": { "ai_tool": [[{"node": "Project Manager", "type": "ai_tool", "index": 0}]] },
  "LlamaCpp PM": { "ai_languageModel": [[{"node": "Project Manager", "type": "ai_languageModel", "index": 0}]] },
  "Memory PM": { "ai_memory": [[{"node": "Project Manager", "type": "ai_memory", "index": 0}]] },
  "GetEvents": { "ai_tool": [[{"node": "CalendarManager", "type": "ai_tool", "index": 0}]] },
  "CreateEvent": { "ai_tool": [[{"node": "CalendarManager", "type": "ai_tool", "index": 0}]] },
  "UpdateEvent": { "ai_tool": [[{"node": "CalendarManager", "type": "ai_tool", "index": 0}]] },
  "DeleteEvent": { "ai_tool": [[{"node": "CalendarManager", "type": "ai_tool", "index": 0}]] },
  "LlamaCpp Calendar": { "ai_languageModel": [[{"node": "CalendarManager", "type": "ai_languageModel", "index": 0}]] },
  "MemoryCalendar": { "ai_memory": [[{"node": "CalendarManager", "type": "ai_memory", "index": 0}]] },
  "Embeddings Ollama": { "ai_embedding": [[{"node": "Qdrant Vector Store", "type": "ai_embedding", "index": 0}]] }
}
'@

# ── Assemble BaxterCore workflow JSON ─────────────────────────────────────────
$coreWorkflow = @"
{
  "id": "$CORE_WORKFLOW_ID",
  "name": "_BaxterCore",
  "nodes": $nodesArrayJson,
  "connections": $connectionsJson,
  "active": false,
  "settings": {
    "executionOrder": "v1"
  },
  "versionId": "1"
}
"@

# Validate
$coreWorkflow | ConvertFrom-Json | Out-Null
Write-Host "BaxterCore workflow JSON valid"

# Write
$corePath = "$workflowDir\_BaxterCore.json"
[System.IO.File]::WriteAllText($corePath, $coreWorkflow, [System.Text.Encoding]::UTF8)
Write-Host "Written: $corePath"

################################################################################
# UPDATE ORCHESTRATOR
################################################################################
Write-Host "`nUpdating Orchestrator..."

# Build call node template as single-quoted string (no expansion), then substitute IDs
$callCoreTemplate = @'
{
  "id": "PLACEHOLDER_ID",
  "name": "Call _BaxterCore",
  "type": "n8n-nodes-base.executeWorkflow",
  "typeVersion": 1,
  "position": [PLACEHOLDER_X, 400],
  "parameters": {
    "workflowId": {"__rl": true, "value": "PLACEHOLDER_WORKFLOW_ID", "mode": "id"},
    "workflowInputs": {
      "mappingMode": "defineBelow",
      "value": {
        "systemPrompt": "={{ $('BuildSystemPrompt').first().json.systemPrompt }}",
        "userMessage": "={{ $('SetVars').first().json.RequestInput.input }}",
        "channelId": "={{ $('SetVars').first().json.ChannelInformation.ChannelID }}",
        "inputType": "={{ $('SetVars').first().json.InputType }}",
        "messageId": "={{ $('SetVars').first().json.ChannelInformation.MessageID }}"
      },
      "matchingColumns": ["systemPrompt"],
      "schema": [
        {"id": "systemPrompt", "displayName": "systemPrompt", "required": false, "defaultMatch": false, "display": true, "canBeUsedToMatch": true, "removed": false},
        {"id": "userMessage", "displayName": "userMessage", "required": false, "defaultMatch": false, "display": true, "canBeUsedToMatch": false, "removed": false},
        {"id": "channelId", "displayName": "channelId", "required": false, "defaultMatch": false, "display": true, "canBeUsedToMatch": false, "removed": false},
        {"id": "inputType", "displayName": "inputType", "required": false, "defaultMatch": false, "display": true, "canBeUsedToMatch": false, "removed": false},
        {"id": "messageId", "displayName": "messageId", "required": false, "defaultMatch": false, "display": true, "canBeUsedToMatch": false, "removed": false}
      ],
      "attemptToConvertTypes": false,
      "convertFieldsToString": true
    },
    "options": {}
  }
}
'@

$orcCallCoreNode = "," + ($callCoreTemplate `
    -replace 'PLACEHOLDER_ID', $ORC_CALLCORE_ID `
    -replace 'PLACEHOLDER_X', '1600' `
    -replace 'PLACEHOLDER_WORKFLOW_ID', $CORE_WORKFLOW_ID)

# Parse ORC, remove shared nodes, update expressions, add Call _BaxterCore
$orcObj2 = $orcRaw | ConvertFrom-Json

# Remove shared nodes from ORC
$orcObj2.nodes = $orcObj2.nodes | Where-Object { $_.name -notin $sharedNames }
Write-Host "ORC nodes after removal: $($orcObj2.nodes.Count)"

# Update Insert rows node: $('SetOutput') → $('Call _BaxterCore')
$insertNode = $orcObj2.nodes | Where-Object { $_.name -like '*Insert*' }
if ($insertNode) {
  $insertParams = $insertNode.parameters | ConvertTo-Json -Depth 10
  $insertParams = [System.Text.RegularExpressions.Regex]::Replace($insertParams, [regex]::Escape("\u0027SetOutput\u0027"), "\u0027Call _BaxterCore\u0027")
  $insertNode.parameters = $insertParams | ConvertFrom-Json
}

# Update Call Communication node  
$commNode = $orcObj2.nodes | Where-Object { $_.name -like "*Communication*" }
if ($commNode) {
  $commParams = $commNode.parameters | ConvertTo-Json -Depth 10
  $commParams = $commParams -replace [regex]::Escape("'SetOutput'"), "'Call _BaxterCore'"
  $commParams = $commParams -replace [regex]::Escape("\u0027SetOutput\u0027"), "\u0027Call _BaxterCore\u0027"
  $commNode.parameters = $commParams | ConvertFrom-Json
}

# Serialize ORC to JSON string (nodes only, we'll handle connections manually)
$orcNodesJson = ($orcObj2.nodes | ConvertTo-Json -Depth 20 -Compress).TrimEnd(']') + $orcCallCoreNode + "]"

# Build ORC connections from scratch (hardcoded, avoids nested-array serialization issues)
# Flow: Start → ParseInput → SetVars → Vault Navigation → FetchProfile → BuildSystemPrompt → Call _BaxterCore → Insert rows → Call Communication
$orcConnStr = @'
{
  "Start": {"main": [[{"node": "ParseInput", "type": "main", "index": 0}]]},
  "ParseInput": {"main": [[{"node": "SetVars", "type": "main", "index": 0}]]},
  "SetVars": {"main": [[{"node": "Vault Navigation", "type": "main", "index": 0}]]},
  "Vault Navigation": {"main": [[{"node": "FetchProfile", "type": "main", "index": 0}]]},
  "FetchProfile": {"main": [[{"node": "BuildSystemPrompt", "type": "main", "index": 0}]]},
  "BuildSystemPrompt": {"main": [[{"node": "Call _BaxterCore", "type": "main", "index": 0}]]},
  "Call _BaxterCore": {"main": [[{"node": "Insert rows in a table", "type": "main", "index": 0}]]},
  "Insert rows in a table": {"main": [[{"node": "Call 'z-Baxter-v2-Communication'", "type": "main", "index": 0}]]}
}
'@

# Build final ORC JSON
$orcId = if ($orcObj2.id) { $orcObj2.id } else { 'orchestrator' }
$orcSettings = if ($orcObj2.settings) { $orcObj2.settings | ConvertTo-Json -Depth 4 } else { '{"executionOrder":"v1"}' }
$orcVersionId = if ($orcObj2.versionId) { $orcObj2.versionId } else { '1' }
$orcFinal = @"
{
  "id": "$orcId",
  "name": "$($orcObj2.name)",
  "nodes": $orcNodesJson,
  "connections": $orcConnStr,
  "active": $($orcObj2.active.ToString().ToLower()),
  "settings": $orcSettings,
  "versionId": "$orcVersionId"
}
"@

# Validate
try {
    $orcFinal | ConvertFrom-Json | Out-Null
    Write-Host "ORC JSON valid"
    [System.IO.File]::WriteAllText("$workflowDir\c-Baxter-v2-Orchestrator-v8.json", $orcFinal, [System.Text.Encoding]::UTF8)
    Write-Host "ORC written"
} catch {
    Write-Host "ORC JSON ERROR: $_"
    $orcFinal | Out-File "$workflowDir\c-Baxter-v2-Orchestrator-v8.json.broken" -Encoding UTF8
}

################################################################################
# UPDATE JOBRUNNER
################################################################################
Write-Host "`nUpdating JobRunner..."

$jrObj2 = $jrRaw | ConvertFrom-Json

# Nodes to remove from JR (JR had a subset — let's check which shared nodes JR actually has)
$jrSharedToRemove = $jrObj2.nodes | Where-Object { $_.name -in $sharedNames }
Write-Host "JR shared nodes to remove: $($jrSharedToRemove.Count) ($($jrSharedToRemove.name -join ', '))"

$jrObj2.nodes = $jrObj2.nodes | Where-Object { $_.name -notin $sharedNames -and $_.name -ne 'SetOutput' }
Write-Host "JR nodes after removal: $($jrObj2.nodes.Count)"

# Add Vault Navigation node to JR (Code node that reads Navigation.md)
$vaultNavCode = 'const fs = require(''fs'');\nconst content = fs.readFileSync(''/data/vault/Maps/Navigation.md'', ''utf8'');\nreturn [{ json: { stdout: content } }];'
$vaultNavNodeJson = @"
{
  "id": "$JR_VAULTNAV_ID",
  "name": "Vault Navigation",
  "type": "n8n-nodes-base.code",
  "typeVersion": 2,
  "position": [1200, 400],
  "parameters": {
    "jsCode": "$vaultNavCode"
  }
}
"@

# The "Call _BaxterCore" node for JR (reuse template, substitute JR ID and x-position)
$jrCallCoreNode = $callCoreTemplate `
    -replace 'PLACEHOLDER_ID', $JR_CALLCORE_ID `
    -replace 'PLACEHOLDER_X', '1800' `
    -replace 'PLACEHOLDER_WORKFLOW_ID', $CORE_WORKFLOW_ID

# Serialize JR nodes + add Vault Navigation + add Call _BaxterCore
$jrNodesJson = ($jrObj2.nodes | ConvertTo-Json -Depth 20 -Compress).TrimEnd(']') + ",$vaultNavNodeJson,$jrCallCoreNode]"

# Update WriteResult node: replace $('SetOutput') refs with $('Call _BaxterCore')
$jrNodesJson = [System.Text.RegularExpressions.Regex]::Replace($jrNodesJson, [regex]::Escape("\u0027SetOutput\u0027"), "\u0027Call _BaxterCore\u0027")

# Build JR connections from scratch (hardcoded, avoids nested-array serialization issues)
# Flow: Schedule Trigger → GetPendingJob → Has Pending Job? → MarkRunning → ParseInput
#       → FetchTaskContext → SetVars → FetchProfile → Vault Navigation → BuildSystemPrompt
#       → Call _BaxterCore → WriteResult → NotifyMax
$jrConnStr = @'
{
  "Schedule Trigger": {"main": [[{"node": "GetPendingJob", "type": "main", "index": 0}]]},
  "GetPendingJob": {"main": [[{"node": "Has Pending Job?", "type": "main", "index": 0}]]},
  "Has Pending Job?": {"main": [[{"node": "MarkRunning", "type": "main", "index": 0}]]},
  "MarkRunning": {"main": [[{"node": "ParseInput", "type": "main", "index": 0}]]},
  "ParseInput": {"main": [[{"node": "FetchTaskContext", "type": "main", "index": 0}]]},
  "FetchTaskContext": {"main": [[{"node": "SetVars", "type": "main", "index": 0}]]},
  "SetVars": {"main": [[{"node": "FetchProfile", "type": "main", "index": 0}]]},
  "FetchProfile": {"main": [[{"node": "Vault Navigation", "type": "main", "index": 0}]]},
  "Vault Navigation": {"main": [[{"node": "BuildSystemPrompt", "type": "main", "index": 0}]]},
  "BuildSystemPrompt": {"main": [[{"node": "Call _BaxterCore", "type": "main", "index": 0}]]},
  "Call _BaxterCore": {"main": [[{"node": "WriteResult", "type": "main", "index": 0}]]},
  "WriteResult": {"main": [[{"node": "NotifyMax", "type": "main", "index": 0}]]}
}
'@

# Build final JR JSON
$jrId = if ($jrObj2.id) { $jrObj2.id } else { 'jobrunner' }
$jrSettings = if ($jrObj2.settings) { $jrObj2.settings | ConvertTo-Json -Depth 4 } else { '{"executionOrder":"v1"}' }
$jrVersionId = if ($jrObj2.versionId) { $jrObj2.versionId } else { '1' }
$jrFinal = @"
{
  "id": "$jrId",
  "name": "$($jrObj2.name)",
  "nodes": $jrNodesJson,
  "connections": $jrConnStr,
  "active": $($jrObj2.active.ToString().ToLower()),
  "settings": $jrSettings,
  "versionId": "$jrVersionId"
}
"@

try {
    $jrFinal | ConvertFrom-Json | Out-Null
    Write-Host "JR JSON valid"
    [System.IO.File]::WriteAllText("$workflowDir\5-JobRunner.json", $jrFinal, [System.Text.Encoding]::UTF8)
    Write-Host "JR written"
} catch {
    Write-Host "JR JSON ERROR: $_"
    $jrFinal | Out-File "$workflowDir\5-JobRunner.json.broken" -Encoding UTF8
}

Write-Host "`nDone! Summary:"
Write-Host "  Created: $corePath"
Write-Host "  Updated: $workflowDir\c-Baxter-v2-Orchestrator-v8.json"
Write-Host "  Updated: $workflowDir\5-JobRunner.json"
Write-Host ""
Write-Host "Next: docker compose restart n8n-import ; docker compose restart n8n"
