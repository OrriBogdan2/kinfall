# Supervive-style feel for Kinfall (phase 1: camera + movement)

Clean-room rebuild. Nothing here comes from Supervive's files. The values come from the community wiki, published settings guides, frame-by-frame measurements of 60fps gameplay videos, or my estimates. Each one is tagged in `scripts/feel/feel_config.gd`: `[wiki]`, `[guide]`, `[footage]` or `[est]`.

## What's in it

| File | What it does |
|---|---|
| `scripts/feel/feel_config.gd` | Every tunable in one Resource. Save it as a `.tres` to give different weapons or kin their own feel. |
| `scripts/feel/hunter_controller.gd` | CharacterBody3D. Covers WASD, jump, hold-to-glide with heat, abyss lift, feathering, the glider balloon, spiking, dash/ex-dash (or tap/hold), deep mantling, jump pads, cursor aim and the aim laser. |
| `scripts/feel/top_down_camera.gd` | Fixed-angle camera with Supervive's 3 presets, zoom-out while gliding, and a purple screen tint that deepens the further you sink into the abyss. |
| `scripts/feel/jump_pad.gd` | Launch pad that keeps your momentum. |
| `scripts/feel/glide_zone.gd` | Wind rings (cool the glider + boost), jetstreams (no heat, faster), abyss storm clouds (more heat, slower). |
| `scripts/combat/class_profile.gd`, `weapon_profile.gd`, `data/` | Light/medium/heavy classes and 9 guns/swords as data files. See KINFALL_CLASSES.md. |
| `scripts/combat/weapon_user.gd`, `projectile.gd`, `training_dummy.gd` | Weapon firing (guns and swords), projectiles, and practice dummies. See WEAPON_FIRING_DATA.md. |
| `tests/weapons_sim.gd` | Headless weapon check: `godot --headless --path . -s tests/weapons_sim.gd` |
| `scripts/feel/kinfall_input.gd` | Registers default binds at runtime (`kf_*` actions). |
| `scenes/feel_test.tscn` | Playground: islands over an abyss, a raised island to mantle onto, pillars, a jump pad and a debug HUD. |
| `tests/feel_sim.gd` | Headless check: `godot --headless --path . -s tests/feel_sim.gd` |

## Controls (Supervive defaults)
WASD move · Space jump (tap) / glide (hold in air) · Shift dash · Ctrl sneak · LMB/RMB attack (the hunter turns to face the cursor) · F1/F2/F3 switch camera preset, 1/2/3 switch class and 4/5/6 switch weapon in the test scene.

## What the footage showed

Videos studied: TheSixGame's full walkthrough (60fps), Ryan Lemur's Celeste guide and Legend solo queue game, Ryan Lemur's all-abilities video, Tom Kick's gliding guide, and Zik's abyss/spike guide.

**Camera**
- Pitch is ~65° (steep, close to top-down) with ~35° vertical FOV, sitting ~25m away. The screen shows ~28m of ground side to side.
- The hunter stays roughly centered and only shifts when the cursor pans the camera.
- The camera visibly zooms out while gliding.
- The screen goes purple as you sink below island level, and darker the deeper you go.

**Gliding**
- Glide speed is ~5 m/s, about the same as running.
- A glider over the abyss holds at island level rather than sinking. Two players in Tom Kick's guide glide level for ~14s before the heat ring by the nameplate turns hot.
- Lift is what eats heat. In Zik's drill, a player walks off an edge, free-falls ~1s (about 8m deep), opens the glider and is back at island level ~1s later. That one lift burns roughly a quarter to a third of the glider.
- Heat keeps climbing across repeated drop-and-lift (feathering) cycles. It only really cools on the ground.
- A balloon on a string appears about 0.25s after stepping off an edge. It stays at island level and glows purple while you glide, which is the cue that you can be spiked.

**Mantling**
- Falling players who touch an island wall spring back onto it, even from a full second deep. It takes ~0.8s.

**Dash**
- Some kits use tap Shift for a short dash and hold Shift for a longer dash on a longer cooldown. This is in as `dash_hold_for_ex`.
- Dash length is different for every hunter. Kinfall's dodge comes from the weapon, so the values here are only a baseline.

## Rules from the wiki
- Run speed is 465 units (4.65 m/s).
- Shiv's attack range is 850 units (8.5m), which is the aim laser length.
- Jin's dash cooldown is 7s and his ex-dash cooldown is 12.5s.
- Most hits on a glider deal double damage and knock them out of the air, with a stun on landing.
- Spiking an overheated or below-ground glider stuns them and sends them plummeting. Over ground the stun is 0.7s.

## Headless sim results (Godot 4.6.2)
| Check | Result | Footage / source |
|---|---|---|
| Run to 95% speed / stop | 0.07s / 0.07s | snappy MOBA feel |
| Glide over abyss until overheat | 14.1s | ~14s |
| Walk off edge, fall 1s | 9.2m deep, balloon at 0.13s | ~8m, ~0.25s |
| Open glider from there | back at island level in 1.25s, 30% heat | ~1s, ~25–35% |
| Deep mantle from 7m below | ✓ | ✓ |
| Hit while gliding | x2 damage, glider drops | wiki |
| Jump | 1.28m apex, 0.62s | [est] |
| Mini / ex dash | 3.9m / 6.7m | [est] |

## Combat hooks for Kinfall
`incoming_damage_multiplier()` · `notify_damaged()` (drops gliders) · `try_spike()` / `is_spikeable()` · `depth_below_ground()` · `launch(impulse)` · `main_ability_on_cooldown`. Signals: `dashed`, `glide_started`/`glide_ended`, `overheat_started`, `overheat_tick(damage)`, `mantled`, `spiked`, `fell_into_abyss`.

## Still estimates
- Jump height: I didn't find a clean plain jump in any of the videos.
- Dash distance per weapon.
- Glider damage while overheated, spike plummet speed, and the jump pad's launch strength.

Tune them in `feel_config.gd`, then rerun the sim.
