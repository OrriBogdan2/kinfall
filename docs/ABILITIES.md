# Kinfall abilities

Every ability in an expedition, by slot. All of them are data: `content/abilities/*.json` (class dashes, weapon RMBs, kin abilities), `content/gloves/*.json` (Q gloves), `content/rules/dash_riders.json` (the kin element riders on Shift) and `content/ultimates/*.json` (R). They are built from the effect verbs in `scripts/combat/effects.gd` and the world verbs in `scripts/combat/verbs.gd` (walls, mirrors, tethers, traps, bridges, yanks, decoys), so a new ability is a new JSON file.

This file is generated from the JSON by a script; the descriptions are the one-liners players see in the kit panel (K) and on hover.

## Ranks

Every run starts with abilities locked (see `Hunter.slot_lv`). A skill point unlocks a slot at rank 1 and further points raise it (RMB, Q, Shift, E: ranks 1-3; R: ranks 1-2). Per rank past the first:

- damage +15% (`Effects.level_k`)
- cooldown 10% shorter (RMB, Q, E via `AbilityRunner`/`Hunter.rank_cd_k`); Shift dashes recharge 15% faster
- each verb grows the numbers that define it (`Effects.RANK_GROW`): walls +20% health, +15% time, +10% length; mirrors +20% time; tethers +15% time, +20% snap stun; traps +15% time and root; zones +15% time, +10% radius; fissures +10% length; shots +10% range and +15% stun/root/slow; pulls +15% strength; chains +1 hop per rank; yanks and swaps +25% stun; bridges +20% time; cloaks/decoys/reveals +20-25% time; shields and heals +15%; blinks +10% distance; blink-strike crit window +25%
- the bond ultimate (R) at rank 2 lasts 30% longer and its cast effects hit 15% harder
- dash and charge distances never grow: dashes stay short

An ability JSON can override any of these with `"per_level": {"key": flat amount per rank}`.

## Shift: class dashes

Each class has its own dodge verb. Grounded with a charge, Shift does the class dodge; in the air or out of charges it does the class's long dash (its own cooldown). Both chain straight into a jump or the glider.

| Class | Dash | Charges / cooldown | What it does |
|---|---|---|---|
| Light | **Phase Step** (3.6m) | 1 / 6.5s | Light: a short, very fast phase. Shots pass straight through you for the whole step. In the air, or on cooldown, Shift does the long dash. |
| Medium | **Combat Roll** (3.4m) | 1 / 9.0s | Medium: a quick roll that slips a third of a magazine in on the way. Roll through a hit as it lands for a perfect dodge: your next shots crit. |
| Heavy | **Shoulder Charge** (3.1m) | 2 / 12.0s | Heavy: a short charge nothing can knock back (2 charges). Anyone you run into is bowled aside, and slammed into a wall they're stunned 1.2s. |

### Kin element riders on every dash

The kin you brought adds a rider to every dash (`content/rules/dash_riders.json`).

| Element (kin) | Rider | What it does |
|---|---|---|
| venom (Vespyx) | **Venom Trail** | anything you dash through is poisoned and blighted (healing halved). |
| spore (Mycroll) | **Spore Puff** | you leave a spore puff where you started that slows and stings foes for 2s. |
| echo (Echolop) | **Echo Step** | a beat after the dash, it echoes: a second, shorter dash the same way. |
| gravity (Gravadillo) | **Gravity Wake** | where you stop, gravity tugs every foe within 3m a step toward you. |
| lunar (Lunowl) | **Moon Blink** | on the ground you don't travel, you blink: there in an instant, through anything in the way. |
| prism (Prismander) | **Prism Decoy** | you leave a crystal copy of yourself behind for 1.8s that draws bots' fire. |

## RMB: weapon signature abilities

Right click is your weapon's own verb. Hold RMB to see its telegraph (lane, landing circle, wall footprint or arc); release to cast. Rail Charge charges while held instead.

