# Down, death, revive and respawn (built on Supervive's rules, tuned for extraction)

Code: `scripts/match/`. Rules per mode: `data/rules/trios.tres`, `duos.tres`, `solo.tres` (script `life_rules.gd`; every value is tagged in that file). Rules per run tier: `data/tiers/shallows.tres`, `deeps.tres`, `abyss.tres`.

## The flow

```
ALIVE ──0 HP──► DOWNED (wisp) ──bleeds out / executed / team wiped──► DEAD (deathbox)
  ▲                  │                                                    │
  └── ally stands on you (4s) ◄┘                                          │
  ├── teammate holds E at your deathbox (5s, soul still there) ◄──────────┤
  └── teammate stands on a revive beacon (6s) ◄───────────────────────────┘
```

| Step | Rule | Value | Source |
|---|---|---|---|
| Knocked | 0 HP with a teammate still up → you become a **wisp**: crawl slowly, can't attack, dash, jump or glide, and can't be shot | crawl at 40% speed | [wiki] "heavily slowed" / [est] |
| Bleed-out | Wisp drains on its own | **15s** | [patch] |
| Ally revive | A teammate standing on your wisp fills the revive bar and pauses the drain; extra teammates speed it up | **4s**, back at 33% HP | [wiki] "a few seconds" / [est] |
| Stomp | An enemy standing on a wisp drains it 4× faster and blocks the revive | ×4 | [wiki] / [est] |
| Execute | Enemy holds E on the wisp: they're locked in place for the finisher, then you're dead | **3s** | [footage] |
| Knock reward | The knocker heals and gets a dash charge back | +250 HP, +1 dash | [patch] |
| Last one standing | Knocking a team's last standing player wipes the team: no wisp, everyone left dies | — | [patch] |
| Dead | Your **deathbox** drops with everything you carried. Abyss deaths drop it at the killer's last ground position, or at the edge you fell from | — | [patch] |
| Box colour | Grey / blue / purple / gold by value | 500 / 2k / 5k | [patch] (colour by value) |
| Deathbox revive | Teammate holds E at your box while your soul is there. Damage cancels the channel. **You get the box's loot back** | **5s**, 50% HP, 90s soul window | [wiki] / [design] |
| Looting | Anyone else holds E: takes everything | 1s | [design] |
| Revive beacon | Teammate stands on it: brings back every dead or downed teammate. Single use. Map-wide alert. Two teams on it pauses (doesn't reset) | **6s** | [patch] 1.0 |
| Everbeacon | Unlimited uses, can't be contested | **10s** | [patch] |
| Beacon revive | Full HP but **no loot** (your box stays where it was, so go get it), plus resurrection sickness | −25% damage for **12s** | [patch] + [design] |

**Why this works for extraction:**
- Getting picked up from a wisp costs nothing.
- A box revive costs a dangerous 5s channel, but you keep your loot.
- A beacon revive is safe-ish, but you come back empty-handed.
- Every death creates a "go back for the box" decision, which is the extraction loop.

## Solos: my recommendation

**Keep solos, but as their own queue with different rules. Don't mix solos into team lobbies.** That's what `solo.tres` does:

- **No wisp:** 0 HP = dead, deathbox, done. That's how solo modes in extraction games generally work, since there's no one to pick you up.
- **Self-revive item** (`self_revive_items`, a rare consumable): you go down as a wisp and get back up on your own after **8s** (Supervive's Guardian Angel), unless an enemy stands on you. It's a high-value find worth fighting over.

Reasons to keep solos:
- A big share of extraction players queue alone.
- Solos give you a clean 1v1 skill test.

The real risk is player count. Three queues (solo, duo, trio) split a small launch population three ways. A sensible order:
1. **Launch trios (plus duos)** while the player base is small.
2. Turn on solos when queue times allow.
3. Same for Supervive: it moved its main queue from squads to trios at 1.0.

## Kin when you die: depends on the run tier

Risk scales with the tier you queue into (`data/tiers/*.tres`, script `run_tier.gd`). Higher tiers pay more and put your kin on the line:

| Tier | Kin you have on you when you die | Kin out of your hands (thrown, following a teammate) | Loot value |
|---|---|---|---|
| **Shallows** (1) | Stay with you, never lost | Follow a living teammate, or flee home | ×1 |
| **Deeps** (2) | **Drop into your deathbox: anyone can loot them** | Follow a teammate, or flee home | ×1.75 |
| **Abyss** (3) | **Drop into your deathbox: lootable** | **Can be captured by enemies** (hold E, 3s) | ×2.75 |

All names and multipliers are placeholders.

**Getting a kin back in the Deeps or Abyss:**
- A box revive by your teammate brings you back with your loot and your kin.
- A teammate can also loot your box for you, and the kin go back to their owner's team.
- A beacon revive brings you back empty-handed, so your kin are still sitting in your box and you have to go get it.
- If an enemy loots your box, your kin leave with them. The `kin_taken(kin, by)` signal fires so the extraction system can decide what that means: they become the enemy's on extract, or can be won back.

**Other kin rules in every tier:**
- **Knocked out while you're alive:** a kin comes back to you after `kin_recall_time` (25s).
- **While you're downed:** your kin guards your wisp (`kin_guards_wisp`).
- **However you come back:** a kin that's still loose returns to you, so kin don't need beacons of their own.

**Worth deciding before launch:**
1. **Do looted kin become the looter's for good?** That's the strongest stakes, and it fits "kin are earned, not bought".
2. **Can the original owner hunt them back?** A softer option: a captured kin is "marked" for a while and its owner can find and reclaim it.
3. **Warn before queueing.** A clear screen before entering the Deeps or Abyss ("your kin can be lost") matters, since losing a kin hurts far more than losing loot.

**Hooks:**
- `HunterLife.kin`: the kin you have on you.
- `run_tier`
- Signals: `kin_dropped`, `kin_recovered`, `Deathbox.kin_taken`.
- `loose_kin_policy()` returns `{escort, flee, capturable, capture_time}` for the kin AI.
- `went_down` / `died` / `revived(how)` / `team_wiped`.

## Hooks for everything else
- `HunterController`:
  - `team_id`
  - `player_controlled` (false = driven by `bot_move` / `bot_actions`, ready for bots and network players)
  - `heal()`, `kill()`, `revive_at()`
  - `damage_dealt_multiplier` (resurrection sickness)
- `ReviveBeacon.alert(position, team)`: hook for the map ping and sound.
- `Deathbox.looted` and `owner_revived` signals; `total_value()`.

## Test scene and test results

**Test scene:** a blue teammate bot, a red enemy bot and a green revive beacon.
- F6 knocks yourself down.
- Hold E for deathboxes and executes.
- HUD shows life state, wisp %, revive % and sickness.

**Headless results** (`tests/life_sim.gd`):

| Case | Result |
|---|---|
| Knocked with teammate up | Wisp; crawl 1.86 m/s; knocker +250 HP and +1 dash |
| Ally stands on wisp | Back up in 4.0s at 33% HP |
| Alone | Bled out at 15.0s; box holds all loot (2,100 value) |
| Ally holds E at box | Revived in 5.0s, 50% HP, loot back |
| Ally shot mid-channel | Channel reset to 0 |
| Enemy execute | Dead after 3.0s |
| Enemy loots box | Takes everything |
| Beacon | Back in 6.0s at the beacon, full HP, no loot, −25% damage for 12s, beacon used up |
| Enemy steps on beacon | Paused at 33%, resumes when they leave |
| Last one standing knocked | Whole team dead |
| Solo | 0 HP = dead. With self-revive item: up after 8.0s |
| Abyss | Dead after ~3s of falling; box at the edge you fell from |
| Shallows death | Kin stays with you; nothing to loot |
| Deeps / Abyss death | Kin goes in the box; an enemy looting the box takes it; Abyss also marks loose kin as capturable |
| Deeps, teammate box-revives you | Back with your kin and your loot |
