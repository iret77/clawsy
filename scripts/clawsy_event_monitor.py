#!/usr/bin/env python3
"""Clawsy Event + Presence Monitor

- Watches the clawsy-service session file for the latest envelopes (clipboard, quick send, etc.)
- Watches the Gateway listener log for presence (connect/disconnect) events of macOS nodes
- Updates memory/clawsy/*.json artifacts and pings the main session on connection changes
"""

from __future__ import annotations

import json
import os
import subprocess
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, Optional

# --- Paths / Constants -----------------------------------------------------
SESSION_DIR = Path.home() / ".openclaw" / "agents" / "main" / "sessions"
OUTPUT_DIR = Path.cwd() / "memory" / "clawsy"
SERVICE_KEY = os.environ.get("CLAW_SY_SERVICE_KEY", "clawsy-service")
LISTENER_LOG = Path.cwd() / "projects" / "clawsy" / "listener.log"
STATE_PATH = OUTPUT_DIR / "connection-state.json"

HOST_KEYWORDS = [kw.strip().lower() for kw in os.environ.get(
    "CLAW_SY_NODE_HOST_KEYWORDS",
    "openclaw macbook"
).split() if kw.strip()]
TARGET_PLATFORM = os.environ.get("CLAW_SY_NODE_PLATFORM", "macos").lower()
NOTIFY_COMMAND = os.environ.get("CLAW_SY_NOTIFY_CMD", "openclaw system event --mode now --text {text}")

POLL_INTERVAL = 0.2
NODE_STATUS_REFRESH_SEC = 30

state_lock = threading.Lock()
connection_state: Dict[str, object] = {}

# --- Helpers ----------------------------------------------------------------

def ensure_output_dir() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def read_json(path: Path) -> Optional[dict]:
    if not path.exists():
        return None
    try:
        with path.open() as f:
            return json.load(f)
    except json.JSONDecodeError:
        return None


def write_json(path: Path, payload: dict) -> None:
    ensure_output_dir()
    with path.open("w") as f:
        json.dump(payload, f, indent=2)


def iso_from_ts(ms: Optional[int]) -> str:
    if ms is None:
        return datetime.now(timezone.utc).isoformat()
    try:
        # Accept both seconds + milliseconds
        ts = ms / 1000 if ms > 10_000_000_000 else ms
        return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()
    except Exception:
        return datetime.now(timezone.utc).isoformat()


def short_id(device_id: Optional[str]) -> str:
    if not device_id:
        return "unknown"
    return device_id[:8]


def send_system_event(text: str) -> None:
    cmd = ["openclaw", "system", "event", "--text", text, "--mode", "now"]
    try:
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        print(f"[clawsy-monitor] openclaw CLI missing; cannot send notification: {text}")
    except Exception as exc:
        print(f"[clawsy-monitor] Failed to send notification: {exc}")


def load_connection_state() -> dict:
    state = read_json(STATE_PATH) or {}
    state.setdefault("status", "unknown")
    state.setdefault("deviceId", None)
    state.setdefault("knownDeviceIds", [])
    state.setdefault("host", None)
    state.setdefault("lastChange", None)
    return state


def persist_connection_state(state: dict) -> None:
    write_json(STATE_PATH, state)


def update_connection_state(new_status: str, *, device_id: Optional[str], host: Optional[str],
                             event_ts_iso: str, reason: str, version: Optional[str] = None,
                             silent: bool = False) -> None:
    global connection_state
    with state_lock:
        prev_state = connection_state or load_connection_state()
        known_ids = set(prev_state.get("knownDeviceIds", []))
        if device_id:
            known_ids.add(device_id)

        changed = (new_status != prev_state.get("status") or device_id != prev_state.get("deviceId"))
        connection_state = {
            "status": new_status,
            "deviceId": device_id,
            "host": host,
            "lastChange": event_ts_iso,
            "reason": reason,
            "version": version,
            "knownDeviceIds": sorted(known_ids),
        }
        persist_connection_state(connection_state)

    if changed and not silent:
        label = host or "Clawsy"
        ts_display = event_ts_iso.replace("T", " ").replace("+00:00", "Z")
        node_ref = short_id(device_id)
        if new_status == "connected":
            text = f"🟢 Clawsy verbunden ({label} · {node_ref}) – {ts_display}"
        else:
            text = f"🔴 Clawsy getrennt ({label} · {node_ref}) – {ts_display}"
        send_system_event(text)
        print(f"[clawsy-monitor] Status change → {text}")


def follow_file(path: Path) -> Iterable[str]:
    with path.open() as f:
        f.seek(0, os.SEEK_END)
        while True:
            line = f.readline()
            if not line:
                time.sleep(POLL_INTERVAL)
                continue
            yield line.rstrip("\n")


def load_service_session_path() -> Optional[Path]:
    sessions_json = SESSION_DIR / "sessions.json"
    if not sessions_json.exists():
        return None
    try:
        with sessions_json.open() as f:
            data = json.load(f)
    except json.JSONDecodeError:
        return None
    entry = data.get(SERVICE_KEY) or data.get("agent:main:clawsy-service")
    if not entry:
        return None
    session_id = entry.get("sessionId")
    if not session_id:
        return None
    session_file = SESSION_DIR / f"{session_id}.jsonl"
    return session_file if session_file.exists() else None


