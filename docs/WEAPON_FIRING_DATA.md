# Weapon firing data: how attacks work in Supervive, and what Kinfall does with it

Sources:
- Frame-by-frame measurements of 60fps practice-range footage: Ryan Lemur's all-abilities video and the TheSixGame walkthrough.
- Patch notes (Steam/SteamDB) and the wiki.

Units: Supervive's 1 unit = 1 cm. Tags: `[footage]`, `[patch]`, `[wiki]`, `[gap]` = never published.

## 1. The big rules

| Rule | Detail | Source |
|---|---|---|
| **No hitscan** | Every attack is a projectile, bolt, shot or beam. Even fast rifles fire real projectiles | [patch]/[wiki] |
| Standard shot speed | **32–40 m/s**: Shiv 32.5 (35 at 1.0, 40 empowered), Crysta 36 | [patch] 1.0–1.04 |
| Rifle tracers | Too fast to follow on video (≥100 m/s visually); streak visible ~0.08s | [footage] |
| Heavy single shots | Sniper round visibly travels ~30 m/s, so it can be dodged | [footage] |
| Shots are height-aware | Hit volumes are 3D (patch fixes for targets above or below the shooter) | [patch] Jun 2025 |
| Range is exact | Projectiles stop at max range ("tech change to precisely control projectile ranges") | [patch] Nov 2024 |
| Fall-off | Elluna: none up to 50% of range, up to −50% past it. Saros: reduced up close, full after 9m. Shrike: 50% point-blank, full from ⅓–½ range | [wiki]/[patch] |
| No crits or headshots | Instead: blade-tip sweet spots, perfect-release bonuses (bow), backstabs (+30%), executes on low HP | [wiki]/[patch] |
| Global damage | S2: all damage ×0.90 | [patch] Nov 2025 |

## 2. Per weapon type

| Type | What Supervive does | Numbers | Source |
|---|---|---|---|
| **Auto rifle** (Ghost) | Hold to fire. 30-round magazine. Damage per round falls over the first 10 rounds to 50%, so short bursts are rewarded | ~12 shots/s (0.08s apart) | [wiki] + [footage] |
| **Burst blaster** (Carbine) | Up to 3 quick shots, then reload. First shot of a full magazine hits harder beyond ~50% range. Dashing gives a free empowered shot | reload time [gap] | [wiki] |
| **Shotgun** (Kingpin) | 7 slugs in a wide fan; two white cone lines show the spread on the ground. Slugs **slow down and stop** at ~4.5m, leaving a row of dots. **Accuracy gets worse with every shot; dashing resets it.** Damage by slugs landing (1→7): 45.7 / 57.9 / 70.1 / 82.4 / 88.3 / 94.1 / 100% | one shot every **~0.9s**, cone **~70°** | [footage] + [patch] Nov 2025 |
| **Minigun** (Hudson) | Hold to fire. Spread starts wide and tightens the longer you hold; standing still tightens it faster. Spin up (hold RMB) for more damage, range (11.5 → 13m) and fire rate, but you slow to 50% and turn at 45°/s max. Letting go when spun up = ~1s you can't fire | 0.1s per shot | [wiki]/[patch] |
| **Sniper** (Shrike) | Press → **~0.6–0.7s aim with a laser enemies can see**, then the shot. 50% damage point-blank, full from ⅓ range. "Warmup" sound plays even in fog of war | one shot per **1.5s**; round ~30 m/s | [footage] + [patch] |
| **Bow / charge** (Myth) | Hold to draw: green stage at 0.5s, blue stage up to 0.6s more (1.1s total). Damage, speed and distance grow. Releasing at the perfect moment gives bonus damage and a smaller self-slow | window [gap] | [wiki] |
| **Rapid darts** (Celeste) | Hold for a burst of semi-homing darts ending in 3 bigger darts | — | [wiki] |
| **Flamethrower** (Felix) | Hold. 0.35s before you can fire again after letting go, plus a 0.35s self-slow | 2 burn stacks every ~65ms | [patch] |
| **Thrown weapon** (Oath hammer) | Throw (pierces), press again to recall. Minimum throw 5m; 0.25s recall lockout "so you can't autoclick" | — | [patch] |
| **Idle-charged shot** (Void, Elluna) | After a short pause in firing, the next shot is empowered (faster or further, passes terrain) | idle time [gap] | [wiki] |

## 3. Melee

