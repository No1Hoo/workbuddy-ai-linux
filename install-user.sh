#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# WorkBuddy AI (international) — rootless, per-user install.
#
# Installs into ~/.local so it needs no root, no sudo, no dpkg database and no
# writable /opt. After it finishes:
#
#   * "WorkBuddy AI" appears in the application menu
#   * `workbuddy-ai` runs from a terminal (if ~/.local/bin is on PATH)
#   * both URI schemes are registered, which the browser OAuth callback needs
#
# Usage:
#   ./install-user.sh                 install into ~/.local
#   PREFIX=/some/where ./install-user.sh
#   ./install-user.sh --uninstall     remove (user data is kept)
#
# Source of the application tree, first match wins:
#   upstream/deb-tool/dist/deb-root/opt/workbuddy-ai   (after a full build)
#   app/                                               (after --app-only)
# ---------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"

PKG_NAME="workbuddy-ai"
DESKTOP_ID="$PKG_NAME.desktop"

APP_DST="$PREFIX/opt/$PKG_NAME"
BIN_DST="$PREFIX/bin/$PKG_NAME"
DESKTOP_DIR="$PREFIX/share/applications"
DESKTOP_DST="$DESKTOP_DIR/$DESKTOP_ID"
ICON_DST="$PREFIX/share/icons/hicolor/256x256/apps/$PKG_NAME.png"
MIME_PKG_DIR="$PREFIX/share/mime/packages"

