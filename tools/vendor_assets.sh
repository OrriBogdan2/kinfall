#!/usr/bin/env bash
# Re-creates res://art/vendor/ from shallow clones of the KayKit packs (all CC0, see
# docs/ASSET_CREDITS.md). Usage: tools/vendor_assets.sh <dir holding the cloned pack repos>
# Only the models the game uses are copied, compacted by tools/vendor_gltf.py.
set -euo pipefail
P="$1"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../art/vendor"
V="python3 -I $HERE/vendor_gltf.py"

HEX="$P/KayKit-Medieval-Hexagon-Pack-1.0/addons/kaykit_medieval_hexagon_pack/Assets/gltf/decoration"
HW="$P/KayKit-Halloween-Bits-1.0/addons/kaykit_halloween_bits/Assets/gltf"
DG="$P/KayKit-Dungeon-Remastered-1.0/addons/kaykit_dungeon_remastered/Assets"
SK="$P/KayKit-Character-Pack-Skeletons-1.0/addons/kaykit_character_pack_skeletons"

mkdir -p "$OUT"/{hexagon,halloween,dungeon,skeletons}
cp "$HEX/nature/hexagons_medieval.png" "$OUT/hexagon/palette.png"
cp "$HW/halloweenbits_texture.png" "$OUT/halloween/palette.png"
cp "$DG/texture/dungeon_texture.png" "$OUT/dungeon/palette.png"
cp "$SK/Assets/gltf/skeleton_texture.png" "$OUT/skeletons/palette.png"

for m in tree_single_A tree_single_B trees_A_small trees_B_small rock_single_A rock_single_B rock_single_C rock_single_D rock_single_E mountain_A mountain_B mountain_C; do
	$V "$HEX/nature/$m.gltf" "$OUT/hexagon/$m.glb"
done
for m in barrel crate_A_big crate_A_small crate_B_small sack tent resource_lumber resource_stone wheelbarrow weaponrack flag_red pallet; do
	$V "$HEX/props/$m.gltf" "$OUT/hexagon/$m.glb"
done
for m in tree_pine_orange_large tree_pine_orange_medium tree_pine_orange_small tree_pine_yellow_large tree_dead_large tree_dead_large_decorated tree_dead_medium tree_dead_small \
		pillar fence fence_pillar fence_broken arch gravestone grave_A gravemarker_A lantern_standing post_lantern bone_A skull shrine_candles bench; do
	$V "$HW/$m.gltf" "$OUT/halloween/$m.glb"
done
for m in chest chest_gold; do
	$V "$DG/gltf/$m.glb" "$OUT/dungeon/$m.glb"
done
for m in pillar pillar_decorated column rubble_large rubble_half barrel_small barrel_large box_small box_large crates_stacked torch_lit; do
	$V "$DG/gltf/$m.gltf.glb" "$OUT/dungeon/$m.glb"
done
ANIMS="Idle,Unarmed_Idle,2H_Melee_Idle,Walking_D_Skeletons,Running_A,1H_Melee_Attack_Chop,1H_Melee_Attack_Stab,2H_Melee_Attack_Chop,Spellcast_Shoot,Unarmed_Melee_Attack_Punch_A,Hit_A,Death_C_Skeletons,Spawn_Ground_Skeletons"
for m in Skeleton_Minion Skeleton_Mage Skeleton_Warrior Skeleton_Rogue; do
	$V "$SK/Characters/gltf/$m.glb" "$OUT/skeletons/$m.glb" --anims "$ANIMS"
done
for m in Skeleton_Axe Skeleton_Blade Skeleton_Staff Skeleton_Shield_Large_A Skeleton_Shield_Small_A; do
	$V "$SK/Assets/gltf/$m.gltf" "$OUT/skeletons/$m.glb"
done
du -sh "$OUT"
