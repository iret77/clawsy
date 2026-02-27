# CLAWSY.md — Clawsy Mac Companion App

Clawsy ist Die macOS Companion App. Sie gibt dem Agenten direkten Zugriff auf das MacBook des Users — Screenshots, Kamera, Zwischenablage, Dateien und mehr. Nutze diese Fähigkeiten proaktiv für eine bessere UX.

**Aktuelle stabile Version:** v0.4.17  
**Repo:** `iret77/clawsy` (GitHub, öffentlich)  
**Build:** GitHub Actions (niemals lokal bauen — immer via CI/CD)

---

## Was Du damit tun kannst

| Fähigkeit | Wann nutzen |
|-----------|-------------|
| **Screenshot** | Wenn der User fragt was auf dem Bildschirm ist, UI-Probleme debuggen, visuelles Feedback |
| **Kamera** | Wenn er etwas zeigen will, Kontext über seine Umgebung |
| **Zwischenablage lesen** | Wenn er "schau mal was ich kopiert habe" sagt oder Text teilen will |
| **Zwischenablage schreiben** | Code/Text direkt in seine Zwischenablage pushen — sehr nützlich! |
| **Quick Send** | Text direkt an den Agenten senden (er tippt, du empfängst) |
| **Dateien** | Dateien lesen/schreiben im konfigurierten Shared Folder (dem konfigurierten Shared Folder) |
| **FinderSync** | Rechtsklick auf Ordner → "Clawsy >" Untermenü → Regeln/Telemetrie/Aktionen |

**Grundregel:** Wenn Clawsy verbunden ist und es die UX verbessert — nutze es. Frag nicht erst ob du dürftest.

---

## Verbindungsarchitektur

```
Mac (Clawsy App) ──SSH-Tunnel──▶ agenthost:18789 (OpenClaw Gateway WS)
```

- Direkter WSS schlägt immer fehl (Gateway nicht extern erreichbar)
- SSH-Key: importiert via Clawsy → Einstellungen → SSH-Fallback → "Importieren…"
- SSH-User: konfigurierbar in den App-Einstellungen
- Tunnel-Port: **dynamisch** ab v0.4.16 (OS-assigned via `bind(port=0)`)
- App Group Container: `group.ai.openclaw.clawsy`
- App Sandbox: **deaktiviert** (GitHub-Distribution, nicht App Store)

### Auth-Flow
1. App sendet `hello` mit `serverToken` (Master-Token aus Einstellungen)
2. Gateway antwortet mit `hello-ok` + `deviceToken`
3. App speichert `deviceToken` per Host in UserDefaults (`clawsy_device_token_<host>`)
4. Bei `AUTH_TOKEN_MISMATCH`: App löscht deviceToken, reconnectet mit Master-Token (auto-recovery)

---

## Kommandos aufrufen (nodes tool)

Clawsy registriert sich als `node`. Nutze das `nodes` Tool:

```
nodes(action="invoke", invokeCommand="screen.capture")
nodes(action="invoke", invokeCommand="clipboard.read")
nodes(action="invoke", invokeCommand="clipboard.write", invokeParamsJson='{"text":"..."}')
nodes(action="invoke", invokeCommand="camera.snap", invokeParamsJson='{"facing":"front"}')
nodes(action="invoke", invokeCommand="file.list", invokeParamsJson='{"path": "."}')
nodes(action="invoke", invokeCommand="file.get", invokeParamsJson='{"name":"report.pdf"}')
```

Verfügbare Kommandos: `screen.capture`, `clipboard.read`, `clipboard.write`, `camera.list`, `camera.snap`, `file.list`, `file.get`, `file.set`, `location.get`

---

## clawsy_envelope — Eingehende Nachrichten

Wenn der User Quick Send nutzt, kommt folgendes JSON als Message:

```json
{
  "clawsy_envelope": {
    "type": "quick_send",
    "content": "Die eigentliche Nachricht",
    "version": "0.4.17",
    "localTime": "2026-02-27T01:09:22.609Z",
    "tz": "Europe/Berlin",
    "telemetry": {
      "deviceName": "<Gerätename>",
      "deviceModel": "Mac",
      "batteryLevel": 0.51,
      "isCharging": false,
      "thermalState": 0,
      "activeApp": "Clawsy",
      "appSwitchRate": 0.22,
      "moodScore": 70,
      "isUnusualHour": false
    }
  }
}
```

**Telemetrie nutzen:**
- `thermalState > 1` → Mac läuft heiß, keine komplexen Tasks vorschlagen
- `batteryLevel < 0.2` → auf Akkustand hinweisen wenn relevant
- `moodScore < 40` → User ist gestresst/beschäftigt, kurz halten
- `isUnusualHour: true` → ungewöhnliche Zeit, vorsichtig sein

