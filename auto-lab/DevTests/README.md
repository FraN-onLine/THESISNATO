# DevTests - everything that only exists to verify the game

This folder is **not part of the game**. No scene, autoload or lesson loads
anything in here; it can be deleted from a build without changing a single
learner-facing behaviour. The VR content lives in `Testing/`, `World/`,
`Game/`, `Player/` and the shared assets in `Audio/` + `Images/`.

Keeping the harness here means:

* the playable folders stay free of `_selftest_*` / validation scripts,
* every check is run with one predictable command,
* nothing in the shipped scene tree can accidentally depend on a test helper.

## Run the checks (headless, no headset needed)

```powershell
$godot = "C:\Autolab\_godot\Godot_v4.7-stable_win64_console.exe"
$game  = "C:\Autolab\auto-lab"

# 1. project integrity: every script compiles, every res:// reference exists
& $godot --path $game --headless --script res://DevTests/validate_scripts.gd

# 2. automata workshop board: layout, tap targets, add/connect/simulate
& $godot --path $game --headless --script res://DevTests/selftest_builder.gd

# 3. adaptive lesson system: library, engine, director, card + maze UI
& $godot --path $game --headless --script res://DevTests/Lessons/selftest_lessons.gd
```

All three print `REPORT` / `FAILED` lines and exit with code `1` when anything
failed, `0` when the layer is clean.

## What each file covers

| File                          | Layer                                                        |
|-------------------------------|--------------------------------------------------------------|
| `validate_scripts.gd`         | Whole project: script compilation + `res://` reference integrity. Missing *media* is reported as `OPTIONAL` because the game degrades gracefully without images/voice clips. |
| `selftest_builder.gd`         | `Testing/AutomataWorkshop.tscn` laid out at the real billboard size (1800x1100): every control on screen, every tap target >= 44 px, add-node / connect / simulate behaviour. |
| `Lessons/selftest_lessons.gd` | The adaptive lesson stack in `Testing/Lessons/`: module library completeness, engine scoring + remedy + practice cap + mastery gate, director phase sequencing, checkpoint card and maze panel layout/tap targets, and the voice hook. |

## Adding a new check

1. Drop a `selftest_*.gd` here that `extends SceneTree` (or add a `_check_*`
   function to an existing one).
2. Print one `REPORT  PASS/FAIL  <label>  <detail>` line per assertion - the
   existing files use the small `_note()` helper.
3. List it in the command block above so it runs with the rest.
