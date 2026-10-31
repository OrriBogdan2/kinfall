class_name KinParts
extends RefCounted
## The kin ability grammar's vocabulary (docs/KIN_GRAMMAR.md). Core-owned: every part a kin or an
## ability may use is listed here, with each parameter's bounds, default and unit. Data files only
## pick parts by name and set numbers inside these bounds. Nothing named in a data file is ever
## loaded, instanced or called: names are looked up in these tables and nowhere else.
##
## A parameter is [type, min_or_values, max, default, unit, doc]:
##   type     "float" | "int" | "bool" | "enum"
##   min/max  inclusive bounds for numbers; for "enum" slot 1 holds the allowed values
##   default  used when the file leaves it out; null means the file must set it
## `cost` is a placeholder power cost per part. Real budgets are Phase 3.

const GRAMMAR_VERSION := 1

# ---- hard caps (the Phase 2 runtime enforces the same numbers) ----
const MAX_STAGES := 4          # top-level stages in one ability
const MAX_DEPTH := 3           # followup nesting: stage > then > then
const MAX_EFFECTS := 6         # effects in one stage
const MAX_MODIFIERS := 4       # modifiers in one stage
const MAX_HITS := 12           # split x (1 + bounce) x (1 + chain) x (1 + pierce): the most units one cast can touch per stage
const BIG_RADIUS := 8.0        # areas wider than this may only carry utility effects (reveal, buffs)

# ---- effect categories: colour means category in Phase 4, never an element ----
const CATEGORIES := {
	"damage": "hurts",
	"control": "moves or locks foes (slow, root, stun, pull, push, lift)",
	"sustain": "keeps you alive (heal, shield, cleanse, reflect)",
	"utility": "information and buffs (mark, buff, signature)",
}

# ---- deliveries: the shape an ability takes ----
const ORIGIN_DOC := "where it starts: caster (the kin), owner (its hunter), aim (the cursor or the kin's target), here (where the previous stage landed; followups only)"

