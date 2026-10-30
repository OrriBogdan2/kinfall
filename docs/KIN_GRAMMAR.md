# Kin ability grammar

Every kin ability is built from a small, fixed set of parts that players learn once: a **delivery**
(the shape), **effects** (what happens to whoever it touches), **modifiers** (how the delivery
behaves) and a **trigger** (when it fires). Anyone can add kin and abilities as data, and a player
who has never seen a kin can still read what it does from the parts.

Status: **Phase 1, data model.** The grammar files under `content/*_v2/` are parsed and checked but
not used by the game yet. The live game still reads `content/kin`, `content/abilities` and
`content/ultimates`. Phase 2 adds the runtime executor and switches over.

Code: `scripts/kin/` (registry `parts.gd`, specs `ability_spec.gd`, `stage_spec.gd`, `part_spec.gd`,
`merge_spec.gd`, `kin_spec.gd`, `evolution_node.gd`, loader/checker `grammar.gd`, errors `grammar_report.gd`).

## Why JSON, not `.tres`

Kinfall will take community-submitted kin. A Godot `.tres`/`.res` file can carry an `ext_resource`
or `sub_resource` of type `Script`, and a resource with a `script` property runs that script when
it loads. Loading a stranger's `.tres` can run arbitrary code on the player's machine. JSON can't
reference anything: `JSON.parse_string` only ever produces dictionaries, arrays, strings, numbers and
booleans. It is also diffable, mergeable, readable in review, and checkable outside the engine (CI or a website).

The rules that keep it safe:

- **Nothing named in data is loaded or called.** Every name a file uses (a part, preset, theme, body
  builder, signature) is looked up in a core table in `KinParts` and nowhere else. An unknown name is an error.
- **Ids** (`id`, `active`, `merge`, node ids) are lowercase letters, digits and `_`, at most 48 characters, so they can never be paths.
- **Strict fields.** An unknown field is an error, so typos and smuggled keys are caught.
- **Reference scan.** Any field named `script`, `class`, `extends`, `path`, `resource`, `load`, `call`,
  `method`, `eval`... and any string containing `res://`, `user://`, a URL, or a word ending in `.gd`
  `.tscn` `.tres` `.res` `.scn` `.dll` `.so` `.exe` is rejected. Nothing is loaded either way; the scan
  is a second line of defence that tells the author why the file was rejected.
- **Versioned.** Every file has `"grammar": 1` so the format can change later without guessing.
- **Bounded.** Every number has a min and max in core code; the runtime clamps to the same bounds.

## Files

```
content/abilities_v2/<id>.json   AbilitySpec   one ability
content/merges_v2/<id>.json      MergeSpec     a bond ultimate (the merge)
content/evolution_v2/<id>.json   EvolutionNode one evolution step (shared or kin-specific)
content/kin_v2/<id>.json         KinSpec       one kin species
```

A file's name must match its `id`. Check everything with:

```
godot --headless --path . -- --grammar-check                  # every v2 file under res://content
godot --headless --path . -- --grammar-check=res://tests/grammar_fixtures/broken
godot --headless --path . -- --grammar-vocab                  # prints the vocabulary tables below
```

`--grammar-check` exits 1 if there are errors. `tests/grammar_fixtures/broken/` holds deliberately bad
files (one per kind of mistake) and should always print errors. Phase 3 builds the validator on top of this.

## The run model the grammar serves

- **One kin per run** (the 2-kin swap stays retired).
- The weapon gives primary fire and the RMB utility. The class gives the Shift dodge (light phase
  step, medium roll, heavy shoulder charge); the kin adds a **dodge rider** to it.
