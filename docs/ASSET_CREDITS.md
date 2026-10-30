# Asset credits

Kinfall's hunters and kin are built procedurally in code (`scripts/match/models.gd`,
`scripts/match/kin_models.gd`). The world's trees, rocks, ruins, crates, chests and the monsters use
free models from the packs below. All of them are **CC0 (public domain)**: free for any use,
commercial included, with no attribution required. We credit them anyway.

| Pack | Author | Source | Commit | License |
| --- | --- | --- | --- | --- |
| KayKit Medieval Hexagon Pack 1.0 | Kay Lousberg (kaylousberg.com) | https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0 | 84fa4e91af6a88989be7c99e0891cede11f2ca38 | CC0 1.0 |
| KayKit Halloween Bits 1.0 | Kay Lousberg | https://github.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0 | 6dc69bf6b2fa766a985754f35ec6a0324090e6c6 | CC0 1.0 |
| KayKit Dungeon Remastered 1.0 | Kay Lousberg | https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0 | b0ca9bd96a8072ab36a3a5464f00ed1e06a16d07 | CC0 1.0 |
| KayKit Character Pack: Skeletons 1.0 | Kay Lousberg | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0 | 15b62b9bad122f72926c10fb14d622c73819fa54 | CC0 1.0 |

Each pack's `LICENSE.txt` reads: "License: (Creative Commons Zero, CC0)
http://creativecommons.org/publicdomain/zero/1.0/ ... This content is free to use in personal,
educational and commercial projects. Support me by crediting Kay Lousberg, www.kaylousberg.com
(this is not mandatory)".

No assets from SUPERVIVE or any other commercial game are used.

## What's vendored

Only the models the game uses are copied into `art/vendor/<pack>/`, one compact `.glb` each, plus the
pack's palette texture as `palette.png`:

- `hexagon/`: tree_single_A/B, trees_A/B_small, rock_single_A-E, mountain_A-C, barrel, crates,
  sack, tent, lumber and stone piles, wheelbarrow, weapon rack, flag, pallet.
- `halloween/`: pine trees (orange/yellow, repainted per biome), dead trees, pillar, fences, arch,
  gravestones, lanterns, bones, skull, candle shrine, bench.
- `dungeon/`: chest and gold chest (with their separate lids), pillars and column, rubble,
  barrels, boxes, stacked crates, lit torch.
- `skeletons/`: Skeleton Minion, Mage, Warrior and Rogue (rigged, with a handful of the pack's
  animations kept), and their axe, blade, staff and shields.

## How they're processed

`tools/vendor_assets.sh <dir with the cloned packs>` rebuilds `art/vendor/` from shallow clones of
the repos above. It runs `tools/vendor_gltf.py` on each model, which only reads the files as data and:

- drops the embedded/linked textures (the palette is vendored once per pack and sampled by our own
  toon shader instead),
- keeps only the animations the game plays (the skeletons ship with 95; we keep 13),
- drops unused buffer data and writes one `.glb`.

In game, `scripts/core/assets.gd` maps prop kinds and biomes to these models, sizes them to the tile
grid, batches repeated props into MultiMeshes and draws them with `shaders/toon.gdshader` (which can
repaint one hue band of the palette, so a pine takes each biome's leaf colour) and an ink outline
(`shaders/outline_smooth.gdshader`). Run with `-- --prim-art` to see the old primitive models; the
game also falls back to them for any model that fails to load.

## Audio

Every sound effect is synthesized from scratch by `tools/gen_sfx.py` and `tools/gen_train_sfx.py`
(written to `audio/*.wav`), and glider skins and the home whistle are made in code by
`scripts/core/synth.gd`. Music and ambience are composed procedurally by `tools/gen_music.py` /
`tools/compose.py`. No recorded or downloaded audio is used. `tools/sfx_stats.py` measures the
sound effects (peak, loudness, attack, onset, spectral centroid).
