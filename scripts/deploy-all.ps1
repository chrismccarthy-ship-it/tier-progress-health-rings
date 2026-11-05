<#
.SYNOPSIS
    Deploys tier-progress-health-rings to one or more Salesforce orgs.

.DESCRIPTION
    Runs the full sequence against each org in turn: deploy, assign the
    permission set, seed the demo data. A failure in one org is reported and
    the run moves on to the next, so one bad alias does not cost you the
    others. A summary table is printed at the end.

    Remember that a Salesforce deploy is all or nothing. If the deploy step
    reports something like "36/37 (97%)" and then "Status: Failed", nothing
    landed in that org - not even the 36. The summary below reflects that.

.PARAMETER Orgs
    Aliases to deploy to. Defaults to devhub, sdo26 and 1010sdo.

.PARAMETER SkipTests
    Deploy without running the Apex tests. Faster, but the first deploy into
    an org is the natural moment to find out whether they pass.

.PARAMETER SkipSeed
    Deploy and assign the permission set, but create no demo records.

.PARAMETER TechcoOrg
    Alias of the one org that holds the Techco Account. The Techco seed
    targets a hard-coded record id, so it is skipped everywhere else.

.EXAMPLE
    .\scripts\deploy-all.ps1

.EXAMPLE
    .\scripts\deploy-all.ps1 -Orgs devhub -SkipSeed

.EXAMPLE
    .\scripts\deploy-all.ps1 -TechcoOrg devhub
#>

[CmdletBinding()]
param(
    [string[]] $Orgs = @('devhub', 'sdo26', '1010sdo'),
    [switch]   $SkipTests,
    [switch]   $SkipSeed,
    [string]   $TechcoOrg = ''
)

$ErrorActionPreference = 'Continue'

# Run from the repository root regardless of where the script was invoked.
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

if (-not (Test-Path 'sfdx-project.json')) {
    Write-Host "sfdx-project.json not found in $repoRoot" -ForegroundColor Red
    Write-Host "Run this from inside the tier-progress-health-rings repository."
    Pop-Location
    exit 1
}

if (-not (Get-Command sf -ErrorAction SilentlyContinue)) {
    Write-Host "The Salesforce CLI (sf) is not on PATH." -ForegroundColor Red
    Write-Host "Install it with: npm install -g @salesforce/cli"
    Pop-Location
    exit 1
}

# ---------------------------------------------------------------------------

function Invoke-Step {
    <#
        Runs one sf command and returns $true on success. Output streams to
        the console as it happens so a long deploy is not a silent wait.
    #>
    param(
        [string]   $Label,
        [string[]] $Arguments,
        [switch]   $TolerateFailure
    )

    Write-Host ""
    Write-Host "  -> $Label" -ForegroundColor Cyan
    & sf @Arguments
    $ok = ($LASTEXITCODE -eq 0)

    if (-not $ok) {
        $colour = if ($TolerateFailure) { 'Yellow' } else { 'Red' }
        $word   = if ($TolerateFailure) { 'warning' } else { 'FAILED' }
        Write-Host "  -> $Label $word (exit $LASTEXITCODE)" -ForegroundColor $colour
    }

    return $ok
}

# ---------------------------------------------------------------------------

$results = [ordered]@{}

foreach ($org in $Orgs) {

    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor DarkGray
    Write-Host " $org" -ForegroundColor White
    Write-Host ("=" * 70) -ForegroundColor DarkGray

    # --- alias resolves? ---------------------------------------------------
    & sf org display --target-org $org --json 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Alias '$org' is not authorised." -ForegroundColor Red
        Write-Host "  Check 'sf org list', or authorise it with:"
        Write-Host "    sf org login web --alias $org"
        $results[$org] = 'not authorised'
        continue
    }

    # --- deploy ------------------------------------------------------------
    $deployArgs = @(
        'project', 'deploy', 'start',
        '--source-dir', 'force-app',
        '--target-org', $org
    )
    if (-not $SkipTests) {
        $deployArgs += @(
            '--test-level', 'RunSpecifiedTests',
            '--tests', 'TierProgressControllerTest'
        )
    }

    $label = if ($SkipTests) { 'Deploy' } else { 'Deploy and run 25 tests' }
    if (-not (Invoke-Step -Label $label -Arguments $deployArgs)) {
        Write-Host ""
        Write-Host "  Nothing landed in $org - a Salesforce deploy is all or nothing." -ForegroundColor Yellow
        Write-Host "  Fix the component failure above and re-run."
        $results[$org] = 'deploy failed'
        continue
    }

    # --- permission set ----------------------------------------------------
    # Already-assigned is not an error worth stopping for.
    $permsetOk = Invoke-Step -Label 'Assign Tier_Progress_User' -TolerateFailure -Arguments @(
        'org', 'assign', 'permset',
        '--name', 'Tier_Progress_User',
        '--target-org', $org
    )

    if ($SkipSeed) {
        $results[$org] = if ($permsetOk) { 'deployed (no seed)' } else { 'deployed, permset warning' }
        continue
    }

    # --- seed --------------------------------------------------------------
    $seedOk = Invoke-Step -Label 'Seed the three portable programmes' -Arguments @(
        'apex', 'run',
        '--file', 'scripts/apex/seed-tier-programs.apex',
        '--target-org', $org
    )

    # The Techco seed targets a hard-coded Account id, so it only means
    # something in the one org that record lives in.
    if ($TechcoOrg -and $org -eq $TechcoOrg) {
        Invoke-Step -Label 'Seed the Techco onboarding climb' -TolerateFailure -Arguments @(
            'apex', 'run',
            '--file', 'scripts/apex/seed-techco-onboarding.apex',
            '--target-org', $org
        ) | Out-Null
    }

    $results[$org] = if ($seedOk) { 'deployed and seeded' } else { 'deployed, seed failed' }
}

# ---------------------------------------------------------------------------

Pop-Location

Write-Host ""
Write-Host ("=" * 70) -ForegroundColor DarkGray
Write-Host " Summary" -ForegroundColor White
Write-Host ("=" * 70) -ForegroundColor DarkGray

foreach ($org in $results.Keys) {
    $state = $results[$org]
    $colour = switch -Wildcard ($state) {
        'deployed and seeded' { 'Green' }
        'deployed*'           { 'Yellow' }
        default               { 'Red' }
    }
    Write-Host ("  {0,-12} {1}" -f $org, $state) -ForegroundColor $colour
}

Write-Host ""
Write-Host "Next: App Builder -> Account record page -> drag on 'Tier Progress Ring'."
Write-Host "Expected rings: Meridian Wealth Partners 73.9%, Coastal Auto Group 75.0%,"
Write-Host "Northwind Treasury 55.9% - each 7 of 9 outstanding."
Write-Host ""

$failed = @($results.Values | Where-Object { $_ -notlike 'deployed*' }).Count
exit $failed
