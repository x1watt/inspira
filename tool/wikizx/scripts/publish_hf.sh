#!/usr/bin/env bash
# Publishes the Wikipedia databases to a Hugging Face dataset
# (docs/plan-wiki-hosting.md, section 2a): each FILE goes up whole with a
# manifest FILE.parts naming it as its only part, so the zx web engine
# reads it in 64 KiB range blocks, plus the dataset card (README.md).
#
#   scripts/publish_hf.sh DATASET_ID FILE [FILE ...]
#   scripts/publish_hf.sh x1watt/inspira-wikipedia ../../build/wiki/en_mini.zx ../../build/wiki/geo.zx
#
# Needs `hf auth login` (a token with write access) once. The dataset is
# created public when it does not exist. Uploads are deduplicated by
# Hugging Face's Xet storage: a new version sends mostly what changed.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
hf=${HF:-$(command -v hf || echo "$HOME/.platformio/penv/bin/hf")}
repo=$1
shift
stage=$(mktemp -d "${TMPDIR:-/tmp}/publish_hf.XXXXXX")
trap 'rm -rf "$stage"' EXIT

for f in "$@"; do
  name=$(basename "$f")
  size=$(stat -c %s "$f")
  sum=$(sha256sum "$f" | cut -d' ' -f1)
  cat > "$stage/$name.parts" <<JSON
{
 "zxParts": 1,
 "name": "$name",
 "size": $size,
 "partSize": $size,
 "parts": [
  {"file": "$name", "size": $size, "sha256": "$sum"}
 ]
}
JSON
  echo "$name: $size bytes, sha256 $sum"
done
cp "$here/dataset_card.md" "$stage/README.md"

"$hf" repos create "$repo" --repo-type dataset --public --exist-ok
for f in "$@"; do
  "$hf" upload "$repo" "$f" "$(basename "$f")" --repo-type dataset \
    --commit-message "$(basename "$f")"
done
"$hf" upload "$repo" "$stage" . --repo-type dataset \
  --commit-message "manifests and dataset card"
echo "Manifests: https://huggingface.co/datasets/$repo/resolve/main/<FILE>.parts"