const DELIVERIES := {
	"projectile": {"cost": 2, "doc": "a shot that flies toward the aim and hits the first foe in its path", "events": ["on_hit", "on_end"],
		"params": {
			"origin": ["enum", ["caster", "owner", "here"], null, "caster", "", ORIGIN_DOC],
			"speed": ["float", 8.0, 80.0, 30.0, "m/s", "flight speed"],
			"range": ["float", 2.0, 20.0, 9.0, "m", "how far it flies"],
			"size": ["float", 0.08, 0.6, 0.2, "m", "hit radius"],
			"rope": ["bool", null, null, false, "", "draws a line back to the caster while it flies (hooks)"]}},
	"cone": {"cost": 2, "doc": "an instant wedge in front of the origin, toward the aim", "events": ["on_hit"],
		"params": {
			"origin": ["enum", ["caster", "owner"], null, "caster", "", ORIGIN_DOC],
			"radius": ["float", 1.5, 8.0, 4.0, "m", "reach"],
			"angle": ["float", 20.0, 180.0, 60.0, "deg", "full width of the wedge"]}},
	"beam": {"cost": 2, "doc": "an instant line (or a short channel) from the origin; with seek it snaps to the foe nearest the aim", "events": ["on_hit"],
		"params": {
			"origin": ["enum", ["caster", "owner", "here"], null, "caster", "", ORIGIN_DOC],
			"range": ["float", 2.0, 16.0, 7.0, "m", "length"],
			"width": ["float", 0.2, 1.5, 0.5, "m", "thickness"],
			"duration": ["float", 0.0, 3.0, 0.0, "s", "0 = one instant hit; above 0 = a channel that ticks every 0.25s"],
			"seek": ["bool", null, null, false, "", "locks onto the foe nearest the aim within range instead of firing straight"]}},
	"burst": {"cost": 1, "doc": "an instant circle at the origin; radius 0 means only the unit at the origin (a self or owner buff)", "events": [],
		"params": {
			"origin": ["enum", ["caster", "owner", "aim", "here"], null, "caster", "", ORIGIN_DOC],
			"radius": ["float", 0.0, 20.0, 2.0, "m", "0 = only the origin unit; above 8 only utility effects"]}},
	"zone": {"cost": 3, "doc": "a ground area that stays and applies its effects every tick to whoever is inside", "events": ["on_end"],
		"params": {
			"origin": ["enum", ["caster", "owner", "aim", "here"], null, "aim", "", ORIGIN_DOC],
			"radius": ["float", 0.5, 6.0, 2.5, "m", "size"],
			"duration": ["float", 0.5, 10.0, 4.0, "s", "how long it stays"],
			"every": ["float", 0.25, 2.0, 0.5, "s", "tick interval"]}},
	"trap": {"cost": 2, "doc": "a hidden zone that fires its effects on the first foe to step on it", "events": ["on_trigger", "on_end"],
		"params": {
			"origin": ["enum", ["caster", "owner", "aim", "here"], null, "aim", "", ORIGIN_DOC],
			"radius": ["float", 0.3, 2.0, 1.0, "m", "trigger radius"],
			"arm": ["float", 0.0, 2.0, 0.5, "s", "delay before it can fire"],
			"duration": ["float", 2.0, 30.0, 15.0, "s", "how long it waits"],
			"count": ["int", 1, 3, 1, "", "how many are placed"],
			"spread": ["float", 0.0, 3.0, 1.5, "m", "distance between them when count > 1"]}},
	"wall": {"cost": 3, "doc": "a barrier that blocks enemy shots (yours pass); its effects apply to shots or foes that touch it", "events": ["on_end"],
		"params": {
			"origin": ["enum", ["caster", "owner", "aim"], null, "aim", "", ORIGIN_DOC],
			"length": ["float", 1.0, 8.0, 4.0, "m", "width across the aim"],
			"hp": ["float", 20.0, 300.0, 120.0, "hp", "damage it soaks before breaking"],
			"duration": ["float", 0.5, 8.0, 4.0, "s", "how long it stands"],
			"offset": ["float", 0.0, 3.0, 0.0, "m", "how far in front of the origin, along the aim"],
			"follow": ["bool", null, null, false, "", "moves with the origin and turns with the aim (a held shield)"]}},
	"aura": {"cost": 3, "doc": "a circle that follows the origin and applies its effects every tick", "events": ["on_end"],
		"params": {
			"origin": ["enum", ["caster", "owner"], null, "caster", "", ORIGIN_DOC],
			"radius": ["float", 1.0, 8.0, 3.0, "m", "size"],
			"duration": ["float", 1.0, 10.0, 4.0, "s", "how long it lasts"],
			"every": ["float", 0.25, 2.0, 1.0, "s", "tick interval"]}},
	"tether": {"cost": 2, "doc": "a leash between the origin and a foe (the one hit, or the nearest to the aim); it snaps if they get too far", "events": ["on_snap", "on_end"],
		"params": {
			"origin": ["enum", ["caster", "owner"], null, "caster", "", ORIGIN_DOC],
			"length": ["float", 2.0, 12.0, 6.0, "m", "it snaps beyond this"],
			"duration": ["float", 0.5, 6.0, 3.0, "s", "how long it holds"]}},
	"dash": {"cost": 2, "doc": "the origin rushes along the aim, hitting what it passes through", "events": ["on_hit", "on_end"],
		"params": {
			"origin": ["enum", ["caster", "owner"], null, "caster", "", "who moves"],
			"distance": ["float", 1.0, 12.0, 6.0, "m", "how far"],
			"speed": ["float", 8.0, 35.0, 22.0, "m/s", "how fast"],
			"width": ["float", 0.3, 2.0, 1.0, "m", "how wide a path it hits"]}},
	"leap": {"cost": 2, "doc": "the origin jumps onto the aim point and lands", "events": ["on_land"],
		"params": {
			"origin": ["enum", ["caster", "owner"], null, "caster", "", "who jumps"],
			"range": ["float", 1.0, 12.0, 7.0, "m", "how far"],
			"time": ["float", 0.25, 1.2, 0.5, "s", "time in the air"],
			"height": ["float", 0.5, 6.0, 2.0, "m", "arc height"]}},
	"blink": {"cost": 2, "doc": "the origin teleports toward the aim (never into the abyss)", "events": ["on_end"],
		"params": {
			"origin": ["enum", ["caster", "owner"], null, "caster", "", "who blinks"],
			"distance": ["float", 1.0, 10.0, 5.0, "m", "how far"]}},
	"summon": {"cost": 4, "doc": "places a core-made unit that applies the effects around it every tick", "events": ["on_end"],
		"params": {
			"origin": ["enum", ["caster", "owner", "aim", "here"], null, "aim", "", ORIGIN_DOC],
			"unit": ["enum", ["totem", "sprite"], null, "totem", "", "totem stands still; sprite follows the caster"],
			"count": ["int", 1, 3, 1, "", "how many"],
			"duration": ["float", 2.0, 15.0, 6.0, "s", "how long they last"],
			"hp": ["float", 10.0, 150.0, 40.0, "hp", "their health"],
			"every": ["float", 0.5, 3.0, 1.0, "s", "how often they apply their effects"],
			"radius": ["float", 1.0, 6.0, 3.0, "m", "their reach"]}},
}

