extends Node
## The player's bag of dropped potions and items for the current run
## (DESIGN_DOC section 6). Run state, like the gold and lives in GameManager,
## but kept in its own autoload so the loot rules stay isolated from the
## economy. Registered in project.godot [autoload] after Loot.
##
## Loot stacks: the bag is a count per Loot.Id, not a list of instances, because
## nothing distinguishes two copies of the same item. Applying a potion or
## equipping an item takes one out of the bag; unequipping puts it back.

signal inventory_changed

## Loot.Id -> count, entries with a count of 0 are removed so `ids()` and
## `is_empty()` never report phantom stacks.
var _stacks: Dictionary = {}

## Total pieces of loot found this run, including ones already used. Shown on
## the bag button's tooltip and useful for tuning drop rates from playtesting.
var total_found: int = 0


## Wipe the bag for a new run. Called from GameManager.new_game() so a restart
## can't carry loot over.
func reset() -> void:
	_stacks.clear()
	total_found = 0
	inventory_changed.emit()


## Put one piece of loot in the bag.
func add(id: int) -> void:
	_stacks[id] = _stacks.get(id, 0) + 1
	total_found += 1
	inventory_changed.emit()


## Take one piece of loot out. False (and no change) if the bag has none, so a
## double-click can't conjure a second copy.
func remove(id: int) -> bool:
	var held: int = _stacks.get(id, 0)
	if held <= 0:
		return false
	if held == 1:
		_stacks.erase(id)
	else:
		_stacks[id] = held - 1
	inventory_changed.emit()
	return true


func count(id: int) -> int:
	return _stacks.get(id, 0)


func has(id: int) -> bool:
	return count(id) > 0


func is_empty() -> bool:
	return _stacks.is_empty()


## Every held loot id, in Loot.DATA order so the bag doesn't reshuffle itself
## as stacks come and go.
func ids() -> Array[int]:
	var out: Array[int] = []
	for id in Loot.DATA:
		if _stacks.has(id):
			out.append(id)
	return out


## Held ids of one Loot.Kind - what the bag shows when it opens filtered to
## potions or to items.
func ids_of_kind(kind: int) -> Array[int]:
	var out: Array[int] = []
	for id in ids():
		if Loot.kind_of(id) == kind:
			out.append(id)
	return out


## Number of pieces held, summed across stacks - the count on the bag button.
func total_held() -> int:
	var total := 0
	for id in _stacks:
		total += _stacks[id]
	return total