log()  { printf '\033[32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------- uninstall ---
if [ "${1:-}" = "--uninstall" ]; then
    log "removing WorkBuddy AI from $PREFIX"
    rm -rf "$APP_DST"
    rm -f  "$BIN_DST" "$DESKTOP_DST" "$ICON_DST" "$MIME_PKG_DIR/$PKG_NAME.xml"
    command -v update-desktop-database >/dev/null 2>&1 && \
        update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    command -v update-mime-database >/dev/null 2>&1 && \
        update-mime-database "$PREFIX/share/mime" 2>/dev/null || true
    log "done. User data in ~/.workbuddy-ai was left untouched."
    exit 0
fi

# ------------------------------------------------------------- locate source -
SRC_APP=""
for candidate in \
    "$HERE/upstream/deb-tool/dist/deb-root/opt/$PKG_NAME" \
    "$HERE/app"
do
    if [ -x "$candidate/start.sh" ]; then SRC_APP="$candidate"; break; fi
done
[ -n "$SRC_APP" ] || die "no application tree found.
  Looked for:
    $HERE/upstream/deb-tool/dist/deb-root/opt/$PKG_NAME
    $HERE/app
  Build it first:  ./build.sh          (or ./build.sh --app-only)"

command -v rsync >/dev/null || die "rsync is required: sudo apt-get install -y rsync"

log "prefix : $PREFIX"
log "source : $SRC_APP"
echo

# ------------------------------------------------------- 1. copy the app -----
mkdir -p "$APP_DST" "$PREFIX/bin" "$DESKTOP_DIR" "$(dirname "$ICON_DST")" "$MIME_PKG_DIR"

log "1/6 copying application files (~1 GB, this takes a moment)…"
rsync -a --delete "$SRC_APP/" "$APP_DST/"
chmod +x "$APP_DST/start.sh" "$APP_DST/electron" 2>/dev/null || true

# ----------------------------------------------------------- 2. launcher -----
log "2/6 writing launcher $BIN_DST"
cat > "$BIN_DST" <<EOF
#!/usr/bin/env bash
# WorkBuddy AI launcher (per-user install, generated $(date -Iseconds))
set -euo pipefail
APP_DIR="$PREFIX/opt/$PKG_NAME"
[ -x "\$APP_DIR/start.sh" ] || { echo "WorkBuddy AI is not installed correctly: \$APP_DIR/start.sh missing" >&2; exit 1; }
# Some IDEs and agent runtimes export ELECTRON_RUN_AS_NODE=1, which turns the
# Electron binary into plain Node and breaks the launch. Clear it.
unset ELECTRON_RUN_AS_NODE || true
exec "\$APP_DIR/start.sh" "\$@"
EOF
chmod +x "$BIN_DST"

# --------------------------------------------------------------- 3. icon -----
log "3/6 installing icon"
ICON_SRC=""
for candidate in \
    "$APP_DST/$PKG_NAME.png" \
    "$APP_DST/.workbuddy-linux/$PKG_NAME.png" \
    "$APP_DST/resources/app.asar.unpacked/resources/icon.png"
do
    [ -f "$candidate" ] && { ICON_SRC="$candidate"; break; }
done
if [ -n "$ICON_SRC" ]; then
    cp -f "$ICON_SRC" "$ICON_DST"
else
    warn "no icon found; skipping (does not affect launching)"
fi

# -------------------------------------------------------- 4. desktop entry ---
# StartupWMClass must match the real X11 WM_CLASS, which is "WorkBuddy AI" —
# not the package name. Otherwise the dock shows a generic icon.
#
# MimeType lists BOTH schemes; see docs/uri-scheme-bug.md.
log "4/6 writing desktop entry $DESKTOP_DST"
cat > "$DESKTOP_DST" <<EOF
[Desktop Entry]
Name=WorkBuddy AI
Comment=Run WorkBuddy AI on Linux
Exec=$BIN_DST %u
Icon=$PKG_NAME
Terminal=false
Type=Application
Categories=Development;
MimeType=x-scheme-handler/$PKG_NAME;x-scheme-handler/workbuddy;
Keywords=workbuddy;ai;agent;coding;
StartupNotify=true
StartupWMClass=WorkBuddy AI
X-GNOME-WMClass=WorkBuddy AI
Actions=new-window;

[Desktop Action new-window]
Name=New Window
Exec=$BIN_DST --new-instance
EOF

# ------------------------------------------------- 5. register URI schemes ---
log "5/6 registering URI schemes (required for the OAuth callback)"
cat > "$MIME_PKG_DIR/$PKG_NAME.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="x-scheme-handler/workbuddy-ai">
    <comment>WorkBuddy AI protocol (OAuth callback)</comment>
  </mime-type>
  <mime-type type="x-scheme-handler/workbuddy">
    <comment>WorkBuddy deep link protocol</comment>
  </mime-type>
</mime-info>
EOF

command -v update-mime-database >/dev/null 2>&1 && \
    update-mime-database "$PREFIX/share/mime" 2>/dev/null || \
    warn "update-mime-database failed (not fatal)"
command -v update-desktop-database >/dev/null 2>&1 && \
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || \
    warn "update-desktop-database failed (not fatal)"

# workbuddy-ai : product.json deepLinkSchemes — the OAuth redirect_uri base
# workbuddy    : hard-coded inside the bundle for internal deep links
if command -v xdg-mime >/dev/null 2>&1; then
    for S in "$PKG_NAME" workbuddy; do
        xdg-mime default "$DESKTOP_ID" "x-scheme-handler/$S" 2>/dev/null || \
            warn "xdg-mime registration for '$S' failed; run manually:
         xdg-mime default $DESKTOP_ID x-scheme-handler/$S"
    done
fi

# ------------------------------------------------------------ 6. self-check --
log "6/6 self-check"
FAIL=0

[ -x "$APP_DST/start.sh" ] || { warn "start.sh missing or not executable"; FAIL=1; }
[ -x "$APP_DST/electron" ] || { warn "electron missing or not executable"; FAIL=1; }
[ -x "$BIN_DST" ]          || { warn "launcher missing"; FAIL=1; }
[ -f "$DESKTOP_DST" ]      || { warn "desktop entry missing"; FAIL=1; }

if command -v desktop-file-validate >/dev/null 2>&1; then
    if desktop-file-validate "$DESKTOP_DST" 2>/dev/null; then
        log "  desktop entry validates cleanly"
    else
        warn "  desktop-file-validate reported issues (usually harmless):"
        desktop-file-validate "$DESKTOP_DST" 2>&1 | sed 's/^/    /'
    fi
fi

for S in "$PKG_NAME" workbuddy; do
    handler="$(xdg-mime query default "x-scheme-handler/$S" 2>/dev/null || true)"
    if [ "$handler" = "$DESKTOP_ID" ]; then
        log "  x-scheme-handler/$S -> $handler"
    else
        warn "  x-scheme-handler/$S -> ${handler:-<unregistered>}  (expected $DESKTOP_ID)"
    fi
done

case ":$PATH:" in
    *":$PREFIX/bin:"*) log "  $PREFIX/bin is on PATH" ;;
    *) warn "  $PREFIX/bin is not on PATH. Add this to ~/.bashrc to run 'workbuddy-ai' directly:
         export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

echo
if [ "$FAIL" -eq 0 ]; then
    log "install complete"
    echo
    echo "  Launch with:"
    echo "    * application menu -> \"WorkBuddy AI\""
    echo "    * terminal -> workbuddy-ai"
    echo "    * full path -> $BIN_DST"
    echo
    echo "  Verify on your real desktop:  ./verify-real-desktop.sh"
    echo "  Uninstall:                    ./install-user.sh --uninstall"
else
    die "self-check failed; see the warnings above."
fi
