#!/bin/bash
set -euo pipefail

PACK=${1:?usage: preview-pack.sh <pack-folder>}
[ -f "$PACK/pack.json" ] || { echo "No pack at $PACK" >&2; exit 1; }

pick() {
  for name in "$@"; do
    for ext in caf wav aiff aif; do
      [ -f "$PACK/$name.$ext" ] && { echo "$PACK/$name.$ext"; return; }
    done
  done
}

key() {
  local category=$1 row=$2
  local down up
  down=$(pick "${category}_down_r$row" "${category}_down_1" "alpha_down_r$row" "alpha_down_1")
  up=$(pick "${category}_up_r$row" "${category}_up_1" "alpha_up_r$row" "alpha_up_1")
  [ -n "$down" ] && afplay "$down" &
  sleep 0.09
  [ -n "$up" ] && afplay "$up" &
  sleep 0.08
}

for row in 3 2 3 4 1 3; do key alpha "$row"; done
key space 4
for row in 2 3 2; do key alpha "$row"; done
sleep 0.15
key enter 3
wait