| Weapon | Class | Ability | Verb | Cooldown | What it does |
|---|---|---|---|---|---|
| Burst Rifle | medium | **Leash Bolt** | tether | 10s | A bolt that leashes whoever it hits to you for 3.5s. If they get 6m away it snaps: 22 damage, stunned 1s, dragged back. |
| Greatsword | heavy | **Earthshatter** | leap slam | 10s | Leap up to 7m and smash down: everyone within 3m is thrown into the air; anyone already airborne is spiked (+60% damage, stunned 1s). |
| Longsword | medium | **Riposte** | reflect | 8s | Raise your blade for 0.7s: shots hitting your front fly back at the shooter (+30%), and a sword or claw that hits it is parried and stunned 1s. |
| Minigun | heavy | **Bulwark** | shield wall | 12s | Raise a 3m energy shield in front of you for 5s (160 HP). It turns with your aim and stops enemy shots; yours go through. |
| Rifle | medium | **Rail Charge** | charge-shot | 8s | Hold to charge for up to 1s, let go to fire a rail that pierces everyone in its line: 10 to 34 damage, 9 to 17m, full charge stuns. |
| Shotgun | heavy | **Breach** | knockback | 8s | A point-blank blast that throws everyone in front of you 6m back (into a wall: stunned) and kicks you backwards out of the fight. |
| SMG | light | **Razor Disc** | boomerang | 7s | Throw a spinning disc 8m that cuts everything it passes, then flies back to you and cuts them again. |
| Sniper | light | **Tripwire Mine** | trap | 10s | Plant a mine up to 8m away (2 charges). The first rival to step on it is rooted 1.4s, revealed for 3s and takes 14. |
| Twin Blades | light | **Shadow Step** | blink-strike | 8s | Throw a knife 9m. If it hits, you appear behind that foe and your next hits for 1.5s crit. |

## Q: active gloves

Gloves drop in runs. Rarer gloves keep the same verb with bigger numbers: damage, wall health, heals and shields x1 / x1.3 / x1.6 / x2 (common to legendary), durations and pull strength by half as much, cooldown 8% shorter per step. Rank (skill points into Q) stacks on top.

| Glove | Verb | Cooldown | What it does |
|---|---|---|---|
| **Barrier Glove** | wall | 18s | Raise a 4.5m stone wall at the cursor for 5s (220 HP): it stops shots and bodies from both sides. Knock people into it to stun them. |
| **Blink Glove** | blink-strike | 12s | Blink 5m toward the cursor (never into the abyss) and slash everything around where you land: 14 damage, slowed. |
| **Mirror Glove** | reflect | 14s | A 0.8s mirror bubble: every shot that reaches you flies back at whoever fired it, and a melee swing is parried. |
| **Ice Bridge Glove** | terrain | 18s | Freeze a 10m ice bridge toward the cursor across the abyss for 7s. Cross gaps, chase, escape, but it melts. |
| **Hook Glove** | hook | 12s | Fire a hook 10m: it drags the first foe it catches to your feet (stunned 0.3s), or pulls you to the wall or rock it bites. |
| **Gust Glove** | launch | 16s | A burst of wind launches you up and forward and cools your glider. Saves falls, reaches high ground. |
| **Hover Glove** | double jump | 7s | A second jump in mid-air, and your glider is ready the moment you want it. |
| **Springpad Glove** | launch pad | 22s | Throw down a jump pad. Anyone who steps on it is launched high. Lasts 20s. |
| **Mending Glove** | heal orb | 22s | Lob a mending orb at the cursor: you and teammates where it lands heal 35 and shake off slows, roots and poison. |
| **Ledge Glove** | terrain | 40s | Pop a floating platform under your feet for 8s. Your rescue over the abyss. |
| **Fissure Glove** | ground line | 14s | Crack the ground in an 8m line toward the cursor: it erupts end to end, throwing everyone on it into the air. |
| **Rocket Glove** | launch | 16s | Blast straight up into the sky and cool your glider by half. Chain it into a glide to go high and far. |
| **Seeker Glove** | reveal | 26s | Reveal every rival hunter within 26 tiles for 3s, through walls and grass. |
| **Vortex Glove** | pull | 16s | Lob a gravity bomb at the cursor: for 1s it drags everyone within 3.5m into its centre, then pops (12 damage, thrown up). |
| **Skyhook Glove** | grapple | 14s | Hook a point toward the cursor and swing up to it: onto a ledge above you, or high into the air. |
| **Smoke Glove** | stealth zone | 22s | A cloud that hides everyone inside it, like tall grass, for 8s. |
| **Decoy Glove** | decoy | 18s | Leave a glowing copy of yourself where you stand and vanish for 1.5s, moving faster. Bots keep shooting the copy. |

