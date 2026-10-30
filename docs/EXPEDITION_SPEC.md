# Kinfall Expedition Spec (estimate-based)

Status: **ESTIMATES**. Every number here is derived from public sources
(official wiki, patch notes, gameplay footage) and reasonable conversion,
not from extracted game data. Treat them as starting points to tune
against, not ground truth. Where a value is a pure guess from footage it
is marked (eyeball).

Sources: supervive.wiki.gg (Gliding, Getting Started), Deltia's Gaming
gliding guide, general gameplay footage. The wiki's own stats pages are
flagged outdated, so hard numbers are scarce; mechanics are well
documented, magnitudes are inferred.

This spec covers the *feel* of a top-down MOBA-survival extraction mode.
It deliberately does not reproduce their map, items, characters or art.

---

## 1. Unit conventions (how to read the numbers)

- Kinfall works in **meters, Y-up** (Godot 3D convention used in the
  project). Unreal source would be **centimeters, Z-up**: divide cm by
  100 for meters, and swap Z<->Y if we ever get real transforms.
- Horizontal plane is **X/Z** in Godot; "up" is **+Y**.
- Camera FOV below is given as **vertical** FOV (Godot's default axis).
  Unreal quotes **horizontal** FOV; convert with
  `vfov = 2*atan(tan(hfov/2) / aspect)` at 16:9.
- Speeds are **meters/second**, times in **seconds**, angles in degrees.

---

## 2. Camera rig

A top-down MOBA camera, slightly pitched so you see a little of the far
side of characters (not a pure 90-degree overhead).

| Param | Estimate | Notes |
|---|---|---|
| Pitch (down-angle) | 55-60 deg from horizontal (eyeball) | not straight down; you read elevation and glide arcs |
| Height above focus | 18-24 m (eyeball) | spring-arm length along the pitched boom |
| Vertical FOV | 38-42 deg | longer boom + narrow FOV keeps it readable, less distortion |
| Follow lag | 0.08-0.15 s smoothing | camera eases toward the hunter, doesn't hard-lock |
| Look-ahead | 1.5-3 m toward aim/cursor | shifts framing toward where you're aiming |
| Glide zoom-out | +15 to +25% boom length while gliding | they pull the camera back in the air for arc readability |

Recommendation: **copy closely.** The pitched-boom + narrow-FOV combo is
most of why the game reads well. Build it as a `SpringArm3D` with a
`Camera3D`, lerp boom length on glide.

---

## 3. Ground movement

| Param | Estimate | Notes |
|---|---|---|
| Base move speed | 5.0-5.5 m/s (eyeball) | our classes already sit 4.7-5.2; in range |
| Sneak speed | ~60-70% of base | Left Ctrl; slower, more vision |
| Accel / decel | near-instant (0.05-0.1 s ramp) | arcade feel, not momentum-heavy |
| Turn | instant facing toward aim | twin-stick style |

Recommendation: **keep ours.** Our class speeds (Light 5.2 / Medium 5.0 /
Heavy 4.73) are already in the plausible band. Add the sneak modifier if
we want their vision tradeoff.

---

## 4. Jump, glide, fall (the signature system)

Gliding is the identity mechanic: jump, hold to deploy the glider, and
you trade height for horizontal distance while "Glider Fuel" / heat
drains. Taking damage mid-glide stuns and smashes you to the ground;
doing it over the abyss is instant death.

| Param | Estimate | Notes |
|---|---|---|
| Jump height | 2-3 m (eyeball) | enough to clear ledges and start a glide |
| Glide horizontal speed | 7-10 m/s (eyeball) | faster than run; the point of gliding |
| Glide descent rate | 2-4 m/s | slow sink while held |
| Glide fuel / capacity | 2.5-4 s of continuous glide (eyeball) | our `glide_cap` 0.85-1.2 is a multiplier, keep as-is and map to seconds |
| Fuel regen | refills on ground over 2-4 s | |
| Spike stun (hit in air) | **0.7 s** | this one IS stated on the wiki |
| Abyss fall | instant death | map hazard, not damage |

Recommendation: **copy closely**, it's the core. We already model glider
heat (`fuel`, `glide_max`, spiking cools the attacker by 0.5). Tie fuel
to real seconds using the capacity above, and keep the 0.7 s spike stun
exact since it's a known value.

---

## 5. Dash / mobility ability

Most hunters have a dash on LShift (one of the four ability slots). Exact
distances and cooldowns are per-character and not public.

| Param | Estimate | Notes |
|---|---|---|
| Dash distance | 5-8 m (eyeball) | our class ex-dash is 5-7 m, in range |
| Dash duration | 0.2-0.3 s | our 0.22-0.24 s is fine |
| Dash cooldown | 10-16 s (eyeball) | our 12-15 s is reasonable |

Recommendation: **keep ours.** Values land in the public-footage band.

---

## 6. Abilities & levels (structure, well documented)

- Hunters start **level 1** with **1 skill point**.
- Four abilities: RMB, Q, LShift, R. **Ultimate (R) unlocks at level 7.**
- One non-ultimate skill can reach **level 4**; the others cap at
  **level 3**.
- Relic actives on F and G; up to **2 Relics, 2 Grips, 1 Kick, 1 Armor**.

Recommendation: our kit is weapon-class based, not hero-ability based, so
**adapt rather than copy.** Borrow the level-gated ultimate idea (unlock
a class ultimate partway through a run) if we want a power curve.

---

## 7. Down / death / revive (already implemented, matches their rules)

This is the system in `DEATH_AND_REVIVE.md` and `life.gd`. Public rules:

- **0 HP -> Wisp state.** Heavily slowed, can't fight. (We model this.)
- **Ally stands on wisp -> revive** with a portion of HP. (We use 0.33.)
- **Enemy stands on wisp -> kill**, drops a **Deathbox** with resources.
  Enemies can also **execute** with E.
- **Deathbox revive:** long-press E near it = full revive.
- **Revive beacons:** revive the whole team, make a sound enemies hear,
  show duration on the minimap. (We model beacons.)

Recommendation: **keep ours**, it already tracks their rules. Our exact
timers (bleed-out 15 s, revive 4 s, soul 90 s, beacon 6 s) are our own
tuning and fine to keep.

---

## 8. Basecamp / extraction

- Claiming a basecamp takes time; gives **vision** and a central
  **healing zone**. Repair armor at the Envil (long-press E), brew at the
  cooking pot. Camps can be **packed up for a price and moved**. Recall
  on B.
- Loot from monsters, coins, shops, chests, vaults, deathboxes, and
  **guaranteed boss drops** (abyssal hatchling, meteor beast).

Kinfall's extraction loop is our own (kin as the thing you carry out, tier
risk, theft/chase). Borrow:
- a **claimable safe node** that heals and gives vision,
- **guaranteed drops from a tier boss** as the reward spike,
- **recall** to leave.