## Deliveries that do something with no effects listed (they move someone or block shots).
const SELF_SUFFICIENT := ["wall", "dash", "leap", "blink"]

# ---- effects: what happens to whoever the delivery touches ----
const DURATION := "s"

const EFFECTS := {
	"damage": {"cat": "damage", "cost": 1, "targets": ["foes"], "doc": "hurts",
		"params": {
			"amount": ["float", 1.0, 60.0, null, "hp", "total damage"],
			"over": ["float", 0.0, 6.0, 0.0, "s", "0 = all at once; above 0 = spread over this long (poison, burn)"]}},
	"slow": {"cat": "control", "cost": 1, "targets": ["foes"], "doc": "slows movement",
		"params": {
			"duration": ["float", 0.2, 4.0, null, "s", "how long"],
			"strength": ["float", 0.1, 0.6, 0.35, "x", "fraction of speed taken away"]}},
	"root": {"cat": "control", "cost": 2, "targets": ["foes"], "doc": "can't move or dodge, can still shoot",
		"params": {"duration": ["float", 0.2, 2.0, null, "s", "how long"]}},
	"stun": {"cat": "control", "cost": 3, "targets": ["foes"], "doc": "can't act",
		"params": {"duration": ["float", 0.1, 1.5, null, "s", "how long"]}},
	"pull": {"cat": "control", "cost": 2, "targets": ["foes"], "doc": "drags toward a point",
		"params": {
			"strength": ["float", 2.0, 30.0, 8.0, "m/s", "pull speed"],
			"to": ["enum", ["center", "caster", "owner"], null, "center", "", "center of the delivery, the kin, or its hunter"],
			"gap": ["float", 0.0, 3.0, 0.0, "m", "above 0: drags all the way and stops this far away (a hook's yank)"]}},
	"push": {"cat": "control", "cost": 2, "targets": ["foes"], "doc": "knocks away from a point",
		"params": {
			"strength": ["float", 2.0, 16.0, 8.0, "m/s", "knockback speed"],
			"from": ["enum", ["center", "caster", "owner"], null, "center", "", "where it pushes away from"]}},
	"lift": {"cat": "control", "cost": 2, "targets": ["foes", "owner", "self"], "doc": "knocks up into the air (airborne foes can be spiked)",
		"params": {
			"strength": ["float", 2.0, 16.0, 8.0, "m/s", "upward speed"],
			"forward": ["float", 0.0, 6.0, 0.0, "m/s", "extra speed along the aim (for lifting your own hunter)"]}},
	"shield": {"cat": "sustain", "cost": 2, "targets": ["owner", "self", "allies"], "doc": "temporary extra health",
		"params": {
			"amount": ["float", 5.0, 120.0, null, "hp", "shield size"],
			"duration": ["float", 1.0, 8.0, 3.0, "s", "how long it lasts"]}},
	"heal": {"cat": "sustain", "cost": 2, "targets": ["owner", "self", "allies"], "doc": "restores health",
		"params": {
			"amount": ["float", 5.0, 60.0, null, "hp", "total healing"],
			"over": ["float", 0.0, 6.0, 0.0, "s", "0 = all at once"]}},
	"cleanse": {"cat": "sustain", "cost": 1, "targets": ["owner", "self", "allies"], "doc": "clears slow, root, stun and damage over time", "params": {}},
	"reflect": {"cat": "sustain", "cost": 3, "targets": ["owner", "self", "wall"], "doc": "enemy shots that reach it fly back at the shooter; a reflected shot can't be reflected again",
		"params": {
			"power": ["float", 0.5, 1.5, 1.0, "x", "fraction of the shot's damage sent back (never grows with repeats)"],
			"duration": ["float", 0.2, 3.0, 1.0, "s", "on a unit: how long (on a wall it lasts as long as the wall)"],
			"radius": ["float", 0.8, 2.5, 1.6, "m", "on a unit: size of the shell"],
			"arc": ["float", 30.0, 360.0, 360.0, "deg", "on a unit: 360 all round, less = only in front"]}},
	"mark": {"cat": "utility", "cost": 1, "targets": ["foes"], "doc": "reveal (seen through walls and grass), vulnerable (takes more damage) or blight (heals less)",
		"params": {
			"mode": ["enum", ["reveal", "vulnerable", "blight"], null, "vulnerable", "", "what the mark does"],
			"duration": ["float", 0.5, 6.0, 3.0, "s", "how long"],
			"amount": ["float", 0.0, 0.6, 0.2, "x", "vulnerable: extra damage taken (max 0.35); blight: healing cut; reveal: ignored"]}},
	"buff": {"cat": "utility", "cost": 2, "targets": ["owner", "self", "allies"], "doc": "a short boost to one stat (see BUFF_STATS)",
		"params": {
			"stat": ["enum", ["move_speed", "guard", "damage", "fire_rate", "crit", "dash_refill", "glider_cool"], null, null, "", "which stat"],
			"amount": ["float", 0.0, 1.0, 0.0, "x", "size of the boost; bounds depend on the stat (BUFF_STATS); 0 = the stat's default"],
			"duration": ["float", 0.5, 8.0, 3.0, "s", "how long (ignored by dash_refill and glider_cool)"]}},
	"signature": {"cat": "utility", "cost": 3, "targets": ["foes", "owner", "self", "allies"], "doc": "a hand-coded mechanic from the reviewed SIGNATURES list",
		"params": {"id": ["enum", ["swap", "decoy", "bridge"], null, null, "", "which signature mechanic"]}},
}

