extends Node
## Turns recipe inputs into outputs, including the "high quality" roll.
## A high quality item gets one random stat (not durability) raised by 10%, at least +1.
## Only the server calls craft(); screens call can_craft() to grey out buttons.

const HIGH_QUALITY_BONUS := 0.10


func find_recipe(recipe_id: String) -> Dictionary:
	for recipe: Dictionary in GameData.recipes:
		if recipe.get("id") == recipe_id:
			return recipe
	return {}


func can_craft(bag: RefCounted, recipe: Dictionary) -> bool:
	var inputs: Dictionary = recipe.get("inputs", {})
	for id: String in inputs:
		if bag.count_of(id) < int(inputs[id]):
			return false
	return true


## Returns {"ok": bool, "item": String, "count": int, "high_quality": bool, "reason": String}.
func craft(bag: RefCounted, recipe: Dictionary) -> Dictionary:
	var output: Dictionary = recipe.get("output", {})
	var out_id := str(output.get("item", ""))
	var out_count := int(output.get("count", 1))
	if not can_craft(bag, recipe):
		return {"ok": false, "reason": "Missing materials"}

	var data := {}
	var high_quality := false
	var base_stats: Dictionary = GameData.get_item(out_id).get("stats", {})
	if not base_stats.is_empty():
		var stats := {}
		for key: String in base_stats:
			stats[key] = int(base_stats[key])
		data = {"quality": "normal", "stats": stats}
		if randf() < float(recipe.get("high_quality_chance", 0.0)):
			high_quality = true
			data.quality = "high"
			var boostable: Array = stats.keys().filter(func(k: String) -> bool: return k != "durability")
			if not boostable.is_empty():
				var stat: String = boostable.pick_random()
				stats[stat] = maxi(int(ceil(stats[stat] * (1.0 + HIGH_QUALITY_BONUS))), stats[stat] + 1)
				data.boosted_stat = stat

	if not bag.has_space_for(out_id, out_count, data):
		return {"ok": false, "reason": "Bag full"}

	var inputs: Dictionary = recipe.get("inputs", {})
	for id: String in inputs:
		bag.remove_item(id, int(inputs[id]))
	bag.add_item(out_id, out_count, data)
	return {"ok": true, "item": out_id, "count": out_count, "high_quality": high_quality, "reason": ""}
