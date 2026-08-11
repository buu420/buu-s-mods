$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function Test-DefinitionAtPath {
    param($Definition, [string]$Root)

    if ([string]::IsNullOrWhiteSpace([string]$Definition.exeName)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Root $Definition.exeName) -PathType Leaf)) { return $false }

    foreach ($rule in @($Definition.probeRules)) {
        $path = Join-Path $Root $rule.relativePath
        $passes = switch ($rule.type) {
            'fileExists' { Test-Path -LiteralPath $path -PathType Leaf }
            'folderExists' { Test-Path -LiteralPath $path -PathType Container }
            default { $false }
        }
        if (-not $passes) { return $false }
    }
    return $true
}

function New-File {
    param([string]$Root, [string]$RelativePath)
    $path = Join-Path $Root $RelativePath
    $parent = Split-Path -Parent $path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    [IO.File]::WriteAllBytes($path, [byte[]]@(0))
}

$catalogPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'index.json'
$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$old = @($catalog.games | Where-Object gameId -eq 'ffviiold')
$new = @($catalog.games | Where-Object gameId -eq 'ffviinew')
$compat = @($catalog.games | Where-Object gameId -eq 'ffviioldsteam2026')
Assert-Equal 1 $old.Count 'The catalog must contain exactly one FFVII 2013 definition.'
Assert-Equal 1 $new.Count 'The catalog must contain exactly one FFVII 2026 definition.'
Assert-Equal 0 $compat.Count 'The separate 7th Heaven compatibility entry must be removed.'
Assert-Equal 2 @($catalog.games).Count 'The Blind Soldier catalog must contain only the supported 2013 and 2026 entries.'
$old = $old[0]
$new = $new[0]

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('amm-ff7-catalog-' + [Guid]::NewGuid().ToString('N'))
$oldFixture = Join-Path $tempRoot '2013'
$newFixture = Join-Path $tempRoot '2026'
$incompleteFixture = Join-Path $tempRoot 'incomplete'

try {
    New-Item -ItemType Directory -Path (Join-Path $oldFixture 'data') -Force | Out-Null
    New-File $oldFixture 'ff7_en.exe'
    New-File $oldFixture 'FF7_Launcher.exe'

    New-Item -ItemType Directory -Path (Join-Path $newFixture 'ff7\workingdir\data') -Force | Out-Null
    New-File $newFixture 'FFVII.exe'
    New-File $newFixture 'FFVII_LAUNCHER.exe'
    New-File $newFixture 'steam_api64.dll'
    New-File $newFixture 'ff7\resources\ff7_1.02\ff7_en'

    New-Item -ItemType Directory -Path $incompleteFixture -Force | Out-Null
    New-File $incompleteFixture 'FFVII.exe'

    Assert-True (Test-DefinitionAtPath $old $oldFixture) 'FFVII 2013 probes rejected a complete 2013 fixture.'
    Assert-True (-not (Test-DefinitionAtPath $old $newFixture)) 'FFVII 2013 probes accepted the 2026 layout.'
    Assert-True (Test-DefinitionAtPath $new $newFixture) 'FFVII 2026 probes rejected a complete 2026 fixture.'
    Assert-True (-not (Test-DefinitionAtPath $new $oldFixture)) 'FFVII 2026 probes accepted the 2013 layout.'
    Assert-True (-not (Test-DefinitionAtPath $old $incompleteFixture)) 'FFVII 2013 probes accepted an incomplete layout.'
    Assert-True (-not (Test-DefinitionAtPath $new $incompleteFixture)) 'FFVII 2026 probes accepted an incomplete layout.'

    foreach ($definition in @($old, $new)) {
        Assert-Equal 0 @($definition.dependencies).Count "$($definition.gameId) must be self-contained and dependency-free."
        Assert-True ($definition.description -match '## Hotkeys') "$($definition.gameId) description must contain the hotkey heading."
        foreach ($key in @('R', 'U', 'O', 'J', 'L', 'K', 'I', 'F5', 'F6', 'F7', 'F8', '1', '2', '3', 'H', 'M', 'D', 'S')) {
            $needle = [string]([char]96) + $key + [char]96
            Assert-True ($definition.description.Contains($needle)) "$($definition.gameId) description is missing hotkey $key."
        }

        $post = $definition.defaultPostInstall
        Assert-True ($null -ne $post) "$($definition.gameId) must declare the legacy-registry cleanup hook."
        Assert-Equal 'files/Blind-Soldier/Tools/Remove-AmethystRegistryEntries-Automatic.cmd' $post.executable "$($definition.gameId) has the wrong cleanup executable."
        Assert-True ([bool]$post.needsAdmin) "$($definition.gameId) cleanup must request elevation."
        Assert-True ([bool]$post.failureFatal) "$($definition.gameId) cleanup failure must abort the install."
        Assert-True ([bool]$post.runOnUpdate) "$($definition.gameId) cleanup must run on update."
        Assert-True (-not [bool]$post.installToGameFolder) "$($definition.gameId) must not retain a root-level cleanup script."
        Assert-True (-not [bool]$post.runFromGameFolder) "$($definition.gameId) cleanup should run from package staging."
    }

    $allDependencies = @($catalog.games | ForEach-Object { @($_.dependencies) })
    $mislabelled = @($allDependencies | Where-Object {
        $_.id -match 'seventh.?heaven' -and $_.fix.downloadUrl -match '/FFNx/'
    })
    Assert-Equal 0 $mislabelled.Count 'A dependency named for 7th Heaven still points to FFNx.'
    Assert-True ($catalog.releasesByGameId.PSObject.Properties.Name -notcontains 'ffviioldsteam2026') 'Release metadata for the removed 7th Heaven entry must also be removed.'

    foreach ($gameId in @('ffviiold', 'ffviinew')) {
        $releases = @($catalog.releasesByGameId.$gameId)
        $matches = @($releases | Where-Object version -eq '0.2.5')
        Assert-Equal 1 $matches.Count "$gameId must publish exactly one v0.2.5 release."
        $latest = $matches[0]
        Assert-Equal 'beta' $latest.channel "$gameId v0.2.5 must be a beta release."
        Assert-True ($latest.packageUrl -match ("/v0\.2\.5/$gameId-v0\.2\.5-amm\.zip$")) "$gameId v0.2.5 points to the wrong package asset."
        Assert-True ($latest.sha256 -match '^[0-9a-f]{64}$') "$gameId v0.2.5 must have a SHA-256 digest."
    }

    Write-Host 'FFVII catalog contract verified.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