---

## clawsy-service Session — WICHTIG

Screenshots, Kamera-Fotos und andere automatische Clawsy-Events landen **nicht im Haupt-Chat** sondern in der dedizierten `clawsy-service` Session. Das hält den Haupt-Chat sauber.

### Warum?
Ohne separaten Channel würde jeder Screenshot den Haupt-Chat unterbrechen. Mit `clawsy-service` sammeln sich alle Push-Events dort und ich kann sie bei Bedarf abrufen.

### Wie abrufen?
```
sessions_history(sessionKey="clawsy-service", limit=5)
```

### Wie es funktioniert (technisch)
Die App sendet Screenshots via `node.event` mit `event: "agent.deeplink"` und `sessionKey: "clawsy-service"` im payloadJSON. Das Gateway routet es in diese Session statt in den aktiven Chat.

### Eingeführt
v0.2.x (Februar 2026)

---

## Mission Control — Agent-Status anzeigen

Der Agent kann laufende Tasks in der Clawsy MissionControl anzeigen indem er eine `.agent_status.json` in den Shared Folder schreibt.

### Format
```json
{
  "updatedAt": "2026-02-27T01:30:00.000Z",
  "tasks": [
    {
      "id": "uuid",
      "agentName": "CyberClaw",
      "title": "Clawsy v0.4.17 bauen",
      "progress": 0.6,
      "statusText": "Kompiliere FinderSync Extension..."
    }
  ]
}
```

### Schreiben via nodes tool
```python
import json, base64, uuid
from datetime import datetime, timezone

status = {
  "updatedAt": datetime.now(timezone.utc).isoformat(),
  "tasks": [{
    "id": str(uuid.uuid4()),
    "agentName": "CyberClaw",
    "title": "Mein Task",
    "progress": 0.5,
    "statusText": "Schritt 2 von 4..."
  }]
}
content = base64.b64encode(json.dumps(status).encode()).decode()
nodes(action="invoke", invokeCommand="file.set",
      invokeParamsJson=json.dumps({"name": ".agent_status.json", "content": content}))
```

### Verhalten
- FileWatcher erkennt Änderung → MissionControl aktualisiert sofort
- `updatedAt` älter als 60 Sekunden → Tasks werden automatisch geleert
- `progress >= 1.0` → Task verschwindet nach 10 Sekunden
- `.agent_status.json` wird nie durch Folder-Regeln verarbeitet (System-Datei)

### Wichtig
Der Agent schreibt diese Datei selbst — **keine Änderungen an OpenClaw nötig**.

### Geplant: clawsy-service Session als bidirektionaler Kontrollkanal
Die `.agent_status.json`-Methode funktioniert für einfache Statusanzeige. Für erweiterte Features (Pause/Resume/Cancel) ist die clawsy-service Session der richtige Ansatz:

**Agent → Clawsy** (Status-Push):
```python
sessions_send(sessionKey="clawsy-service", message=json.dumps({
    "type": "task_status",
    "tasks": [{"id": "abc", "title": "Build läuft", "progress": 0.4}]
}))
```

**Clawsy → Agent** (Steuerung):
- User drückt ⏸ in MissionControl → Clawsy schreibt `{"action":"pause","taskId":"abc"}` in clawsy-service
- Agent pollt clawsy-service während langer Tasks → reagiert auf pause/resume/cancel
- Kein File-IO, echter Rückkanal, keine OpenClaw-Änderungen nötig

Noch nicht implementiert — ersetzt `.agent_status.json` wenn Pause/Resume gebraucht wird.

---

## .clawsy Manifest-Dateien

Im Shared Folder (dem konfigurierten Shared Folder) und allen Unterordnern existiert eine versteckte `.clawsy`-Datei (JSON). Diese wird **automatisch von der App angelegt** — der User muss sie nie manuell erstellen oder berühren.

```json
{
  "version": 1,
  "folderName": "Clawsy",
  "rules": [
    {
      "id": "uuid",
      "trigger": "file_added",
      "filter": "*.pdf",
      "action": "send_to_agent",
      "prompt": "Fasse dieses Dokument zusammen"
    }
  ],
  "createdAt": "...",
  "updatedAt": "..."
}
```

**Trigger:** `file_added` | `file_changed` | `manual`  
**Filter:** Glob-Pattern (`*.pdf`, `*.mov`, `*`)  
**Action:** `send_to_agent` | `notify`

### Rule Editor aufrufen
- Via FinderSync: Rechtsklick auf Ordner → Clawsy → "Regeln für diesen Ordner..."
- Via Clawsy-App: (direkter Aufruf noch nicht im Hauptmenü, nur via FinderSync)

---

## FinderSync Extension

