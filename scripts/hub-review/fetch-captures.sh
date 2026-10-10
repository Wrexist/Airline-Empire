#!/usr/bin/env bash
# Download the Hub View frames rendered by the `Hub view review` workflow.
#
#   scripts/hub-review/fetch-captures.sh <run-id|head-sha> [out-dir]
#
# Writes <out-dir>/{ipad,iphone}/KEY-HUB-*.png, with the iPad frames rotated
# upright (XCUIScreen captures a landscape iPad into a portrait buffer).
set -euo pipefail
REPO=${REPO:-Wrexist/Airline-Empire}
ARG=${1:?usage: fetch-captures.sh <run-id|head-sha> [out-dir]}
OUT=${2:-.hub-review/captures}
if [[ ${#ARG} -ge 7 && ! $ARG =~ ^[0-9]+$ ]]; then
  RUN=$(gh api "repos/$REPO/actions/runs?head_sha=$ARG" \
        --jq '.workflow_runs[] | select(.name=="Hub view review") | .id' | head -1)
  [[ -n $RUN ]] || { echo "no Hub view review run for $ARG" >&2; exit 1; }
else
  RUN=$ARG
fi
echo "run $RUN -> $OUT"
TMP=$(mktemp -d)
gh api "repos/$REPO/actions/runs/$RUN/artifacts" --jq '.artifacts[] | "\(.id) \(.name)"' |
while read -r id name; do
  gh api "repos/$REPO/actions/artifacts/$id/zip" > "$TMP/$name.zip"
  mkdir -p "$TMP/$name" && unzip -q -o "$TMP/$name.zip" -d "$TMP/$name"
done
python3 -I "$(dirname "$0")/collect.py" "$TMP" "$OUT"
rm -rf "$TMP"
