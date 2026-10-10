#!/usr/bin/env bash
# Cut the five reference frames out of the owner's reference clip.
#
#   scripts/hub-review/extract-reference.sh <reference.mp4> [out-dir]
#
# The clip is NOT in the repo (the repo is public and the clip is someone
# else's work). Ask the owner for it and keep it under .hub-review/, which is
# git-ignored. The clip is 540x780: two stacked 540x300 panels; the lower
# panel (y 459-763 in the 4 fps frames) is the primary target.
set -euo pipefail
CLIP=${1:?usage: extract-reference.sh <reference.mp4> [out-dir]}
OUT=${2:-.hub-review/reference}
mkdir -p "$OUT"
# shot  time(s)
for pair in "01-overview 0.5" "02-gate 2.5" "03-terminal 5.5" "04-district 7.0" "05-district-night 8.5"; do
  set -- $pair
  ffmpeg -loglevel error -y -ss "$2" -i "$CLIP" -frames:v 1 \
    -vf "crop=540:304:0:459,scale=1080:-1:flags=lanczos" "$OUT/REF-HUB-$1.png"
done
# Every frame at 4 fps too, for finding the sharpest one per shot.
mkdir -p "$OUT/all"
ffmpeg -loglevel error -y -i "$CLIP" -vf fps=4 "$OUT/all/%03d.png"
ls "$OUT"
