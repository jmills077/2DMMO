# 2DMMO

A top-down 2D pixel art online game about crafting, built in Godot 4.7 with GDScript.

Each server is a town of crafters preparing for waves of invasion. Players gather, craft, trade, and vote together through their crafting guilds on how to spend the town's resources.

## Playing the current build

1. Pull the latest changes in GitHub Desktop.
2. Open `2dmmo/project.godot` in Godot 4.7 and press **Play** (F5).

| Key | Action |
| --- | --- |
| WASD or arrows | Move |
| E or Space | Interact: hold to mine or fell, press to use a station or plant a sapling |
| I or Tab | Open or close your bag |
| F5 | Save (the game also saves every minute and when you quit) |
| Esc | Close menus |

## Milestone 1: crafting prototype

- Mine iron and coal rocks in the hills east of the river. Rocks respawn after 45 seconds.
- Fell trees in the forest to the west for logs and saplings. A stump stays bare until you plant a sapling on it, and the sapling grows back in 90 seconds.
- In town, smelt iron ingots at the furnace, then saw planks, carve handles, and craft an iron sword and a wooden shield at the workbench.
- Gear has a 20% chance to come out high quality, with one stat raised by 10%. Hover over an item in your bag to see its stats.

## Changing the game without code

- **Items:** `2dmmo/data/items.json` (name, icon, stack size, stats)
- **Recipes:** `2dmmo/data/recipes.json` (station, inputs, output, high quality chance)
- **Art:** replace any PNG in `2dmmo/art/` with your own 16 x 16 art of the same name and size.
- **Map:** open `scenes/main.tscn` and paint on the Ground layer, or drag rocks and trees around.

## For developers

| Task | Command (run inside `2dmmo/`) |
| --- | --- |
| Run the automated checks | `godot --headless --path . res://tests/smoke_test.tscn` |
| Rebuild scenes from scratch (overwrites map edits) | `godot --headless --path . res://tools/build_scenes.tscn` |
| Regenerate placeholder art (run from the repo root) | `python3 tools/make_placeholder_art.py` |
