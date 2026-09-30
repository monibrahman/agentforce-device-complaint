# Deploys the backend, creates the agent user, and publishes the agent (Windows).
# Usage (from the project folder, in Command Prompt or PowerShell):
#   powershell -ExecutionPolicy Bypass -File .\scripts\deploy.ps1 complaints
# To reuse an agent user from an earlier run:
#   powershell -ExecutionPolicy Bypass -File .\scripts\deploy.ps1 complaints -AgentUser <username>
param(
    [string]$Org = "complaints",
    [string]$AgentUser = ""
)

$ErrorActionPreference = "Stop"
$Bundle = "MedTech_Complaint_Agent"
$Placeholder = "__AGENT_USER_PLACEHOLDER__"

Set-Location (Join-Path $PSScriptRoot "..")
$AgentFile = "force-app\main\default\aiAuthoringBundles\$Bundle\$Bundle.agent"

function Invoke-Sf {
    param([string[]]$SfArgs, [switch]$AllowFail)
    & sf @SfArgs
    if ($LASTEXITCODE -ne 0 -and -not $AllowFail) {
        throw "Command failed: sf $($SfArgs -join ' ')"
    }
}

Write-Host "==> 1/6 Deploying backend: Case fields, queue, remote site, Apex, permission set"
Invoke-Sf @("project", "deploy", "start", "--target-org", $Org,
    "--source-dir", "force-app\main\default\objects",
    "--source-dir", "force-app\main\default\queues",
    "--source-dir", "force-app\main\default\remoteSiteSettings",
    "--source-dir", "force-app\main\default\classes",
    "--source-dir", "force-app\main\default\permissionsets")

Write-Host "==> 2/6 Running Apex tests"
Invoke-Sf @("apex", "run", "test", "--target-org", $Org, "--test-level", "RunLocalTests",
    "--code-coverage", "--result-format", "human", "--wait", "10")

Write-Host "==> 3/6 Giving you (the admin) access to the complaint fields"
Invoke-Sf @("org", "assign", "permset", "--target-org", $Org, "--name", "Complaint_Agent_Access") -AllowFail

Write-Host "==> 4/6 Creating the agent user the service agent runs as"
if (-not $AgentUser) {
    $json = & sf org create agent-user --target-org $Org --json | Out-String
    if ($LASTEXITCODE -ne 0) { Write-Host $json; throw "Could not create the agent user." }
    $AgentUser = ($json | ConvertFrom-Json).result.username
}
# Guard: a service agent must never run as a human admin. Confirm the user has the Einstein Agent User profile.
$profileJson = & sf data query --target-org $Org --json --query "SELECT Profile.Name FROM User WHERE Username = '$AgentUser'" | Out-String
$profileName = (($profileJson | ConvertFrom-Json).result.records | Select-Object -First 1).Profile.Name
if ($profileName -ne "Einstein Agent User") {
    throw "'$AgentUser' has profile '$profileName', not 'Einstein Agent User'. A service agent must run as a dedicated agent user, never as an admin. Find it with: sf data query --target-org $Org --query `"SELECT Username FROM User WHERE Profile.Name = 'Einstein Agent User'`""
}
Write-Host "   Agent user: $AgentUser   (re-run with -AgentUser $AgentUser to reuse it)"
Invoke-Sf @("org", "assign", "permset", "--target-org", $Org, "--name", "Complaint_Agent_Access",
    "--on-behalf-of", $AgentUser) -AllowFail

Write-Host "==> 5/6 Validating and publishing the agent"
# The agent user is org-specific, so it never gets committed. Swap it in, then restore.
$original = Get-Content $AgentFile -Raw
try {
    $updated = $original.Replace($Placeholder, $AgentUser)
    [System.IO.File]::WriteAllText((Resolve-Path $AgentFile), $updated, (New-Object System.Text.UTF8Encoding $false))
    Invoke-Sf @("agent", "validate", "authoring-bundle", "--target-org", $Org, "--api-name", $Bundle)
    Invoke-Sf @("agent", "publish", "authoring-bundle", "--target-org", $Org, "--api-name", $Bundle, "--skip-retrieve")
}
finally {
    [System.IO.File]::WriteAllText((Resolve-Path $AgentFile), $original, (New-Object System.Text.UTF8Encoding $false))
}

Write-Host "==> 6/6 Activating the agent"
Invoke-Sf @("agent", "activate", "--target-org", $Org, "--api-name", $Bundle)

Write-Host ""
Write-Host "Done. Try it:"
Write-Host "  sf agent preview --target-org $Org --api-name $Bundle"
