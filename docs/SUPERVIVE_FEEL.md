# Supervive-style feel for Kinfall (phase 1: camera + movement)

Clean-room rebuild. Nothing here comes from Supervive's files. The numbers come from the community wiki, published settings guides, or my estimates, and each one is tagged in `scripts/feel/feel_config.gd`.

## What's in it

| File | What it does |
|---|---|
| `scripts/feel/feel_config.gd` | Every tunable in one Resource. Save it as a `.tres` and give different weapons or kin different feel profiles. |
| `scripts/feel/hunter_controller.gd` | CharacterBody3D. Covers WASD, jump, hold-to-glide with heat, abyss lift, mini-dash/ex-dash, mantling, jump-pad launches, spike, cursor aim and the aim laser. |
| `scripts/feel/top_down_camera.gd` | Fixed-angle camera with Supervive's 3 presets: Locked, Standard Dynamic and Fully Dynamic. |
| `scripts/feel/jump_pad.gd` | Launch pad that keeps your momentum (dash into it for extra speed). |
| `scripts/feel/kinfall_input.gd` | Registers default binds at runtime (`kf_*` actions), so project.godot doesn't need editing. |
| `scenes/feel_test.tscn` | Playground: two islands over an abyss, a ledge, pillars, a jump pad and a debug HUD. |
| `tests/feel_sim.gd` | Headless check: `godot --headless --path . -s tests/feel_sim.gd` |

## Controls (Supervive defaults)
WASD move · Space jump (tap) / glide (hold in air) · Shift dash · Ctrl sneak · LMB/RMB attack (hunter faces cursor) · F1/F2/F3 camera preset in the test scene.

## Rules this copies
- **Move speed** 4.65 m/s (465 units). It's the same for every hunter I checked. Accel/decel are near-instant.
- **Dash**: Shift does a mini-dash (7s cooldown). Pressing it while airborne or while the mini-dash is on cooldown does a longer ex-dash (12.5s cooldown). Direction comes from WASD and falls back to the cursor.
- **Momentum carries**: dash or jump-pad speed bleeds off slowly in the air and in glide, and fast on the ground.
- **Glide**: hold Space while airborne. Gliding builds heat, and getting hit builds it faster. When overheated you take damage over time and can be spiked (0.7s stun, then you plummet).
- **Abyss**: opening the glider below ground level gives strong lift, then brakes at ground level. Releasing just before ground level turns the lift into height (feathering). So you can hover over the abyss until heat runs out.
- **Mantle**: if you're falling or near the top of a jump and moving into a wall whose top is within 3m, you pop up onto it.
- **Camera presets** (from the settings guides): Standard is deadzone 0.2 / maxzone 0.8 / pan 6 / speed 7 / quadratic. Fully Dynamic is 0.1 / 0.9 / 10 / 10 / locks to the cursor. Every preset zooms out while gliding.

## Measured in the headless sim (Godot 4.6.2)
| Check | Result |
|---|---|
| 0 → 95% run speed | 0.07s |
| Stop | 0.07s |
| Jump | 1.28m apex, 0.62s airtime |
| Mini / ex dash | 3.9m / 6.7m |
| Glide over abyss until overheat | ~4.9s |
| Abyss lift from 6m below | 0.9s back to ground level |
| Feathered release at -3m | peaks 1.15m above ground |
| Mantle from 2.5m below a ledge | ✓ |
| Jump pad | 4.7m apex |
| Fall with no glide | dies, respawns |

## Measured from footage (60fps gameplay, frame-stepped)
- **Camera pitch ~65°** (not the 56° I first guessed). Ground circles near screen center are ~0.91 as tall as wide.
- **Vertical FOV ~35°**, **distance ~25m**. A hunter running at 4.55 m/s scrolls ~175px/s on a 1080p frame, so the screen shows ~28m of ground side to side.
- Hunters sit roughly at screen center and only shift when the cursor pans the camera.
- Some kits use **tap Shift = short dash, hold Shift = longer dash on a longer cooldown**. Turn on `dash_hold_for_ex` for those.

## Tuning against footage (the remaining [est] values)
1. Grab a clean 60fps Supervive clip (pro VOD on YouTube) and the same shot from the test scene.
2. **Camera first**: match the pitch angle, FOV and distance by how big a hunter looks on screen and how much ground fits in frame. Those three numbers decide most of the "looks like Supervive" feeling.
3. **Then timing**: count frames in the clip for jump airtime, dash length (measured in hunter widths) and glide sink rate. Change those values in `feel_config.gd` and rerun `feel_sim.gd`.

## Dropping into Kinfall
Copy `scripts/feel/` into the project and put a `HunterController` on the player with its collision capsule offset up by half its height (origin at the feet). Point `visual_path` at the mesh root and add a `TopDownCameraRig` with `target_path` set to the player. Hook these into combat: `notify_damaged()`, `spike()`, `is_spikeable()`, `main_ability_on_cooldown`, and the signals `overheat_tick(damage)` and `fell_into_abyss`.

## Not in phase 1
Networking/prediction, real attacks and abilities, animations, VFX, and kin throw/recall. Kin throw/recall is the next phase and plugs into `launch()` and the aim point.