Recommendation: **adapt.** Use the basecamp idea for our extraction
points; keep our kin-centric stakes.

---

## 9. Map scale (roughest estimates)

No public map dimensions. From footage, a full match map reads as a
large island broken into zones around a shrinking boundary.

| Param | Estimate | Notes |
|---|---|---|
| Playable radius | 300-500 m per side (eyeball) | a hunter crosses a zone in ~20-40 s |
| Zones | 6-9 named areas | each with a basecamp + loot |
| Boundary | shrinks over the match (storm) | standard BR pressure |

Recommendation: our expedition maps are smaller and tier-based; **don't
match their scale.** Use the "zone with a basecamp and a boss" unit as a
building block and size to our match length.

---

## 10. What to copy closely vs change

**Copy closely (this is the feel):**
- Pitched top-down spring-arm camera with narrow vertical FOV and glide
  zoom-out.
- The jump/glide/fuel loop and the 0.7 s spike stun.
- Wisp -> deathbox -> beacon death-and-revive flow (done).

**Keep ours (already in range):**
- Ground speeds, dash distance/duration/cooldown, revive timers.

**Change / make our own (don't clone):**
- Hero abilities -> our weapon-class kits.
- Their map, zones, items, bosses, art, audio -> original Kinfall
  content and kin-centric extraction stakes.

---

## 11. If we later get exact data (legal routes only)

With written permission from Theorycraft, or an official data source, the
real values live in these tables (names seen in the asset registry, not
their contents):

- `CT_LokiCharacterAttributes`, `CT_PrimaryAttackSpeeds`,
  `CT_LokiAbilityAttributes`, `CT_LokiPowerAttributes`,
  per-hero `CT_*Attributes`, `CT_*DashScaling`,
  `CT_StunDurationByDistance`.
- Camera: `BP_LokiPlayerCameraManager`, player-controller camera
  components, `GE_Gliding_CameraZoom`.
- Main map bounds: the Skylands map level asset.

Swap the estimates above for those values and re-flag this doc as
measured. Until then: estimates.
