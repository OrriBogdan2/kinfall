#!/usr/bin/env python3
"""Builds content/maps/skyreach.json: the hand-designed expedition map.

Layout (216 x 216 tiles, north up):

            [Skyport]
                |
 [Lantern]--[  Frostkeep  ]--[Gull]
    |    *     ||  ||     *    |
 [Quarry ]==[    HEART    ]==[Storm-]
 [ lobes ]  [  vault ring ]  [reach ]
    |    *     ||  ||     *    |
 [Moss  ]--[  Bloomwild   ]--[Still]
                |
             [Dawn]

  Iron (far west) and Fern (far east) hang off the side regions.
  * = high perches over the four diagonal gaps.

Big walkable regions, wide bridges between neighbours, and only six ways
into the Heart (two wide spans, two narrow walks, two causeways), plus one
wind road. Bridge ends are worked out from the island shapes, so they always
start and end on solid ground.
"""
import json, math, os

C = 108  # map centre

def circle(x, z, r, lv=0, **k):
    return dict(circle=[x, z], r=r, lv=lv, **k)

def ellipse(x, z, rx, rz, lv=0, rot=0, **k):
    d = dict(ellipse=[x, z], rx=rx, rz=rz, lv=lv, **k)
    if rot: d["rot"] = rot
    return d

def capsule(x0, z0, x1, z1, r, lv=0, **k):
    return dict(capsule=[x0, z0, x1, z1], r=r, lv=lv, **k)

def rect(x0, z0, x1, z1, lv=0, **k):
    return dict(rect=[x0, z0, x1, z1], lv=lv, **k)

islands = [
    # The Heart: a big gloomy plaza, a raised ring and the vault crown in the middle.
    dict(id="heart", name="The Heart", role="heart", region=0, poi=[108, 108], noise=0.12, biome="gloom", danger=2,
         shapes=[circle(108, 108, 21), circle(108, 108, 13, 1), circle(108, 108, 5.5, 2)],
         sheer=[[30, 60], [120, 150], [210, 240], [300, 330]],
         walls=[dict(ring=[108, 108], r=8.5, gates=4, gate_w=2.5)],
         pillars=[[98, 98], [118, 98], [98, 118], [118, 118], [108, 92], [108, 124], [92, 108], [124, 108]],
         bush=[[122, 120, 1.8], [94, 96, 1.8], [94, 121, 1.5], [122, 95, 1.5]],
         extras=[[108, 92, "grove"], [108, 125, "grove"]]),
    # North: Frostkeep, a long frozen ridge with the keep on its plateau.
    dict(id="keep", name="Frostkeep", role="camp", region=2, poi=[108, 52], noise=0.1, biome="frost", danger=1,
         shapes=[ellipse(108, 54, 36, 17), rect(98, 45, 118, 60, 1), circle(130, 50, 6, 1)],
         sheer=[[60, 120]],
         walls=[dict(box=[101, 47, 115, 58], gates=["s", "n", "e", "w"], gate_w=3)],
         bush=[[84, 60, 1.8], [134, 62, 1.6]],
         extras=[[82, 52, "grove", "Rimefield"], [134, 50, "nest", "Icewing Roost"]]),
    # South: Bloomwild, a wide flowering meadow with terraces down to a nest.
    dict(id="nest", name="Bloomwild", role="nest", region=4, poi=[108, 166], noise=0.1, biome="bloom", danger=1,
         shapes=[ellipse(108, 162, 36, 17), ellipse(92, 166, 12, 8, 1), circle(126, 168, 7, 1)],
         sheer=[[240, 300]],
         bush=[[100, 152, 2.0], [118, 156, 1.8], [80, 162, 1.8], [136, 158, 1.6]],
         extras=[[84, 162, "grove", "Petal Hollow"], [132, 160, "camp", "Thornwatch"]]),
    # West: the Ember Quarry, two hot lobes joined by a broad neck.
    dict(id="quarry", name="Ember Quarry", role="camp", region=3, poi=[54, 124], noise=0.1, biome="ember", danger=1,
         shapes=[capsule(54, 90, 54, 126, 10), circle(54, 88, 15), circle(54, 128, 15), circle(52, 128, 8, 1)],
         sheer=[[330, 30]],
         walls=[dict(line=[46, 120, 46, 126]), dict(line=[60, 132, 60, 136])],
         bush=[[62, 84, 1.6], [44, 96, 1.6]],
         extras=[[54, 86, "grove", "Cinder Steps"]]),
    # East: Stormreach, a long storm-swept spine with the shrine on a raised table.
    dict(id="shrine", name="Stormreach", role="shrine", region=1, poi=[164, 108], noise=0.1, biome="storm", danger=1,
         shapes=[capsule(162, 86, 162, 130, 15), ellipse(165, 108, 7, 11, 1)],
         sheer=[[150, 210]],
         bush=[[154, 88, 1.6], [170, 128, 1.6]],
         extras=[[160, 84, "camp", "Static Field"], [160, 132, "grove", "Rainbreak"]]),
    # Corners: four big, calmer islands joined to both neighbouring regions.
    dict(id="lantern", name="Lantern Hollow", role="grove", region=2, poi=[44, 44], noise=0.14, biome="ember", danger=0,
         shapes=[circle(44, 44, 17), circle(40, 40, 7, 1)], sheer=[[30, 60]], bush=[[52, 52, 1.6]],
         walls=[dict(box=[34, 48, 42, 56], gates=["e", "n"], gate_w=3)]),
    dict(id="gull", name="Gullcrest", role="camp", region=1, poi=[172, 44], noise=0.14, biome="frost", danger=0,
         shapes=[circle(172, 44, 17), circle(176, 40, 7, 1)], sheer=[[120, 150]], bush=[[164, 52, 1.6]],
         walls=[dict(box=[174, 48, 182, 56], gates=["w", "s"], gate_w=3)]),
    dict(id="moss", name="Mossmere", role="grove", region=3, poi=[44, 172], noise=0.14, biome="bloom", danger=0,
         shapes=[circle(44, 172, 17), circle(40, 176, 7, 1)], sheer=[[300, 330]], bush=[[52, 164, 1.6]]),
    dict(id="still", name="Stillwater", role="nest", region=4, poi=[172, 172], noise=0.14, biome="storm", danger=0,
         shapes=[circle(172, 172, 17), circle(176, 176, 7, 1)], sheer=[[210, 240]], bush=[[164, 164, 1.6]],
         walls=[dict(box=[162, 164, 170, 172], gates=["w", "n"], gate_w=3)]),
    # The outer ring: smaller landings where the first gates open.
    dict(id="skyport", name="Skyport", role="landing", region=2, poi=[108, 17], noise=0.12, biome="frost", danger=0,
         shapes=[circle(108, 17, 10)], sheer=[]),
    dict(id="dawn", name="Dawnrest", role="landing", region=4, poi=[108, 199], noise=0.12, biome="bloom", danger=0,
         shapes=[circle(108, 199, 10)], sheer=[]),
    dict(id="iron", name="Ironfall", role="landing", region=3, poi=[16, 108], noise=0.12, biome="ember", danger=0,
         shapes=[circle(16, 108, 10)], sheer=[]),
    dict(id="fern", name="Fernway", role="landing", region=1, poi=[200, 108], noise=0.12, biome="storm", danger=0,
         shapes=[circle(200, 108, 10)], sheer=[]),
]

