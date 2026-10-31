# Adding content to Kinfall

Everything here is plain JSON under `content/`. The game reads it when it starts; no code changes.
Colours are hex strings, times are seconds, distances are tiles.

Kin are moving to a compositional ability grammar (`content/*_v2/`, see `docs/KIN_GRAMMAR.md`).
Those files are checked with `--grammar-check` but not used by the game yet; the formats below are still live.

## A new kin: `content/kin/<id>.json`

```json
{
	"id": "mosslet",
	"name": "Mosslet",
	"type": "thorn",
	"color": "#5a9a4f", "belly": "#d8f0b0", "glow": "#b8f07a",
	"stats": {"hp": 90, "dmg": 8, "speed": 6.4, "range": 1.3},
	"look": {"body": "burr", "ears": "leaf", "tail": "sprout", "feet": "paws", "aura": "leaves"},
	"traits": {"bravery": 0.5, "loyalty": 0.7, "temper": 0.3, "curiosity": 0.6},
	"voice": "sleepy and kind, speaks slowly",
	"shoulder": "briar",
	"abilities": ["snare", "thorn_patch"],
	"ultimate": "thornwake",
	"ai": {"aggression": 0.4, "loyalty": 0.7, "caution": 0.5, "style": "trapper"},
	"throw_hit": {"root": 0.8}
}
```

- `look`: `body` is round, drop, burr, pear, boulder or cloud; `ears` is flame, fin, leaf, bolt, horn or wisp;
  `tail` is flame, fish, sprout, zig, stub or wisp; `feet` is paws, stumps or none; `aura` is embers, bubbles,
  leaves, sparks, pebbles, wind, drips, prism, spores, rings or moondust. The six built-in species have
  hand-built animal bodies instead (scripts/match/kin_models.gd); a new species uses these parts unless it
  gets a builder there too. `wing` (optional) colours wing membranes.
- `abilities`: one or two ability ids. The first is the kin's ability on E. The second is kept for later (the current kit has one kin ability) and is only cast by the kin itself when auto-cast is on.
- `ultimate`: an ultimate id (R).
- `ai`: the species' fighting temperament, mixed 50/50 with each kin's own traits. Aggression chases further and
  uses attacks more; loyalty stays close and goes after whoever hurts its hunter; caution backs off when hurt.
- `shoulder`: the passive while it rides on your shoulder (kindle, spring, briar, charge, bedrock, updraft).
- `throw_hit`: extra status when it's thrown into a foe (burn, slow, root, stun, kb).
- `animals`: the one or two real animals it's based on (shown on the hatch reveal card).
- `desc`: a line about it for the hatch reveal card.
- `egg`: how its egg is shown: `name` (e.g. "Venom Egg"), `temper`, `desc` and `play` (used on the first-egg picker and the Nesting Nook).
- `work`: its work elements, the farm jobs it does on its own, each at a level 1-4, e.g. `{"bloom": 3, "forage": 2, "ranch": 1}`. Elements: ember, tide, bloom, spark, craft, forage, timber, stone, frost, haul, mend, ranch (see `scripts/core/work.gd`). Two or three per kin.
- `shiny`: its hand-picked shimmer palette, `{"color", "belly", "glow"}` (and `"wing"` for winged kin). Shimmers are 1 in 4096 (see `scripts/core/shiny.gd`).

Open `tests/kin_gallery.tscn` and press F6 to see it next to the others.

## A new ability: `content/abilities/<id>.json`

```json
{
	"id": "fireball", "name": "Fireball", "icon": "fireball", "color": "#ff7a3d",
	"desc": "Your kin spits a fireball that explodes and sets everything nearby burning.",
	"cooldown": 6, "charges": 1,
	"from": "kin", "range": 9,
	"auto": {"when": "foe_in_range", "range": 9},
	"effects": [
		{"type": "projectile", "dmg": 18, "speed": 13, "range": 9, "size": 0.32, "color": "#ff7a3d", "burn": 5,
			"on_end": [{"type": "area", "at": "here", "radius": 1.9, "dmg": 8, "kb": 6, "burn": 5}]}
	]
}
```

- `from`: `kin` (the kin casts it; from your shoulder it's thrown out first) or `owner` (works on you wherever the kin is).
- `auto`: when the kin uses it by itself: `foe_in_range` (range), `foes_clumped` (count, radius), `owner_hurt` (below),
  `owner_falling`, `owner_fighting` (chance). Leave it out for player-only abilities.
- `effects`: steps run in order. Types (see `scripts/combat/effects.gd` for every field):
  projectile, area, cone, chain, pull, zone, telegraph, rush, leap, dash, blink, launch, heal, shield, haste,
  guard, cleanse, refill_dash, cool_glider, crit, burst. Any effect can have a `delay`. Buffs take a `target`
  (self, owner, both, allies); areas take an `at` (self, owner, aim, here).

## A new bond ultimate: `content/ultimates/<id>.json`

- `form`: `armor` (fuses onto the hunter) or `giant` (the kin grows huge). `time` in seconds.
- Armor: `owner` (dmg, speed multipliers; shield, regen, refill_dash) and `shots` (burn, slow, boom, chain).
- Giant: `giant` (scale, hp, dmg, range, speed, and `stomp` effects on every attack).
- `on_start`, `on_end` and `aura` (`{"every": 0.6, "effects": [...]}`) are effect lists.

## Combos: `content/combos/<id>.json`

`setup_by` (kin, owner, any) applies one of `statuses`; within `window` seconds the next hit by `payoff_by`
(owner, kin, kin_ability) deals `bonus` times damage and adds `bond` to the meter.

## Tuning: `content/rules/`

- `bond.json`: how fast the bond meter fills from your hits, your kin's hits, combos and knockouts.
- `kin_ai.json`: how traits turn into chase range, leash, retreat health, and the recall and swap cooldowns.

## Weapons and classes

`content/weapons/<id>.json` (primary fire and an optional `utility` ability) and `content/classes/<id>.json`
(the class `dodge` ability).


## A new glove: `content/gloves/<id>.json`

Gloves are found on the run (chests, vaults, bosses) and last one expedition. A glove with a `cd`
above 0 is an **active** glove and goes in the Q slot; one with `cd` 0 is **passive** and goes in the
other slot. Picking one up replaces the glove in its slot.

```json
{
 "id": "quake", "name": "Quake Glove", "cd": 18, "col": "ff9a5a", "icon": "quake",
 "stats": {"dmg": 0.04},
 "desc": "Punch the ground: after a short wind-up, everyone close is thrown into the air.",
 "effects": [
  {"type": "telegraph", "radius": 2.8, "time": 0.35, "at": "self", "color": "ff9a5a"},
  {"type": "area", "radius": 2.8, "dmg": 14, "lift": 9, "kb": 3, "at": "self", "delay": 0.35, "color": "ff9a5a"}
 ]
}
```

- `stats`: `speed`, `glide_speed`, `heat`, `armor`, `dmg`, `cdr` (scaled up by rarity).
- `effects`: the same building blocks abilities use (see `scripts/combat/effects.gd`). The older
  actives (jump pad, gust, platform, smoke, mending, seeker, shock) are coded in `Match.use_gear`.
- `icon`: any id from `scripts/ui/icons.gd`.