def parse_service_line(line: str) -> None:
    if not line:
        return
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        return
    message = obj.get("message") or {}
    for part in message.get("content", []):
        if part.get("type") != "text":
            continue
        text = part.get("text", "")
        if "clawsy_envelope" not in text:
            continue
        try:
            data = json.loads(text)
        except json.JSONDecodeError:
            continue
        envelope = data.get("clawsy_envelope")
        if not envelope:
            continue
        event_type = envelope.get("type", "unknown")
        write_json(OUTPUT_DIR / f"{event_type}-latest.json", envelope)


def host_matches(entry: dict) -> bool:
    host = (entry.get("host") or "").lower()
    text = (entry.get("text") or "").lower()
    combo = f"{host} {text}".strip()
    if not combo:
        return True
    if not HOST_KEYWORDS:
        return True
    return any(keyword in combo for keyword in HOST_KEYWORDS)


def is_clawsy_presence(entry: dict) -> bool:
    if entry.get("mode") != "node":
        return False
    platform = (entry.get("platform") or "").lower()
    if TARGET_PLATFORM and TARGET_PLATFORM not in platform:
        return False
    device_id = entry.get("deviceId")
    known_ids = set(connection_state.get("knownDeviceIds", []))
    if device_id in known_ids:
        return True
    return host_matches(entry)


def parse_presence_line(line: str) -> None:
    if "RAW_IN" not in line:
        return
    start = line.find("{")
    if start == -1:
        return
    try:
        payload = json.loads(line[start:])
    except json.JSONDecodeError:
        return
    if payload.get("event") != "presence":
        return
    for entry in payload.get("payload", {}).get("presence", []):
        if not is_clawsy_presence(entry):
            continue
        reason = entry.get("reason")
        if reason not in {"connect", "disconnect"}:
            continue
        status = "connected" if reason == "connect" else "disconnected"
        ts_iso = iso_from_ts(entry.get("ts"))
        update_connection_state(
            status,
            device_id=entry.get("deviceId"),
            host=entry.get("host"),
            event_ts_iso=ts_iso,
            reason=reason,
            version=entry.get("version"),
        )


def refresh_initial_node_status() -> None:
    try:
        output = subprocess.check_output(["openclaw", "nodes", "status", "--json"], text=True)
        data = json.loads(output)
    except Exception as exc:
        print(f"[clawsy-monitor] Unable to load node status: {exc}")
        return

    nodes = data.get("nodes", [])
    if not nodes:
        return

    current_connected = next((n for n in nodes if n.get("connected") and (n.get("platform") or "").lower().startswith("mac")), None)
    if current_connected:
        update_connection_state(
            "connected",
            device_id=current_connected.get("nodeId"),
            host=current_connected.get("displayName") or current_connected.get("platform"),
            event_ts_iso=iso_from_ts(current_connected.get("connectedAtMs")),
            reason="connect",
            version=current_connected.get("version"),
            silent=True,
        )
    else:
        update_connection_state(
            "disconnected",
            device_id=None,
            host=None,
            event_ts_iso=datetime.now(timezone.utc).isoformat(),
            reason="bootstrap",
            version=None,
            silent=True,
        )

    # Track historical IDs
    with state_lock:
        known_ids = set(connection_state.get("knownDeviceIds", []))
        for node in nodes:
            if (node.get("platform") or "").lower().startswith("mac") and node.get("nodeId")):
                known_ids.add(node["nodeId"])
        connection_state["knownDeviceIds"] = sorted(known_ids)
        persist_connection_state(connection_state)


# --- Watchers ---------------------------------------------------------------

def watch_service_session() -> None:
    while True:
        path = load_service_session_path()
        if not path:
            time.sleep(2)
            continue
        print(f"[clawsy-monitor] Watching service session: {path}")
        try:
            for line in follow_file(path):
                parse_service_line(line)
        except FileNotFoundError:
            print("[clawsy-monitor] Session file disappeared; retrying…")
            time.sleep(1)
        except Exception as exc:
            print(f"[clawsy-monitor] Service watcher error: {exc}")
            time.sleep(2)


def watch_listener_log() -> None:
    while True:
        if not LISTENER_LOG.exists():
            print(f"[clawsy-monitor] Waiting for listener log at {LISTENER_LOG}")
            time.sleep(5)
            continue
        print(f"[clawsy-monitor] Watching listener log: {LISTENER_LOG}")
        try:
            for line in follow_file(LISTENER_LOG):
                parse_presence_line(line)
        except FileNotFoundError:
            print("[clawsy-monitor] Listener log missing; retrying…")
            time.sleep(2)
        except Exception as exc:
            print(f"[clawsy-monitor] Listener watcher error: {exc}")
            time.sleep(2)


def main() -> None:
    global connection_state
    ensure_output_dir()
    connection_state = load_connection_state()
    refresh_initial_node_status()

    service_thread = threading.Thread(target=watch_service_session, daemon=True)
    listener_thread = threading.Thread(target=watch_listener_log, daemon=True)
    service_thread.start()
    listener_thread.start()

    try:
        while True:
            time.sleep(5)
    except KeyboardInterrupt:
        print("[clawsy-monitor] Stopping.")


if __name__ == "__main__":
    main()
