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
Assert-Equal 1 $compat.Count 'The catalog must contain exactly one 2013-on-2026 compatibility definition.'
$old = $old[0]
$new = $new[0]
$compat = $compat[0]

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
    Assert-True (Test-DefinitionAtPath $compat $newFixture) 'The 2013 compatibility entry rejected the 2026 layout.'
    Assert-True (-not (Test-DefinitionAtPath $compat $oldFixture)) 'The 2013 compatibility entry accepted a real 2013 layout.'
    Assert-True (-not (Test-DefinitionAtPath $old $incompleteFixture)) 'FFVII 2013 probes accepted an incomplete layout.'
    Assert-True (-not (Test-DefinitionAtPath $new $incompleteFixture)) 'FFVII 2026 probes accepted an incomplete layout.'

    $officialUrl = 'https://github.com/tsunamods-codes/7th-Heaven/releases/download/4.5.2/7thHeaven-v4.5.2.0_Release.exe'
    $officialSha = '1a6cb7b3da0788e5fdc4174fd75367cb81a0825fec92e2817a8e95ef8f455c55'
    $uninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{E66AE545-C285-4B8C-8BD0-67282E160BF4}_is1'

    foreach ($definition in @($old, $compat)) {
        $dep = @($definition.dependencies | Where-Object id -eq 'seventh-heaven')
        Assert-Equal 1 $dep.Count "$($definition.gameId) must offer exactly one seventh-heaven dependency."
        $dep = $dep[0]
        $expectedRequired = $definition.gameId -eq 'ffviioldsteam2026'
        Assert-Equal $expectedRequired ([bool]$dep.required) "$($definition.gameId) has the wrong 7th Heaven requirement state."
        Assert-Equal '4.5.2.0' $dep.minVersion "$($definition.gameId) has the wrong 7th Heaven minimum version."
        Assert-Equal $uninstallKey $dep.check.registryKey "$($definition.gameId) has the wrong 7th Heaven registry key."
        Assert-Equal 'DisplayVersion' $dep.check.registryValue "$($definition.gameId) must read 7th Heaven's DisplayVersion."
        Assert-Equal 'HKCU' $dep.check.registryHive "$($definition.gameId) must check the per-user 7th Heaven install."
        Assert-Equal $officialUrl $dep.fix.downloadUrl "$($definition.gameId) does not use the official 7th Heaven installer."
        Assert-Equal 'runInstaller' $dep.fix.autoInstall.kind "$($definition.gameId) must run the official installer."
        Assert-Equal $officialSha $dep.fix.autoInstall.sha256 "$($definition.gameId) has the wrong installer SHA-256."
        Assert-True (-not [bool]$dep.fix.autoInstall.needsAdmin) "$($definition.gameId) should let the installer handle its own privileges."
    }

    $ffnxUrl = 'https://github.com/julianxhokaxhiu/FFNx/releases/download/1.24.3/FFNx-Steam-v1.24.3.0.zip'
    $ffnxSha = '2be45f486974f0979b849d0525eb66427df62483ec99e9339e9773e9e52afc0d'
    foreach ($case in @(
        [pscustomobject]@{ Definition = $old; Required = $false; Check = 'FFNx.toml'; Target = $null },
        [pscustomobject]@{ Definition = $compat; Required = $true; Check = 'ff7\workingdir\FFNx.toml'; Target = 'ff7\workingdir' }
    )) {
        $definition = $case.Definition
        $dep = @($definition.dependencies | Where-Object id -eq 'ffnx-game-driver')
        Assert-Equal 1 $dep.Count "$($definition.gameId) must contain exactly one FFNx game-driver dependency."
        $dep = $dep[0]
        Assert-Equal $case.Required ([bool]$dep.required) "$($definition.gameId) has the wrong FFNx requirement state."
        Assert-Equal $case.Check $dep.check.filePath "$($definition.gameId) checks FFNx in the wrong runtime."
        Assert-Equal $ffnxUrl $dep.fix.downloadUrl "$($definition.gameId) uses the wrong FFNx archive."
        Assert-Equal 'extractZip' $dep.fix.autoInstall.kind "$($definition.gameId) must extract the FFNx archive."
        Assert-Equal $case.Target $dep.fix.autoInstall.targetDir "$($definition.gameId) installs FFNx into the wrong runtime."
        Assert-Equal $ffnxSha $dep.fix.autoInstall.sha256 "$($definition.gameId) has the wrong FFNx SHA-256."
    }

    $nativeLegacyDeps = @($new.dependencies | Where-Object { $_.id -in @('seventh-heaven', 'ffnx-game-driver') })
    Assert-Equal 0 $nativeLegacyDeps.Count 'The native 2026 entry must not install 7th Heaven or FFNx.'

    $mislabelled = @($catalog.games.dependencies | Where-Object {
        $_.id -match 'seventh.?heaven' -and $_.fix.downloadUrl -match '/FFNx/'
    })
    Assert-Equal 0 $mislabelled.Count 'A dependency named for 7th Heaven still points to FFNx.'

    $compatReleases = @($catalog.releasesByGameId.ffviioldsteam2026)
    Assert-True ($compatReleases.Count -gt 0) 'The 2013-on-2026 compatibility entry has no installable release.'
    $latestCompat = $compatReleases | Sort-Object { [Version]$_.version } | Select-Object -Last 1
    Assert-True ($latestCompat.packageUrl -match '/ffviioldsteam2026-v[^/]+-amm\.zip$') 'The compatibility release points to the wrong package asset.'

    Write-Host 'FFVII catalog contract verified.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
