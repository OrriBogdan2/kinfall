import json, os, sys
R = sys.argv[1]
def j(p): return json.load(open(os.path.join(R, p)))
def ab(i): return j(f"content/abilities/{i}.json")
out = []
w = out.append
w("# Kinfall abilities\n")
w("Every ability in an expedition, by slot. All of them are data: `content/abilities/*.json` (class dashes, weapon RMBs, kin abilities), `content/gloves/*.json` (Q gloves), `content/rules/dash_riders.json` (the kin element riders on Shift) and `content/ultimates/*.json` (R). They are built from the effect verbs in `scripts/combat/effects.gd` and the world verbs in `scripts/combat/verbs.gd` (walls, mirrors, tethers, traps, bridges, yanks, decoys), so a new ability is a new JSON file.\n")
w("This file is generated from the JSON by a script; the descriptions are the one-liners players see in the kit panel (K) and on hover.\n")
w("## Ranks\n")
w("Every run starts with abilities locked (see `Hunter.slot_lv`). A skill point unlocks a slot at rank 1 and further points raise it (RMB, Q, Shift, E: ranks 1-3; R: ranks 1-2). Per rank past the first:\n")
w("- damage +15% (`Effects.level_k`)")
w("- cooldown 10% shorter (RMB, Q, E via `AbilityRunner`/`Hunter.rank_cd_k`); Shift dashes recharge 15% faster")
w("- each verb grows the numbers that define it (`Effects.RANK_GROW`): walls +20% health, +15% time, +10% length; mirrors +20% time; tethers +15% time, +20% snap stun; traps +15% time and root; zones +15% time, +10% radius; fissures +10% length; shots +10% range and +15% stun/root/slow; pulls +15% strength; chains +1 hop per rank; yanks and swaps +25% stun; bridges +20% time; cloaks/decoys/reveals +20-25% time; shields and heals +15%; blinks +10% distance; blink-strike crit window +25%")
w("- the bond ultimate (R) at rank 2 lasts 30% longer and its cast effects hit 15% harder")
w("- dash and charge distances never grow: dashes stay short\n")
w("An ability JSON can override any of these with `\"per_level\": {\"key\": flat amount per rank}`.\n")
w("## Shift: class dashes\n")
w("Each class has its own dodge verb. Grounded with a charge, Shift does the class dodge; in the air or out of charges it does the class's long dash (its own cooldown). Both chain straight into a jump or the glider.\n")
w("| Class | Dash | Charges / cooldown | What it does |\n|---|---|---|---|")
for c in ["light", "medium", "heavy"]:
    a = ab(j(f"content/classes/{c}.json")["dodge"])
    e = a["effects"][0]
    w(f"| {c.capitalize()} | **{a['name']}** ({e['speed']*e['time']:.1f}m) | {a.get('charges',1)} / {a['cooldown']}s | {a['desc']} |")
w("\n### Kin element riders on every dash\n")
w("The kin you brought adds a rider to every dash (`content/rules/dash_riders.json`).\n")
w("| Element (kin) | Rider | What it does |\n|---|---|---|")
dr = j("content/rules/dash_riders.json")
kin = {}
for f in sorted(os.listdir(os.path.join(R, "content/kin"))):
    k = j("content/kin/" + f); kin[k["type"]] = k
for el, d in dr.items():
    w(f"| {el} ({kin.get(el,{}).get('name','?')}) | **{d['name']}** | {d['desc'].split(': ',1)[-1]} |")
w("\n## RMB: weapon signature abilities\n")
w("Right click is your weapon's own verb. Hold RMB to see its telegraph (lane, landing circle, wall footprint or arc); release to cast. Rail Charge charges while held instead.\n")
w("| Weapon | Class | Ability | Verb | Cooldown | What it does |\n|---|---|---|---|---|---|")
for f in sorted(os.listdir(os.path.join(R, "content/weapons"))):
    wp = j("content/weapons/" + f)
    a = ab(wp["utility"])
    w(f"| {wp['name']} | {', '.join(wp['classes'])} | **{a['name']}** | {a.get('verb','')} | {a['cooldown']}s | {a['desc']} |")
