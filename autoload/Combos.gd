extends Node
## Data authority for combination towers (DESIGN_DOC section 8). Pure data plus
## lookups, mirroring ElementTypes; no GameManager dependency. Adding a combo is
## a DATA entry, never a logic change. Registered in project.godot [autoload]
## after ElementTypes (DATA references ElementTypes.Element at load time).

enum Combo { FIRE_BREATH }

const DATA := {
	Combo.FIRE_BREATH: {
		"name": "Fire Breath",
		"parents": [ElementTypes.Element.FIRE, ElementTypes.Element.AIR],
		# Element used for the damage multiplier AND the projectile colour.
		"damage_element": ElementTypes.Element.FIRE,
		"color": Color(0.98, 0.55, 0.15),  # distinct orange-gold
		"damage": 18.0,
		"fire_rate": 1.3,
		"range": 200.0,
		"aoe_radius": 85.0,
		"cost": 130,            # feeds upgrade_cost (x3) and sell_value (75%)
		"transform_cost": 100,  # gold to transform, on top of the basic build
	},
}


## The combo formed by an unordered pair of distinct elements, or -1 if none.
func combo_for(a: int, b: int) -> int:
	for id in DATA:
		var parents: Array = DATA[id]["parents"]
		if a != b and a in parents and b in parents:
			return id
	return -1


## Every combo whose parents include `element` (for partner-ownership checks).
func combos_including(element: int) -> Array[int]:
	var out: Array[int] = []
	for id in DATA:
		if element in DATA[id]["parents"]:
			out.append(id)
	return out


func name_of(combo_id: int) -> String:
	return DATA[combo_id]["name"]


func color_of(combo_id: int) -> Color:
	return DATA[combo_id]["color"]
