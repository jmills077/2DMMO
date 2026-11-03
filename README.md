# 2DMMO

A top-down 2D pixel art online game about crafting, built in Godot 4.7 with GDScript.

Each server is a town of crafters preparing for waves of invasion. Players gather, craft, trade, and vote together through their crafting guilds on how to spend the town's resources.

## Playing the current build

1. Pull the latest changes in GitHub Desktop.
2. Open `2dmmo/project.godot` in Godot 4.7 and press **Play** (F5). The first window hosts the world.

### Testing multiplayer on one computer

1. In Godot, open **Debug > Customize Run Instances**.
2. Tick **Enable Multiple Instances** and set the count to 2 or 3.
3. Press **Play**. Each window is a different player: the first hosts, the others join it automatically. The top-left line says who each window is (Tester1, Tester2...).

The Output panel will show "Couldn't create an ENet host" once per joining window. That is expected: it is the window finding that someone is already hosting, then joining instead.

To play with someone on your home network, start the game with `-- --host` on your computer and `-- --join=YOUR_IP` on theirs. Playing over the internet comes in milestone 5.

| Key | Action |
| --- | --- |
| WASD or arrows | Move |
| E or Space | Interact: hold to mine or fell, press to use a station or plant a sapling |
| I or Tab | Open or close your bag |
| F5 | Save the world (the host also saves every minute, when anyone leaves, and when it closes) |
| Esc | Close menus |

## Milestone 1: crafting prototype

- Mine iron and coal rocks in the hills east of the river. Rocks respawn after 45 seconds.
- Fell trees in the forest to the west for logs and saplings. A stump stays bare until you plant a sapling on it, and the sapling grows back in 90 seconds.
- In town, smelt iron ingots at the furnace, then saw planks, carve handles, and craft an iron sword and a wooden shield at the workbench.
- Gear has a 20% chance to come out high quality, with one stat raised by 10%. Hover over an item in your bag to see its stats.

## Milestone 2: multiplayer foundation

- Several players share one world. You see each other move, with names over your heads.
- The host decides everything: who mined a rock first, whether a crafter is standing at the right station, and what is in every bag. Players' games only ask.
- Rocks and trees are shared. If one player mines a rock, it is depleted for everyone until it respawns.
- The host saves the world plus each player's position and bag by name, so joining again as the same name picks up where you left off.
- The milestone 1 single-player save is not carried over.

## Changing the game without code

- **Items:** `2dmmo/data/items.json` (name, icon, stack size, stats)
- **Recipes:** `2dmmo/data/recipes.json` (station, inputs, output, high quality chance)
- **Art:** replace any PNG in `2dmmo/art/` with your own 16 x 16 art of the same name and size.
- **Map:** open `scenes/main.tscn` and paint on the Ground layer, or drag rocks and trees around.

## For developers

| Task | Command (run inside `2dmmo/`) |
| --- | --- |
| Run the automated checks | `godot --headless --path . res://tests/smoke_test.tscn` |
| Run the three-player network test | `GODOT=godot tests/net_test.sh` |
| Run a server with no player of its own | `godot --headless --path . -- --server` |
| Rebuild scenes from scratch (overwrites map edits) | `godot --headless --path . res://tools/build_scenes.tscn` |
| Regenerate placeholder art (run from the repo root) | `python3 tools/make_placeholder_art.py` |