w("\n## Q: active gloves\n")
w("Gloves drop in runs. Rarer gloves keep the same verb with bigger numbers: damage, wall health, heals and shields x1 / x1.3 / x1.6 / x2 (common to legendary), durations and pull strength by half as much, cooldown 8% shorter per step. Rank (skill points into Q) stacks on top.\n")
w("| Glove | Verb | Cooldown | What it does |\n|---|---|---|---|")
pas = []
for f in sorted(os.listdir(os.path.join(R, "content/gloves"))):
    g = j("content/gloves/" + f)
    if float(g.get("cd", 0)) > 0:
        w(f"| **{g['name']}** | {g.get('verb','')} | {g['cd']}s | {g['desc']} |")
    else:
        pas.append(g)
w("\nPassive gloves (no Q, stats only): " + "; ".join(f"**{g['name']}** ({g['desc']})" for g in pas) + "\n")
w("## E, the kin's own ability, and R, the bond ultimate\n")
w("Each kin has one E verb fitting its element, a second ability it uses by itself, a throw (C) status, a dash rider and an ultimate. The E ability is cast from the shoulder or by the kin where it stands, aimed at the cursor.\n")
for el in ["venom", "prism", "spore", "echo", "gravity", "lunar"]:
    k = kin[el]
    w(f"### {k['name']} ({el})\n")
    e1 = ab(k["abilities"][0]); e2 = ab(k["abilities"][1]) if len(k["abilities"]) > 1 else None
    u = j(f"content/ultimates/{k['ultimate']}.json")
    w(f"- **E: {e1['name']}** ({e1.get('verb','')}, {e1['cooldown']}s): {e1['desc']}")
    if e2: w(f"- **Auto: {e2['name']}** ({e2.get('verb','')}, {e2['cooldown']}s): {e2['desc']}")
    th = ", ".join(f"{a} {b}" for a, b in k.get("throw_hit", {}).items())
    w(f"- **Throw (C)**: stuns what it hits and applies {th}.")
    w(f"- **Shift rider: {dr[el]['name']}**: {dr[el]['desc'].split(': ',1)[-1]}")
    w(f"- **R: {u['name']}** ({u.get('form','')}, {u.get('time','')}s): {u['desc']}\n")
w("## Element variants of shared verbs\n")
w("Several verbs appear in more than one element, tuned to fit it:\n")
w("- **Hook / yank**: Hook Glove (neutral, drags to your feet or zips you to terrain), Stinger Hook (venom: poisons and blights), Leash Bolt (tether that snaps back).")
w("- **Wall**: Barrier Glove (stone, blocks shots and bodies both ways), Bulwark (energy, follows your aim, yours pass through), Mass Guard (gravity plate, raised for you when you're shot), Prism Wall (crystal, reflects shots).")
w("- **Reflect**: Mirror Glove (all-round bubble), Riposte (frontal, parries melee), Refraction (prism, auto when hurt), Prism Wall (reflecting wall).")
w("- **Slam / knock-up**: Earthshatter (hunter leap), Gravity Slam (kin meteor that pulls in first), Fissure Glove (a line eruption), Vortex Glove (pull then pop).")
w("- **Blink**: Blink Glove (blink-strike), Shadow Step (appear behind who your knife hits), Moon Swap (lunar: trade places), Lunar dash rider.")
w("- **Trap / zone**: Tripwire Mine (root + reveal), Puffcap Mines (spore triangle), Spore Patch (spore cloud), Spore dash rider.\n")
w("## Readability\n")
w("- Holding RMB, Q, E or R shows the cast's shape before you let go: a lane for shots and rushes (with a tick at the far end), a range ring plus landing circle for lobs and leaps, the wall's footprint across your aim, a cone, or a ring round you (`Match._update_indicators`, shape from `AbilityDef.aim_spec`).")
w("- Enemy area casts get a 0.32s filling ground marker before they land; leaps show their landing circle to everyone; fissures show their lane filling.")
w("- Each verb has its own shape in the world (wall slabs, a mirror shell, a rope for tethers, a disc, a hook, an orb, trap pads, ice tiles, ghost decoys) in its element colour, plus HOOKED / SPIKED / PARRIED / SNAP / TRAP words when they go off.\n")
w("## Bots\n")
w("Each ability carries a `bot` hint (`when`: in_range, under_fire, clumped, hurt, gap, always; `min`/`max`), read by `Bot.ability_aim`: walls and mirrors go up when a bot is being shot, hooks and slams when the target is in reach and in sight, vortex and fissure when foes bunch, Rail Charge is held to full. Bots shoot decoys while the real hunter is cloaked. Bot points are spent automatically (`Hunter._bot_spend`).\n")
open(os.path.join(R, "docs/ABILITIES.md"), "w").write("\n".join(out) + "\n")
print("ok")