## Buff stats: [min, max, default, unit, doc]. amount 0 in a file means "use the default".
const BUFF_STATS := {
	"move_speed": [0.05, 0.4, 0.35, "x", "moves faster"],
	"guard": [0.05, 0.4, 0.25, "x", "takes less damage"],
	"damage": [0.05, 0.35, 0.2, "x", "deals more damage"],
	"fire_rate": [0.05, 0.3, 0.2, "x", "fires faster"],
	"crit": [1.0, 1.0, 1.0, "", "shots crit for the duration"],
	"dash_refill": [1.0, 1.0, 1.0, "", "dodge charges refill at once"],
	"glider_cool": [0.25, 1.0, 1.0, "x", "glider heat cooled by this fraction"],
}

## Signature mechanics: hand-coded, reviewed one by one (Phase 6). Their own parameters.
const SIGNATURES := {
	"swap": {"doc": "the target trades places with the caster or its hunter", "params": {
		"who": ["enum", ["owner", "caster"], null, "owner", "", "who trades places with the target"]}},
	"decoy": {"doc": "leaves a copy of the origin unit that draws bots' fire", "params": {
		"duration": ["float", 0.5, 3.0, 1.8, "s", "how long the copy stays"]}},
	"bridge": {"doc": "abyss along the aim becomes walkable ground for a while", "params": {
		"length": ["float", 2.0, 12.0, 8.0, "m", "how long"],
		"width": ["float", 0.5, 2.0, 1.3, "m", "half width"],
		"duration": ["float", 2.0, 10.0, 6.0, "s", "how long it stays"]}},
}

## Which effects a wall may carry (applied to shots or foes touching it).
const WALL_EFFECTS := ["reflect", "damage", "slow", "push"]

