$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'fixtures/installer_game.ps1')
$install = Join-Path $projectRoot 'tools\Install.ps1'
$uninstall = Join-Path $projectRoot 'tools\Uninstall.ps1'
if (-not (Test-Path -LiteralPath $install) -or -not (Test-Path -LiteralPath $uninstall)) {
    throw 'Reversible installation is not implemented yet.'
}
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ftn-coop-install-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
function New-TestGame([string]$Name) {
    return New-FtnTestGame (Join-Path $testRoot $Name)
}
function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
$demo = New-FtnTestGame (Join-Path $testRoot 'mixed-library') 'Find The Needle Demo' '5165210' '26260645'
$null = New-FtnTestGame (Join-Path $testRoot 'mixed-library')
$demoConfig = Join-Path $demo 'override.cfg'
[IO.File]::WriteAllText($demoConfig, '[rendering]')
foreach ($script in $install, $uninstall) {
    $refused = $false
    try { & $script -GameDir $demo | Out-Null }
    catch { $refused = $_.Exception.Message.Contains('GAME_FOLDER_INVALID') }
    Require $refused 'The full-game installer must refuse the demo before touching it.'
}
Require (([IO.File]::ReadAllText($demoConfig) -eq '[rendering]') -and -not (Test-Path (Join-Path $demo 'mods'))) 'The full-game installer modified the demo.'
$unsupported = New-FtnTestGame (Join-Path $testRoot 'new-game-build') -Build '99999999'
$refused = $false
try { & $install -GameDir $unsupported | Out-Null }
catch { $refused = $_.Exception.Message.Contains('GAME_BUILD_UNSUPPORTED') }
Require $refused 'The installer must refuse unknown full-game builds.'
Require (-not (Test-Path -LiteralPath (Join-Path $unsupported 'mods'))) 'An unsupported install left mod files.'
$linked = New-TestGame 'linked-mod-directory'
$foreignMods = Join-Path $demo 'mods'
$null = New-Item -ItemType Directory -Path $foreignMods
$null = New-Item -ItemType Junction -Path (Join-Path $linked 'mods') -Target $foreignMods
$refused = $false
try { & $install -GameDir $linked | Out-Null }
catch { $refused = $_.Exception.Message.Contains('UNSAFE_PATH') }
Require $refused 'The installer must refuse a junction to another game folder.'
Require (-not (Test-Path -LiteralPath (Join-Path $foreignMods 'ftn_coop'))) 'Installer followed a junction into the demo.'
$hardlinked = New-TestGame 'linked-renderer-settings'
$null = New-Item -ItemType HardLink -Path (Join-Path $hardlinked 'override.cfg') -Target $demoConfig
$refused = $false
try { & $install -GameDir $hardlinked | Out-Null }
catch { $refused = $_.Exception.Message.Contains('UNSAFE_PATH') }
Require $refused 'The installer must refuse a hard-linked override configuration.'
Require ([IO.File]::ReadAllText($demoConfig) -eq '[rendering]') 'Installer modified the demo config through a hard link.'
$game = New-TestGame 'existing-config'
$config = Join-Path $game 'override.cfg'
$original = "[rendering]`r`nrendering_device/driver.windows=`"d3d12`"`r`n[autoload]`r`nOtherMod=`"*mods/other.gd`"`r`n"
[System.IO.File]::WriteAllText($config, $original, [System.Text.UTF8Encoding]::new($true))
$originalBytes = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($config))
& $install -GameDir $game | Out-Null
Require ((Get-Content -LiteralPath (Join-Path $game 'mods/ftn_coop/install-state.json') -Raw | ConvertFrom-Json).mod_version -eq '0.2.0') 'Installed metadata must record the package mod version.'
Require ((Get-Content -LiteralPath $config -Raw).Contains('OtherMod=')) 'Other autoload was lost.'
Require ((Get-Content -LiteralPath $config -Raw).Contains('rendering_device/driver.windows="d3d12"')) 'Original renderer setting was lost.'
$oldStatePath = Join-Path $game 'mods/ftn_coop/install-state.json'
$oldState = Get-Content -LiteralPath $oldStatePath -Raw | ConvertFrom-Json
$oldState.PSObject.Properties.Remove('mod_version')
[IO.File]::WriteAllText($oldStatePath,($oldState | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
& $install -GameDir $game | Out-Null
Require ((Get-Content -LiteralPath $oldStatePath -Raw | ConvertFrom-Json).mod_version -eq '0.2.0') 'Updating an old manifest must add version metadata.'
Require (([regex]::Matches((Get-Content -LiteralPath $config -Raw), '(?m)^FtnCoop=')).Count -eq 1) 'Duplicate autoload entry.'
$steamManifest = Join-Path (Split-Path -Parent (Split-Path -Parent $game)) 'appmanifest_5160800.acf'
[IO.File]::WriteAllText($steamManifest, ([IO.File]::ReadAllText($steamManifest).Replace('26547680','99999999')))
& $uninstall -GameDir $game | Out-Null
Require ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($config)) -eq $originalBytes) 'Original config bytes were not restored.'
Require ((Get-FileHash -LiteralPath (Join-Path $game 'FindTheNeedle.exe')).Hash -eq (Get-FileHash -LiteralPath (Join-Path (New-TestGame 'comparison') 'FindTheNeedle.exe')).Hash) 'Original executable changed.'

