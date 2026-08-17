extends Node
## Data authority for potions and items (DESIGN_DOC section 6), plus the drop
## roll that decides what a dying enemy leaves behind. Pure data and lookups,
## mirroring Combos/ElementTypes; no GameManager or Inventory dependency.
## Adding a potion or item is a DATA entry, never a logic change. Registered in
## project.godot [autoload].
##
## Effects are never one-off flags. Every entry carries a `mods` dictionary of
## generic stat keys (the MOD_* constants below), which Tower sums across its
## applied potions and equipped items and folds into _recompute_stats(). A new
## effect that fits an existing key costs one DATA entry; a genuinely new axis
## costs one key and one line in Tower.

enum Kind { POTION, ITEM }
enum Rarity { COMMON, RARE, EPIC }

## Stat keys usable in an entry's `mods`. The _MULT keys are additive fractions
## of the tower's BASE stat (0.10 = +10%), summed across every source and
## applied once, so two +10% damage sources give +20%, not +21%.
const MOD_DAMAGE := "damage_mult"
const MOD_FIRE_RATE := "fire_rate_mult"
const MOD_RANGE := "range_mult"
const MOD_AOE := "aoe_mult"
## Flat extra gold when this tower lands a killing blow (DESIGN_DOC, "Potions").
const MOD_GOLD_FIND := "gold_find"
## Additive fraction added to this tower's drop chance when it lands the kill.
const MOD_MAGIC_FIND := "magic_find"

enum Id {
	GOLD_FIND,
	SHARPENING_OIL,
	SWIFTNESS,
	FARSIGHT,
	RUBY_CORE,
	WINDSTONE,
	EAGLE_LENS,
	GREED_IDOL,
	BLAST_CAP,
}

## `badge` is the short label drawn on the tower detail panel's badges and slots,
## so it has to stay 2-4 characters. `rarity` drives both the drop weight and the
## colour; magnitudes are fixed per entry rather than scaled by rarity.
const DATA := {
	Id.GOLD_FIND: {
		"name": "Gold Find",
		"kind": Kind.POTION,
		"rarity": Rarity.COMMON,
		"badge": "GF",
		"mods": {MOD_GOLD_FIND: 2},
	},
	Id.SHARPENING_OIL: {
		"name": "Sharpening Oil",
		"kind": Kind.POTION,
		"rarity": Rarity.COMMON,
		"badge": "DMG",
		"mods": {MOD_DAMAGE: 0.10},
	},
	Id.SWIFTNESS: {
		"name": "Swiftness",
		"kind": Kind.POTION,
		"rarity": Rarity.COMMON,
		"badge": "SPD",
		"mods": {MOD_FIRE_RATE: 0.10},
	},
	Id.FARSIGHT: {
		"name": "Farsight",
		"kind": Kind.POTION,
		"rarity": Rarity.RARE,
		"badge": "RNG",
		"mods": {MOD_RANGE: 0.08},
	},
	Id.RUBY_CORE: {
		"name": "Ruby Core",
		"kind": Kind.ITEM,
		"rarity": Rarity.RARE,
		"badge": "RUB",
		"mods": {MOD_DAMAGE: 0.20},
	},
	Id.WINDSTONE: {
		"name": "Windstone",
		"kind": Kind.ITEM,
		"rarity": Rarity.RARE,
		"badge": "WND",
		"mods": {MOD_FIRE_RATE: 0.20},
	},
	# Dead weight on a single-target tower, strong on a combo with splash - the
	# one item whose value depends on where you put it.
	Id.BLAST_CAP: {
		"name": "Blast Cap",
		"kind": Kind.ITEM,
		"rarity": Rarity.RARE,
		"badge": "AOE",
		"mods": {MOD_AOE: 0.25},
	},
	Id.EAGLE_LENS: {
		"name": "Eagle Lens",
		"kind": Kind.ITEM,
		"rarity": Rarity.EPIC,
		"badge": "EYE",
		"mods": {MOD_RANGE: 0.15},
	},
	Id.GREED_IDOL: {
		"name": "Greed Idol",
		"kind": Kind.ITEM,
		"rarity": Rarity.EPIC,
		"badge": "GRD",
		"mods": {MOD_GOLD_FIND: 5, MOD_MAGIC_FIND: 0.25},
	},
}

const RARITY_COLOR := {
	Rarity.COMMON: Color(0.72, 0.75, 0.80),
	Rarity.RARE: Color(0.35, 0.62, 0.95),
	Rarity.EPIC: Color(0.78, 0.45, 0.92),
}