# High perches over the diagonal gaps around the Heart.
PERCHES = [("spire", "Stormspire", "storm", 134, 82, 12), ("needle", "Frost Needle", "frost", 82, 82, 13),
           ("emberspire", "Ember Spire", "ember", 82, 134, 12), ("eye", "Gloom Eye", "gloom", 134, 134, 11)]
for pid, name, biome, x, z, lv in PERCHES:
    islands.append(dict(id=pid, name=name, role="perch", biome=biome, danger=2, poi=[x, z], noise=0.08, perch=True, no_rocks=True,
                        shapes=[circle(x, z, 4.2, lv)], sheer=[], chests=[[x, z, 2]]))

BY = {d["id"]: d for d in islands}

def shape_d(S, x, z):
    if "circle" in S:
        cx, cz = S["circle"]; return math.hypot(x - cx, z - cz) / S["r"]
    if "ellipse" in S:
        cx, cz = S["ellipse"]; a = -math.radians(S.get("rot", 0))
        dx, dz = x - cx, z - cz
        qx, qz = dx * math.cos(a) - dz * math.sin(a), dx * math.sin(a) + dz * math.cos(a)
        return math.hypot(qx / S["rx"], qz / S["rz"])
    if "rect" in S:
        x0, z0, x1, z1 = S["rect"]
        return max(abs(x - (x0 + x1) / 2) / ((x1 - x0) / 2), abs(z - (z0 + z1) / 2) / ((z1 - z0) / 2))
    if "capsule" in S:
        x0, z0, x1, z1 = S["capsule"]
        vx, vz = x1 - x0, z1 - z0; L2 = vx * vx + vz * vz
        t = max(0, min(1, ((x - x0) * vx + (z - z0) * vz) / L2)) if L2 else 0
        return math.hypot(x - (x0 + vx * t), z - (z0 + vz * t)) / S["r"]
    return 99

