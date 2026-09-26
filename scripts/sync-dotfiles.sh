#!/usr/bin/env bash
#
# Vendor Lumin-OS/dotfiles into the archiso profile.
#
#   ./scripts/sync-dotfiles.sh [path-to-dotfiles-checkout]
#
# Copies the dotfiles repo's .config/ into
# releng/airootfs/home/luminos/.config/ and records the source commit in
# dotfiles.pin.
#
# Why vendor instead of cloning during the build:
#   - An ISO build that fetches from GitHub is not reproducible. The image would
#     change whenever dotfiles moved, with nothing in the LuminOS repo recording
#     which version went in.
#   - It would also make the build require network at a point where it otherwise
#     only needs the pinned package snapshot.
# So the copy is committed, and dotfiles.pin is the provenance record. Run this
# whenever dotfiles changes, then commit the result.

set -euo pipefail

cd -- "$(dirname -- "$(readlink -f -- "$0")")/.."
readonly DEST="releng/airootfs/home/luminos/.config"
readonly PIN="dotfiles.pin"

# Default to the sibling checkout the Paperclip workspace provides, but accept an
# explicit path so this works from an ordinary clone too.
src="${1:-}"
if [[ -z $src ]]; then
    # shellcheck disable=SC2012
    src=$(ls -d .paperclip-repositories/dotfiles-* 2>/dev/null | head -1 || true)
fi
[[ -n $src && -d $src ]] || {
    echo "usage: $0 <path-to-dotfiles-checkout>" >&2
    echo "  (no .paperclip-repositories/dotfiles-* found to default to)" >&2
    exit 1
}
[[ -d "$src/.config" ]] || { echo "ERROR: $src has no .config/ directory" >&2; exit 1; }

commit=$(git -C "$src" rev-parse HEAD 2>/dev/null || echo "unknown")
dirty=""
if ! git -C "$src" diff --quiet HEAD 2>/dev/null; then
    dirty=" (DIRTY WORKTREE — commit dotfiles first for a reproducible pin)"
fi

echo "source : $src"
echo "commit : $commit$dirty"
echo "dest   : $DEST"

rm -rf -- "$DEST"
mkdir -p -- "$DEST"

# --exclude: repo furniture that has no business in a 900MB squashfs.
# Screenshot.png in particular is a README asset, not a runtime file.
rsync -a --delete \
    --exclude '.git' \
    --exclude 'README.md' \
    --exclude 'Screenshot.png' \
    --exclude 'LICENSE' \
    -- "$src/.config/" "$DEST/"

cat > "$PIN" <<EOF
# Provenance for the vendored copy of Lumin-OS/dotfiles in
# releng/airootfs/home/luminos/.config/.
#
# Regenerate with ./scripts/sync-dotfiles.sh — do not edit by hand.
DOTFILES_REPO="https://github.com/Lumin-OS/dotfiles"
DOTFILES_COMMIT="$commit"
DOTFILES_SYNCED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF

echo
echo "Vendored files:"
find "$DEST" -type f | sort | sed 's/^/  /'
echo
echo "Wrote $PIN. Commit both $DEST and $PIN together."
