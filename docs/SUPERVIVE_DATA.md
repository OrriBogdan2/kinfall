# Supervive reference data: combat, hunters, match systems

Everything we didn't yet have, collected from public sources: the community wiki (supervive.wiki.gg), Steam/SteamDB patch notes, guides, and frame-by-frame measurements of 60fps gameplay video. Nothing comes from game files.

**How to read it**
- Units: Supervive is Unreal, so 1 unit (uu) = 1 cm. Values are shown as uu / meters.
- Game eras: Open Beta (Nov 2024) → Season 0 (Jan–Apr 2025) → **1.0 (24 Jul 2025, reworked map and systems)** → Season 2 (21 Oct 2025) → shutdown (Feb 2026). Where eras conflict, the latest dated value wins, and the date is noted.
- Tags: `[wiki]` wiki page, `[patch]` patch notes (most reliable), `[footage]` measured from video, `[gap]` not published anywhere.
- Already built into the controller (see SUPERVIVE_FEEL.md): camera, run speed, glide, heat, abyss lift, balloon, mantle, dash.

---

## 1. Combat feel (what you see and feel when fighting)

| Thing | Value | Source |
|---|---|---|
| Rifle tracers (walkthrough hunter) | Near-instant: cross ~4m in 2–3 frames (~100 m/s+). Rapid bursts, a shot every ~0.07–0.13s | [footage] |
| Projectile speeds in general | Not published for any hunter. Measure per weapon or tune | [gap] |
| Finisher on a downed enemy | Hold E → ~3s cinematic: camera cuts in close on the two players, then fades back to the normal camera | [footage] |
| Knockback | Players can steer knockback with WASD ("directional influence"); attacks are rated high or medium influence. No distance values published | [patch] Jun 2025 |
| Knock reward (1.0) | Small heal (250 HP) + dash cooldown reset (multi-charge dashes get 1 charge back) | [patch] Jul / Sep 2025 |
| Hit-stop / hitflash / screen shake | Not documented anywhere | [gap] |
| Damage display | Floating numbers; overkill not counted on stat screens | [patch] Dec 2024 |
| Global damage/heal tuning (S2) | All outgoing damage ×0.90, healing ×0.65 | [patch] Nov 2025 |

## 2. Down, finish, revive, respawn

