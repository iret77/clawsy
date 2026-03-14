/**
 * clawsy-bridge — OpenClaw Gateway Plugin
 *
 * Monitors session transcripts for clawsy_envelope messages and writes them
 * to clawsy-context.json in the workspace for fast agent access.
 *
 * Uses api.runtime.events.onSessionTranscriptUpdate() instead of
 * registerGatewayMethod("node.event") — the latter collides with the
 * core gateway handler and is reserved for NEW method names only.
 *
 * Also registers clawsy.server.probe so Clawsy clients can detect the bridge.
 */

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";

const CONTEXT_FILE = "clawsy-context.json";
const MAX_ENTRIES = 50;

/** Read the context store (never throws) */
function readContext(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return { clipboard: null, screenshots: [], quickSend: [], shares: [], raw: [] };
  }
}

/** Atomically write context (never throws) */
function writeContext(path, data) {
  try {
    writeFileSync(path, JSON.stringify(data, null, 2), "utf8");
  } catch (err) {
    console.error("[clawsy-bridge] writeContext failed:", err?.message);
  }
}

/** Trim array to max length (newest last) */
function ring(arr, max) {
  return arr.length > max ? arr.slice(arr.length - max) : arr;
}

/** Parse clawsy_envelope from a raw text string */
function parseEnvelope(text) {
  if (!text || typeof text !== "string") return null;
  try {
    const parsed = JSON.parse(text);
    return parsed?.clawsy_envelope ?? null;
  } catch {
    return null;
  }
}

export default function (api) {
  const workspaceDir =
    api.config?.workspace?.dir ?? process.env.OPENCLAW_WORKSPACE ?? "";
  const contextPath = join(workspaceDir, CONTEXT_FILE);

  try {
    mkdirSync(workspaceDir, { recursive: true });
  } catch {}

  api.logger.info(`[clawsy-bridge] active — writing to ${contextPath}`);

  // ── Transcript watcher ────────────────────────────────────────────────────
  // onSessionTranscriptUpdate fires for ALL sessions. We track file positions
  // and scan new content for clawsy_envelope messages. Non-matching sessions
  // are skipped with minimal overhead (one string-includes check).

  /** Map<sessionFile, lastReadPosition> */
  const filePositions = new Map();

  let unsubscribe = null;

  if (typeof api.runtime?.events?.onSessionTranscriptUpdate === "function") {
    unsubscribe = api.runtime.events.onSessionTranscriptUpdate(
      ({ sessionFile }) => {
        try {
          if (!sessionFile || !sessionFile.endsWith(".jsonl")) return;

          let content;
          try {
            content = readFileSync(sessionFile, "utf8");
          } catch {
            return; // file gone or unreadable — skip silently
          }

          const lastPos = filePositions.get(sessionFile) ?? 0;
          if (content.length <= lastPos) return;

          const newContent = content.slice(lastPos);
          filePositions.set(sessionFile, content.length);

          // Quick check: skip files that clearly have no clawsy content
          if (!newContent.includes("clawsy_envelope")) return;

          const lines = newContent.trim().split("\n").filter(Boolean);
          let updated = false;

          for (const line of lines) {
            try {
              const msg = JSON.parse(line);
              // Messages in JSONL can have content/text/message fields
              const text = msg.content ?? msg.text ?? msg.message ?? "";
              if (typeof text !== "string") continue;

              const envelope = parseEnvelope(text);
              if (!envelope) continue;

              const type = envelope.type ?? "unknown";
              const now = new Date().toISOString();
              const ctx = readContext(contextPath);
              const entry = { type, receivedAt: now, envelope };

              switch (type) {
                case "clipboard":
                  ctx.clipboard = entry;
                  break;
                case "screenshot":
                  ctx.screenshots = ring(
                    [...ctx.screenshots, entry],
                    MAX_ENTRIES,
                  );
                  break;
                case "quick_send":
                case "quick_send_trigger":
                  ctx.quickSend = ring([...ctx.quickSend, entry], MAX_ENTRIES);
                  break;
                case "share":
                  ctx.shares = ring([...ctx.shares, entry], MAX_ENTRIES);
                  break;
                default:
                  ctx.raw = ring([...ctx.raw, entry], MAX_ENTRIES);
              }

              writeContext(contextPath, ctx);
              updated = true;
            } catch {
              /* skip unparseable lines */
            }
          }

          if (updated) {
            api.logger.info(`[clawsy-bridge] updated ${CONTEXT_FILE}`);
          }
        } catch (err) {
          api.logger.warn(
            `[clawsy-bridge] transcript handler error: ${err?.message}`,
          );
        }
      },
    );

    api.logger.info(
      "[clawsy-bridge] transcript watcher active (onSessionTranscriptUpdate)",
    );
  } else {
    api.logger.warn(
      "[clawsy-bridge] onSessionTranscriptUpdate not available — " +
        "clawsy-context.json will not be populated. " +
        "Agents can still read clawsy-service via sessions_history().",
    );
  }

  // Clean up watcher on gateway stop
  api.on("gateway_stop", () => {
    if (typeof unsubscribe === "function") {
      unsubscribe();
      api.logger.info("[clawsy-bridge] transcript watcher stopped");
    }
  });

  // ── Server probe ──────────────────────────────────────────────────────────
  // Lets Clawsy clients detect if the bridge plugin is active
  api.registerGatewayMethod("clawsy.server.probe", ({ respond }) => {
    respond(true, { alive: true, version: "2.0.0", ts: Date.now() });
  });
}