# ---- modifiers: change how a delivery behaves ----
const MODIFIERS := {
	"bounce": {"cost": 2, "on": ["projectile"], "doc": "after a hit, flies on to another foe nearby",
		"params": {
			"count": ["int", 1, 3, 1, "", "extra bounces"],
			"range": ["float", 2.0, 8.0, 5.0, "m", "how far it looks for the next foe"],
			"falloff": ["float", 0.0, 0.5, 0.2, "x", "strength lost per bounce"]}},
	"pierce": {"cost": 2, "on": ["projectile", "beam", "dash"], "doc": "keeps going through foes",
		"params": {"count": ["int", 1, 5, 3, "", "extra foes it passes through"]}},
	"chain": {"cost": 2, "on": ["projectile", "beam"], "doc": "the hit arcs on to nearby foes",
		"params": {
			"count": ["int", 1, 4, 2, "", "extra jumps"],
			"range": ["float", 2.0, 8.0, 4.5, "m", "jump distance"],
			"falloff": ["float", 0.0, 0.6, 0.0, "x", "strength lost per jump"]}},
	"split": {"cost": 3, "on": ["projectile"], "doc": "fires several at once in a fan",
		"params": {
			"count": ["int", 2, 5, 3, "", "how many"],
			"angle": ["float", 10.0, 90.0, 30.0, "deg", "full width of the fan"]}},
	"delay": {"cost": 0, "on": ["projectile", "cone", "beam", "burst", "zone", "trap", "wall", "aura", "tether", "summon"], "doc": "waits before it happens (a telegraph ring shows where)",
		"params": {"time": ["float", 0.1, 3.0, 0.6, "s", "wait"]}},
	"linger": {"cost": 2, "on": ["projectile", "cone", "beam", "burst", "dash", "leap"], "doc": "leaves a ground patch where it ends that repeats its effects, weaker; never repeats stun or root",
		"params": {
			"duration": ["float", 0.5, 6.0, 2.0, "s", "how long the patch stays"],
			"radius": ["float", 0.5, 4.0, 1.5, "m", "patch size"],
			"every": ["float", 0.25, 2.0, 0.5, "s", "tick interval"],
			"strength": ["float", 0.1, 0.5, 0.3, "x", "fraction of the effects each tick"]}},
	"repeat": {"cost": 2, "on": ["projectile", "cone", "beam", "burst", "dash", "leap", "blink", "tether"], "doc": "happens again a beat later at the same spot, weaker (an echo)",
		"params": {
			"count": ["int", 1, 2, 1, "", "repeats"],
			"delay": ["float", 0.1, 2.0, 0.8, "s", "time between"],
			"falloff": ["float", 0.3, 0.8, 0.5, "x", "each repeat is this strong"]}},
	"return": {"cost": 1, "on": ["projectile"], "doc": "flies back to the origin after reaching its range, hitting again on the way", "params": {}},
	"spike": {"cost": 1, "on": ["burst", "cone", "leap", "dash"], "doc": "extra against airborne foes, slamming them down",
		"params": {
			"bonus": ["float", 0.0, 1.0, 0.5, "x", "extra damage against airborne foes"],
			"stun": ["float", 0.0, 1.5, 0.0, "s", "stun on a spiked foe"]}},
}

# ---- triggers: when an ability fires ----
const TRIGGERS := {
	"on_cast": {"doc": "the player presses the slot key (E for the active)", "params": {}},
	"auto": {"doc": "the kin decides, from the ability's cue and its personality", "params": {}},
	"on_throw": {"doc": "the thrown kin hits a foe", "params": {}},
	"on_hit": {"doc": "every n-th hit of the kin's own attack", "params": {
		"every": ["int", 1, 10, 3, "hits", "how many hits between"]}},
	"on_recall": {"doc": "the kin is recalled to its hunter", "params": {}},
	"on_bond_full": {"doc": "the bond meter fills", "params": {}},
	"on_low_hp": {"doc": "the owner or the kin drops below a share of its health", "params": {
		"who": ["enum", ["owner", "kin"], null, "owner", "", "whose health"],
		"below": ["float", 0.1, 0.6, 0.35, "x", "health fraction"]}},
}

# ---- cues: the situation an auto ability answers (also used by bots and auto-cast) ----
const CUES := {
	"foe_in_range": {"doc": "a foe is within range", "params": {"range": ["float", 2.0, 20.0, 7.0, "m", "how near"]}},
	"foes_clumped": {"doc": "several foes stand close together", "params": {
		"count": ["int", 2, 5, 2, "", "how many"],
		"radius": ["float", 1.0, 5.0, 3.0, "m", "how close together"],
		"range": ["float", 2.0, 20.0, 7.0, "m", "how near the kin"]}},
	"owner_hurt": {"doc": "the hunter is hurt", "params": {"below": ["float", 0.1, 0.9, 0.5, "x", "health fraction"]}},
	"owner_falling": {"doc": "the hunter is falling into the abyss", "params": {}},
	"owner_fighting": {"doc": "the hunter is in a fight", "params": {"chance": ["float", 0.05, 1.0, 0.3, "x", "chance per check"]}},
	"owner_under_fire": {"doc": "the hunter is being shot at", "params": {}},
}

