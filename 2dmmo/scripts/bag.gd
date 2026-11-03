extends RefCounted
## A bag of items. The server keeps one per player; each player's screen
## shows a copy of their own (see autoload/inventory.gd).
## Each slot is a Dictionary:  {"id": "iron_ore", "count": 12, "data": {}}
## "data" holds per-item details such as crafted quality and stats.
## Items with data never stack.

const MAX_SLOTS := 24

var slots: Array = []


func count_of(id: String) -> int:
	var total := 0
	for slot: Dictionary in slots:
		if slot.id == id:
			total += int(slot.count)
	return total


func has_space_for(id: String, count: int, data: Dictionary = {}) -> bool:
	var room := (MAX_SLOTS - slots.size()) * (GameData.stack_size(id) if data.is_empty() else 1)
	if data.is_empty():
		for slot: Dictionary in slots:
			if slot.id == id and slot.data.is_empty():
				room += GameData.stack_size(id) - int(slot.count)
	return room >= count


## Adds items and returns how many did not fit.
func add_item(id: String, count: int = 1, data: Dictionary = {}) -> int:
	var left := count
	var stack_max := GameData.stack_size(id)
	if data.is_empty():
		for slot: Dictionary in slots:
			if left == 0:
				break
			if slot.id == id and slot.data.is_empty() and int(slot.count) < stack_max:
				var added := mini(stack_max - int(slot.count), left)
				slot.count = int(slot.count) + added
				left -= added
	while left > 0 and slots.size() < MAX_SLOTS:
		var added := mini(stack_max, left) if data.is_empty() else 1
		slots.append({"id": id, "count": added, "data": data.duplicate(true)})
		left -= added
	return left


## Removes items, taking from the last slots first. Returns false if there were not enough.
func remove_item(id: String, count: int) -> bool:
	if count_of(id) < count:
		return false
	var left := count
	for i in range(slots.size() - 1, -1, -1):
		var slot: Dictionary = slots[i]
		if slot.id != id:
			continue
		var taken := mini(int(slot.count), left)
		slot.count = int(slot.count) - taken
		left -= taken
		if slot.count <= 0:
			slots.remove_at(i)
		if left == 0:
			break
	return true


func to_save_data() -> Array:
	return slots.duplicate(true)


func load_save_data(saved: Array) -> void:
	slots.clear()
	for entry: Variant in saved:
		if entry is Dictionary and GameData.items.has(str(entry.get("id", ""))):
			slots.append({
				"id": str(entry.id),
				"count": int(entry.get("count", 1)),
				"data": entry.get("data", {}),
			})