| Rule | Value | Source |
|---|---|---|
| Knocked | 0 HP → you become a **wisp**: a slow-moving orb that attacks can't hurt. Its own wisp-HP drains over time | [wiki] |
| Bleed-out | **15s** (was 30s) | [patch] Dec 2024 |
| Ally revive | Ally stands on the wisp: a green revive bar fills and the drain stops. Step off and both drain again. Duration: "a few seconds" | [wiki] / [gap] |
| Enemy stomp | Enemy standing on the wisp drains it fast and blocks revives | [wiki] |
| Execute | Press E on the wisp → finisher animation (~3s) → wisp dies → deathbox | [wiki] + [footage] |
| Last player alive knocked | Whole team eliminated instantly (no wisp) | [patch] Aug 2025 |
| Deathbox | Spawns where you died (abyss deaths: near the killer's last ground position). Color shows gold inside. Holds grips, kicks, relics; enemy box armor comes at full durability | [wiki] / [patch] |
| Deathbox revive | Teammate holds E on the box. Channel length not published | [gap] |
| Revive beacons | Stand on one: **6s** channel revives the whole team (Everbeacons: **10s**, unlimited uses). Two teams on it pauses the timer. Plays a map-wide sound | [patch] Jul 2025 |
| Resurrection sickness | **12s** after a beacon respawn: −25% damage dealt, −25% healing received | [patch] 1.0 |
| Day 1 | Killed on Day 1 → auto-respawn on nearest ally (unranked) | [patch] 1.0 |
| Team respawn timer (S0) | 30 / 35 / 40 / 45 / 50 / 55s by respawns used. 1.0 "significantly reduced" (no numbers) | [patch] |
| Loss on death | 50% gold; 33% Prisma (persistent currency) | [patch] |
| Leave match | Option after 90s dead; free leave after 3 min | [patch] |

## 3. HP, armor, healing, mana

**Armor** (damage reduction applied first; the rest hits both HP and armor durability; 0 durability = no reduction) [wiki, May 2025]

| Tier | Reduction | Durability |
|---|---|---|
| Common | 20% | 2,500 |
| Uncommon | 25% | 2,500 |
| Rare | 30% | 2,500 |
| Legendary | 35% | 3,000 |
| Exotic | 35% | 3,500 |

- Armor levels up by dealing damage: 2k / 3.6k / 12k / 20k (1.04 values).
- Storm damage ignores armor.
- "Armor shred" damages durability only.
- Repairs at 1.0: Armor Shards or the Forge.

**Healing**
- **Vive Brew:** 304 HP + 120 mana after 1s, 200 gold, stacks to 8. Cancelled by damage. You are Vulnerable while drinking. Cleanses anti-heal.
- **Hypervive:** full HP and mana, but slows you 60% and makes you Vulnerable for 5s.
- **Anti-heal:** 70% healing reduction (S2).
- **Base camp:** standing on it heals.
- **Out-of-combat regen:** not published [gap].

**Mana** (universal)
- Regen pauses 4s after spending.
- Regen rate rises with level: 4.5 → 9/s over Lv1–10 (Aug 2025).
- Base max mana: not published [gap].

## 4. Crowd control

| Effect | Rule | Typical duration |
|---|---|---|
| Stun | No movement, no air control, no abilities | 0.5–2.0s (median 1.2) |
| Spike (glider) | Stun + plummet. Over ground 0.7s stun; over the abyss near-certain death | 0.7s |
| Dunk | Stun + downward slam, both scale with missing HP. Lethal over the abyss only below ~70% HP | 0.35–1.0s |
| Grounded | Can't use movement abilities (Shift, movement items) | per ability |
| Root | Can't move | ~1.1–1.4s |
| Slow | % movespeed | 10–65%, 0.5–6s (median 2.5) |
| Silence | No abilities, powers or consumables | e.g. 5s on recall |
| Daze | Ghost's version of stun | 1.2 / 2.0s |
| Anti-heal | −70% healing | 1–6s (median 4.5) |
| Vulnerable | Takes 2× damage (gliders, healing players, staggered monsters) | 5s on monsters |
| Incorporeal | Can't be hit, projectiles pass through | e.g. 0.1s dash |
| Knockback | Pushes you; you can steer it with WASD | no values |

No global CC immunity or diminishing returns; only items grant immunity [patch].

## 5. Glider rules at 1.0 (now built into the controller; see KINFALL_CLASSES.md)

- Heat replaced fuel at 1.0.
- **Heat rises** from gliding, from taking damage while gliding, and inside abyss storm clouds.
- **Overheat from normal gliding:** slower glide + damage over time + spikeable.
- **Damage that pushes heat to 100%:** instant spike.
- **Heat drops** from touching ground, flying through **wind rings**, and **spiking someone**.
- Monsters can't spike.
- Glide Boots give +40% heat capacity.

## 6. Class and weapon baselines (from all 24 hunters' stats)

We're not porting hunters. Their wiki stats are only used here to work out believable numbers for Kinfall's light, medium and heavy classes and for guns vs swords.

**Classes**

| Class | HP (Lv1) | HP per level | Movespeed | Dash cooldown | Hunters these numbers come from |
|---|---|---|---|---|---|
| Light | 880–980 | ~6% of base | 4.65–4.9 m/s | 6.5–7s (ex/air dash ~12.5s) | Jin, Shiv, Myth, Shrike |
| Medium | 980–1,100 | ~6% | 4.55–4.65 m/s | 9–12s | Ghost, Carbine, Joule, Void, Crysta |
| Heavy | 1,200–1,600 | ~6% | 4.3–4.55 m/s | 12–14s (often 2 charges) | Kingpin, Wukong, Brall, Felix, Hudson |

- Spread across the whole roster: HP 880–1,596 (median 1,030); movespeed 4.15–4.9 m/s (median 4.6). Speed differences between classes are small (±0.3 m/s); HP does most of the work.
- Other cooldowns: utility/Q abilities 8–30s (median 12.5), ultimates 35–80s (median 50).
- Heal on knocking someone: 250, or 500 for some kits.

**Guns** (ranged hunters)

| Type | Pattern from Supervive | Range |
|---|---|---|
| Rifle | 30-round magazine; damage falls off to 50% over the first 10 rounds of a burst (Ghost) | ~9m |
| Burst blaster | 3 shots then reload; first shot from a full magazine hits harder at long range (Carbine) | ~9m |
| Shotgun | 7 pellets per shot (Kingpin) | short |
| Minigun | Spin up first; range 11.5m, 13m once spun up; moving slows you (Hudson) | 11.5–13m |
| Sniper | One heavy shot every 1.5s; 50% damage point-blank, full damage from half range (Shrike) | long |
| Bow / charged | Hold to charge up to 1.1s; damage climbs in stages (Myth) | ~9m |

- Known primary ranges: 8.5m (Shiv), 9.5m (Void), 11.5m (Hudson).
- Tracers look near-instant on screen (~100 m/s+) [footage].

**Swords / melee** (melee hunters)

| Pattern | From |
|---|---|
| Tap for a 3-hit combo, hold for a flurry | Wukong |
| Charged stab that lunges you forward, then a follow-up and a spin; 0.2s between swings | Jin |
| Quick swing with a "sweet spot" bonus at the blade tip, plus a charged blast | Brall |

**Shared timings**
- Charge to full: 0.5–1.25s (median 1.0).
- Cast / wind-up: 0.1–0.65s (median 0.45).
- Stuns: 0.5–2.0s (median 1.2).
- Slows: 10–65% for 0.5–6s.

## 7. Levels and progression in a match

- Max level **15**. Abilities rank up to 4. Ultimate unlocks at level 7.
- XP to reach Lv1–6: 45 / 55 / 85 / 100 / 115 / 300 (Feb 2025). No full table published.
- Each level: +5 Power.
- Daily soft cap (Days 1–4 / Endgame): 6 / 9 / 11 / 13 / 15. Past the cap, monsters give 20% XP.
- XP comes on knock, not kill. Each repeat knock on the same person is worth 50% less.
- Haste: cooldown × 1/1.15^x.

## 8. Match format and flow

- **Players:**
  - Beta: 40 (10 squads of 4).
  - 1.0: **36** (12 trios).
  - Season 2: up to 24 (8 teams of 3).
  - Other modes: Arena 4v4, Duos.
- **Length:** ~15–20 min. Last team standing wins.
- **Drop:**
  - A dropship flies a random path. The team's Drop Leader picks a point and the team drops as one pod, steering with WASD. Players can detach.
  - Enemy landing spots are visible during the drop.
- **Day/night clock** (wiki, ~S0, edited Aug 2025):

| Phase | Starts | Length | Notes |
|---|---|---|---|
| Day 1 | 0:00 | 4:20 | |
| Night 1 | 4:20 | 1:15 | Night bosses; meteors land ~45s in |
| Day 2 | 5:35 | 1:30 | |
| Night 2 | 7:05 | 1:15 | Supply drop (1 fast crate); Most Wanted |
| Day 3 | 8:20 | 1:10 | |
| Night 3 | 9:30 | 1:15 | Supply drop (3 crates) |
| Day 4 | 10:45 | 1:00 | |
| Night 4 | 11:45 | 1:15 | Major Monster / endgame boss |
| Endgame 1 | 13:00 | 0:50 | |
| Endgame 2–4 | 13:50 | 1:55 each | Most Wanted at each storm close |

- **Storm:** 8 closes, at 2:30, 5:45, 8:30, 10:55, 13:10, 14:30, 16:25 and 18:20. Damage and radii aren't published [gap]. The final-circle search radius was widened 20% at 1.0.
- **Day start:** creep camps respawn and train loot resets.
- **Storm Shifts:** one random rule per lobby, e.g. Global Oracles (map-wide scan every 10s), Bullet Trains, Final Destination (end circle shown at start), Glider Engines (unlimited glide).

## 9. Map and world (The Breach)

- **Layout:** 8 regions, 26 biomes of floating islands over the abyss. Map size isn't published [gap].
- **The Heart (center):**
  - Unlimited revive beacon.
  - Touching the orb kills.
- **Kobayashi's (town):**
  - PvP banned by day: damaging another player marks you **Criminal** and guards hunt you.
  - PvP is allowed at night.
- **1.0 abyss rework:** islands split into drifting shards.
- **Abyss traversal:**
  - **Wind rings:** speed boost and lower heat.
  - **Jetstreams/wind tunnels:** stop heat gain, add speed.
  - **Abyss storm clouds:** slow you, more heat.
  - **Skysharks:** 2-seat vehicles, faster over the abyss, fuel-limited, explode when destroyed.
- **Movement objects:**
  - **Jump pad:** arms in 2s; lasts 30s, or 10s after first use; 3,000 gold.
  - **Deployable fan:** 2 charges, lasts 60s.
  - **Emergency platform:** 30s, abyss only.
  - **Grind rails:** grabbable from below.
  - **Geysers, warp anomalies.**
  - No ziplines.
- **Train:** runs the map nonstop, with a chest puzzle, a revive beacon in the rear car, and a storm-immunity box.

## 10. Economy, base camps, vaults, creeps

- **Coin** (in-match):
  - Sources: objectives, monsters, vaults. Lose 50% on death.
  - Gold pickups get vacuumed from 3m.
  - Quest rewards: e.g. 2,000 for 3 kills or a team wipe, 500 for a vault.
- **Shops:**
  - Base shops sell Grips and Kicks.
  - Relic shops sit at Forges/outposts.
  - Everywhere: Vive Brew 200, Armor Repair 400.
  - Consumables: Hypervive 1,000, Pocket UAV 1,500, Jump Pad 3,000, Two-Way Teleporter 3,000, Most Wanted 3,000, Mobile Respawn Beacon 8,000.
- **Rarity colors:** grey, green, blue, purple, gold, red (Exotic).
- **Loadout (1.0 Armory):** 2 Relics, 2 Grips, 5 Perks, 1 Kicks, 1 Armor. Unlock items between matches, then buy them in-match.
- **Base camp:**
  - Capture by standing on it (one per team).
  - Benefits: heals and restores mana, gives vision around it, alerts on enemy capture attempts, has a shop and armor repair.
  - Recall to it: **4s** channel (B), cancelled by damage.
- **Vaults:**
  - Opened with a timing minigame on a rotating arm. Hit the sweet spot for big door damage; a miss spawns homing orbs.
  - Teammates shoot spawned buttons.
  - Cracking a vault alerts the whole map.
- **Most Wanted:**
  - Reveals you for **120s**.
  - Survive it: team revive + rewards.
  - Knocked while carrying it: you go straight to deathbox.
- **Creeps:**
  - Camps: 3 small mobs + 1 elite, respawn each day.
  - Clearing a biome spawns a Biome Leader.
  - Night bosses, Soul Bosses (3 phases), Major Monster.
  - Stagger window: stunned for several seconds and takes 3× damage.
  - Sneaking players are ignored unless close.

## 11. Vision and stealth

- **Sneak** (hold Ctrl): slower, wider vision, doubles as aim-down-sights. Numbers not published [gap].
- **Bushes and stealth items** hide you from base camp vision.
- **Oracle scanners** (world objects) reveal enemy positions roughly.
- Vision radius, fog-of-war and ping rules aren't published [gap].

---

## Still unknown after all sources

Measure from footage or set by design:
- Dash distances and projectile speeds
- Knockback distances
- Hit-stop and screen shake
- Wisp crawl speed and ally revive time
- Deathbox revive time
- Storm damage and radii
- Map size
- Vision radius
- Sneak speed
- Base mana and base HP regen
- Skyshark speeds
- Jump height

## Sources
- Wiki: https://supervive.wiki.gg/wiki/ (pages: Gliding, Abyss, Armor, Reviving, Revive_Beacons, Glossary, Getting_Started, Game_Modes, The_Breach, Time_of_Day, Basecamps, Vaults, Creeps, Jump_Pad, Storm_Shifts, every hunter page, and the patch pages)
- 1.0 feature rundown: https://steamdb.info/patchnotes/19334165
- Feb 2025 patch: https://steamdb.info/patchnotes/17253819
- Mar 2025 patch: https://steamdb.info/patchnotes/17782514
- 1.0 hotfix (Jul 30 2025): https://www.sportskeeda.com/esports/supervive-1-0-patch-notes-july-30-2025-increased-prisma-gains
- Steam announcements: https://steamcommunity.com/app/1283700/allnews/
- Footage: TheSixGame walkthrough (youtube.com/watch?v=JnqmcxXB8Uc), Zik (vj4MuuqHaNc), Tom Kick (YCVtyUszkg0), Ryan Lemur (JhhGgHNeJhE, 0D_6XNLUl9I)