# ---- presets: named parameter bundles (what used to be elements) ----
## A part names a preset with "preset": id; the preset fills that part's params, and the file can
## still override any of them. Each preset lists the part types it can fill.
const PRESETS := {
	"poison": {"doc": "damage over 3s", "parts": {"damage": {"over": 3.0}}},
	"blight": {"doc": "healing cut by 60% for 3s", "parts": {"mark": {"mode": "blight", "duration": 3.0, "amount": 0.6}}},
	"frost": {"doc": "a strong slow", "parts": {"slow": {"duration": 1.5, "strength": 0.5}}},
	"snare": {"doc": "a long root", "parts": {"root": {"duration": 1.4}}},
	"jolt": {"doc": "a short stun", "parts": {"stun": {"duration": 0.4}}},
	"echo": {"doc": "repeats once at half strength", "parts": {"repeat": {"count": 1, "delay": 0.9, "falloff": 0.5}}},
	"gravity_well": {"doc": "a strong pull to the centre", "parts": {"pull": {"strength": 9.0, "to": "center"}}},
	"hook": {"doc": "a yank all the way back to the kin", "parts": {"pull": {"strength": 30.0, "to": "caster", "gap": 1.2},
		"projectile": {"rope": true, "speed": 30.0, "size": 0.18}}},
	"gust": {"doc": "a hard shove", "parts": {"push": {"strength": 12.0}}},
	"mirror": {"doc": "full-strength reflect", "parts": {"reflect": {"power": 1.0}}},
}

## Cosmetic themes: tint and particle flavour only. Never a rule.
const THEMES := ["venom", "spore", "gravity", "prism", "lunar", "echo", "ember", "frost", "storm", "stone", "bloom", "shadow", "none"]

# ---- the kin: body, stats, carry ----
const ROLES := ["bruiser", "tank", "skirmisher", "controller", "support", "trickster"]
const TRAITS := ["bravery", "loyalty", "temper", "curiosity"]
const AI_KEYS := ["aggression", "loyalty", "caution"]

## Body ids are model builders in the core (KinModels); a new kin uses the generic parts.
const LOOK := {
	"body": ["round", "drop", "burr", "pear", "boulder", "cloud", "vespyx", "mycroll", "gravadillo", "prismander", "lunowl", "echolop"],
	"ears": ["none", "flame", "fin", "leaf", "bolt", "horn", "wisp"],
	"tail": ["none", "flame", "fish", "sprout", "zig", "stub", "wisp"],
	"feet": ["none", "paws", "stumps"],
	"aura": ["none", "embers", "bubbles", "leaves", "sparks", "pebbles", "wind", "drips", "prism", "spores", "rings", "moondust"],
}

const BODY := {
	"size": ["enum", ["small", "medium", "large"], null, "small", "", "small rides a shoulder, medium perches, large is ridden"],
	"reach": ["float", 1.0, 2.5, 1.3, "m", "melee reach"],
	"mass": ["float", 0.5, 3.0, 0.8, "x", "how hard it is to knock around"],
}
const GAIT := {
	"hop_rate": ["float", 3.0, 12.0, 9.0, "hops/s", "how quickly it bounces when it walks"],
	"hop_height": ["float", 0.0, 0.25, 0.14, "m", "how high"],
	"pace": ["float", 0.7, 1.3, 1.0, "x", "walk speed at home"],
}

## The stat profile: every kin spends exactly STAT_BUDGET points. Kin stats are base + points x
## per_point; owner stats are bonuses to the hunter while this kin is their kin for the run.
const STAT_BUDGET := 20
const STATS := {
	"kin_hp": {"base": 60.0, "per_point": 5.0, "max_points": 16, "unit": "hp", "doc": "the kin's health"},
	"kin_damage": {"base": 6.0, "per_point": 1.0, "max_points": 8, "unit": "hp/hit", "doc": "the kin's attack damage"},
	"kin_speed": {"base": 5.0, "per_point": 0.2, "max_points": 16, "unit": "m/s", "doc": "the kin's run speed"},
	"owner_max_hp": {"base": 0.0, "per_point": 4.0, "max_points": 8, "unit": "hp", "doc": "hunter max health"},
	"owner_armor": {"base": 0.0, "per_point": 0.04, "max_points": 8, "unit": "x", "doc": "hunter armor durability"},
	"owner_shield": {"base": 0.0, "per_point": 4.0, "max_points": 8, "unit": "hp", "doc": "a small shield that refills out of combat"},
	"owner_regen": {"base": 0.0, "per_point": 0.25, "max_points": 8, "unit": "hp/s", "doc": "hunter health regen"},
	"owner_move_speed": {"base": 0.0, "per_point": 0.015, "max_points": 8, "unit": "x", "doc": "hunter move speed"},
}

