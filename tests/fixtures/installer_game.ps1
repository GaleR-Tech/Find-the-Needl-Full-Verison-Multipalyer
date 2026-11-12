function New-FtnTestGame {
    param(
        [string]$Library,
        [string]$Directory = 'Find The Needle',
        [string]$AppId = '5160800',
        [string]$Build = '26547680'
    )
    $steamApps = Join-Path $Library 'steamapps'
    $game = Join-Path $steamApps ('common/' + $Directory)
    $null = New-Item -ItemType Directory -Path $game -Force
    [IO.File]::WriteAllBytes((Join-Path $game 'FindTheNeedle.exe'), [byte[]](1,2,3))
    [IO.File]::WriteAllBytes((Join-Path $game 'FindTheNeedle.pck'), [byte[]](4,5,6))
    $manifest = @"
"AppState"
{
    "appid" "$AppId"
    "installdir" "$Directory"
    "buildid" "$Build"
}
"@
    [IO.File]::WriteAllText((Join-Path $steamApps ("appmanifest_$AppId.acf")), $manifest, [Text.UTF8Encoding]::new($false))
    return $game
}
