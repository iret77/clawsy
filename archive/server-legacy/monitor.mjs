#!/usr/bin/env node
/**
 * clawsy-monitor.mjs
 *
 * Watches the clawsy-service session JSONL and extracts new relevant messages
 * into a small clawsy-context.json + a flat image cache directory.
 * No external dependencies. Node.js built-ins only.
 *
 * Resilient to JSONL truncation / rotation:
 *   - Saves {lastLineIndex, lineHash} as bookmark
 *   - On mismatch: searches backwards for matching line
 *   - If not found: assumes reset → clears cache, restarts from line 0
 *
 * Portable: All paths are auto-detected via environment variables.
 *   OPENCLAW_HOME     — OpenClaw home directory (default: ~/.openclaw)
 *   OPENCLAW_AGENT    — Agent ID (default: "main")
 *   OPENCLAW_WORKSPACE — Workspace directory (default: $OPENCLAW_HOME/workspace)
 */

import { readFileSync, writeFileSync, mkdirSync, watch, existsSync, unlinkSync, readdirSync } from "node:fs";
import { createHash } from "node:crypto";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// ── Config (portable — auto-detect all paths) ────────────────────────────────

const OPENCLAW_HOME = process.env.OPENCLAW_HOME
  || join(process.env.HOME || "/home/" + process.env.USER, ".openclaw");
const AGENT_ID = process.env.OPENCLAW_AGENT || "main";
const SESSIONS_FILE = join(OPENCLAW_HOME, `agents/${AGENT_ID}/sessions/sessions.json`);
const WORKSPACE = process.env.OPENCLAW_WORKSPACE
  || join(OPENCLAW_HOME, "workspace");
const CONTEXT_FILE = join(WORKSPACE, "clawsy-context.json");
const CACHE_DIR = join(WORKSPACE, "clawsy-cache");
const STATE_FILE = join(WORKSPACE, "clawsy-monitor-state.json");

const SESSION_KEY    = `agent:${AGENT_ID}:clawsy-service`;

const MAX_ENTRIES    = 20;          // max items per bucket
const MAX_AGE_MS     = 24 * 60 * 60 * 1000;  // 24 hours

// ── Helpers ───────────────────────────────────────────────────────────────────

function hashLine(line) {
  return createHash("sha1").update(line).digest("hex").slice(0, 16);
}

function readJSON(path, fallback) {
  try { return JSON.parse(readFileSync(path, "utf8")); }
  catch { return fallback; }
}

function writeJSON(path, data) {
  try { writeFileSync(path, JSON.stringify(data, null, 2), "utf8"); }
  catch (e) { log("warn", `writeJSON ${path}: ${e.message}`); }
}

function log(level, ...args) {
  const ts = new Date().toISOString().slice(11, 19);
  console.error(`[clawsy-monitor ${ts}] [${level}]`, ...args);
}

function ring(arr, maxItems) {
  const cutoff = Date.now() - MAX_AGE_MS;
  const fresh = arr.filter(x => (x.ts ?? 0) > cutoff);
  return fresh.length > maxItems ? fresh.slice(fresh.length - maxItems) : fresh;
}

function getSessionFile() {
  const store = readJSON(SESSIONS_FILE, {});
  return store[SESSION_KEY]?.sessionFile ?? null;
}

// ── Bookmark ──────────────────────────────────────────────────────────────────

function loadState() {
  return readJSON(STATE_FILE, { lastLineIndex: 0, lineHash: null });
}

function saveState(state) {
  writeJSON(STATE_FILE, state);
}

/**
 * Resolve the starting line index given the current file lines.
 * Returns { startIndex, reset } where reset=true means the file changed
 * fundamentally and the cache was cleared.
 */
function resolveStartIndex(lines, state) {
  const { lastLineIndex, lineHash } = state;

  // First run
  if (!lineHash) return { startIndex: 0, reset: false };

  // Check if bookmark line is still at the expected position
  const candidate = lines[lastLineIndex];
  if (candidate && hashLine(candidate) === lineHash) {
    return { startIndex: lastLineIndex + 1, reset: false };
  }

  // Mismatch — search backwards from lastLineIndex for the bookmarked line
  const searchFrom = Math.min(lastLineIndex, lines.length - 1);
  for (let i = searchFrom; i >= 0; i--) {
    if (lines[i] && hashLine(lines[i]) === lineHash) {
      log("info", `Bookmark shifted: found at line ${i} (was ${lastLineIndex}) — file truncated from front`);
      return { startIndex: i + 1, reset: false };
    }
  }

  // Not found anywhere → file was reset
  log("warn", "Bookmark not found — JSONL reset detected. Clearing cache.");
  clearCache();
  return { startIndex: 0, reset: true };
}

function clearCache() {
  try {
    const files = readdirSync(CACHE_DIR);
    for (const f of files) unlinkSync(join(CACHE_DIR, f));
  } catch {}
  writeJSON(CONTEXT_FILE, emptyContext());
  writeJSON(STATE_FILE, { lastLineIndex: 0, lineHash: null });
}

function emptyContext() {
  return { clipboard: null, screenshots: [], shares: [], quickSend: [], updatedAt: null };
}

// ── Envelope processing ───────────────────────────────────────────────────────