const CARRY := {
	"shoulder": {"sizes": ["small"], "doc": "rides your shoulder; its passive works once it has settled"},
	"perch": {"sizes": ["small", "medium"], "doc": "perches on your pack; same passive rules as shoulder"},
	"mount": {"sizes": ["large"], "doc": "a big kin you ride: it changes your movement, and you can't glide while mounted"},
}
const MOUNT := {
	"speed": ["float", 0.8, 1.3, 1.0, "x", "ground speed while riding"],
	"jump": ["float", 0.8, 1.3, 1.0, "x", "jump height while riding"],
	"turn": ["float", 0.5, 1.0, 0.8, "x", "how sharply it turns"],
}

## Owner passives (carry passive and merge). [category, type, carry_max, merge_max, unit, doc].
## All minimums are 0. carry_max 0 means only a merge may grant it.
const OWNER_STATS := {
	"move_speed": ["movement", "float", 0.15, 0.4, "x", "run speed"],
	"extra_jumps": ["movement", "int", 0, 1, "", "jumps in the air (1 = a double jump)"],
	"air_dashes": ["movement", "int", 0, 1, "", "dodges in the air"],
	"glide": ["movement", "float", 0.2, 0.5, "x", "glide speed and time (a big glide); never free flight"],
	"dodge_charges": ["movement", "int", 1, 1, "", "extra dodge charges"],
	"dodge_regen": ["movement", "float", 0.3, 1.0, "x", "faster dodge recharge (1 = instant)"],
	"armor": ["defence", "float", 0.2, 0.5, "x", "armor durability"],
	"damage_reduction": ["defence", "float", 0.15, 0.3, "x", "less damage taken"],
	"knockback_resist": ["defence", "float", 0.5, 0.75, "x", "less knockback"],
	"shield": ["defence", "float", 0.0, 150.0, "hp", "a shield when the merge starts"],
	"regen": ["defence", "float", 3.0, 8.0, "hp/s", "health regen"],
	"damage": ["offence", "float", 0.1, 0.35, "x", "more damage"],
	"fire_rate": ["offence", "float", 0.2, 0.3, "x", "faster firing"],
	"reload": ["offence", "float", 0.2, 0.3, "x", "faster reloads"],
	"reveal_radius": ["senses", "float", 0.0, 20.0, "m", "rivals this near are revealed"],
}

## Riders on the owner's shots (carry passive and merge). Hard CC is never allowed on every shot.
const SHOT_EFFECTS := ["damage", "slow", "push", "mark"]
const SHOT := {
	"splash": ["float", 0.0, 2.0, 0.0, "m", "each shot bursts this wide for part of its damage (0 = none)"],
	"chain": ["int", 0, 2, 0, "", "each shot arcs on to this many more foes at half damage"],
}

const MERGE := {
	"duration": ["float", 4.0, 10.0, 6.0, "s", "how long the merge lasts at bond and level 1"],
	"grow_duration": ["float", 0.0, 3.0, 1.0, "s", "extra time at full kin level and bond"],
	"grow_strength": ["float", 0.0, 0.25, 0.1, "x", "extra strength at full kin level and bond"],
}
const PULSE := {"every": ["float", 0.4, 3.0, 1.0, "s", "how often the pulse fires"]}
const MERGED_SCALE := [1.0, 1.3]   # merged ability numbers may grow up to 30%
## Core merge rules (not data): unlocks at run level Hunter.ULT_AT[0] (6), the first unlock fills
## the bond meter once, then the meter refills by fighting together. Ends early when you're knocked
## or you throw the kin; then a short spent window.
const MERGE_SPENT_TIME := 3.0

# ---- evolution ----
const AFFINITIES := ["fierce", "steadfast", "curious", "swift"]
const EVO_PARTS := ["horns", "spikes", "fangs", "brow", "plates", "shell", "club", "antennae", "spots", "third_eye", "crest", "wings", "tail_long", "fins"]
const EVO_GRANTS := ["stat_shift", "add_modifier", "sidegrade"]
const SIDEGRADE_UP := [1.05, 1.3]
const SIDEGRADE_DOWN := [0.7, 0.95]
const EVO_SLOTS := ["active", "auto"]

