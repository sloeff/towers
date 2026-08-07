extends Node
## Autoload singleton. Encodes the elemental damage rules from the design doc:
## - Same element as target: 75% damage
## - Opposite element (fire<->water, earth<->air): 125% damage
## - Any other combination: 100% damage
## Also holds the per-element presentation and basic-tower stats (BALANCE.md).
## Registered in project.godot under [autoload] as "ElementTypes".

enum Element { FIRE, WATER, EARTH, AIR }

const ALL := [Element.FIRE, Element.WATER, Element.EARTH, Element.AIR]

const OPPOSITES := {
	Element.FIRE: Element.WATER,
	Element.WATER: Element.FIRE,
	Element.EARTH: Element.AIR,
	Element.AIR: Element.EARTH,
}

const DATA := {
	Element.FIRE: {
		"name": "Fire",
		"color": Color(0.91, 0.31, 0.16),
		"cost": 50,
		"damage": 8.0,
		"fire_rate": 1.2,
		"range": 170.0,
	},
	Element.WATER: {
		"name": "Water",
		"color": Color(0.24, 0.55, 0.9),
		"cost": 50,
		"damage": 6.0,
		"fire_rate": 1.0,
		"range": 190.0,
	},
	Element.EARTH: {
		"name": "Earth",
		"color": Color(0.45, 0.34, 0.19),
		"cost": 60,
		"damage": 12.0,
		"fire_rate": 0.7,
		"range": 150.0,
	},
	Element.AIR: {
		"name": "Air",
		"color": Color(0.62, 0.78, 0.85),
		"cost": 55,
		"damage": 7.0,
		"fire_rate": 1.5,
		"range": 200.0,
	},
}


## Returns the damage multiplier when a tower of `attacker_element` hits
## an enemy of `defender_element`.
func get_multiplier(attacker_element: Element, defender_element: Element) -> float:
	if attacker_element == defender_element:
		return 0.75
	if OPPOSITES[attacker_element] == defender_element:
		return 1.25
	return 1.0


func element_name(element: Element) -> String:
	return DATA[element]["name"]


func color_of(element: Element) -> Color:
	return DATA[element]["color"]
