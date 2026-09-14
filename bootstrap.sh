#!/usr/bin/env bash
#
# Fetch the two upstream community toolchains at the exact commits this project
# was built and verified against, then apply our packaging patches on top.
#
# We deliberately do NOT vendor upstream code into this repository. Both
# upstream projects are MIT licensed and could legally be vendored, but keeping
# this repo as a thin, auditable layer means:
#
#   * no 1.3 GB of third-party build output in git history
#   * the provenance of every file stays obvious (upstream vs. ours)
#   * upstream fixes can be picked up by bumping the pinned commits below
#
# Layout produced:
#
#   upstream/port-tool/   LX2000WASD/workbuddy-international-linux  (DMG -> app)
#   upstream/deb-tool/    Xboxpig/workbuddy-desktop-linux           (app -> .deb)
#                         ^ our patches/deb-tool.patch applied in place
#
# Usage:
#   ./bootstrap.sh            fetch and patch
#   ./bootstrap.sh --force    wipe upstream/ and re-fetch from scratch
#
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM="$ROOT/upstream"

# --------------------------------------------------------------- pinned ------
# Pinned commits, not branches. A branch would make builds non-reproducible the
# moment upstream force-pushes or rewrites history.
PORT_REPO="https://github.com/LX2000WASD/workbuddy-international-linux.git"
PORT_COMMIT="c2b731cf0fa566306c89697ef95c472d17525a93"

DEB_REPO="https://github.com/Xboxpig/workbuddy-desktop-linux.git"
DEB_COMMIT="66103bafff518ad17a64ca34dbdbee0d2085f4a3"

PATCH="$ROOT/patches/deb-tool.patch"

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

info() { echo "[bootstrap] $*" >&2; }
die()  { echo "[bootstrap] ERROR: $*" >&2; exit 1; }

for tool in git patch; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required but not installed"
done

# Fetch one repository at one exact commit. A shallow fetch of a specific SHA
# keeps the download small (these repos are mostly binary assets upstream keeps
# out of git, but the history is still not worth pulling).
fetch_at_commit() {
    local dir="$1" repo="$2" commit="$3" name="$4"

    if [ -d "$dir/.git" ]; then
        if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$commit" ] && [ "$FORCE" -eq 0 ]; then
            info "$name already at ${commit:0:8}"
            return 0
        fi
        info "$name present but at the wrong commit; re-fetching"
        /usr/bin/rm -rf "$dir"
    fi

    info "fetching $name @ ${commit:0:8}"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" remote add origin "$repo"
    # --depth 1 on an explicit SHA works on GitHub and avoids pulling history.
    if ! git -C "$dir" fetch -q --depth 1 origin "$commit" 2>/dev/null; then
        info "  shallow fetch of a bare SHA was refused; falling back to full fetch"
        git -C "$dir" fetch -q origin "$commit"
    fi
    git -C "$dir" checkout -q FETCH_HEAD
    git -C "$dir" -c advice.detachedHead=false checkout -q "$commit" 2>/dev/null || true

    local actual
    actual="$(git -C "$dir" rev-parse HEAD)"
    [ "$actual" = "$commit" ] || die "$name landed on $actual, expected $commit"
    info "$name ready ($(git -C "$dir" rev-list --count HEAD 2>/dev/null || echo 1) commit(s))"
}

mkdir -p "$UPSTREAM"

fetch_at_commit "$UPSTREAM/port-tool" "$PORT_REPO" "$PORT_COMMIT" "port-tool"
fetch_at_commit "$UPSTREAM/deb-tool"  "$DEB_REPO"  "$DEB_COMMIT"  "deb-tool"

# ------------------------------------------------------------- patching ------
# The patch is idempotent: if it is already applied we say so instead of
# failing, so `bootstrap.sh` can be re-run safely at any time.
[ -f "$PATCH" ] || die "missing $PATCH"

if git -C "$UPSTREAM/deb-tool" apply --check "$PATCH" 2>/dev/null; then
    info "applying patches/deb-tool.patch"
    git -C "$UPSTREAM/deb-tool" apply "$PATCH"
    info "patch applied"
elif git -C "$UPSTREAM/deb-tool" apply --check --reverse "$PATCH" 2>/dev/null; then
    info "patches/deb-tool.patch already applied"
else
    die "patch does not apply cleanly and is not already applied.
  Upstream may have changed. Inspect:
    git -C upstream/deb-tool status
    git -C upstream/deb-tool apply --check -v patches/deb-tool.patch"
fi

# ------------------------------------------------------------- summary -------
echo >&2
info "upstream ready:"
echo "    port-tool  $(git -C "$UPSTREAM/port-tool" rev-parse --short HEAD)  LX2000WASD/workbuddy-international-linux" >&2
echo "    deb-tool   $(git -C "$UPSTREAM/deb-tool" rev-parse --short HEAD)  Xboxpig/workbuddy-desktop-linux (+ $(basename "$PATCH"))" >&2
echo >&2
info "next: ./build.sh            # convert DMG + build .deb"
info "      ./install-user.sh     # install to ~/.local (no root needed)"
