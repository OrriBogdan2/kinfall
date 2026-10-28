# Kinfall

A creature-raising farm and a PvPvE extraction game, built in Godot 4.6.

Your kin live with you on a floating-island farm. Each one has its own personality, remembers what you do together, and decides how far it trusts you. In matches it rides on your shoulder, gets thrown into fights, fights on its own, and might refuse an order it thinks is reckless.

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
| Left click | Shoot |
| Right click | Throw your kin at the cursor, or call it back |
| Q | Your kin's skill at the cursor (throws it first if it's on your shoulder) |
| E | Hero ability |
| R | Ultimate |
| Shift | Dash |
| Space | Jump; hold it in the air to glide |
| F (hold) | Catch a dazed wild kin, revive a teammate, open a chest |
| F (tap) | Swap to a found weapon on the ground |
| 1 | Tonic |
| Tab | Scoreboard |
| Esc | Menu: settings, controls, save files |
| F1 or ` | Admin tools (god mode, gems, unlocks) for the game's owner |

Every key can be rebound in Settings > Controls. On the farm: WASD to walk, Space to jump, F to use whatever is in front of you, Esc for the menu.

Touch the side of an island while you're falling (or gliding) and you float back up onto it. Walk into a single terrace and you hop up it; walk into a step a few terraces high and you climb it. Dash through an attack just as it lands for a perfect dodge: you get some dash back and your next shots crit.

## How a run works

- **Farm.** Plant seeds and water them (F): a watered plant grows a stage every 90 seconds while you're home, and every expedition grows everything a stage too. Rain waters for you, and one kin can be your farmhand. A plant watered every stage gives a bigger harvest and a seed back. Crops become tonics, treats, snacks, a level for your partner (Starfruit), or gems at the stall.
- **Training area.** From the expedition menu: a safe island with target dummies and a checklist for every button.
- **Expedition.** Pick a class (Light, Medium, Heavy), a tier (Meadow, Dusk Isles, Hollow) and a mode. Every match is PvPvE: rival squads, monsters, wild kin, chests. Exits open partway through; stand in one for 3 seconds to leave with everything you carry. You have lives (3 in the Meadow, 2 in the Dusk Isles, 1 in the Hollow): losing one drops some of your gems and glides you back in somewhere quiet. Lose the last and everything you carry is gone. You heal on your own after a few seconds out of the fight. At 6:00 the islands fall.
- **The drop.** Expeditions happen on a big map. Everyone starts aboard the skyship as it crosses the islands: press Space to jump when you're over the spot you want, then glide down. A ring on the ground shows where you'd land. Anyone still aboard at the far side gets dropped.
- **Loot.** Crates, pots and red barrels break when you shoot or dash through them (barrels explode, so mind where you stand). Some crates, chests and the Glimmerkin drop found weapons: Fine, Rare, Epic or Legendary versions of any weapon, stronger than the one you brought, yours until the expedition ends.
- **Events.** A meteor shower comes down about a quarter of the way in (the stars leave gems), the Warden wakes on the center island, and halfway through a Glimmerkin appears and runs. Bring it down before it slips away.
- **Islands and flight.** Every island has a shape of its own: crescents, atolls with a hole to the sky, twin lobes on a narrow neck, mesas, stepped terraces, split canyons, highlands, some with ruined walls to fight around. Close islands are crossed by gliding: jump off the edge and glide through the air rings between them for a burst of speed. The glider runs on fuel, and speed is what keeps you up: fast gliders barely sink, slow ones drift down. Steer hard against your heading to brake. Jump pads only cover the long gaps.
- **Combat.** You have armor over your health (40 light, 50 medium, 65 heavy). It soaks hits first, shatters with a blue flash, and snaps back a few seconds after you stop taking damage; health only regenerates once armor is full. Armor shards drop from crates and big monsters. Shots spread more while you move, jump or dash, so plant your feet for accuracy. Hold E, R or Q to see where an ability will land and let go to cast it (right click cancels; "Quick cast" in Settings fires on press instead). Red arcs around the middle of the screen point at whoever is hitting you.
- **Stagger.** Big monsters (Brutes, Sentinels, the Warden, the Glimmerkin) open short purple-ring windows, always while winding up a slam. Hit one with an ability (E, R, your kin's skill or a throw) in that window, not a regular shot: it takes a big hit, is stunned for a few seconds, takes extra damage the whole time, and your E or kin skill comes straight back.
- **The Hollow.** If you fall there and your partner's trust is below 80, it stays behind.

## Raising kin

Code: `scripts/core/care.gd`, `scripts/core/kin_speak.gd`, the raising section of `scripts/home/home.gd`.

- **Needs.** Full, Energy, Happy and Clean drift down at home and drop after every expedition. A thought bubble over a kin shows what it wants. Hungry kin hang around the cooking pot, tired ones go to bed, dusty ones shed dust. How it's doing changes how it fights: a kin in great shape gets +10%, a struggling one loses up to 18% and is more likely to refuse you.
- **Care.** Pet (F), fetch (G) and talk (T) out in the world. The card (C) has Feed, Brush, Bath, Nap, Train, Dress and Pair, and each one plays out on the farm, not in a menu.
- **Likes.** Every kin loves one food, refuses another and has a favourite way to spend time. You find out by trying, and the card remembers.
- **Training.** Four stats (Power, Guard, Speed, Focus) trained at the yard with a three-round timing drill. A happy kin learns faster, a tired one won't train. Points are capped by level.
- **Bond.** Trust ranks: Wary, Friendly, Close (skills hit harder), Devoted (rushes to revive you), Soulbound (never refuses, +10% to everything).
- **Talking.** Newly hatched kin only say their own name ("Cin! Cindle?"), and get their meaning across with tone and what they do. Around level 4 with some trust they pick up a few words, around level 8 short sentences, and by level 12 with a Devoted bond they talk freely.
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

## Project layout

```
scripts/core/    data.gd (all tuning), save.gd, game.gd, sfx.gd, bridge.gd, net.gd, social.gd, evo.gd
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