# ---- helpers ----

## The table of parts for a kind: "delivery", "effect", "modifier", "trigger", "cue".
static func table(kind: String) -> Dictionary:
	match kind:
		"delivery": return DELIVERIES
		"effect": return EFFECTS
		"modifier": return MODIFIERS
		"trigger": return TRIGGERS
		"cue": return CUES
	return {}

## Parameter definitions of one part, as dictionaries.
static func params_of(kind: String, type: String) -> Dictionary:
	var t := table(kind)
	if not t.has(type):
		return {}
	return t[type].get("params", {})

static func category(effect_type: String) -> String:
	return String(EFFECTS.get(effect_type, {}).get("cat", ""))

## Placeholder power cost of one part (Phase 3 replaces this with real budgets).
static func cost(kind: String, type: String) -> float:
	return float(table(kind).get(type, {}).get("cost", 0))

## Checks the registry itself: every default inside its bounds, every preset valid. Returns problems.
static func self_check() -> Array:
	var out: Array = []
	for kind in ["delivery", "effect", "modifier", "trigger", "cue"]:
		var t := table(kind)
		for type in t:
			var ps: Dictionary = t[type].get("params", {})
			for p in ps:
				var msg := _default_ok(ps[p])
				if msg != "": out.append("%s %s.%s: %s" % [kind, type, p, msg])
	for s in SIGNATURES:
		for p in SIGNATURES[s]["params"]:
			var msg := _default_ok(SIGNATURES[s]["params"][p])
			if msg != "": out.append("signature %s.%s: %s" % [s, p, msg])
	if (EFFECTS["signature"]["params"]["id"][1] as Array) != SIGNATURES.keys():
		out.append("effect signature.id values don't match SIGNATURES")
	if (EFFECTS["buff"]["params"]["stat"][1] as Array) != BUFF_STATS.keys():
		out.append("effect buff.stat values don't match BUFF_STATS")
	for pr in PRESETS:
		for type in PRESETS[pr]["parts"]:
			var kind := kind_of(type)
			if kind == "":
				out.append("preset %s: unknown part %s" % [pr, type]); continue
			var ps := params_of(kind, type)
			for p in PRESETS[pr]["parts"][type]:
				if not ps.has(p):
					out.append("preset %s: %s has no param %s" % [pr, type, p]); continue
				var msg := value_error(ps[p], PRESETS[pr]["parts"][type][p])
				if msg != "": out.append("preset %s: %s.%s %s" % [pr, type, p, msg])
	return out

static func _default_ok(pd: Array) -> String:
	if pd[3] == null:
		return ""
	return value_error(pd, pd[3])

## Which kind a part type belongs to ("" if none).
static func kind_of(type: String) -> String:
	for kind in ["delivery", "effect", "modifier"]:
		if table(kind).has(type):
			return kind
	return ""

## "" if v is a valid value for parameter definition pd, otherwise why not.
static func value_error(pd: Array, v: Variant) -> String:
	match String(pd[0]):
		"bool":
			if typeof(v) != TYPE_BOOL: return "must be true or false, got %s" % _show(v)
		"enum":
			if typeof(v) != TYPE_STRING: return "must be one of %s, got %s" % [_list(pd[1]), _show(v)]
			if not (pd[1] as Array).has(v): return "'%s' isn't one of %s" % [v, _list(pd[1])]
		"int", "float":
			if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT: return "must be a number, got %s" % _show(v)
			var f := float(v)
			if String(pd[0]) == "int" and not is_equal_approx(f, roundf(f)): return "must be a whole number, got %s" % _num(f)
			if f < float(pd[1]): return "%s is below the min %s%s" % [_num(f), _num(float(pd[1])), _unit(pd)]
			if f > float(pd[2]): return "%s is above the max %s%s" % [_num(f), _num(float(pd[2])), _unit(pd)]
	return ""

static func _unit(pd: Array) -> String:
	return (" " + String(pd[4])) if String(pd[4]) != "" else ""

static func _num(f: float) -> String:
	return str(int(f)) if is_equal_approx(f, roundf(f)) else str(snappedf(f, 0.001))

static func _list(a: Array) -> String:
	return "[" + ", ".join(a.map(func(x): return str(x))) + "]"

static func _show(v: Variant) -> String:
	if typeof(v) == TYPE_STRING: return "'%s'" % v
	return JSON.stringify(v)
