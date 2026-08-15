extends Node
## Data authority for combination towers (DESIGN_DOC section 8). Pure data plus
## lookups, mirroring ElementTypes; no GameManager dependency. Adding a combo is
## a DATA entry, never a logic change. Registered in project.godot [autoload]
## after ElementTypes (DATA references ElementTypes.Element at load time).

enum Combo { FIRE_BREATH, LAVA, STEAM, METEOR, QUICKSAND, HAIL }

## Each entry is a full data spec for one combo. Beyond the shared stats
## (name, parents, damage_element, color, damage, fire_rate, range, aoe_radius,
## cost, transform_cost) an entry may carry OPTIONAL keys that drive its unique
## ability (DESIGN_DOC section 8). All are absent for a plain AoE/single-target
## combo, so Fire Breath and Steam need none:
##   firing_mode: "projectile" (default) | "aura"  - aura has no projectile and
##     applies its effect to every enemy in range each frame (Quicksand)
##   slow_factor / slow_duration   - on-hit slow, factor<1 (Hail)
##   dot_dps / dot_duration        - burn, damage-over-time (Lava)
##   stun_duration / stun_primary_only - on-hit stun (Meteor)
##   aura_dps                      - per-second tick damage of an aura (Quicksand)
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
	# Fire + Earth. Burn: a modest direct hit plus a Fire-typed damage-over-time
	# that ticks for 3s; re-hitting refreshes the burn (apply_dot, keyed by source).
	Combo.LAVA: {
		"name": "Lava",
		"parents": [ElementTypes.Element.FIRE, ElementTypes.Element.EARTH],
		"damage_element": ElementTypes.Element.FIRE,
		"color": Color(0.78, 0.20, 0.07),  # deep molten red
		"damage": 14.0,
		"fire_rate": 1.0,
		"range": 160.0,
		"aoe_radius": 0.0,
		"cost": 140,
		"transform_cost": 110,
		"dot_dps": 8.0,
		"dot_duration": 3.0,
	},
	# Fire + Water. Wide pure-AoE, Water-typed - larger and weaker splash than
	# Fire Breath, no rider effect. Distinct through radius and matchup.
	Combo.STEAM: {
		"name": "Steam",
		"parents": [ElementTypes.Element.FIRE, ElementTypes.Element.WATER],
		"damage_element": ElementTypes.Element.WATER,
		"color": Color(0.80, 0.86, 0.88),  # pale steam white
		"damage": 12.0,
		"fire_rate": 1.1,
		"range": 190.0,
		"aoe_radius": 110.0,
		"cost": 140,
		"transform_cost": 110,
	},
	# Earth + Air. Slow, heavy single hit with a small splash; stuns the primary
	# target for 1s (stun_primary_only, so the splashed enemies aren't frozen).
	Combo.METEOR: {
		"name": "Meteor",
		"parents": [ElementTypes.Element.EARTH, ElementTypes.Element.AIR],
		"damage_element": ElementTypes.Element.EARTH,
		"color": Color(0.52, 0.40, 0.28),  # scorched rock brown
		"damage": 55.0,
		"fire_rate": 0.35,
		"range": 220.0,
		"aoe_radius": 60.0,
		"cost": 160,
		"transform_cost": 120,
		"stun_duration": 1.0,
		"stun_primary_only": true,
	},
	# Earth + Water. Aura: no projectile. Every enemy in range is continuously
	# slowed (x0.6) and takes a small tick of Earth damage each frame.
	Combo.QUICKSAND: {
		"name": "Quicksand",
		"parents": [ElementTypes.Element.EARTH, ElementTypes.Element.WATER],
		"damage_element": ElementTypes.Element.EARTH,
		"color": Color(0.82, 0.72, 0.42),  # sandy tan
		"damage": 0.0,          # aura deals aura_dps, not per-shot damage
		"fire_rate": 1.0,       # unused in aura mode; kept for the stat panel
		"range": 150.0,
		"aoe_radius": 0.0,
		"cost": 150,
		"transform_cost": 110,
		"firing_mode": "aura",
		"aura_dps": 6.0,
		"slow_factor": 0.6,
	},
	# Air + Water. Small splash + a light slow (x0.75 for 1.5s) on everything hit.
	Combo.HAIL: {
		"name": "Hail",
		"parents": [ElementTypes.Element.AIR, ElementTypes.Element.WATER],
		"damage_element": ElementTypes.Element.WATER,
		"color": Color(0.50, 0.75, 0.98),  # icy blue
		"damage": 10.0,
		"fire_rate": 1.4,
		"range": 200.0,
		"aoe_radius": 55.0,
		"cost": 135,
		"transform_cost": 100,
		"slow_factor": 0.75,
		"slow_duration": 1.5,
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
