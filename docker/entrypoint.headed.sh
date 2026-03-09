#!/bin/sh
set -eu

export DISPLAY="${DISPLAY:-:99}"
export ALLOW_DOCKER_HEADED_CAPTCHA="${ALLOW_DOCKER_HEADED_CAPTCHA:-true}"
export XVFB_WHD="${XVFB_WHD:-1920x1080x24}"
export VNC_PORT="${VNC_PORT:-5900}"
export NOVNC_PORT="${NOVNC_PORT:-6080}"
export NOVNC_WEB_DIR="${NOVNC_WEB_DIR:-/usr/share/novnc}"
export VNC_PASSWORD="${VNC_PASSWORD:-}"

require_process_running() {
  pid="$1"
  name="$2"
  log_file="$3"
  sleep 1
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "[entrypoint] ${name} failed to stay running"
    if [ -f "$log_file" ]; then
      echo "[entrypoint] last log from ${name}:"
      tail -n 50 "$log_file" || true
    fi
    exit 1
  fi
}

echo "[entrypoint] starting Xvfb on ${DISPLAY} (${XVFB_WHD})"
Xvfb "${DISPLAY}" -screen 0 "${XVFB_WHD}" -ac -nolisten tcp +extension RANDR >/tmp/xvfb.log 2>&1 &
XVFB_PID=$!
require_process_running "$XVFB_PID" "Xvfb" "/tmp/xvfb.log"

echo "[entrypoint] starting Fluxbox"
fluxbox >/tmp/fluxbox.log 2>&1 &
FLUXBOX_PID=$!
require_process_running "$FLUXBOX_PID" "Fluxbox" "/tmp/fluxbox.log"

if [ -z "${VNC_PASSWORD}" ]; then
  echo "[entrypoint] VNC_PASSWORD must not be empty"
  exit 1
fi

mkdir -p /tmp/flow2api-vnc
chmod 700 /tmp/flow2api-vnc

X11VNC_PASSWORD_FILE="/tmp/flow2api-vnc/passwd"
x11vnc -storepasswd "${VNC_PASSWORD}" "${X11VNC_PASSWORD_FILE}" >/tmp/x11vnc-passwd.log 2>&1
chmod 600 "${X11VNC_PASSWORD_FILE}"

echo "[entrypoint] starting x11vnc on ${DISPLAY} (port ${VNC_PORT})"
x11vnc \
  -display "${DISPLAY}" \
  -rfbport "${VNC_PORT}" \
  -rfbauth "${X11VNC_PASSWORD_FILE}" \
  -forever \
  -shared \
  -noxdamage \
  -xkb \
  >/tmp/x11vnc.log 2>&1 &
X11VNC_PID=$!
require_process_running "$X11VNC_PID" "x11vnc" "/tmp/x11vnc.log"

if [ ! -d "${NOVNC_WEB_DIR}" ]; then
  echo "[entrypoint] noVNC web dir not found: ${NOVNC_WEB_DIR}"
  exit 1
fi

if ! command -v websockify >/dev/null 2>&1; then
  echo "[entrypoint] websockify not found in PATH"
  exit 1
fi

echo "[entrypoint] starting noVNC on port ${NOVNC_PORT}"
websockify --web="${NOVNC_WEB_DIR}" "${NOVNC_PORT}" "127.0.0.1:${VNC_PORT}" >/tmp/novnc.log 2>&1 &
NOVNC_PID=$!
require_process_running "$NOVNC_PID" "websockify" "/tmp/novnc.log"

if [ -z "${BROWSER_EXECUTABLE_PATH:-}" ]; then
  BROWSER_EXECUTABLE_PATH="$(python - <<'PY'
from playwright.sync_api import sync_playwright

try:
    with sync_playwright() as p:
        print(p.chromium.executable_path)
except Exception:
    print("")
PY
)"
  if [ -n "${BROWSER_EXECUTABLE_PATH}" ]; then
    export BROWSER_EXECUTABLE_PATH
    echo "[entrypoint] browser executable: ${BROWSER_EXECUTABLE_PATH}"
  fi
fi

exec python main.py
