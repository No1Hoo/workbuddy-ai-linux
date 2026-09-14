#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Launch WorkBuddy AI on your real X session and capture evidence that it
# rendered. Useful after installing, and after changing anything that touches
# the launcher or the URI-scheme registration.
#
# Usage:
#   ./verify-real-desktop.sh          launch, wait for the window, screenshot
#   ./verify-real-desktop.sh --kill   stop a running instance
#
# Overridable environment:
#   DISPLAY_ID=:0            X display to use (default: $DISPLAY, else :0/:1)
#   XAUTH=/path/Xauthority   X authority file (default: $XAUTHORITY, else auto)
#   APP_BIN=/path/to/launcher
#
# Requirements: xdotool, and either ffmpeg or ImageMagick's `import`.
# ---------------------------------------------------------------------------
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$HERE/real-launch.log"
SHOT="$HERE/real-desktop.png"

WINDOW_NAME="WorkBuddy AI"
# Matches the installed launcher path, not the package name, so it cannot
# accidentally match this script or the invoking shell.
PROC_PATTERN="opt/workbuddy-ai/electron"

# ------------------------------------------------------------------- kill ----
if [ "${1:-}" = "--kill" ]; then
    pkill -f "$PROC_PATTERN" 2>/dev/null || true
    sleep 1
    echo "[verify] stopped any running WorkBuddy AI process"
    exit 0
fi

# ------------------------------------------------------- locate the binary ---
APP_BIN="${APP_BIN:-}"
if [ -z "$APP_BIN" ]; then
    for candidate in "$HOME/.local/bin/workbuddy-ai" /usr/bin/workbuddy-ai; do
        [ -x "$candidate" ] && { APP_BIN="$candidate"; break; }
    done
fi
[ -n "$APP_BIN" ] || { echo "[verify] no launcher found; run ./install-user.sh first, or set APP_BIN" >&2; exit 1; }

# ------------------------------------------------------ resolve the display --
DISPLAY_ID="${DISPLAY_ID:-${DISPLAY:-}}"
if [ -z "$DISPLAY_ID" ]; then
    for candidate in :0 :1; do
        if command -v xdpyinfo >/dev/null 2>&1 && DISPLAY="$candidate" xdpyinfo >/dev/null 2>&1; then
            DISPLAY_ID="$candidate"; break
        fi
    done
fi
[ -n "$DISPLAY_ID" ] || { echo "[verify] could not find a usable X display; set DISPLAY_ID" >&2; exit 1; }

XAUTH="${XAUTH:-${XAUTHORITY:-}}"
if [ -z "$XAUTH" ]; then
    for candidate in "$HOME/.Xauthority" "/run/user/$(id -u)/gdm/Xauthority"; do
        [ -f "$candidate" ] && { XAUTH="$candidate"; break; }
    done
fi

command -v xdotool >/dev/null 2>&1 \
    || { echo "[verify] xdotool is required (apt-get install xdotool)" >&2; exit 1; }

# ------------------------------------------------------- clean old instance --
pkill -f "$PROC_PATTERN" 2>/dev/null || true
sleep 2

# Scratch space on real disk: /tmp may be a small tmpfs, which breaks Chromium.
RUNTIME_DIR="${XDG_RUNTIME_DIR:-$HOME/tmp/wb-xdg}"
TMP_DIR="${TMPDIR_OVERRIDE:-$HOME/tmp/wbtmp}"
mkdir -p "$TMP_DIR" "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR" 2>/dev/null || true

echo "[verify] display   : $DISPLAY_ID"
echo "[verify] xauthority: ${XAUTH:-<none>}"
echo "[verify] launcher  : $APP_BIN"

