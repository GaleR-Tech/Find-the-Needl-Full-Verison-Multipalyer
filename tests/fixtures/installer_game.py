"""Create a disposable Steam library containing fake game files."""
from pathlib import Path


def make_game(library, directory="Find The Needle", appid="5160800", build="26547680"):
    steam_apps = Path(library) / "steamapps"
    game = steam_apps / "common" / directory
    game.mkdir(parents=True)
    (game / "FindTheNeedle.exe").write_bytes(b"original executable")
    (game / "FindTheNeedle.pck").write_bytes(b"original game data")
    (steam_apps / f"appmanifest_{appid}.acf").write_text(
        f'"AppState"\n{{\n "appid" "{appid}"\n "installdir" "{directory}"\n "buildid" "{build}"\n}}\n',
        encoding="utf-8",
    )
    return game