| Rule | Detail | Source |
|---|---|---|
| Swing speed | Combo swings land **~0.2s apart**; each swing's trail shows for only ~2 frames | [footage] (Brall) |
| Reach | Blade arc ~1.7m; a finishing spin ~2.5m; Brall's swing radius 3.2m (Sep 2025) | [footage]/[patch] |
| Hitbox shape | A wedge ("slice") matching the animation, not a box. Width tuned to match the visual effect | [patch] |
| Sweet spot | The central tip of the blade only (Brall, Nyx's 3rd hit) | [patch] Jan 2025 |
| Tap vs hold | Tap = 3-hit combo (Wukong, Jin, Nyx); hold = charged attack. Jin: "release the moment it's fully charged" | [wiki]/[patch] |
| Lunges | Many swings push you forward. **Repeated lunges get weaker: −25% per use within a short window**; lunges on the ground don't count toward it (Wukong) | [patch] Jul–Sep 2025 |
| Aim during lunges | Jin's dashes curve to follow the cursor (for backstab angles) | [patch] Nov 2025 |
| Knockback | Players **steer knockback with WASD**. High influence: Brall LMB, Beebo tap, Jin's first hit. Medium: charged hits | [patch] Jun 2025 |
| Knockback and lag | Small knockbacks caused rubber-banding at high ping, so some were removed | [patch] Dec 2024 |
| Flick tech | Sweeping the aim mid-swing to hit several enemies was removed | [patch] Sep 2025 |

## 4. Attacking while moving, buffers, telegraphs

| Rule | Detail | Source |
|---|---|---|
| Input buffer | Press during a lockout and it fires when allowed, within **0.2s** (was 0.3) | [patch] Jan 2025 |
| Self-slows | Common on heavy or charged attacks: minigun 50%, Joule LMB 0.4s, Felix 0.35s after release, bow while drawing, Wukong combo | [patch] |
| Turn limits | Big wind-ups restrict turning (minigun 45°/s, Brall and Kingpin windups) | [patch] |
| Wind-down | Some attacks and dashes have recovery frames where you can't open the glider | [patch] |
| Telegraphs | Sniper laser visible to enemies; red ground decals on big attacks; warning icon over a charging melee player; cast bar on the health bar; separate tap and hold cast bars | [patch]/[footage] |
| Aim UI | Aiming laser (can extend past the cursor for piercing shots), ground circles showing hitboxes (including targets above or below you), cooldown ring on the cursor | [guide]/[patch] |
| Aim-down-sights | Ctrl (sneak) is listed as "Sneaking/Aiming-down-sights". The exact effect isn't published | [patch]/[gap] |
| Attacking while gliding | Not documented | [gap] |
| Netcode | Client-predicted movement with server correction. Tick rate and lag compensation aren't published | [patch]/[gap] |

## 5. Hit feedback

- Floating damage numbers.
- A broken-armor marker on health bars.
- "Hit confirm" effect (can be toggled).
- HUD damage effect when you're hit (0.5s recommended).
- Fights show as pulses on the minimap.
- Knocking someone refills mana and gives a dash charge back.
- Not published: hit-stop and screen shake [gap].

## 6. Attack speed

- Attack speed is its own stat, separate from Ability Haste (which skips dashes and possibly primaries).
- Items give +6–20% primary attack speed.
- No formula or cap is published [gap].

---

## What Kinfall now does with this (`scripts/combat/`)

- **`projectile.gd`:** real projectiles for every gun:
  - Each frame does a sweep test, so fast shots can't pass through targets.
  - Slowdown support (shotgun slugs stop at max range).
  - Piercing and hit radius.
  - Tracer length scales with speed.
- **`weapon_user.gd`:** fires whatever WeaponProfile is equipped.
  - **Guns:** auto, burst, single shot, spin-up and sniper warmup. Magazines with auto-reload; spread that grows per shot and recovers; dashing resets spread; minigun spread that tightens; rifle damage that drops when holding fire; fall-off near and far; shotgun slug-count damage table; slowed while firing; lockout and slow after letting go.
  - **Swords:** tap for the combo, hold to charge. Wedge-shaped hits with a blade-tip sweet spot; lunges that weaken when repeated (charged lunges don't); lunge hits land at the end of the lunge; knockback the target can steer.
- **`training_dummy.gd`:** target with floating damage numbers, a hit flash, knockback and DPS tracking.
- **The hunter** now has HP, `take_hit(info)` (gliders take ×2, damage heat, spike credit, steerable knockback, stun), and a speed multiplier weapons set while firing.

Headless results (`tests/weapons_sim.gd`, 4s of fire at a 1,050 HP dummy):

| Weapon | Measured | Notes |
|---|---|---|
| SMG | 180 DPS | 36 of 36 hits |
| Sniper | 96 DPS | first hit 0.75s after press (0.6s aim + travel) |
| Twin Blades | 175 DPS | charged stab: 120, lunged 3.5m |
| Rifle (held) | 141 DPS | 30 rounds, then a 1.8s reload |
| Burst Rifle | 250 DPS while firing | 186 including reloads |
| Longsword | 170 DPS | charged 160, lunged 2.7m |
| Shotgun | 120 DPS at 3m | spread grows to the 24° max after a few shots |
| Minigun | 208 DPS | first shot after a 0.7s spin-up |
| Greatsword | 192 DPS | charged slam with sweet spot: 260 |