Rechtsklick auf jeden Ordner im Shared Folder zeigt "Clawsy >" Untermenü:
- **Regeln für diesen Ordner...** → öffnet Rule Editor
- **Status & Telemetrie senden** → manueller Snapshot ans Gateway  
- **Ordner-Aktionen ausführen** → triggert alle Regeln manuell

**Ersteinrichtung nötig:** Systemeinstellungen → Datenschutz & Sicherheit → Erweiterungen → Finder → Clawsy aktivieren.

Kommunikation: `ActionBridge` via App Group container + `DistributedNotificationCenter` (cross-process, kein C-Funktionszeiger-Problem).

---

## Share Extension ("Teilen...")

Clawsy erscheint im macOS Share Sheet. Dateien/Text aus jeder App können direkt ans Gateway gesendet werden.

**Ersteinrichtung:** App muss in `/Applications` liegen (nicht aus Downloads starten).

---

## Update-Mechanismus

- Automatische Checks alle 4h via Timer
- Bei neuem Update: macOS-Notification (nur bei auto-check, nicht bei manuallem "Jetzt prüfen")
- Download mit Live-Fortschrittsbalken (`URLSessionDownloadDelegate`)
- Install-Script in `/tmp/clawsy_updater.sh` (#!/bin/sh), Fallback → GitHub Releases Page
- Download-URL: `/releases/tags/{version}` (NICHT `/releases/latest`!)

---

## ⚠️ Bekannte Probleme / Offene Tasks

### Kritisch
- **Pairing Watchdog-Bug**: 8s Watchdog disconnected WS während App auf `node.pair.resolved` wartet. Fix: Watchdog bei `STATUS_PAIRING` pausieren.
- **Gateway lädt paired.json nicht beim Start**: Tokens gehen nach Gateway-Restart verloren (upstream Gateway-Bug).

### Onboarding
- FinderSync-Berechtigung: User muss einmalig Systemeinstellungen → Finder-Erweiterungen aktivieren
- Accessibility (Bedienungshilfen): nötig für globale Hotkeys
- App muss in `/Applications` liegen für Extensions

---

## Node ermitteln

Nutze `nodes(action="status")` um den verbundenen Node zu finden:

```python
nodes(action="status")
# → Liste aller verbundenen Nodes; wähle den mit platform="macos" und connected=true
# → Merke dir die nodeId für alle weiteren Aufrufe
```

Den Shared Folder-Pfad findest du via:
```python
nodes(action="invoke", node="<nodeId>", invokeCommand="file.list",
      invokeParamsJson='{"path": "."}')
# Clawsy konfiguriert den Shared Folder in den App-Einstellungen (Standard: ~/Documents/Clawsy)
```

---

## Architektur-Übersicht

```
ClawsyMac (App)
├── NetworkManager.swift      — WebSocket + SSH-Tunnel, Auth, Events
├── UpdateManager.swift       — Auto-Update, Download-Progress
├── ContentView.swift         — Haupt-UI (Menu Bar Popover)
├── RuleEditorView.swift      — .clawsy Regel-Editor
├── MissionControlView.swift  — Task-Übersicht (agent.status Events)
└── AppDelegate.swift         — Hotkeys, Lifecycle, applicationWillTerminate

ClawsyShared (Framework)
├── NetworkManager.swift      — Core WS-Logic
├── ClawsyManifest.swift      — .clawsy Format + Auto-Provisioning
├── ActionBridge.swift        — FinderSync ↔ App Kommunikation
├── TaskStore.swift           — Task-Tracking für MissionControl
└── Resources/                — Lokalisierungen (de, en, fr, es)

ClawsyFinderSync (Extension)
└── FinderSyncExtension.swift — Finder Rechtsklick-Menü

ClawsyMacShare (Extension)
└── ShareViewController.swift — macOS Share Sheet
```

## .agent_info.json — Modell-Anzeige im Header

Clawsy zeigt das aktuelle Chat-Modell im Popover-Header an (unter dem Verbindungsstatus).
Der Agent schreibt dazu eine `.agent_info.json` in den Shared Folder:

```python
import json, base64
from datetime import datetime, timezone

info = {
    "agentName": "CyberClaw",
    "model": "claude-sonnet-4-6",
    "updatedAt": datetime.now(timezone.utc).isoformat()
}
content = base64.b64encode(json.dumps(info).encode()).decode()
nodes(action="invoke", node="<nodeId>", invokeCommand="file.set",
      invokeParamsJson=json.dumps({"name": ".agent_info.json", "content": content}))
```

- Silent write (kein Dialog) — in der Allowlist zusammen mit `.agent_status.json`
- FileWatcher erkennt Änderung → Header aktualisiert sofort
- Empfehlung: beim Session-Start schreiben, dann bei Modell-Wechsel