# A clean environment on purpose: this strips ELECTRON_RUN_AS_NODE and similar
# variables injected by IDEs / agent runtimes, which otherwise break Electron.
# setsid + nohup detach the app so it survives the calling shell.
setsid nohup env -i \
    HOME="$HOME" \
    DISPLAY="$DISPLAY_ID" \
    ${XAUTH:+XAUTHORITY="$XAUTH"} \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    TMPDIR="$TMP_DIR" \
    PATH=/usr/local/bin:/usr/bin:/bin \
    LANG="${LANG:-C.UTF-8}" \
    bash "$APP_BIN" >"$LOG" 2>&1 < /dev/null &
APP_PID=$!
disown 2>/dev/null || true
echo "[verify] started pid=$APP_PID, waiting for the window…"

# ---------------------------------------------------------- wait for window --
WINDOW=""
for i in $(seq 1 30); do
    sleep 2
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        echo "[verify] FAILED: process exited after $((i*2))s. Last log lines:"
        tail -30 "$LOG"
        exit 1
    fi
    WINDOW=$(DISPLAY="$DISPLAY_ID" ${XAUTH:+XAUTHORITY="$XAUTH"} \
             xdotool search --name "$WINDOW_NAME" 2>/dev/null | head -1)
    [ -n "$WINDOW" ] && break
done

if [ -z "$WINDOW" ]; then
    echo "[verify] FAILED: no window appeared. Last log lines:"
    tail -30 "$LOG"
    exit 1
fi

echo "[verify] window id=$WINDOW"
DISPLAY="$DISPLAY_ID" ${XAUTH:+XAUTHORITY="$XAUTH"} xdotool getwindowname "$WINDOW" 2>/dev/null | sed 's/^/[verify]   title:    /'
DISPLAY="$DISPLAY_ID" ${XAUTH:+XAUTHORITY="$XAUTH"} xdotool getwindowgeometry "$WINDOW" 2>/dev/null | sed 's/^/[verify]   /'

sleep 6   # let the first screen finish rendering

# --------------------------------------------------------------- capture -----
capture() {
    local out="$1"
    local part="$out.part.png"
    rm -f "$part"

    if command -v ffmpeg >/dev/null 2>&1; then
        local size
        size=$(DISPLAY="$DISPLAY_ID" ${XAUTH:+XAUTHORITY="$XAUTH"} xdpyinfo 2>/dev/null | awk '/dimensions/{print $2}')
        if [ -n "$size" ] && ffmpeg -loglevel error -f x11grab -draw_mouse 0 \
                -video_size "$size" -i "$DISPLAY_ID" -frames:v 1 -y "$part" >/dev/null 2>&1 \
                && [ -s "$part" ]; then
            mv -f "$part" "$out"
            echo "[verify] full-screen screenshot: $out ($(stat -c%s "$out") bytes)"
            return 0
        fi
    fi

    if command -v import >/dev/null 2>&1; then
        if DISPLAY="$DISPLAY_ID" ${XAUTH:+XAUTHORITY="$XAUTH"} import -window root "$part" 2>/dev/null \
                && [ -s "$part" ]; then
            mv -f "$part" "$out"
            echo "[verify] full-screen screenshot (import): $out ($(stat -c%s "$out") bytes)"
            return 0
        fi
    fi

    echo "[verify] WARNING: could not capture a screenshot (install ffmpeg or imagemagick)"
    return 1
}

capture "$SHOT" || true

# A window-only shot, if the compositor allows it.
if command -v import >/dev/null 2>&1; then
    if DISPLAY="$DISPLAY_ID" ${XAUTH:+XAUTHORITY="$XAUTH"} import -window "$WINDOW" "$HERE/window-shot.png" 2>/dev/null \
            && [ -s "$HERE/window-shot.png" ]; then
        echo "[verify] window screenshot: $HERE/window-shot.png ($(stat -c%s "$HERE/window-shot.png") bytes)"
    fi
fi

echo "[verify] done. The app is still running (pid=$APP_PID)."
echo "[verify] stop it with: $HERE/verify-real-desktop.sh --kill"
