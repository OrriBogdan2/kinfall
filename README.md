# Kinfall

A creature-raising farm and a PvPvE extraction game, built in Godot 4.6.

Your kin live with you on a floating-island farm. Each species is built from one or two real animals and has an element of its own: Vespyx (fox and scorpion, Venom), Prismander (axolotl with crystal gills, Prism), Mycroll (a hedgehog grown over with glowing toadstools, Spore), Echolop (hare and bat, Echo), Gravadillo (armadillo and rhino beetle, Gravity) and Lunowl (owl and luna moth, Lunar). Each one has its own personality, remembers what you do together, and decides how far it trusts you. In matches it rides on your shoulder, gets thrown into fights, fights on its own, and might refuse an order it thinks is reckless.

## Running it

1. Install [Godot 4.6](https://godotengine.org/download) (the standard build, not .NET).
2. Open Godot, choose **Import**, and pick this folder's `project.godot`.
3. Press **F5** to play.

The project uses the Compatibility renderer so the same build runs on the web.

## Controls

| Key | In a match |
|---|---|
| WASD | Move |
| Mouse | Aim |
| Left click | Weapon attack |
| Right click | Your weapon's ability |
| Shift | Dash (in the air it's the long dash; your class decides distance and charges) |
| Space | Jump; hold it in the air to glide |
| Mouse 5 | Glide (hold in the air; never jumps) |
| Q | Your active glove (gloves are found on the run) |
| E | Your kin's ability (thrown out first if it's on your shoulder) |
| C or middle mouse | Throw your kin at the cursor, or recall it |
| R | Bond ultimate, once the bond meter is full |
| B | Base to a teammate (squads): a 3s channel, broken by moving, attacking or any hit; you arrive weakened for 3s (half damage, CC, healing and shields); 40s cooldown |
| 1 | Heal: a tonic when you're hurt, an armor kit when your health is full |
| F | Catch a dazed kin, revive a teammate, open a chest, take a found weapon or glove |
| Ctrl | Sneak (hold; tap to toggle on the web version, since Ctrl+W closes browser tabs) |
| Tab | Scoreboard |
| Esc | Menu: settings, controls, save files |
| F1 or ` | Admin tools (god mode, gems, unlocks) for the game's owner |

Every key can be rebound in Settings > Controls. On the farm: WASD to walk, Space to jump, F to use whatever is in front of you, Esc for the menu.

Touch the side of an island while you're falling (or gliding) and you float back up onto it. Walk into a single terrace and you hop up it; walk into a step a few terraces high and you climb it. Dash through an attack just as it lands for a perfect dodge: you get some dash back and your next shots crit.

## How a run works

- **Farm.** Plant seeds and water them (F): a watered plant grows a stage every 90 seconds while you're home, and every expedition grows everything a stage too. Rain waters for you, and one kin can be your farmhand. A plant watered every stage gives a bigger harvest and a seed back. Crops become tonics, treats, snacks, a level for your partner (Starfruit), or gems at the stall.
- **Training area.** From the expedition menu: a safe island with target dummies and a checklist for every button.
- **Expedition.** Pick a class (Light, Medium, Heavy), a tier (Meadow, Dusk Isles, Hollow) and a mode. Every match is PvPvE: rival squads, monsters, wild kin, chests. Three ways out: call a sky-skiff at a dock on an outer landing (loud: monsters and rivals come, hold out about 45 seconds, then board in a 12-second window; docks close one by one late in the match), open a rift hatch with a scarce Rift Key (instant and quiet, lost to your deathbox if you die), or start an outpost's uplink and hold the yard until its lift opens. One life, and health and armor don't come back on their own (tonics and armor kits do). At 6:00 the islands fall.
- **Down, dead and back (Supervive's rules, docs/DEATH_AND_REVIVE.md).** At 0 health you become a wisp: you crawl, can't be shot, and bleed out in 15s. A teammate standing on you brings you back in 4s at a third of your health (more teammates are faster); an enemy standing on you drains you four times as fast, and holding F executes you in 3s. Your kin pulls you up too (8s) and goes after anyone who comes to stomp you. Knock the last standing member of a squad and the whole squad is out. Knocking someone heals you a little and gives a dash back. When you die, everything you carry goes in a deathbox where you fell: for 90s a teammate can hold F there for 5s to bring you back at half health with your loot, and anyone can hold F to take what's in it. Revive beacons (green pillars, six per map, single use) bring back every dead or downed teammate after 6s of standing on one: full health, nothing you carried, and 12s of -25% damage. Two squads on a beacon pause it. While you're dead the camera follows a teammate; once nobody's left to bring you back, the expedition's over.
- **The drop.** Expeditions happen on a big map. Everyone starts aboard the skyship as it crosses the islands: press Space to jump when you're over the spot you want, then glide down. A ring on the ground shows where you'd land. Anyone still aboard at the far side gets dropped.
- **Loot.** Crates, pots and red barrels break when you shoot or dash through them (barrels explode, so mind where you stand). Some crates, chests and the Glimmerkin drop found weapons: Fine, Rare, Epic or Legendary versions of any weapon, stronger than the one you brought, yours until the expedition ends.
- **Boss lairs.** Every map has walled lairs (Skyreach has three; each match rolls two or three of them live, shown on the full map; the rest lie dormant). A ward seals each one. Open the gate's lock: a dial with a sweeping needle and lit arcs; press F (or click, or A on a pad) as the needle crosses each arc, through three or four locks that get faster and tighter. A miss resets the lock, rings a chime that pings you to everyone nearby and calls guards. Stormcrown Eyrie can also be opened by lighting three rune pylons, the Thornhive by breaking three ward stones. Inside: the Stone Colossus (slams with shockwave rings you jump, boulders, fissures), Stormcoil the Sky Serpent (telegraphed lunges, lightning circles, static discharge) or the Brood Mother (acid spit and puddles, egg sacs that hatch adds, burrowing). Phases at 66% and 33%, an enrage timer, and they fight anyone in the lair. The boss drops a Rare Egg (on everyone's minimap for a few seconds): it takes a backpack slot, stays in your deathbox if you fall, and if you get it home it hatches in your nest into a rare kin (Cairnback, Zephyrak or Hivara).
- **Events.** A meteor shower comes down about a quarter of the way in (the stars leave gems), the Warden wakes on the center island, and halfway through a Glimmerkin appears and runs. Bring it down before it slips away.
- **Islands and flight.** Every island has a shape of its own: crescents, atolls with a hole to the sky, twin lobes on a narrow neck, mesas, stepped terraces, split canyons, highlands, some with ruined walls to fight around. Close islands are crossed by gliding: jump off the edge and glide through the air rings between them for a burst of speed. The glider runs on fuel, and speed is what keeps you up: fast gliders barely sink, slow ones drift down. Steer hard against your heading to brake. Jump pads only cover the long gaps.
- **Combat.** You have armor over your health (40 light, 50 medium, 65 heavy). It soaks hits first, shatters with a blue flash, and snaps back a few seconds after you stop taking damage; health only regenerates once armor is full. Armor shards drop from crates and big monsters. Shots spread more while you move, jump or dash, so plant your feet for accuracy. Hold E, R or Q to see where an ability will land and let go to cast it (right click cancels; "Quick cast" in Settings fires on press instead). Red arcs around the middle of the screen point at whoever is hitting you.
- **Weapons.** Each class carries one of three weapons (two guns and a sword): SMG, sniper or twin blades (light), rifle, burst rifle or longsword (medium), shotgun, minigun or greatsword (heavy). Every weapon has its own right-click utility.
- **Walls and grass.** Islands have stone walls, corners, pillars and small keeps to fight around. Walls block shots and sight, so you can peek and duck back. Jump at a wall in the air to kick off it (light hunters get two kicks). Anyone knocked hard into a wall is stunned, monsters too.
- **Sight.** You see a cone in front of you (where you aim) plus a small circle around you; everything else is dimmed and rival hunters there are hidden. Walls cast sight shadows. Teammates share what they see. Tall grass hides you from anyone outside it, and firing or getting hit gives you away for a moment. Crouching (Ctrl) slows you down and steadies your aim, and rivals only spot you at close range.
- **Stagger.** Big monsters (Brutes, Sentinels, the Warden, the Glimmerkin) open short purple-ring windows, always while winding up a slam. Hit one with an ability (a kin ability, your utility or a throw) in that window, not a regular shot: it takes a big hit, is stunned for a few seconds, takes extra damage the whole time, and your kin's abilities come straight back.
- **Your kit.** Class (light, medium, heavy) sets health, armor, speed and your dodge. Your weapon gives left click and its right-click utility. Everything else comes from your kin.
- **One kin per run.** Your kin gives you its ability (E) and its bond ultimate (R). Change kin and your build changes.
- **Gloves.** Found on the run, like Supervive's grips: one active glove (Q) and one passive glove at a time. A new one replaces the one in its slot. They last one expedition.
- **Throw and recall.** C (or middle mouse) throws the kin into a fight, where it picks targets and fights on its own. Pressing it again recalls it straight to your shoulder; after a recall there's a one-second wait before the next throw.
- **Bond meter.** Your hits, your kin's hits, combos and kin knockouts fill a shared meter. When it's full, R calls the active kin's bond ultimate: an armor form (it fuses onto you: bonus damage, shields, shots that burn, slow or arc) or a giant form (it grows huge and stomps).
- **Combos.** Your kin stuns or roots a foe and your next hit on it lands a COMBO (bonus damage and bond). You stun or slow a foe and your kin's next hit POUNCES for more. A kin ability on a burning foe FLARES.
- **How kin fight.** Each kin's aggression, loyalty and caution (from its species and its own traits) decide how far it chases, how close it stays, who it goes after and when it backs off. Kin also use their abilities on their own (Settings can turn that off); Lunowl's Moonlift will lift you out of a fall into the abyss if it's loyal enough.
- **Kin at risk by tier.** In the Meadow your kin are never lost: while you're dead they keep out of sight and come back if you're revived (or go home). In the Dusk Isles the kin you have on you (shoulder or bench) drop into your deathbox when you die, and anyone who loots the box takes them; kin out of your hands escape. In the Hollow, kin out of your hands are also left dazed where they were and anyone can capture them (hold F for 3s). A box revive or looting your own box gets your kin back; a teammate who loots it carries them home for you. Kin still in a box at the end go to Old Pell's Ransom House on your farm (buy them back or haggle; after 6 expeditions he sells them on), and kin a rival took stay with that rival (make them an offer, or meet them on a later expedition, sense your kin nearby, knock them out and take it back). Everything is paid in gems you earn in play.

## Raising kin

Code: `scripts/core/care.gd`, `scripts/core/kin_speak.gd`, the raising section of `scripts/home/home.gd`.

- **Needs.** Full, Energy, Happy and Clean drift down at home and drop after every expedition. A thought bubble over a kin shows what it wants. Hungry kin hang around the cooking pot, tired ones go to bed, dusty ones shed dust. How it's doing changes how it fights: a kin in great shape gets +10%, a struggling one loses up to 18% and is more likely to refuse you.
- **Care.** Pet (F), fetch (G) and talk (T) out in the world. The card (C) has Feed, Brush, Bath, Nap, Train, Dress and Pair, and each one plays out on the farm, not in a menu.
- **Likes.** Every kin loves one food, refuses another and has a favourite way to spend time. You find out by trying, and the card remembers.
- **Training.** Four stats (Power, Guard, Speed, Focus) trained at the yard with a three-round timing drill. A happy kin learns faster, a tired one won't train. Points are capped by level.
- **Bond.** Trust ranks: Wary, Friendly, Close (skills hit harder), Devoted (rushes to revive you), Soulbound (never refuses, +10% to everything).
- **Talking.** Newly hatched kin only say their own name ("Ves! Vespyx?"), and get their meaning across with tone and what they do. Around level 4 with some trust they pick up a few words, around level 8 short sentences, and by level 12 with a Devoted bond they talk freely.
- **Natures, life stages, eggs.** Each kin has a nature from its strongest traits and grows from Hatchling to Youngling, Grown and Elder. Two kin at level 5 with a Close bond can leave an egg in the nest; the baby mixes their personalities and may come out shimmering (rare colours, also found wild about 1 in 25).
- **Outfits and the Kindex.** The stall sells things for kin to wear, worn into matches too. The Kindex tab in the inventory tracks every species you've seen, caught, evolved and found shimmering.

## The kin's mind

Code: `scripts/match/kin.gd`, `scripts/match/kin_voice.gd`, `scripts/core/bridge.gd`.

- **Traits.** Bravery, loyalty, temper and curiosity, seeded per species and varied per kin. They drift with experience.
- **Trust** (0 to 100). It rises when you extract together, chat, pet and feed. It falls when you throw the kin into danger while it's hurt, or when you lose.
- **In matches.**
  - Before a throw it weighs the danger at the target against its courage (bravery plus trust). It may hesitate or refuse.
  - Brave kin engage from farther away. Timid ones retreat when hurt.
  - Loyal kin go after whoever is hitting you.
  - Hot-tempered kin sometimes ignore a recall to finish a kill.
  - When you go down, it decides how fast to come and revive you, based on loyalty and trust.
  - It calls out hunters you can't see and wild kin nearby.
- **Memory.** Notable moments are saved on the kin. On the web build, conversations and personal voice lines are written by Claude from its traits, trust and memories. Offline it uses stock lines.

## Online

Open the game with `#online` at the end of its link to go straight to the lobby, or use **Play online with friends** at the portal.

- Matches run over the artifact's room capability. Locally they fall back to a BroadcastChannel between browser tabs.
- Each player's game owns their hunter and kin. The host's game owns monsters, bots, loot and wild kin.
- Hits on something you don't own are sent to its owner.

Code: `scripts/core/net.gd`, the `# online` section of `scripts/match/match.gd`, and `tools/shell.html`.

## Shared places

The ferry at home goes to places other players share. They need the web version, where the page's shared store holds them; desktop builds say so instead.

- **Visiting.** Your island is published as a snapshot. Friends can walk around it, pet your kin (they remember the visit) and leave seeds or crops at your house.
- **The town.** A market for seeds and crops (the seller is paid when an item sells), a notice board, the guild registry, and the portal to online expeditions. Everyone in town right now walks around with you.
- **Guild isles.** Each member gets a cottage with their partner kin outside. Members put gems into four projects (Hall, Forge, Kin Shrine, Lighthouse) and each finished one gives every member a perk on expeditions.

Anything read from the shared store is untrusted and cleaned before use (`Social.clean_island`), and market payouts are only paid for listings your own save made. Code: `scripts/core/social.gd`, `scripts/social/town.gd`, and the store functions in `tools/shell.html`.

## Music

The soundtrack is original folk-style music written as note data in `tools/compose.py` and rendered through the GeneralUser GS instrument bank by S. Christian Collins. Each area has its own track (home by day and night, each outer island, the town, guild isles, expeditions, the Hollow) and every track you've heard is kept in the music list in your house.

## Adding content

Kin, abilities, ultimates, weapons, class dodges, combos and the bond and kin-AI tuning are JSON files under `content/`. Drop in a new file and the game picks it up; see `CONTENT.md`. `tests/kin_gallery.tscn` (F6 in the editor) shows every kin side by side, and `tests/combat_sandbox.tscn` drops you in the training area to try a kit.

## Project layout

```
content/         kin, abilities, ultimates, weapons, classes, combos, rules (JSON, no code needed)
scripts/combat/  the combat systems: CombatBus signals, AbilityRunner, Effects, KinTactics (kin AI), Bond, Combos, Ultimate, Fields
scripts/core/    data.gd (all tuning), save.gd, game.gd, ransom.gd, sfx.gd, bridge.gd, net.gd, social.gd, evo.gd
scripts/match/   match.gd, world.gd, hunter.gd, kin.gd, mob.gd, bot.gd, fx.gd, cam.gd, models.gd
scripts/home/    home.gd
scripts/social/  town.gd (the town and guild isles)
scripts/ui/      hud.gd, results.gd, lobby.gd, ui.gd
shaders/         toon, outline, telegraph, ring, clouds, glow
audio/           sound effects from tools/gen_sfx.py, music from tools/compose.py
tools/           web export wrapper, sound generator, test hooks
```

Every character and prop is built from simple meshes in `models.gd`. Swapping in real art means replacing those builder functions with scenes.

## Testing without a screen

```
godot --headless --path . -- --check                # compile every script
godot --headless --path . -- --simtest --seed=5      # a whole match on autopilot, printed
godot --headless --path . -- --mapcheck              # 200 maps: every island reachable, pads clear
```

## Web build

`tools/build_web.sh` exports the Web preset (no threads) and wraps it for publishing. The engine is gzipped so every file stays under 15MB, and `tools/shell.html` inflates it in the browser.

## Contributing

Kinfall is open source and anyone can fork it. New kin, abilities and items are plain JSON (see [CONTENT.md](CONTENT.md)), so you don't need to write code to add content. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request, and use the issue templates for bugs and kin ideas.

## Community

Join the Discord: DISCORD_INVITE_LINK

## License

Code and original assets: [GNU GPL v3](LICENSE). Forks are welcome and must stay open source. Vendored models in `art/vendor/` are CC0 and fonts in `fonts/` are OFL (see [docs/ASSET_CREDITS.md](docs/ASSET_CREDITS.md)). Kinfall is a fan-inspired original game and is not affiliated with Supervive or Theorycraft Games.