function processEnvelope(envelope, ctx) {
  const type = envelope?.type ?? "unknown";
  const ts   = Date.now();
  const iso  = new Date().toISOString();

  switch (type) {
    case "clipboard": {
      const content = envelope.content ?? {};
      const text = typeof content === "string" ? content : content.text ?? null;
      ctx.clipboard = { text, ts, receivedAt: iso };
      log("info", `clipboard: ${String(text).slice(0, 60)}`);
      break;
    }

    case "screenshot": {
      // Envelope may contain base64 image directly or a reference
      const imageB64 = envelope.image ?? envelope.content?.image ?? null;
      let filePath = null;
      if (imageB64) {
        mkdirSync(CACHE_DIR, { recursive: true });
        filePath = join(CACHE_DIR, `screenshot-${ts}.jpg`);
        writeFileSync(filePath, Buffer.from(imageB64, "base64"));
        log("info", `screenshot saved: ${filePath}`);
      }
      ctx.screenshots = ring([...ctx.screenshots, { filePath, ts, receivedAt: iso }], MAX_ENTRIES);
      break;
    }

    case "share": {
      const content = envelope.content ?? {};
      const text = typeof content === "string" ? content : JSON.stringify(content).slice(0, 500);
      ctx.shares = ring([...ctx.shares, { text, ts, receivedAt: iso }], MAX_ENTRIES);
      log("info", `share: ${text.slice(0, 60)}`);
      break;
    }

    case "quick_send":
    case "quick_send_trigger": {
      const text = envelope.message ?? envelope.content ?? "";
      ctx.quickSend = ring([...ctx.quickSend, { text, ts, receivedAt: iso }], MAX_ENTRIES);
      log("info", `quickSend: ${String(text).slice(0, 60)}`);
      break;
    }

    default:
      // Ignore unknown types silently
      break;
  }
}

// ── Image extraction from session JSONL messages ──────────────────────────────

/**
 * The JSONL contains full OpenClaw session messages. User messages may have
 * content blocks of type "image" (base64) when a screenshot was sent.
 * Extract and save those too.
 */
function processSessionMessage(msg, ctx) {
  const role    = msg?.role;
  const content = msg?.content;
  if (!Array.isArray(content)) return;

  for (const block of content) {
    if (block.type === "text") {
      // Try to parse clawsy_envelope from text
      try {
        const parsed = JSON.parse(block.text);
        const envelope = parsed?.clawsy_envelope;
        if (envelope) processEnvelope(envelope, ctx);
      } catch {}
    }

    if (block.type === "image" && block.data && role === "user") {
      // Raw image block (screenshot sent via Clawsy)
      mkdirSync(CACHE_DIR, { recursive: true });
      const ts       = Date.now();
      const filePath = join(CACHE_DIR, `screenshot-${ts}.jpg`);
      try {
        writeFileSync(filePath, Buffer.from(block.data, "base64"));
        ctx.screenshots = ring([...ctx.screenshots, {
          filePath,
          ts,
          receivedAt: new Date().toISOString()
        }], MAX_ENTRIES);
        log("info", `image block saved: ${filePath}`);
      } catch (e) {
        log("warn", `image save failed: ${e.message}`);
      }
    }
  }
}

// ── Main scan ─────────────────────────────────────────────────────────────────

function scan(jsonlPath) {
  let raw;
  try { raw = readFileSync(jsonlPath, "utf8"); }
  catch (e) { log("warn", `read failed: ${e.message}`); return; }

  const lines = raw.split("\n").filter(l => l.trim());
  if (lines.length === 0) return;

  const state = loadState();
  const { startIndex, reset } = resolveStartIndex(lines, state);

  if (startIndex >= lines.length) return; // nothing new

  const ctx = reset ? emptyContext() : readJSON(CONTEXT_FILE, emptyContext());

  let lastProcessedIndex = startIndex - 1;
  let changed = false;

  for (let i = startIndex; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;

    try {
      const obj = JSON.parse(line);
      if (obj.type === "message" && obj.message) {
        processSessionMessage(obj.message, ctx);
        changed = true;
      }
    } catch {}

    lastProcessedIndex = i;
  }

  if (lastProcessedIndex >= 0 && lastProcessedIndex < lines.length) {
    const lastLine = lines[lastProcessedIndex];
    saveState({ lastLineIndex: lastProcessedIndex, lineHash: hashLine(lastLine) });
  }

  if (changed || reset) {
    ctx.updatedAt = new Date().toISOString();
    writeJSON(CONTEXT_FILE, ctx);
  }
}

// ── Watcher ───────────────────────────────────────────────────────────────────

function start() {
  log("info", `OpenClaw Home: ${OPENCLAW_HOME}`);
  log("info", `Agent:         ${AGENT_ID}`);
  log("info", `Workspace:     ${WORKSPACE}`);

  mkdirSync(CACHE_DIR, { recursive: true });

  const jsonlPath = getSessionFile();
  if (!jsonlPath) {
    log("error", `Session key "${SESSION_KEY}" not found in ${SESSIONS_FILE}`);
    process.exit(1);
  }

  log("info", `Watching: ${jsonlPath}`);
  log("info", `Context:  ${CONTEXT_FILE}`);
  log("info", `Cache:    ${CACHE_DIR}`);

  // Initial scan
  scan(jsonlPath);

  // Watch for changes (debounced 200ms to avoid double-fires)
  let debounce = null;
  try {
    watch(jsonlPath, () => {
      clearTimeout(debounce);
      debounce = setTimeout(() => scan(jsonlPath), 200);
    });
  } catch (e) {
    log("error", `watch failed: ${e.message}`);
    process.exit(1);
  }

  // Also re-resolve session file path every 5 min (in case of session rotation)
  setInterval(() => {
    const newPath = getSessionFile();
    if (newPath && newPath !== jsonlPath) {
      log("info", `Session file rotated to ${newPath} — restarting`);
      process.exit(0); // systemd will restart us
    }
  }, 5 * 60 * 1000);

  // Graceful shutdown
  process.on("SIGTERM", () => { log("info", "SIGTERM — exiting"); process.exit(0); });
  process.on("SIGINT",  () => { log("info", "SIGINT — exiting");  process.exit(0); });

  log("info", "Running.");
}

start();