def inside(iid, x, z, margin=0.0):
    """Inside the island's outline (only lv-0 / base shapes count, so bridges land on the low ground)."""
    return any(shape_d(S, x, z) < 1.0 - margin for S in BY[iid]["shapes"] if not S.get("cut"))

def level_at(iid, x, z):
    lv = -1
    for S in BY[iid]["shapes"]:
        if shape_d(S, x, z) < 1.0: lv = max(lv, S.get("lv", 0))
    return lv

def bridge(name, a, b, p0, p1, r, dig=3.0):
    """A bridge along the line p0 -> p1 (rough points near each island). The ends are pulled to the
    rims, then pushed a few tiles inside so the neck joins solid ground on both sides."""
    (x0, z0), (x1, z1) = p0, p1
    L = math.hypot(x1 - x0, z1 - z0); ux, uz = (x1 - x0) / L, (z1 - z0) / L
    # last point inside a walking forward, first point inside b walking forward
    t_a = 0.0
    t = 0.0
    while t < L:
        if inside(a, x0 + ux * t, z0 + uz * t, 0.04): t_a = t
        t += 0.25
    t_b = L
    t = t_a + 0.5
    while t <= L:
        if inside(b, x0 + ux * t, z0 + uz * t, 0.04): t_b = t; break
        t += 0.25
    fa = (round(x0 + ux * (t_a - dig), 1), round(z0 + uz * (t_a - dig), 1))
    fb = (round(x0 + ux * (t_b + dig), 1), round(z0 + uz * (t_b + dig), 1))
    assert inside(a, *fa) and inside(b, *fb), (name, fa, fb)
    return dict(name=name, a=a, b=b, **{"from": list(fa)}, to=list(fb), r=r, span=round(t_b - t_a, 1))

bridges = [
    # ways into the Heart: these are the chokepoints
    bridge("North Span", "heart", "keep", (106, 108), (106, 40), 2.2),
    bridge("Frost Steps", "heart", "keep", (120, 108), (124, 40), 1.0),
    bridge("Bramble Bridge", "heart", "nest", (110, 108), (110, 176), 1.6),
    bridge("Thorn Walk", "heart", "nest", (96, 108), (92, 176), 1.0),
    bridge("Quarry Causeway", "heart", "quarry", (108, 106), (40, 104), 2.0),
    bridge("Storm Causeway", "heart", "shrine", (108, 110), (176, 112), 1.8),
    # the ring road: regions to corners, wide enough to fight on
    bridge("Lantern Road", "keep", "lantern", (80, 50), (40, 46), 1.6),
    bridge("Gull Road", "keep", "gull", (136, 50), (176, 46), 1.6),
    bridge("Moss Road", "nest", "moss", (80, 166), (40, 170), 1.6),
    bridge("Still Road", "nest", "still", (136, 166), (176, 170), 1.6),
    bridge("Quarry North Road", "quarry", "lantern", (54, 82), (46, 40), 1.4),
    bridge("Quarry South Road", "quarry", "moss", (54, 134), (46, 176), 1.4),
    bridge("Storm North Road", "shrine", "gull", (162, 80), (170, 40), 1.4),
    bridge("Storm South Road", "shrine", "still", (162, 136), (170, 176), 1.4),
    # out to the landings
    bridge("Port Stair", "keep", "skyport", (108, 50), (108, 14), 1.4),
    bridge("Dawn Bridge", "nest", "dawn", (108, 166), (108, 202), 1.4),
    bridge("Iron Rope", "quarry", "iron", (50, 108), (12, 108), 1.0),
    bridge("Fern Rope", "shrine", "fern", (166, 108), (204, 108), 1.0),
]

winds = [
    ["heart", "shrine", "Wind Gap"],
    ["skyport", "lantern"], ["skyport", "gull"], ["dawn", "moss"], ["dawn", "still"],
    ["iron", "lantern"], ["iron", "moss"], ["fern", "gull"], ["fern", "still"],
]

pads = [["heart", "spire", "up"], ["heart", "needle", "up"], ["heart", "emberspire", "up"], ["heart", "eye", "up"],
        ["keep", "needle", "up"], ["shrine", "spire", "up"], ["quarry", "emberspire", "up"], ["nest", "eye", "up"]]

