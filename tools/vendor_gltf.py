#!/usr/bin/env python3
"""Copies glTF models from a downloaded CC0 asset pack into res://art/vendor/, compacted.

Each model is rewritten as one small .glb with no embedded images: KayKit packs colour every model
from one shared palette texture, which we vendor once per pack and sample in our own toon shader
(see scripts/core/assets.gd). Animations can be filtered down to the ones the game plays.
Only reads the source files as data (JSON and binary buffers); nothing in them is executed.

usage: vendor_gltf.py SRC DEST [--anims Name1,Name2,...]
  SRC  a .gltf (with its .bin next to it) or .glb
  DEST the .glb to write
"""
import json
import os
import struct
import sys


def load(src):
    if src.endswith(".glb"):
        data = open(src, "rb").read()
        assert data[:4] == b"glTF", "not a glb"
        off = 12
        j = None
        binchunk = b""
        while off < len(data):
            ln, typ = struct.unpack("<II", data[off:off + 8])
            chunk = data[off + 8:off + 8 + ln]
            if typ == 0x4E4F534A:
                j = json.loads(chunk)
            elif typ == 0x004E4942:
                binchunk = chunk
            off += 8 + ln
        return j, [binchunk]
    j = json.load(open(src))
    bufs = []
    for b in j["buffers"]:
        uri = b["uri"]
        assert not uri.startswith("data:") and "/" not in uri and ".." not in uri, "unexpected buffer uri"
        bufs.append(open(os.path.join(os.path.dirname(src), uri), "rb").read())
    return j, bufs


def compact(j, bufs, keep_anims=None):
    # drop textures and images: the palette texture is shared and applied by our shader
    for m in j.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        pbr.pop("baseColorTexture", None)
        pbr.pop("metallicRoughnessTexture", None)
        for k in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            m.pop(k, None)
    for k in ("images", "textures", "samplers"):
        j.pop(k, None)
    for k in ("extensionsUsed", "extensionsRequired"):
        if k in j:
            j[k] = [e for e in j[k] if e != "KHR_texture_transform"]
            if not j[k]:
                j.pop(k)
    if keep_anims is not None:
        j["animations"] = [a for a in j.get("animations", []) if a["name"] in keep_anims]
        missing = set(keep_anims) - {a["name"] for a in j["animations"]}
        if missing:
            print("  missing animations:", sorted(missing))
        if not j["animations"]:
            j.pop("animations")
    # which accessors are still used
    used = set()
    for me in j.get("meshes", []):
        for p in me["primitives"]:
            used.update(p["attributes"].values())
            if "indices" in p:
                used.add(p["indices"])
            for t in p.get("targets", []):
                used.update(t.values())
    for s in j.get("skins", []):
        if "inverseBindMatrices" in s:
            used.add(s["inverseBindMatrices"])
    for a in j.get("animations", []):
        for s in a["samplers"]:
            used.add(s["input"]); used.add(s["output"])
    acc_map = {}
    new_acc = []
    for i, a in enumerate(j.get("accessors", [])):
        if i in used:
            acc_map[i] = len(new_acc)
            new_acc.append(a)
    used_views = sorted({a["bufferView"] for a in new_acc if "bufferView" in a})
    view_map = {}
    out = bytearray()
    new_views = []
    for vi in used_views:
        v = dict(j["bufferViews"][vi])
        src = bufs[v.get("buffer", 0)]
        start = v.get("byteOffset", 0)
        blob = src[start:start + v["byteLength"]]
        while len(out) % 4:
            out.append(0)
        v["buffer"] = 0
        v["byteOffset"] = len(out)
        out += blob
        view_map[vi] = len(new_views)
        new_views.append(v)
    while len(out) % 4:
        out.append(0)
    for a in new_acc:
        if "bufferView" in a:
            a["bufferView"] = view_map[a["bufferView"]]
    j["accessors"] = new_acc
    j["bufferViews"] = new_views
    j["buffers"] = [{"byteLength": len(out)}]
    for me in j.get("meshes", []):
        for p in me["primitives"]:
            p["attributes"] = {k: acc_map[v] for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = acc_map[p["indices"]]
            p["targets"] = [{k: acc_map[v] for k, v in t.items()} for t in p.get("targets", [])]
            if not p["targets"]:
                p.pop("targets")
    for s in j.get("skins", []):
        if "inverseBindMatrices" in s:
            s["inverseBindMatrices"] = acc_map[s["inverseBindMatrices"]]
    for a in j.get("animations", []):
        for s in a["samplers"]:
            s["input"] = acc_map[s["input"]]; s["output"] = acc_map[s["output"]]
    return j, bytes(out)


def write_glb(dest, j, binblob):
    js = json.dumps(j, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(binblob)
    with open(dest, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(binblob), 0x004E4942)); f.write(binblob)


def main():
    args = sys.argv[1:]
    anims = None
    if "--anims" in args:
        k = args.index("--anims")
        anims = args[k + 1].split(",")
        del args[k:k + 2]
    src, dest = args
    j, bufs = load(src)
    j, blob = compact(j, bufs, anims)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    write_glb(dest, j, blob)
    print("%s -> %s (%d KB)" % (os.path.basename(src), dest, os.path.getsize(dest) // 1024))


if __name__ == "__main__":
    main()
