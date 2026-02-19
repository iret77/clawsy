#!/usr/bin/env python3
"""Clawsy Event Monitor

Watches the Clawsy service session log and writes the latest payloads to memory/clawsy/*.json.
Intended for inclusion in the Clawsy package; portable across installations.
"""
import json
import os
import time
from pathlib import Path
from typing import Optional

SESSION_DIR = Path.home() / ".openclaw" / "agents" / "main" / "sessions"
OUTPUT_DIR = Path.cwd() / "memory" / "clawsy"
SERVICE_KEY = os.environ.get("CLAW_SY_SERVICE_KEY", "clawsy-service")


def load_service_session_path() -> Optional[Path]:
    sessions_json = SESSION_DIR / "sessions.json"
    if not sessions_json.exists():
        return None
    with sessions_json.open() as f:
        data = json.load(f)
    entry = data.get(SERVICE_KEY) or data.get("agent:main:clawsy-service")
    if not entry:
        return None
    session_id = entry.get("sessionId")
    if not session_id:
        return None
    session_file = SESSION_DIR / f"{session_id}.jsonl"
    return session_file if session_file.exists() else None


def ensure_output_dir():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def write_latest(event_type: str, payload: dict):
    ensure_output_dir()
    out_path = OUTPUT_DIR / f"{event_type}-latest.json"
    with out_path.open("w") as f:
        json.dump(payload, f, indent=2)


def follow_file(path: Path):
    with path.open() as f:
        f.seek(0, os.SEEK_END)
        while True:
            line = f.readline()
            if not line:
                time.sleep(0.2)
                continue
            yield line.strip()


def parse_and_store(line: str):
    if not line:
        return
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        return
    message = obj.get("message") or {}
    for part in message.get("content", []):
        if part.get("type") == "text":
            text = part.get("text", "")
            if "clawsy_envelope" in text:
                try:
                    data = json.loads(text)
                except json.JSONDecodeError:
                    continue
                envelope = data.get("clawsy_envelope")
                if not envelope:
                    continue
                event_type = envelope.get("type", "unknown")
                write_latest(event_type, envelope)


def main():
    session_file = load_service_session_path()
    if not session_file:
        print("[clawsy-monitor] No service session file found. Exiting.")
        return
    print(f"[clawsy-monitor] Watching {session_file}")
    for line in follow_file(session_file):
        parse_and_store(line)


if __name__ == "__main__":
    main()