Passive gloves (no Q, stats only): **Glider Glove** (Glide 20% faster and longer.); **Swift Glove** (10% faster on foot.); **Focus Glove** (Abilities recharge 18% faster.); **Cooling Glove** (Your glider holds 45% more heat.); **Power Glove** (12% more damage.); **Plated Glove** (25 more armor.)

## E, the kin's own ability, and R, the bond ultimate

Each kin has one E verb fitting its element, a second ability it uses by itself, a throw (C) status, a dash rider and an ultimate. The E ability is cast from the shoulder or by the kin where it stands, aimed at the cursor.

### Vespyx (venom)

- **E: Stinger Hook** (hook, 8s): Vespyx lashes its tail 8m: the first foe it stings is dragged back to it, poisoned, blighted (healing halved) and stunned 0.3s.
- **Auto: Stinger Dash** (rush, 9s): On its own, Vespyx lunges 7m tail first, poisoning everything it passes through.
- **Throw (C)**: stuns what it hits and applies burn 5.
- **Shift rider: Venom Trail**: anything you dash through is poisoned and blighted (healing halved).
- **R: Venom Mantle** (armor, 7s): Vespyx fuses onto you as venomous armor for 7s: 30% more damage, and your shots poison and burst.

### Prismander (prism)

- **E: Prism Wall** (reflect wall, 10s): Prismander raises a 4m crystal wall at the spot: enemy shots that hit it bounce back at them. Lasts 4.5s or 140 damage.
- **Auto: Refraction** (reflect, 12s): When you're hurt, Prismander wraps you in a 1s mirror shell: shots that reach you fly back at the shooter, and you get a 20 shield.
- **Throw (C)**: stuns what it hits and applies slow 1.5.
- **Shift rider: Prism Decoy**: you leave a crystal copy of yourself behind for 1.8s that draws bots' fire.
- **R: Prism Shell** (armor, 7s): Prismander wraps around you as a shell of living crystal for 7s: an 80 point shield, steady healing, and shots that slow.

### Mycroll (spore)

- **E: Puffcap Mines** (trap, 10s): Mycroll plants three puffcaps in a triangle. Step on one and it bursts: rooted 1.4s inside a lingering spore cloud.
- **Auto: Spore Patch** (zone, 11s): On its own, when foes bunch up, Mycroll puffs a 4s spore cloud on them: slowed and taking damage while inside.
- **Throw (C)**: stuns what it hits and applies root 0.9.
- **Shift rider: Spore Puff**: you leave a spore puff where you started that slows and stings foes for 2s.
- **R: Sporewake** (giant, 8s): Mycroll grows into a giant toadstool beast for 8s. Its stomps root everything around it.

### Echolop (echo)

- **E: Echo Chain** (bounce + echo, 7s): A sound pulse leaps between up to 3 foes, stunning each 0.4s, then echoes 0.9s later and does it all again at half strength.
- **Auto: Echolocate** (reveal, 14s): On its own in a fight, Echolop pings: every rival within 18m is revealed through grass and walls for 3s, and your next shots for 1.5s crit.
- **Throw (C)**: stuns what it hits and applies stun 0.9.
- **Shift rider: Echo Step**: a beat after the dash, it echoes: a second, shorter dash the same way.
- **R: Resonance** (armor, 6s): Echolop hums over you for 6s: 30% faster, every dash back, and each shot echoes to a second foe.