- The kin gives **1 player-cast active (E)**, optionally **1 auto active** it casts itself when it's
  out (driven by its personality and the ability's cue), and the **merge** (bond ultimate, R).
- Throw/recall, the shared bond meter, player-kin combos (`content/combos`), personality-driven kin
  AI (KinTactics), run levels and slot ranks (`Hunter.slot_lv`) all stay. Ranks grow an ability's numbers
  through a core table per part (today's `Effects` rank table), never through data.

## AbilitySpec (`content/abilities_v2/<id>.json`)

```json
{
	"grammar": 1,
	"id": "stinger_hook",
	"name": "Stinger Hook",
	"short": "Hook",
	"flavor": "Vespyx lashes its tail and reels in whatever it stings.",
	"theme": "venom",
	"tier": 1,
	"from": "kin",
	"range": 8,
	"cooldown": 8,
	"charges": 1,
	"cost": {"bond": 0},
	"trigger": {"type": "on_cast"},
	"cue": {"type": "foe_in_range", "range": 8},
	"stages": [
		{
			"delivery": {"type": "projectile", "preset": "hook", "range": 8},
			"effects": [
				{"type": "damage", "amount": 8},
				{"type": "damage", "preset": "poison", "amount": 18},
				{"type": "mark", "preset": "blight", "duration": 4},
				{"type": "pull", "preset": "hook"},
				{"type": "stun", "duration": 0.3}
			]
		}
	]
}
```

| field | required | meaning |
|---|---|---|
| `grammar` | yes | format version, `1` |
| `id`, `name` | yes | id (lowercase, matches the file name) and display name |
| `short` | | one or two words for the HUD slot (default: `name`) |
| `flavor` | | the creator's own words. Rules text is generated from the parts in Phase 4; creators never write it |
| `theme` | | cosmetic tint and particles only (`THEMES`); never a rule |
| `tier` | | 1-3, the budget bracket (Phase 3 sets each tier's cap) |
| `from` | | `kin` (default): the kin performs it, thrown out first if carried. `owner`: it works on the hunter wherever the kin is; its stages can't start at `caster` |
| `range` | | 0-25 m, how far from the caster it can be aimed (0 = no limit or self) |
| `cooldown` | | 1-60 s (default 8) |
| `charges` | | 1-3 |
| `cost.bond` | | 0-0.5 of the bond meter spent on use |
| `trigger` | yes | when it fires (see Triggers). The E active must be `on_cast`; the auto active can't be |
| `cue` | for `auto` | the situation the AI uses it in (see Cues). Also read by bots and the auto-cast option |
| `stages` | yes | 1-4 stages, run in order |

**Stage**: `{"delivery": {...}, "effects": [...], "modifiers": [...], "then": {"<event>": [stages]}}`.
The delivery is required. Effects apply to whatever the delivery touches (each effect has a `target`;
harmful effects hit foes, sustain and buffs default to the owner or self). `then` starts followup
stages on a delivery event (`on_hit`, `on_end`, `on_land`, `on_trigger`, `on_snap`); followups usually
start at `"origin": "here"`, where the previous stage landed.

**Part**: `{"type": "<part>", "preset": "<preset>", ...params}`. Any delivery, effect or modifier may
name a preset; the preset fills its numbers and the file can still override any of them. (The plan
asked for an optional preset on the AbilityDef. A whole-ability preset is ambiguous when an ability
has two damage effects, so presets live on parts.)

## KinSpec (`content/kin_v2/<id>.json`)

| field | required | meaning |
|---|---|---|
| `id`, `name` | yes | |
| `animals` | yes | the 1 or 2 real animals it's based on |
| `theme` | | cosmetic (what used to be its element "type") |
| `flavor` | | reveal card / Kindex line |
| `colors` | yes | `body`, `belly`, `glow`, optional `wing` (hex) |
| `look` | yes | `body` `ears` `tail` `feet` `aura`: core model builder ids (`LOOK`) |
| `body` | yes | `size` (small, medium, large), `reach`, `mass`, `gait` (`hop_rate`, `hop_height`, `pace`) |
| `stats` | yes | the stat profile: points spent across `STATS`, exactly `STAT_BUDGET` (20) in total |
| `personality` | yes | starting traits `bravery` `loyalty` `temper` `curiosity`, 0-1 |
| `ai` | yes | AI weights `aggression` `loyalty` `caution` 0-1 (mixed 50/50 with each kin's own traits by KinTactics) and `role` (bruiser, tank, skirmisher, controller, support, trickster) |
| `carry` | yes | `style` (shoulder, perch, mount; must suit `body.size`), `name`, `passives` (owner stats, carry caps), `on_shot` (riders on your shots), `mount` (speed, jump, turn; mount only). No gliding while mounted is a core rule |
| `throw` | | `effects` (max 3, on foes) when the thrown kin hits a foe |
| `dodge_rider` | | added to the class dodge: `name`, `as` (dash or blink), `on_pass` (effects on what you dodge through; no stun or root), `on_start`/`on_end` (stages), `modifiers` (repeat only) |
| `active` | yes | ability id for E (trigger `on_cast`) |
| `auto` | | ability id the kin casts itself (any trigger except `on_cast`) |
| `merge` | yes | merge id |
| `evolution` | | `root` (start of evolved names, "Cind" + "fang") and `paths`: `[{"affinity": "fierce", "nodes": [ids]}]` |
| `voice` | | `line` (how it talks) and `syllables` (its two name syllables) |
| `egg` | | `name`, `temper`, `desc`, `play` |

The stat profile is a fixed budget: each kin spends exactly 20 points. Kin stats are
`base + points x per_point`; owner stats are bonuses the hunter gets while this is their kin.
A tank leans on `owner_armor` and `kin_hp`, a speedy kin on `kin_speed` and `owner_move_speed`.
The numbers per point are placeholders until Phase 3.

## MergeSpec (`content/merges_v2/<id>.json`)

The merge is the bond ultimate: hunter and kin fight as one for a short time.

| field | required | meaning |
|---|---|---|
| `id`, `name`, `flavor`, `theme` | id, name | |
| `duration` | yes | 4-10 s at kin level and bond 1 |
| `grow_duration`, `grow_strength` | | up to +3 s and +25% at full kin level and bond (the core curve decides in between) |
| `passives` | yes | owner stats with merge caps: movement, defence, offence, senses |
| `on_shot` | | riders on every shot: `effects` (damage, slow, push, mark only; never stun or root), `splash` (m), `chain` (extra foes) |
| `on_start`, `on_end` | | stages |
| `pulses` | | `[{"every": s, "stage": {...}}]`, stages repeated while merged |
| `merged` | | merged versions of the kin's abilities: `{"active": {"stage": 0, "add_modifiers": [...], "scale": {"range": 1.2}}}`. Scales are x1.0 to x1.3, and the result must stay inside the part's bounds |

Core rules (not data): it unlocks at run level `Hunter.ULT_AT[0]` (6); the first unlock fills the bond
meter once; after that the meter refills by fighting together. It ends early if you're knocked or
you throw the kin, then a short spent window (`KinParts.MERGE_SPENT_TIME`). Mobility is capped by
the owner-stat bounds: at most a double jump, one air dash and a big glide (+50%). There is no
flight stat, so free flight can't be expressed.

## EvolutionNode (`content/evolution_v2/<id>.json`)

Evolution adds variety, not raw power. A node can:

- `stat_shift`: move 1-2 stat points from one stat to another (the total stays 20),
- `add_modifier`: give one of the kin's abilities a modifier (Phase 3 prices it against the tier budget),
- `sidegrade`: one number up (x1.05 to x1.3) and another down (x0.7 to x0.95) on one stage of an ability.

```json
{"grammar": 1, "id": "cindle_barbed_tail", "name": "Barbed Tail", "affinity": "fierce",
 "requires": {"level": 8, "after": ["fierce_form"]},
 "grants": [{"kind": "sidegrade", "slot": "active", "stage": 0,
             "up": {"param": "delivery.range", "scale": 1.2}, "down": {"param": "effects.4.duration", "scale": 0.7}}],
 "cosmetic": {"parts": ["spikes"]}}
```

`affinity` is one of fierce, steadfast, curious, swift (the existing `Evo` affinities: how you raise
it decides the path). The four shared `*_form` nodes replace today's "+5% per form" growth with
budget-neutral point shifts. Body-part mutations stay cosmetic (`cosmetic.parts`, `tint`). The checker
follows each path in order: nodes must match the path's affinity, levels can't go down, `after` nodes
must come earlier, shifted stats stay within 0 and their max, and targeted stages and numbers must
exist and stay within bounds.

## Rules across parts and hard caps

| rule | why |
|---|---|
| at most 4 stages, 6 effects and 4 modifiers per stage, followups 3 deep | keeps abilities readable |
| split x (1 + bounce) x (1 + chain) x (1 + pierce) ≤ 12 | no runaway hit counts |
| a modifier must suit its delivery (e.g. bounce only on projectiles), once per stage | |
| `then` events must exist on the delivery | |
| `origin: here` only in followups | |
| a stage with no effects and no followups is an error, except wall, dash, leap, blink | it would do nothing |
| burst, zone or aura wider than 8 m may only carry utility effects | a map-wide reveal is fine, a map-wide stun isn't |
| `linger` can't repeat stun or root | no lingering hard CC |
| walls carry only reflect, damage, slow, push | |
| shot riders never stun or root; a dodge never stuns or roots what it passes | |
| a reflected shot can't be reflected again; reflect power ≤ 1.5 | fixes the uncapped reflection growth found in the audit |
| a vulnerable mark adds at most +35% damage taken | |
| merge and sidegrade scales must land inside the part's bounds | |

Phase 2 adds the runtime rules: diminishing returns on repeated slow, root and stun per target, with
brief immunity after a full stun (zones and pulses included), no ability triggering itself, the same
caps enforced at runtime, and auto-cast respecting slot locks.

## Presets and themes (what used to be elements)

Elements are no longer a rule. A kin is based on 1-2 animals, and its old element type is now a
cosmetic `theme`. What an element used to mean is a named **preset**: "poison" is damage over 3 s,
"frost" a strong slow, "hook" a projectile with a rope plus a yank. Colour will mean effect category
in Phase 4 (damage, control, sustain, utility), never theme.

## How existing content maps onto the grammar

Fit: **yes** = expressible as-is · **gap** = needs a small vocabulary addition · **signature** = a
hand-coded mechanic from the reviewed list · **core** = stays in core code, not grammar.

### Kin abilities (converted in `content/abilities_v2/`)

| old file | kin, slot | grammar form | fit |
|---|---|---|---|
| stinger_hook | Vespyx, E | projectile (hook preset) → damage 8, damage 18 over 3s (poison), mark blight 4s, pull to caster (hook), stun 0.3 | yes |
| flare_dash | Vespyx, auto | dash 7 m → damage 14, poison 18; then on_end: burst 1.6 → damage 8, push 5 | yes |
| slam | Gravadillo, E | leap 7 m; on_land: burst 3.5 → pull (gravity_well); burst 2.4 → damage 18, lift 8, spike (+50%, stun 0.8) | yes |
| rock_guard | Gravadillo, auto (owner) | wall at owner, offset 1.2, follow, 120 hp, 3 s (blocks shots, no effects) | yes |
| prism_wall | Prismander, E | wall at aim, 4 m, 140 hp, 4.5 s → reflect (mirror) | yes |
| refraction | Prismander, auto (owner) | burst r0 at owner → reflect on owner 1 s, shield 20 | yes |
| puffcap_mines | Mycroll, E | trap x3 at aim; on_trigger: burst 1.8 → damage 8, root 1.4 (snare); zone 1.8, 3 s → damage 2 a tick, slow 0.8 | yes |
| thorn_patch | Mycroll, auto | zone 2.6, 4 s → damage 4 a tick, slow 0.8; cue foes_clumped | yes |
| chain_spark | Echolop, E | beam (seek) 7 m → damage 14, stun 0.4 (jolt); chain 2 jumps; repeat (echo) | yes |
| echolocate | Echolop, auto (owner) | burst r18 at owner → mark reveal 3 s, buff crit 1.5 s on owner (uses the big-area utility rule) | yes |
| moon_swap | Lunowl, E | projectile 9 m → damage 4, **signature swap** (owner), stun 0.4 | signature |
| updraft | Lunowl, auto (owner) | burst r0 at owner → lift owner 14 (+3 forward), buff glider_cool | yes |

Field changes: `burn: n` (n dps for 3 s) became `damage` with `over: 3`; `blight` became a `mark`
mode; old chain `count` counted targets, the grammar's counts extra jumps; `auto` on E abilities
became the `cue`; `desc` moved to `flavor` as placeholder text until Phase 4 generates rules text.
`icon`, `color`, `element`, `verb`, `deco`, `sfx`, `pitch` and per-effect colours are dropped, since
Phase 4 derives the look and sound from the parts.

### Bond ultimates → merges (converted in `content/merges_v2/`)

| old file | form | merge | fit |
|---|---|---|---|
| blaze_mantle | armor | damage +30%; shots poison (18 over 3 s) and splash 1.2 m; on_start burst 3.2; merged auto: flare_dash gains linger | yes |
| stormcoat | armor | move speed +30%, damage +15%, dodge_regen 1 (was refill_dash); shots chain 1; on_start beam + chain 3; merged E range x1.2 | yes |
| tidal_shell | armor | shield 80, regen 6; shots slow 1.2 s; on_start burst 3.5 + heal allies 20 in 5 m; merged E wall x1.25 long, x1.2 hp | yes |
| tempest | giant | move speed +30%, double jump, big glide +50%; pulse every 0.6 s: pull 7 in 5.5 m; on_start lift; merged E range x1.3 | **gap**: giant scale, hp and stomp dropped |
| thornwake | giant | armor +30%, knockback resist 50%; pulse every 1.5 s: damage 10, root 1.0 in 2.8 m (was its stomp); on_start root 1.6; merged E trap radius x1.3 | **gap**, as above |
| titan | giant | armor +50%, knockback resist 75%, shield 120 (was giant hp 250); pulse every 1.5 s: damage 14, push 12, lift 7; on_start; merged E range x1.3 | **gap**, as above |

"Giant" (the kin grows huge and fights beside you) isn't a merge, so these were rebuilt as merges
with the nearest passives and pulses. The merged ability patches are placeholders for review.

### Hunter-owned abilities (not kin, mapped to test the vocabulary's coverage)

| old file | grammar form | fit |
|---|---|---|
| bulwark | wall at caster, offset 1.3, follow, 160 hp, 5 s | yes |
| earthshatter | leap 7 m; on_land: burst 3 → damage 20, push 3, lift 8, spike (+60%, stun 1) | yes |
| leash_bolt | projectile → then on_hit: tether 6 m, 3.5 s → then on_snap: burst r0 here → damage 22, stun 1, pull to caster | yes |
| razor_disc | projectile + return → damage 9, slow 0.6 | yes |
| tripwire_mine | trap → on_trigger: burst 1.6 → damage 14, root 1.4, mark reveal 3 s | yes |
| breach | cone 4 m → damage 18, push 13; then the caster hops backwards | **gap**: dash/leap need a `direction: back` option |
| rail_charge | projectile + pierce with hold-to-charge numbers | **gap**: no `charge` (hold) modifier yet |
| riposte | burst r0 → reflect (front arc, power 1.3) + melee parry stun | **gap/signature**: parry |
| shadow_step | projectile → on_hit appear behind the target + crit | **signature** candidate ("behind") or blink-to-target |
| dash, combat_roll, phase_step, shoulder_charge | class dodges: invuln frames, phasing, reload, shove | **core**; kin add a `dodge_rider` |

### Other per-kin data and hardcoded spots

| today | grammar home |
|---|---|
| `type` element (venom, spore, ...) | `theme` (cosmetic) + presets |
| `stats` hp dmg speed range | `stats` points (hp, damage, speed) + `body.reach` |
| `traits` | `personality` |
| `ai` aggression loyalty caution + `style` (unused by code) | `ai` weights + `role` |
| `shoulder` perk by name in hunter.gd and Data.SHOULDER (kindle, spring, briar, charge, bedrock, updraft) | `carry.passives` / `carry.on_shot` |
| `throw_hit` | `throw.effects` |
| content/rules/dash_riders.json per element | `dodge_rider` per kin (the prism decoy is signature `decoy`) |
| kin.gd mass for pebbit | `body.mass` |
| kin_models.gd per-species builders | `look.body` (still core builders; new kin use the generic parts) |
| evo.gd ROOTS | `evolution.root` |
| Evo affinity stat growth (+5% damage etc. per form) | `*_form` nodes: budget-neutral `stat_shift` |
| kin_speak.gd syllables | `voice.syllables` |
| home.gd gait per element | `body.gait` |
| HUD throw tooltip via Data.SHOULDER; ultimate icons by id | generated from parts (Phase 4) |
| legacy glove code in match.use_gear | not kin; out of scope (gloves can adopt the grammar later) |

### The six kin

Kin stats are unchanged (hp, damage, speed come out the same from the points). The points left over go
to new owner bonuses that lean into each kin's role. Phase 2 makes them real.

| kin | animals | role | carry | kin hp/dmg/speed (points) | owner bonus points | dodge rider |
|---|---|---|---|---|---|---|
| Vespyx (cindle) | Fox, Scorpion | bruiser | shoulder: shots poison | 80/9/6.8 (4/3/9) | max hp 2, move speed 2 | on_pass poison + blight |
| Gravadillo (pebbit) | Armadillo, Rhino beetle | tank | **mount** (proposed): -15% damage taken, half knockback | 120/11/5.4 (12/5/2) | armor 1 | on_end pull |
| Prismander (puddlet) | Axolotl | support | shoulder: regen 3 | 95/7/6.0 (7/1/5) | shield 4, regen 3 | on_start decoy (signature) |
| Mycroll (burrlet) | Hedgehog, Toadstool | controller | shoulder: shots slow | 90/8/6.2 (6/2/6) | max hp 3, shield 3 | on_start spore zone |
| Echolop (zapple) | Hare, Bat | skirmisher | shoulder: +20% fire rate and reload | 70/8/7.6 (2/2/13) | move speed 3 | repeat (echo step) |
| Lunowl (wisplet) | Owl, Luna moth | trickster | **perch** (proposed): +1 dodge charge | 70/7/8.0 (2/1/15) | move speed 2 | as blink |

## Vocabulary

Generated from `KinParts` by `--grammar-vocab`; the code is the source of truth. Units: m metres,
s seconds, m/s, hp, deg degrees, x a fraction or multiplier.

### Deliveries

| part | what it does | parameter | min | max | default | unit |
|---|---|---|---|---|---|---|
| **projectile** | a shot that flies toward the aim and hits the first foe in its path · then: on_hit, on_end | origin | caster/owner/here |  | caster |  |
|  |  | speed | 8 | 80 | 30 | m/s |
|  |  | range | 2 | 20 | 9 | m |
|  |  | size | 0.08 | 0.6 | 0.2 | m |
|  |  | rope | true/false |  | false |  |
| **cone** | an instant wedge in front of the origin, toward the aim · then: on_hit | origin | caster/owner |  | caster |  |
|  |  | radius | 1.5 | 8 | 4 | m |
|  |  | angle | 20 | 180 | 60 | deg |
| **beam** | an instant line (or a short channel) from the origin; with seek it snaps to the foe nearest the aim · then: on_hit | origin | caster/owner/here |  | caster |  |
|  |  | range | 2 | 16 | 7 | m |
|  |  | width | 0.2 | 1.5 | 0.5 | m |
|  |  | duration | 0 | 3 | 0 | s |
|  |  | seek | true/false |  | false |  |
| **burst** | an instant circle at the origin; radius 0 means only the unit at the origin (a self or owner buff) | origin | caster/owner/aim/here |  | caster |  |
|  |  | radius | 0 | 20 | 2 | m |
| **zone** | a ground area that stays and applies its effects every tick to whoever is inside · then: on_end | origin | caster/owner/aim/here |  | aim |  |
|  |  | radius | 0.5 | 6 | 2.5 | m |
|  |  | duration | 0.5 | 10 | 4 | s |
|  |  | every | 0.25 | 2 | 0.5 | s |
| **trap** | a hidden zone that fires its effects on the first foe to step on it · then: on_trigger, on_end | origin | caster/owner/aim/here |  | aim |  |
|  |  | radius | 0.3 | 2 | 1 | m |
|  |  | arm | 0 | 2 | 0.5 | s |
|  |  | duration | 2 | 30 | 15 | s |
|  |  | count | 1 | 3 | 1 |  |
|  |  | spread | 0 | 3 | 1.5 | m |
| **wall** | a barrier that blocks enemy shots (yours pass); its effects apply to shots or foes that touch it · then: on_end | origin | caster/owner/aim |  | aim |  |
|  |  | length | 1 | 8 | 4 | m |
|  |  | hp | 20 | 300 | 120 | hp |
|  |  | duration | 0.5 | 8 | 4 | s |
|  |  | offset | 0 | 3 | 0 | m |
|  |  | follow | true/false |  | false |  |
| **aura** | a circle that follows the origin and applies its effects every tick · then: on_end | origin | caster/owner |  | caster |  |
|  |  | radius | 1 | 8 | 3 | m |
|  |  | duration | 1 | 10 | 4 | s |
|  |  | every | 0.25 | 2 | 1 | s |
| **tether** | a leash between the origin and a foe (the one hit, or the nearest to the aim); it snaps if they get too far · then: on_snap, on_end | origin | caster/owner |  | caster |  |
|  |  | length | 2 | 12 | 6 | m |
|  |  | duration | 0.5 | 6 | 3 | s |
| **dash** | the origin rushes along the aim, hitting what it passes through · then: on_hit, on_end | origin | caster/owner |  | caster |  |
|  |  | distance | 1 | 12 | 6 | m |
|  |  | speed | 8 | 35 | 22 | m/s |
|  |  | width | 0.3 | 2 | 1 | m |
| **leap** | the origin jumps onto the aim point and lands · then: on_land | origin | caster/owner |  | caster |  |
|  |  | range | 1 | 12 | 7 | m |
|  |  | time | 0.25 | 1.2 | 0.5 | s |
|  |  | height | 0.5 | 6 | 2 | m |
| **blink** | the origin teleports toward the aim (never into the abyss) · then: on_end | origin | caster/owner |  | caster |  |
|  |  | distance | 1 | 10 | 5 | m |
| **summon** | places a core-made unit that applies the effects around it every tick · then: on_end | origin | caster/owner/aim/here |  | aim |  |
|  |  | unit | totem/sprite |  | totem |  |
|  |  | count | 1 | 3 | 1 |  |
|  |  | duration | 2 | 15 | 6 | s |
|  |  | hp | 10 | 150 | 40 | hp |
|  |  | every | 0.5 | 3 | 1 | s |
|  |  | radius | 1 | 6 | 3 | m |

### Effects

| part | what it does | parameter | min | max | default | unit |
|---|---|---|---|---|---|---|
| **damage** | hurts · damage · targets foes | amount | 1 | 60 | required | hp |
|  |  | over | 0 | 6 | 0 | s |
| **slow** | slows movement · control · targets foes | duration | 0.2 | 4 | required | s |
|  |  | strength | 0.1 | 0.6 | 0.35 | x |
| **root** | can't move or dodge, can still shoot · control · targets foes | duration | 0.2 | 2 | required | s |
| **stun** | can't act · control · targets foes | duration | 0.1 | 1.5 | required | s |
| **pull** | drags toward a point · control · targets foes | strength | 2 | 30 | 8 | m/s |
|  |  | to | center/caster/owner |  | center |  |
|  |  | gap | 0 | 3 | 0 | m |
| **push** | knocks away from a point · control · targets foes | strength | 2 | 16 | 8 | m/s |
|  |  | from | center/caster/owner |  | center |  |
| **lift** | knocks up into the air (airborne foes can be spiked) · control · targets foes/owner/self | strength | 2 | 16 | 8 | m/s |
|  |  | forward | 0 | 6 | 0 | m/s |
| **shield** | temporary extra health · sustain · targets owner/self/allies | amount | 5 | 120 | required | hp |
|  |  | duration | 1 | 8 | 3 | s |
| **heal** | restores health · sustain · targets owner/self/allies | amount | 5 | 60 | required | hp |
|  |  | over | 0 | 6 | 0 | s |
| **cleanse** | clears slow, root, stun and damage over time · sustain · targets owner/self/allies | - | | | | |
| **reflect** | enemy shots that reach it fly back at the shooter; a reflected shot can't be reflected again · sustain · targets owner/self/wall | power | 0.5 | 1.5 | 1 | x |
|  |  | duration | 0.2 | 3 | 1 | s |
|  |  | radius | 0.8 | 2.5 | 1.6 | m |
|  |  | arc | 30 | 360 | 360 | deg |
| **mark** | reveal (seen through walls and grass), vulnerable (takes more damage) or blight (heals less) · utility · targets foes | mode | reveal/vulnerable/blight |  | vulnerable |  |
|  |  | duration | 0.5 | 6 | 3 | s |
|  |  | amount | 0 | 0.6 | 0.2 | x |
| **buff** | a short boost to one stat (see BUFF_STATS) · utility · targets owner/self/allies | stat | move_speed/guard/damage/fire_rate/crit/dash_refill/glider_cool |  | required |  |
|  |  | amount | 0 | 1 | 0 | x |
|  |  | duration | 0.5 | 8 | 3 | s |
| **signature** | a hand-coded mechanic from the reviewed SIGNATURES list · utility · targets foes/owner/self/allies | id | swap/decoy/bridge |  | required |  |

### Modifiers

| part | what it does | parameter | min | max | default | unit |
|---|---|---|---|---|---|---|
| **bounce** | after a hit, flies on to another foe nearby · on projectile | count | 1 | 3 | 1 |  |
|  |  | range | 2 | 8 | 5 | m |
|  |  | falloff | 0 | 0.5 | 0.2 | x |
| **pierce** | keeps going through foes · on projectile, beam, dash | count | 1 | 5 | 3 |  |
| **chain** | the hit arcs on to nearby foes · on projectile, beam | count | 1 | 4 | 2 |  |
|  |  | range | 2 | 8 | 4.5 | m |
|  |  | falloff | 0 | 0.6 | 0 | x |
| **split** | fires several at once in a fan · on projectile | count | 2 | 5 | 3 |  |
|  |  | angle | 10 | 90 | 30 | deg |
| **delay** | waits before it happens (a telegraph ring shows where) · on projectile, cone, beam, burst, zone, trap, wall, aura, tether, summon | time | 0.1 | 3 | 0.6 | s |
| **linger** | leaves a ground patch where it ends that repeats its effects, weaker; never repeats stun or root · on projectile, cone, beam, burst, dash, leap | duration | 0.5 | 6 | 2 | s |
|  |  | radius | 0.5 | 4 | 1.5 | m |
|  |  | every | 0.25 | 2 | 0.5 | s |
|  |  | strength | 0.1 | 0.5 | 0.3 | x |
| **repeat** | happens again a beat later at the same spot, weaker (an echo) · on projectile, cone, beam, burst, dash, leap, blink, tether | count | 1 | 2 | 1 |  |
|  |  | delay | 0.1 | 2 | 0.8 | s |
|  |  | falloff | 0.3 | 0.8 | 0.5 | x |
| **return** | flies back to the origin after reaching its range, hitting again on the way · on projectile | - | | | | |
| **spike** | extra against airborne foes, slamming them down · on burst, cone, leap, dash | bonus | 0 | 1 | 0.5 | x |
|  |  | stun | 0 | 1.5 | 0 | s |

### Triggers

| part | what it does | parameter | min | max | default | unit |
|---|---|---|---|---|---|---|
| **on_cast** | the player presses the slot key (E for the active) | - | | | | |
| **auto** | the kin decides, from the ability's cue and its personality | - | | | | |
| **on_throw** | the thrown kin hits a foe | - | | | | |
| **on_hit** | every n-th hit of the kin's own attack | every | 1 | 10 | 3 | hits |
| **on_recall** | the kin is recalled to its hunter | - | | | | |
| **on_bond_full** | the bond meter fills | - | | | | |
| **on_low_hp** | the owner or the kin drops below a share of its health | who | owner/kin |  | owner |  |
|  |  | below | 0.1 | 0.6 | 0.35 | x |

### Cues (auto and AI)

| part | what it does | parameter | min | max | default | unit |
|---|---|---|---|---|---|---|
| **foe_in_range** | a foe is within range | range | 2 | 20 | 7 | m |
| **foes_clumped** | several foes stand close together | count | 2 | 5 | 2 |  |
|  |  | radius | 1 | 5 | 3 | m |
|  |  | range | 2 | 20 | 7 | m |
| **owner_hurt** | the hunter is hurt | below | 0.1 | 0.9 | 0.5 | x |
| **owner_falling** | the hunter is falling into the abyss | - | | | | |
| **owner_fighting** | the hunter is in a fight | chance | 0.05 | 1 | 0.3 | x |
| **owner_under_fire** | the hunter is being shot at | - | | | | |

### Signature mechanics (reviewed, hand-coded)

| id | what it does | parameter | min | max | default | unit |
|---|---|---|---|---|---|---|
| **swap** | the target trades places with the caster or its hunter | who | owner/caster |  | owner |  |
| **decoy** | leaves a copy of the origin unit that draws bots' fire | duration | 0.5 | 3 | 1.8 | s |
| **bridge** | abyss along the aim becomes walkable ground for a while | length | 2 | 12 | 8 | m |
|  |  | width | 0.5 | 2 | 1.3 | m |
|  |  | duration | 2 | 10 | 6 | s |

### Buff stats

| stat | what | min | max | default | unit |
|---|---|---|---|---|---|
| move_speed | moves faster | 0.05 | 0.4 | 0.35 | x |
| guard | takes less damage | 0.05 | 0.4 | 0.25 | x |
| damage | deals more damage | 0.05 | 0.35 | 0.2 | x |
| fire_rate | fires faster | 0.05 | 0.3 | 0.2 | x |
| crit | shots crit for the duration | 1 | 1 | 1 |  |
| dash_refill | dodge charges refill at once | 1 | 1 | 1 |  |
| glider_cool | glider heat cooled by this fraction | 0.25 | 1 | 1 | x |

### Owner stats (carry passive and merge passives)

| stat | category | type | carry max | merge max | unit | what |
|---|---|---|---|---|---|---|
| move_speed | movement | float | 0.15 | 0.4 | x | run speed |
| extra_jumps | movement | int | 0 | 1 |  | jumps in the air (1 = a double jump) |
| air_dashes | movement | int | 0 | 1 |  | dodges in the air |
| glide | movement | float | 0.2 | 0.5 | x | glide speed and time (a big glide); never free flight |
| dodge_charges | movement | int | 1 | 1 |  | extra dodge charges |
| dodge_regen | movement | float | 0.3 | 1 | x | faster dodge recharge (1 = instant) |
| armor | defence | float | 0.2 | 0.5 | x | armor durability |
| damage_reduction | defence | float | 0.15 | 0.3 | x | less damage taken |
| knockback_resist | defence | float | 0.5 | 0.75 | x | less knockback |
| shield | defence | float | 0 | 150 | hp | a shield when the merge starts |
| regen | defence | float | 3 | 8 | hp/s | health regen |
| damage | offence | float | 0.1 | 0.35 | x | more damage |
| fire_rate | offence | float | 0.2 | 0.3 | x | faster firing |
| reload | offence | float | 0.2 | 0.3 | x | faster reloads |
| reveal_radius | senses | float | 0 | 20 | m | rivals this near are revealed |

### Stat profile (exactly 20 points per kin)

| stat | base | per point | max points | unit | what |
|---|---|---|---|---|---|
| kin_hp | 60 | 5 | 16 | hp | the kin's health |
| kin_damage | 6 | 1 | 8 | hp/hit | the kin's attack damage |
| kin_speed | 5 | 0.2 | 16 | m/s | the kin's run speed |
| owner_max_hp | 0 | 4 | 8 | hp | hunter max health |
| owner_armor | 0 | 0.04 | 8 | x | hunter armor durability |
| owner_shield | 0 | 4 | 8 | hp | a small shield that refills out of combat |
| owner_regen | 0 | 0.25 | 8 | hp/s | hunter health regen |
| owner_move_speed | 0 | 0.015 | 8 | x | hunter move speed |

### Body

| parameter | min | max | default | unit | what |
|---|---|---|---|---|---|
| size | small/medium/large |  | small |  | small rides a shoulder, medium perches, large is ridden |
| reach | 1 | 2.5 | 1.3 | m | melee reach |
| mass | 0.5 | 3 | 0.8 | x | how hard it is to knock around |

### Gait

| parameter | min | max | default | unit | what |
|---|---|---|---|---|---|
| hop_rate | 3 | 12 | 9 | hops/s | how quickly it bounces when it walks |
| hop_height | 0 | 0.25 | 0.14 | m | how high |
| pace | 0.7 | 1.3 | 1 | x | walk speed at home |

### Mount

| parameter | min | max | default | unit | what |
|---|---|---|---|---|---|
| speed | 0.8 | 1.3 | 1 | x | ground speed while riding |
| jump | 0.8 | 1.3 | 1 | x | jump height while riding |
| turn | 0.5 | 1 | 0.8 | x | how sharply it turns |

### Shot riders

| parameter | min | max | default | unit | what |
|---|---|---|---|---|---|
| splash | 0 | 2 | 0 | m | each shot bursts this wide for part of its damage (0 = none) |
| chain | 0 | 2 | 0 |  | each shot arcs on to this many more foes at half damage |

### Merge

| parameter | min | max | default | unit | what |
|---|---|---|---|---|---|
| duration | 4 | 10 | 6 | s | how long the merge lasts at bond and level 1 |
| grow_duration | 0 | 3 | 1 | s | extra time at full kin level and bond |
| grow_strength | 0 | 0.25 | 0.1 | x | extra strength at full kin level and bond |

### Merge pulse

| parameter | min | max | default | unit | what |
|---|---|---|---|---|---|
| every | 0.4 | 3 | 1 | s | how often the pulse fires |

### Presets

| preset | fills | what |
|---|---|---|
| poison | damage {"over":3.0} | damage over 3s |
| blight | mark {"amount":0.6,"duration":3.0,"mode":"blight"} | healing cut by 60% for 3s |
| frost | slow {"duration":1.5,"strength":0.5} | a strong slow |
| snare | root {"duration":1.4} | a long root |
| jolt | stun {"duration":0.4} | a short stun |
| echo | repeat {"count":1,"delay":0.9,"falloff":0.5} | repeats once at half strength |
| gravity_well | pull {"strength":9.0,"to":"center"} | a strong pull to the centre |
| hook | pull {"gap":1.2,"strength":30.0,"to":"caster"}; projectile {"rope":true,"size":0.18,"speed":30.0} | a yank all the way back to the kin |
| gust | push {"strength":12.0} | a hard shove |
| mirror | reflect {"power":1.0} | full-strength reflect |
