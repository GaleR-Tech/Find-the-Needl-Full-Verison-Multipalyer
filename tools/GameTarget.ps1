function Assert-FtnPlainPath([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.LinkType -eq 'HardLink')) {
        throw 'UNSAFE_PATH: Linked mod or configuration paths cannot be changed.'
    }
}

function Resolve-FtnGameDirectory {
    param([string]$GameDir, [switch]$RequireSupportedBuild)

    $root = Get-Item -LiteralPath $GameDir -ErrorAction SilentlyContinue
    if (-not $root -or -not $root.PSIsContainer -or $root.Parent.Name -ne 'common' -or $root.Parent.Parent.Name -ne 'steamapps' -or
        -not (Test-Path -LiteralPath (Join-Path $root.FullName 'FindTheNeedle.exe') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $root.FullName 'FindTheNeedle.pck') -PathType Leaf)) {
        throw 'GAME_FOLDER_INVALID: Choose the Find The Needle full game in a Steam library.'
    }

    $manifest = Get-Item -LiteralPath (Join-Path $root.Parent.Parent.FullName 'appmanifest_5160800.acf') -ErrorAction SilentlyContinue
    if (-not $manifest -or $manifest.PSIsContainer -or $manifest.Length -gt 1048576) {
        throw 'GAME_FOLDER_INVALID: Steam app 5160800 was not found in this library.'
    }
    $content = [IO.File]::ReadAllText($manifest.FullName)
    $app = [regex]::Match($content, '(?m)^[ \t]*"appid"[ \t]+"([^"]+)"[ \t]*\r?$').Groups[1].Value
    $directory = [regex]::Match($content, '(?m)^[ \t]*"installdir"[ \t]+"([^"]+)"[ \t]*\r?$').Groups[1].Value
    if ($app -ne '5160800' -or $directory -ne $root.Name) {
        throw 'GAME_FOLDER_INVALID: The selected folder does not match Steam app 5160800.'
    }
    $build = [regex]::Match($content, '(?m)^[ \t]*"buildid"[ \t]+"([0-9]+)"[ \t]*\r?$').Groups[1].Value
    if ($RequireSupportedBuild -and $build -ne '26547680') {
        throw 'GAME_BUILD_UNSUPPORTED: This installer supports Steam build 26547680.'
    }
    Assert-FtnPlainPath $root.FullName
    foreach ($name in 'mods','mods/ftn_coop','mods/ftn_coop/install-state.json','override.cfg') {
        Assert-FtnPlainPath (Join-Path $root.FullName $name)
    }
    return $root.FullName
}