### Gravadillo (gravity)

- **E: Gravity Slam** (leap slam, 9s): Gravadillo drops onto the spot like a meteor: everything within 3.5m is sucked into the crater and flung up; anyone already airborne is spiked.
- **Auto: Mass Guard** (shield wall, 12s): When you're under fire, Gravadillo curls into a heavy plate in front of you for 3s that stops enemy shots (120 HP).
- **Throw (C)**: stuns what it hits and applies kb 7.
- **Shift rider: Gravity Wake**: where you stop, gravity tugs every foe within 3m a step toward you.
- **R: Heavy Star** (giant, 8s): Gravadillo collapses into a towering heavy star for 8s. Huge health, and every stomp launches foes away.

### Lunowl (lunar)

- **E: Moon Swap** (swap, 10s): Lunowl throws a moon mark 9m. The first foe it touches trades places with YOU (stunned 0.4s): pull a rival off a ledge, or step behind them.
- **Auto: Moonlift** (rescue, 14s): On its own, when you fall into the abyss, Lunowl throws up a column of moonlight that lifts you high and cools your glider.
- **Throw (C)**: stuns what it hits and applies kb 8.
- **Shift rider: Moon Blink**: on the ground you don't travel, you blink: there in an instant, through anything in the way.
- **R: Eclipse** (giant, 7s): Lunowl swells into a living eclipse for 7s that drags foes in and flings them skyward.

## Element variants of shared verbs

Several verbs appear in more than one element, tuned to fit it:

- **Hook / yank**: Hook Glove (neutral, drags to your feet or zips you to terrain), Stinger Hook (venom: poisons and blights), Leash Bolt (tether that snaps back).
- **Wall**: Barrier Glove (stone, blocks shots and bodies both ways), Bulwark (energy, follows your aim, yours pass through), Mass Guard (gravity plate, raised for you when you're shot), Prism Wall (crystal, reflects shots).
- **Reflect**: Mirror Glove (all-round bubble), Riposte (frontal, parries melee), Refraction (prism, auto when hurt), Prism Wall (reflecting wall).
- **Slam / knock-up**: Earthshatter (hunter leap), Gravity Slam (kin meteor that pulls in first), Fissure Glove (a line eruption), Vortex Glove (pull then pop).
- **Blink**: Blink Glove (blink-strike), Shadow Step (appear behind who your knife hits), Moon Swap (lunar: trade places), Lunar dash rider.
- **Trap / zone**: Tripwire Mine (root + reveal), Puffcap Mines (spore triangle), Spore Patch (spore cloud), Spore dash rider.

## Readability

- Holding RMB, Q, E or R shows the cast's shape before you let go: a lane for shots and rushes (with a tick at the far end), a range ring plus landing circle for lobs and leaps, the wall's footprint across your aim, a cone, or a ring round you (`Match._update_indicators`, shape from `AbilityDef.aim_spec`).
- Enemy area casts get a 0.32s filling ground marker before they land; leaps show their landing circle to everyone; fissures show their lane filling.
- Each verb has its own shape in the world (wall slabs, a mirror shell, a rope for tethers, a disc, a hook, an orb, trap pads, ice tiles, ghost decoys) in its element colour, plus HOOKED / SPIKED / PARRIED / SNAP / TRAP words when they go off.

## Bots

Each ability carries a `bot` hint (`when`: in_range, under_fire, clumped, hurt, gap, always; `min`/`max`), read by `Bot.ability_aim`: walls and mirrors go up when a bot is being shot, hooks and slams when the target is in reach and in sight, vortex and fissure when foes bunch, Rail Charge is held to full. Bots shoot decoys while the real hunter is cloaked. Bot points are spent automatically (`Hunter._bot_spend`).

