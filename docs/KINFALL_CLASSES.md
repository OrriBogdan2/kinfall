# Kinfall classes and weapons (v1 numbers)

These are Kinfall's own numbers, set inside the ranges Supervive's roster used (docs/SUPERVIVE_DATA.md §6). They're data files you can retune without touching code:

- `data/classes/light.tres`, `medium.tres`, `heavy.tres` (script: `scripts/combat/class_profile.gd`)
- `data/weapons/*.tres`, 9 weapons (script: `scripts/combat/weapon_profile.gd`), fired by `scripts/combat/weapon_user.gd`
- `tools/build_profiles.gd` regenerates all of them and prints the damage table below. Run it with `godot --headless --path . -s tools/build_profiles.gd`.

`HunterController.class_profile` (or `apply_class()` at runtime) pushes a class's movement, dash and glider numbers into the controller. In the test scene, press 1/2/3 to switch classes, 4/5/6 to switch weapons, and attack the three dummies with LMB.

## Classes

| | Light | Medium | Heavy | Supervive range |
|---|---|---|---|---|
| HP (level 1) | 900 | 1,050 | 1,400 | 880–1,596 |
| HP at level 15 | 1,656 | 1,932 | 2,576 | +~6%/level |
| Run speed | 4.85 m/s | 4.65 m/s | 4.40 m/s | 4.15–4.9 |
| Hitbox radius | 0.35m | 0.40m | 0.50m | — |
| Dash | 4.5m, every 6.5s | 3.8m, every 9s | 3.2m, 2 charges, 12s each | 6.5–15s |
| Air dash (ex) | 7m, 12s | 6m, 13s | 5m, 15s | Jin: 12.5s |
| Knockback taken | ×1.18 (weight 0.85) | ×1.0 | ×0.74 (weight 1.35) | Beebo is "10% lighter" |
| Glide before overheat | ~17s (heat ×1.2) | ~14s | ~12s (heat ×0.85) | ~14s; Glide Boots +40% |
| Knock heal | 250 | 250 | 250 | 250 (1.0) |

How the classes differ:
- **Light:** fragile and slippery. Fastest dash, longest glide, gets thrown furthest by hits.
- **Medium:** the Supervive baseline.
- **Heavy:** most HP, slowest, two short dashes instead of one long one, hard to push off ledges. That last point matters a lot in an abyss game.

## Weapons

Each class has two guns and one sword. Firing behavior is measured from Supervive footage and patch notes (see WEAPON_FIRING_DATA.md).

| Weapon | Class | How it fires | Per hit | Rate | Range | Magazine / reload |
|---|---|---|---|---|---|---|
| SMG | Light | Hold; spread grows while firing; damage drops to 60% past 60% of range | 20 | 14/s | 7m, 55 m/s shots | 36 / 1.4s |
| Sniper | Light | Press → 0.6s aim with a laser enemies can see → one round at 32 m/s you can dodge. 50% damage point-blank, full from half range. Slowed while aiming (Shrike) | 240 | every 1.5s | 16m | 5 / 2.2s |
| Twin Blades | Light | Tap for a 3-hit combo with small lunges; hold 0.5s for a 4.5m lunging stab (Jin) | 38 / 38 / 64; charged 120 | 0.22s per swing | 2.0m, 110° | — |
| Rifle | Medium | Hold; damage falls to 60% over the first 10 rounds, so short bursts win (Ghost) | 28 | 12.5/s | 9.5m, 110 m/s | 30 / 1.8s |
| Burst Rifle | Medium | 3-round bursts | 40 ×3 | burst every 0.48s | 10.5m, 60 m/s | 27 / 1.5s |
| Longsword | Medium | 3-hit combo, +25% on the blade tip; hold 0.8s for a 3m lunge | 46 / 46 / 74; charged 160 | 0.28s | 2.4m, 140° | — |
| Shotgun | Heavy | 7 slugs in a 60° fan that slow down and stop at 5m. Spread grows +8° per shot (max +24°); dashing resets it. One slug landing still does 46% (Kingpin) | 7 × 25 | every 0.9s | 5m | 6 / 1.8s |
| Minigun | Heavy | Hold: 0.7s spin-up, then spread narrows from 14° to 3° over 1.5s. Slowed to 50% while firing; +1.5m range once spun up (Hudson) | 17 | 16.7/s | 10m (11.5m spun) | 150 / 3s |
| Greatsword | Heavy | Slow 3-hit combo, +30% on the tip; hold 1s for a slam that stuns 0.6s and knocks back hard (Brall: 3.2m reach) | 64 / 64 / 104; charged 200 | 0.4s | 3.2m, 160° | — |

## Time to kill (primary weapon only, every hit lands, reloads included, no armor)

| Weapon | DPS | vs Light 900 | vs Medium 1,050 | vs Heavy 1,400 |
|---|---|---|---|---|
| SMG | 184 | 4.9s | 5.7s | 7.6s |
| Sniper | 94 | 9.5s (4 shots) | 11.1s (5 shots) | 14.8s (6 shots) |
| Twin Blades | 212 | 4.2s | 5.0s | 6.6s |
| Rifle (held) | 135 | 6.7s | 7.8s | 10.4s |
| Burst Rifle | 186 | 4.9s | 5.7s | 7.5s |
| Longsword | 198 | 4.6s | 5.3s | 7.1s |
| Shotgun | 146 | 6.2s | 7.2s | 9.6s |
| Minigun | 213 | 4.2s | 4.9s | 6.6s |
| Greatsword | 193 | 4.7s | 5.4s | 7.2s |

Notes on the table:
- **Rifle:** the number is for holding the trigger. Tapping keeps damage near full, ~250+ DPS while firing.
- **Sniper and shotgun:** built around one big hit (240, and up to 175 point-blank), not DPS.

**Why it's set this way.** Supervive fights are long by shooter standards, with abilities doing a big share of the damage. With guns and swords alone, ~5s of perfect aim to kill a Medium leaves room for dashing, gliding and knocking people into the abyss to matter more than raw DPS. Once kin abilities are in, real TTK will drop to ~3s.

- **Armor stretches these times.** Common armor (20% reduction) makes them ~1.25× longer; Legendary (35%) makes them ~1.5× longer.
- **Rifle DPS is the tapping number.** Held fire averages lower because of the falloff.
- **Sniper and shotgun are built around one big hit** (240, and up to 176 point-blank), not DPS.

## Also built in this update (1.0 glider rules)

- Overheated gliders slow to 60% speed.
- Damage while gliding adds heat (250 damage = 30 heat), and damage that pushes heat to 100% spikes instantly: 4 hits of 250 on a fresh glider.
- Wind rings cool the glider by 35 heat and add 4 m/s.
- Jetstreams stop heat gain and speed you up ×1.4.
- Abyss storm clouds double heat gain and slow you ×0.7.
- Spiking someone cools your own glider by 50 (call `on_spiked_enemy()` on the attacker).
- The test scene has one of each zone over the gap.

## Hooks for the combat code
- `notify_damaged(amount)`: returns true if the hit spiked a glider (credit the attacker).
- `knockback(impulse)`: divided by the target's class weight.
- `refund_dash_charge()`: call on knock (Supervive 1.0 knock reward), alongside healing `knock_heal`.
- `incoming_damage_multiplier()`: ×2 while gliding.
- `WeaponProfile.dps()`: sustained DPS, for balance checks.
