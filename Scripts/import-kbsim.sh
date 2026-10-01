#!/bin/bash
set -euo pipefail
shopt -s nullglob

DEST=${1:?usage: import-kbsim.sh <packs-folder>}
REV=master
BASE="https://raw.githubusercontent.com/tplai/kbsim/$REV/src/assets/audio"
WORK=$(mktemp -d -t thock-kbsim)
trap 'rm -rf "$WORK"' EXIT

PACKS=(
  "holypanda|holypanda|Holy Panda"
  "cream|cream|NovelKeys Cream"
  "mxbrown|mxbrown|Cherry MX Brown"
  "mxblack|mxblack|Cherry MX Black"
  "mxblue|mxblue|Cherry MX Blue"
  "boxnavy|boxnavy|Kailh Box Navy"
  "bluealps|bluealps|Alps SKCM Blue"
  "topre|topre|Topre"
)

FILES=(
  "press/GENERIC_R0|alpha_down_r0" "press/GENERIC_R1|alpha_down_r1" "press/GENERIC_R2|alpha_down_r2"
  "press/GENERIC_R3|alpha_down_r3" "press/GENERIC_R4|alpha_down_r4"
  "press/SPACE|space_down_1" "press/ENTER|enter_down_1" "press/BACKSPACE|backspace_down_1"
  "release/GENERIC|alpha_up_1" "release/SPACE|space_up_1" "release/ENTER|enter_up_1" "release/BACKSPACE|backspace_up_1"
)

install_if_changed() {
  if ! cmp -s "$1" "$2"; then
    cp "$1" "$2"
    echo "  wrote $(basename "$2")"
  fi
}

curl -fsSL "https://raw.githubusercontent.com/tplai/kbsim/$REV/LICENSE.md" -o "$WORK/LICENSE.txt"

for pack in "${PACKS[@]}"; do
  IFS='|' read -r id folder name <<<"$pack"
  echo "$id"
  out="$WORK/$id"
  mkdir -p "$out"
  for file in "${FILES[@]}"; do
    IFS='|' read -r source target <<<"$file"
    if ! curl -fsL "$BASE/$folder/$source.mp3" -o "$out/$target.mp3"; then
      echo "  no $source"
      continue
    fi
    afconvert -f caff -d LEI16@48000 -c 1 -r 127 "$out/$target.mp3" "$out/$target.caf"
  done
  cat >"$out/pack.json" <<EOF
{
  "name": "$name",
  "author": "Thomas Lai (kbsim)",
  "license": "MIT",
  "source": "https://github.com/tplai/kbsim/tree/$REV/src/assets/audio/$folder"
}
EOF
  cp "$WORK/LICENSE.txt" "$out/LICENSE.txt"
  mkdir -p "$DEST/$id"
  for existing in "$DEST/$id"/*; do
    [ -e "$out/$(basename "$existing")" ] || { rm "$existing"; echo "  removed $(basename "$existing")"; }
  done
  for converted in "$out"/*.caf "$out/pack.json" "$out/LICENSE.txt"; do
    install_if_changed "$converted" "$DEST/$id/$(basename "$converted")"
  done
done
