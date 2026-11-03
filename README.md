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

## Milestone 3: towns and guilds

- The first time you play a character, you choose one of six crafting guilds: Blacksmith, Woodworker, Tailor, Leatherworker, Apothecary or Engineer. It is permanent. Names over players' heads are in their guild's color.
- **Town stockpile** (the chest in town): donate raw materials. Each item is 1 point of contribution. Gear can't be donated.
- **Guild halls** (the six banners along the south of town): see a guild's members, contributions, leader and assistant. The top contributor leads the guild and can appoint one assistant there.
- **Round table**: a guild leader proposes an upgrade the stockpile can pay for. Every leader and assistant has a vote; other members advise with their own vote. It passes when more than half of the seats say yes, or when the 5 minute vote ends with more yes than no. The cost comes out of the stockpile and the building appears in town.
- **Guild recipes**: each guild crafts only its own recipes (other guilds' recipes show greyed out). Anyone can gather anything. Many recipes need another guild's materials, for example a woodworker's bow needs a tailor's string.
- **New materials**: shear sheep in the pasture north of town for wool, hunt deer in the meadow south of town for hide, and pick herbs at the forest edges.
- **New stations**: loom (tailors), tanning rack (leatherworkers) and brewing stand (apothecaries). Blacksmiths now forge swords at the furnace; engineers use the workbench.
- Upgrades so far: Palisade, Watchtower and Supply Silo. They don't do anything yet; invasions in milestone 4 will use them.

## Changing the game without code

- **Items:** `2dmmo/data/items.json` (name, icon, stack size, stats)
- **Recipes:** `2dmmo/data/recipes.json` (station, inputs, output, high quality chance)
- **Guilds:** `2dmmo/data/guilds.json` (name, color, description)
- **Town upgrades:** `2dmmo/data/upgrades.json` (cost, art, where it is drawn on the map)
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
