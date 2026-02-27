# CLAWSY.md — Clawsy Mac Companion App

Clawsy ist Christians macOS Companion App. Sie gibt dem Agenten direkten Zugriff auf sein MacBook — Screenshots, Kamera, Zwischenablage, Dateien und mehr. Nutze diese Fähigkeiten proaktiv für eine bessere UX.

**Aktuelle stabile Version:** v0.4.17  
**Repo:** `iret77/clawsy` (GitHub, öffentlich)  
**Build:** GitHub Actions (Christian baut NICHTS lokal — immer via CI/CD)

---

## Was Du damit tun kannst

| Fähigkeit | Wann nutzen |
|-----------|-------------|
| **Screenshot** | Wenn Christian fragt was auf dem Bildschirm ist, UI-Probleme debuggen, visuelles Feedback |
| **Kamera** | Wenn er etwas zeigen will, Kontext über seine Umgebung |
| **Zwischenablage lesen** | Wenn er "schau mal was ich kopiert habe" sagt oder Text teilen will |
| **Zwischenablage schreiben** | Code/Text direkt in seine Zwischenablage pushen — sehr nützlich! |
| **Quick Send** | Text direkt an den Agenten senden (er tippt, du empfängst) |
| **Dateien** | Dateien lesen/schreiben im konfigurierten Shared Folder (`~/Documents/Clawsy`) |
| **FinderSync** | Rechtsklick auf Ordner → "Clawsy >" Untermenü → Regeln/Telemetrie/Aktionen |

**Grundregel:** Wenn Clawsy verbunden ist und es die UX verbessert — nutze es. Frag nicht erst ob du dürftest.

---

## Verbindungsarchitektur

```
Mac (Clawsy App) ──SSH-Tunnel──▶ agenthost:18789 (OpenClaw Gateway WS)
```

- Direkter WSS schlägt immer fehl (Gateway nicht extern erreichbar)
- SSH-Key: importiert via Clawsy → Einstellungen → SSH-Fallback → "Importieren…"
- SSH-User: `claw` (auf agenthost)
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
nodes(action="invoke", invokeCommand="file.list", invokeParamsJson='{"path":"/Users/cwendler/Documents/Clawsy"}')
nodes(action="invoke", invokeCommand="file.get", invokeParamsJson='{"name":"report.pdf"}')
```

Verfügbare Kommandos: `screen.capture`, `clipboard.read`, `clipboard.write`, `camera.list`, `camera.snap`, `file.list`, `file.get`, `file.set`, `location.get`

---

## clawsy_envelope — Eingehende Nachrichten

Wenn Christian Quick Send nutzt, kommt folgendes JSON als Message:

```json
{
  "clawsy_envelope": {
    "type": "quick_send",
    "content": "Die eigentliche Nachricht",
    "version": "0.4.17",
    "localTime": "2026-02-27T01:09:22.609Z",
    "tz": "Europe/Berlin",
    "telemetry": {
      "deviceName": "MacBook Pro M4 von Christian",
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
- `moodScore < 40` → Christian ist gestresst/beschäftigt, kurz halten
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

### Geschichte
Diese Architektur wurde am 19. Februar 2026 entwickelt und am 27. Februar 2026 nach Context-Compact wiederhergestellt und dokumentiert. **Bitte nicht wieder verlieren.**

---

## .clawsy Manifest-Dateien

Im Shared Folder (`~/Documents/Clawsy`) und allen Unterordnern existiert eine versteckte `.clawsy`-Datei (JSON). Diese wird **automatisch von der App angelegt** — der User muss sie nie manuell erstellen oder berühren.

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

## Device-Info (Christians MacBook)

- **Device ID:** `731fa2e610292b52723a8b3f9da53929b9c432de415abbd9a3fe755ae39f0d7c`
- **Name:** MacBook Pro M4 von Christian
- **Mac Username:** `cwendler`
- **Shared Folder:** `/Users/cwendler/Documents/Clawsy`

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