const RARITY_NAME := {
	Rarity.COMMON: "Common",
	Rarity.RARE: "Rare",
	Rarity.EPIC: "Epic",
}

## Relative odds of each rarity band once a drop is rolled. Within a band every
## entry is equally likely, so adding an entry dilutes its own band only.
const RARITY_WEIGHT := {
	Rarity.COMMON: 60,
	Rarity.RARE: 30,
	Rarity.EPIC: 10,
}

## Chance that a kill drops anything at all, before the killing tower's magic
## find. Tougher ranks are the reliable source: a boss always drops.
const DROP_CHANCE_BASIC := 0.04
const DROP_CHANCE_ALL_RESIST := 0.08
const DROP_CHANCE_CAPTAIN := 0.25
const DROP_CHANCE_BOSS := 1.0

## Human-readable effect line, built from the generic mods so a new entry needs
## no extra text. Used by the inventory cards and the detail panel tooltips.
func describe(id: int) -> String:
	var parts: PackedStringArray = []
	var mods: Dictionary = DATA[id]["mods"]
	for key in mods:
		var value: float = mods[key]
		match key:
			MOD_DAMAGE: parts.append("+%d%% damage" % roundi(value * 100.0))
			MOD_FIRE_RATE: parts.append("+%d%% fire rate" % roundi(value * 100.0))
			MOD_RANGE: parts.append("+%d%% range" % roundi(value * 100.0))
			MOD_AOE: parts.append("+%d%% splash" % roundi(value * 100.0))
			MOD_GOLD_FIND: parts.append("+%dg per kill" % roundi(value))
			MOD_MAGIC_FIND: parts.append("+%d%% magic find" % roundi(value * 100.0))
	return ", ".join(parts)


func name_of(id: int) -> String:
	return DATA[id]["name"]


func badge_of(id: int) -> String:
	return DATA[id]["badge"]


func kind_of(id: int) -> int:
	return DATA[id]["kind"]


func mods_of(id: int) -> Dictionary:
	return DATA[id]["mods"]


func is_potion(id: int) -> bool:
	return DATA[id]["kind"] == Kind.POTION


func color_of(id: int) -> Color:
	return RARITY_COLOR[DATA[id]["rarity"]]


func rarity_name(id: int) -> String:
	return RARITY_NAME[DATA[id]["rarity"]]


func ids_of_kind(kind: int) -> Array[int]:
	var out: Array[int] = []
	for id in DATA:
		if DATA[id]["kind"] == kind:
			out.append(id)
	return out


## Base drop chance for a kill of this rank, before magic find. `rank` is an
## Enemy.Rank; all-resist units count as basic rank but drop a little better.
func drop_chance(rank: int, all_resist: bool = false) -> float:
	if rank == Enemy.Rank.BOSS:
		return DROP_CHANCE_BOSS
	if rank == Enemy.Rank.CAPTAIN:
		return DROP_CHANCE_CAPTAIN
	return DROP_CHANCE_ALL_RESIST if all_resist else DROP_CHANCE_BASIC


## Roll one kill's loot: an Id, or -1 for nothing. `magic_find` is the killing
## tower's additive bonus to the drop chance (0.25 = a quarter better odds); the
## rarity band is unaffected by it. Randomness comes from the global RNG, so a
## test can seed it for a deterministic result.
func roll_drop(rank: int, all_resist: bool = false, magic_find: float = 0.0) -> int:
	if randf() >= drop_chance(rank, all_resist) * (1.0 + magic_find):
		return -1
	return _roll_id()


## Pick a rarity band by weight, then an entry uniformly inside it.
func _roll_id() -> int:
	var total := 0
	for rarity in RARITY_WEIGHT:
		total += RARITY_WEIGHT[rarity]
	var pick := randi() % total
	for rarity in RARITY_WEIGHT:
		pick -= RARITY_WEIGHT[rarity]
		if pick < 0:
			return _random_of_rarity(rarity)
	return Id.GOLD_FIND  # unreachable; keeps the return type honest


func _random_of_rarity(rarity: int) -> int:
	var candidates: Array[int] = []
	for id in DATA:
		if DATA[id]["rarity"] == rarity:
			candidates.append(id)
	if candidates.is_empty():
		return Id.GOLD_FIND
	return candidates[randi() % candidates.size()]