$game = New-TestGame 'later-config-change'
$config = Join-Path $game 'override.cfg'
& $install -GameDir $game | Out-Null
Add-Content -LiteralPath $config -Value "[unrelated]`nsetting=42" -Encoding utf8
& $install -GameDir $game | Out-Null
& $uninstall -GameDir $game | Out-Null
Require ((Get-Content -LiteralPath $config -Raw).Contains('setting=42')) 'Later user settings were lost after updating the mod.'
Require (-not (Get-Content -LiteralPath $config -Raw).Contains('FtnCoop=')) 'Own autoload entry remained.'

$game = New-TestGame 'unrelated-mod'
$otherFolder = Join-Path $game 'mods\other'
New-Item -ItemType Directory -Path $otherFolder -Force | Out-Null
Set-Content -LiteralPath (Join-Path $otherFolder 'keep.txt') -Value 'keep'
& $install -GameDir $game | Out-Null
& $uninstall -GameDir $game | Out-Null
Require (Test-Path -LiteralPath (Join-Path $otherFolder 'keep.txt')) 'An unrelated mod was removed.'
Require (-not (Test-Path -LiteralPath (Join-Path $game 'override.cfg'))) 'Originally missing config was not removed.'

$game = New-TestGame 'edited-own-file'
& $install -GameDir $game | Out-Null
$edited = Join-Path $game 'mods\ftn_coop\bootstrap.gd'
Add-Content -LiteralPath $edited -Value '# edited locally'
& $uninstall -GameDir $game | Out-Null
Require (Test-Path -LiteralPath $edited) 'A locally edited mod file was deleted.'
$game = New-TestGame 'windows-powershell'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $install -GameDir $game
Require ($LASTEXITCODE -eq 0) 'Bundled Windows PowerShell could not install the package.'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uninstall -GameDir $game
Require ($LASTEXITCODE -eq 0) 'Bundled Windows PowerShell could not remove the package.'
$game = New-TestGame 'old-manifest-new-file-collision'
& $install -GameDir $game | Out-Null
$manifestPath = Join-Path $game 'mods\ftn_coop\install-state.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifest.files = @($manifest.files | Where-Object { $_.path -ne 'locale.gd' })
[IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
$collisionPath = Join-Path $game 'mods\ftn_coop\locale.gd'
[IO.File]::WriteAllText($collisionPath,'# local file predating the update',[Text.UTF8Encoding]::new($false))
$manifestHash = (Get-FileHash -LiteralPath $manifestPath).Hash
$configHash = (Get-FileHash -LiteralPath (Join-Path $game 'override.cfg')).Hash
$refused = $false
try { & $install -GameDir $game | Out-Null }
catch { $refused = $_.Exception.Message.Contains('LOCAL_MOD_CHANGED') }
Require $refused 'An update must refuse an incoming file that collides with an unowned local file.'
Require ([IO.File]::ReadAllText($collisionPath) -eq '# local file predating the update') 'Unowned local file was overwritten.'
Require ((Get-FileHash -LiteralPath $manifestPath).Hash -eq $manifestHash) 'Refused update changed the installation manifest.'
Require ((Get-FileHash -LiteralPath (Join-Path $game 'override.cfg')).Hash -eq $configHash) 'Refused update changed config.'
Write-Output 'PASS installer_full_game_scope_and_config_preservation'
exit 0
