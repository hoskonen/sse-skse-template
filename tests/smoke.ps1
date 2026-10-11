[CmdletBinding()]
param(
    [switch]$Build,
    [string]$RepositoryUrl = 'https://github.com/hoskonen/sse-skse-template.git'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Native {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command $($Arguments -join ' ') failed: $LASTEXITCODE" }
}
function Check {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}
function Setup {
    param([string]$Path, [string[]]$Options, [bool]$Fails = $false)
    # -File loses embedded double quotes through Windows PowerShell's native
    # argument marshalling. Put literal arguments in a disposable runner instead.
    $tokens = @($Options | ForEach-Object {
        if ($_ -match '^-[A-Za-z]+$') { $_ } else { "'" + $_.Replace("'", "''") + "'" }
    })
    $command = "try { & '" + (Join-Path $Path 'setup.ps1').Replace("'", "''") +
        "' " + ($tokens -join ' ') + "; exit 0 } catch { Write-Error `$_; exit 1 }"
    $runner = Join-Path $Path '.git/smoke-invoke.ps1'
    Set-Content -LiteralPath $runner -Value $command -Encoding UTF8
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner
    $code = $LASTEXITCODE
    Check (($code -ne 0) -eq $Fails) "setup exit code $code (expected failure: $Fails)"
}
function Clone-Case {
    param([string]$Name)
    $path = Join-Path $testRoot $Name
    Native git @('clone', '--local', $fixture, $path)
    Native git @('-C', $path, 'config', 'user.name', 'Template Smoke Test')
    Native git @('-C', $path, 'config', 'user.email', 'smoke@example.invalid')
    return $path
}

$source = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('skse-template-smoke-' + [guid]::NewGuid().ToString('N'))
$fixture = Join-Path $testRoot 'fixture'
New-Item -ItemType Directory -Path $testRoot | Out-Null
Write-Host "Disposable clones retained at: $testRoot"
Native git @('clone', '--recurse-submodules', $RepositoryUrl, $fixture)
Copy-Item -LiteralPath (Join-Path $source 'setup.ps1'), (Join-Path $source 'README.md'), (Join-Path $source 'xmake.lua') -Destination $fixture
Native git @('-C', $fixture, 'add', '--', 'setup.ps1', 'README.md', 'xmake.lua')
Native git @('-C', $fixture, '-c', 'user.name=Template Smoke Test', '-c', 'user.email=smoke@example.invalid', 'commit', '--allow-empty', '-m', 'Disposable smoke fixture')

$project = Clone-Case 'project'
$original = Native git @('-C', $project, 'rev-parse', 'HEAD')
foreach ($options in @(
    @('-ProjectName', '', '-Description', 'Test', '-SkipConfigure'),
    @('-ProjectName', 'CON', '-Description', 'Test', '-SkipConfigure'),
    @('-ProjectName', 'Bad-Name', '-Description', 'Test', '-SkipConfigure'),
    @('-ProjectName', 'GoodName', '-Description', '', '-SkipConfigure'),
    @('-ProjectName', 'GoodName', '-Description', 'A "quoted" description', '-SkipConfigure')
)) { Setup $project $options $true }
Check ((Native git @('-C', $project, 'rev-parse', 'HEAD')) -eq $original) 'invalid input preserves HEAD'
Check (-not (Native git @('-C', $project, 'status', '--porcelain'))) 'invalid input preserves files'

Add-Content -LiteralPath (Join-Path $project 'src/main.cpp') -Value '// dirty smoke input'
Setup $project @('-ProjectName', 'GoodName', '-Description', 'Test', '-SkipConfigure') $true
Native git @('-C', $project, 'restore', '--', 'src/main.cpp')
# Whitespace survives PS 5.1 native argument passing and Git rejects it as
# an empty identity; empty native arguments would instead query the setting.
Native git @('-C', $project, 'config', 'user.name', ' ')
Native git @('-C', $project, 'config', 'user.email', ' ')
Setup $project @('-ProjectName', 'GoodName', '-Description', 'Test', '-SkipConfigure') $true
Check (-not (Native git @('-C', $project, 'status', '--porcelain'))) 'missing identity preserves files'
Native git @('-C', $project, 'config', 'user.name', 'Template Smoke Test')
Native git @('-C', $project, 'config', 'user.email', 'smoke@example.invalid')

# Emulate interruption just before the branch is replaced. The only lock we
# remove is the one this test creates, inside its own disposable clone.
$lock = Join-Path $project '.git/refs/heads/main.lock'
[IO.File]::WriteAllText($lock, 'smoke test lock')
$description = 'Smoke $1 and apostrophe '' with Unicode: caf' + [char]0xE9
Setup $project @('-ProjectName', 'SmokePlugin', '-Description', $description, '-SkipConfigure') $true
Check ((Native git @('-C', $project, 'rev-parse', 'HEAD')) -eq $original) 'failed branch update preserves template HEAD'
Check (Test-Path -LiteralPath (Join-Path $project '.git/template-setup.json')) 'interruption leaves a recovery record'
Remove-Item -LiteralPath $lock
Setup $project @('-SkipConfigure')
$head = Native git @('-C', $project, 'rev-parse', 'HEAD')
Check ((Native git @('-C', $project, 'branch', '--show-current')) -eq 'main') 'main branch'
Check ((Native git @('-C', $project, 'rev-list', '--count', 'HEAD')) -eq '1') 'one root commit'
Check ((Native git @('-C', $project, 'rev-list', '--parents', 'HEAD')) -eq $head) 'initial commit has no parent'
Check (-not (Native git @('-C', $project, 'remote'))) 'template origin removed'
Check (-not (Native git @('-C', $project, 'status', '--porcelain'))) 'clean generated project'
$entry = Native git @('-C', $project, 'ls-files', '--stage', '--', 'lib/commonlibsse-ng')
$fixtureEntry = Native git @('-C', $fixture, 'ls-files', '--stage', '--', 'lib/commonlibsse-ng')
Check ($entry -eq $fixtureEntry -and $entry -match '^160000 ') 'pinned CommonLib gitlink preserved'
$submodules = @(Native git @('-C', $project, 'submodule', 'status', '--recursive'))
Check ($submodules.Count -eq 2 -and @($submodules | Where-Object { $_ -notmatch '^ ' }).Count -eq 0) 'missing and nested submodules initialized'
$xmake = [IO.File]::ReadAllText((Join-Path $project 'xmake.lua'))
Check ($xmake.Contains('set_project("SmokePlugin")') -and $xmake.Contains('target("SmokePlugin")') -and
    $xmake.Contains('name = "SmokePlugin"') -and $xmake.Contains('description = "' + $description + '"') -and
    -not $xmake.Contains('__PROJECT_')) 'all XMake substitutions are literal and complete'
$readme = [IO.File]::ReadAllText((Join-Path $project 'README.md'))
Check ($readme.StartsWith("# SmokePlugin`n`n$description`n")) 'README name and description including UTF-8'
Setup $project @('-SkipConfigure')
Setup $project @('-ProjectName', 'RenameAttempt', '-Description', 'Test', '-SkipConfigure') $true
Check ((Native git @('-C', $project, 'rev-parse', 'HEAD')) -eq $head) 'reruns preserve history'
Check (-not (Native git @('-C', $project, 'status', '--porcelain'))) 'reruns preserve clean files'

# A native configuration failure must not corrupt completed initialization.
$fakeBin = Join-Path $testRoot 'fake-bin'
New-Item -ItemType Directory -Path $fakeBin | Out-Null
[IO.File]::WriteAllText((Join-Path $fakeBin 'xmake.cmd'), "@exit /b 17`r`n")
$oldPath = $env:PATH
try {
    $env:PATH = "$fakeBin;$oldPath"
    Setup $project @() $true
} finally { $env:PATH = $oldPath }
Check ((Native git @('-C', $project, 'rev-parse', 'HEAD')) -eq $head) 'configuration failure preserves initialized history'
Setup $project @('-SkipConfigure')

try {
    $gitDirectory = Split-Path (Get-Command git).Source
    $psDirectory = Split-Path (Get-Command powershell.exe).Source
    $env:PATH = "$gitDirectory;$psDirectory;$env:SystemRoot\System32"
    Check (-not (Get-Command xmake -ErrorAction SilentlyContinue)) 'XMake excluded from test PATH'
    Setup $project @()
} finally { $env:PATH = $oldPath }
Check ((Native git @('-C', $project, 'rev-parse', 'HEAD')) -eq $head) 'missing XMake preserves initialized history'

if ($Build) {
    $modsPath = $env:XSE_TES5_MODS_PATH
    $gamePath = $env:XSE_TES5_GAME_PATH
    Push-Location $project
    try {
        $env:XSE_TES5_MODS_PATH = $null
        $env:XSE_TES5_GAME_PATH = $null
        Setup $project @()
        Native xmake @('-y')
        Check (Test-Path -LiteralPath 'build/windows/x64/releasedbg/SmokePlugin.dll') 'minimal SKSE DLL built'
        $versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $project 'build/windows/x64/releasedbg/SmokePlugin.dll'))
        Check ($versionInfo.FileDescription -ceq $description -and $versionInfo.ProductName -ceq 'SmokePlugin') 'compiled DLL contains exact Unicode description and project name'
        Check (-not (Native git @('status', '--porcelain'))) 'build leaves generated repository clean'
    } finally {
        $env:XSE_TES5_MODS_PATH = $modsPath
        $env:XSE_TES5_GAME_PATH = $gamePath
        Pop-Location
    }
}
Write-Host "Smoke tests passed. Inspect disposable clones at: $testRoot"