updrafts = []
glides = []
for pid, name, biome, x, z, lv in PERCHES:
    ux, uz = (x - C) / math.hypot(x - C, z - C), (z - C) / math.hypot(x - C, z - C)
    # a short column just off the Heart's rim, then a tall one beside the perch
    # (nudged a little round the ring where a train stop's pier runs out beside the diagonal)
    rot = {"eye": -6, "needle": 6}.get(pid, 0)
    a = math.atan2(uz, ux) + math.radians(rot)
    updrafts.append(dict(at=[round(C + math.cos(a) * 24.5), round(C + math.sin(a) * 24.5)], top=6))
    updrafts.append(dict(at=[round(x - ux * 4 - uz * 4.5), round(z - uz * 4 + ux * 4.5)], top=lv + 2))
    # and back down to the Heart or either neighbouring region
    glides.append([pid, "heart"])
    near = {"spire": ["keep", "shrine"], "needle": ["keep", "quarry"], "emberspire": ["quarry", "nest"], "eye": ["nest", "shrine"]}[pid]
    for n in near: glides.append([pid, n])
# glide lanes over the long outer gaps
for at in [[76, 28], [140, 28], [76, 188], [140, 188], [28, 76], [28, 140], [188, 76], [188, 140]]:
    updrafts.append(dict(at=at, top=3))

# The sky train: a loop round the Heart, through the gaps between it and the regions. It stops at four
# piers (walk on), dips under the six Heart bridges between them, and never stops running.
train = dict(center=[108, 108], r=30, stations=[52, 151, 220, 331], names=["Thornwatch Stop", "Petal Stop", "Cinder Stop", "Static Stop"],
             cars=4, speed=8.0, dwell=6.0)

# The ways out (see scripts/match/exits.gd):
#  docks    [x, z, out_x, out_z]: a skiff dock on each outer landing, its pier pointing out over the abyss
#  outposts [x, z, walled]: uplink outposts in the walled yards on three corner islands (walls above; the
#           yards sit beside the roads in, with a gate facing each, never across a bridge's end)
#  hatches  [x, z]: sealed rift hatches spread over the regions, opened with a Rift Key
docks = [[108, 11, 0, -1], [108, 205, 0, 1], [10, 108, -1, 0], [206, 108, 1, 0]]
outposts = [[38, 52, 1], [178, 52, 1], [166, 168, 1]]
hatches = [[90, 62], [124, 152], [48, 92], [172, 100], [50, 178], [119, 95]]
chokepoints = ["North Span", "Frost Steps", "Bramble Bridge", "Thorn Walk", "Quarry Causeway", "Storm Causeway", "Wind Gap"]

# sanity: islands must not touch (keep at least a 3-tile gap between outlines)
def cells(iid):
    d = BY[iid]
    xs = []
    for z in range(216):
        for x in range(216):
            if inside(iid, x + 0.5, z + 0.5): xs.append((x, z))
    return set(xs)

if __name__ == "__main__":
    import sys
    occ = {}
    clash = []
    for d in islands:
        for c in cells(d["id"]):
            for dx in range(-2, 3):
                for dz in range(-2, 3):
                    o = occ.get((c[0] + dx, c[1] + dz))
                    if o and o != d["id"]: clash.append((o, d["id"]))
        for c in cells(d["id"]): occ[c] = d["id"]
    if clash:
        print("too close:", sorted(set(clash)))
    for u in updrafts:
        if (u["at"][0], u["at"][1]) in occ: print("updraft on ground:", u, occ[(u["at"][0], u["at"][1])])
    print("ground tiles ~", len(occ), " islands", len(islands), " bridges", len(bridges))
    for b in bridges: print("  %-18s %-7s->%-8s span %5.1f r %.1f" % (b["name"], b["a"], b["b"], b["span"], b["r"]))
    out = dict(id="skyreach", name="Skyreach", size=216, seed=4242,
               notes=("Hand-made expedition map. Big walkable regions: the Heart in the middle, four large regions around it "
                      "(Frostkeep N, Stormreach E, Bloomwild S, Ember Quarry W), four calm corner islands and four outer landings. "
                      "A ring road of wide bridges joins every region to its corners, so most of the map can be walked. Only six "
                      "bridges and one wind road lead into the Heart: these are the chokepoints. Perches float over the four diagonal "
                      "gaps; reach them by a one-way pad or an updraft chain and glide back down. Angles are degrees around an island's "
                      "centre (0 = east, 90 = south); 'sheer' arcs can't be grabbed, every other rim has a stone lip. Exits: skiff docks on "
                      "the four landings, walled uplink outposts on three corner islands, rift hatches scattered over the regions. Generated by "
                      "tools/make_skyreach.py."),
               islands=islands, bridges=[{k: v for k, v in b.items() if k != "span"} for b in bridges],
               winds=winds, pads=pads, updrafts=updrafts, train=train, docks=docks, outposts=outposts, hatches=hatches,
               chokepoints=chokepoints, glides=glides)
    path = os.path.join(os.path.dirname(__file__), "..", "content", "maps", "skyreach.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=1)
    print("wrote", os.path.normpath(path))
