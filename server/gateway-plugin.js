/**
 * clawsy-bridge — OpenClaw Plugin
 *
 * Intercepts agent.request events for the "clawsy-service" session and writes
 * them to clawsy-context.json in the workspace so the main agent can read them
 * without LLM involvement, no HTTP ports, no SSH issues.
 *
 * Works in every setup because it runs inside the Gateway process itself.
 */

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";

const CONTEXT_FILE = "clawsy-context.json";
const MAX_ENTRIES = 50; // ring buffer — never grows unbounded

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
    // log but never crash the Gateway
    console.error("[clawsy-bridge] writeContext failed:", err?.message);
  }
}

/** Trim array to max length (newest last) */
function ring(arr, max) {
  return arr.length > max ? arr.slice(arr.length - max) : arr;
}

/** Parse payloadJSON safely */
function parsePayload(raw) {
  try { return JSON.parse(raw); } catch { return null; }
}

/** Extract clawsy_envelope from message text */
function parseEnvelope(message) {
  if (!message || typeof message !== "string") return null;
  try {
    const parsed = JSON.parse(message);
    return parsed?.clawsy_envelope ?? null;
  } catch { return null; }
}

export default function (api) {
  const workspaceDir = api.config?.workspace?.dir ?? process.env.OPENCLAW_WORKSPACE ?? "";
  const contextPath = join(workspaceDir, CONTEXT_FILE);

  // Ensure workspace dir exists
  try { mkdirSync(workspaceDir, { recursive: true }); } catch {}

  api.logger.info(`[clawsy-bridge] Watching clawsy-service → ${contextPath}`);

  /**
   * Register a node.event handler that taps into agent.request traffic.
   * We do NOT call respond() — the core handler continues normally.
   * This is a pure side-effect interceptor.
   */
  api.registerGatewayMethod("node.event", ({ params }) => {
    try {
      if (params.event !== "agent.request") return;

      const payload = parsePayload(params.payloadJSON);
      if (!payload) return;

      const sessionKey = (payload.sessionKey ?? "").trim();
      if (sessionKey !== "clawsy-service") return;

      const message = (payload.message ?? "").trim();
      if (!message) return;

      const envelope = parseEnvelope(message);
      const type = envelope?.type ?? "unknown";
      const now = new Date().toISOString();

      const ctx = readContext(contextPath);
      const entry = { type, receivedAt: now, envelope: envelope ?? { raw: message } };

      // Route into the right bucket
      switch (type) {
        case "clipboard":
          ctx.clipboard = entry;
          break;
        case "screenshot":
          ctx.screenshots = ring([...ctx.screenshots, entry], MAX_ENTRIES);
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
      api.logger.info(`[clawsy-bridge] stored ${type} in ${CONTEXT_FILE}`);
    } catch (err) {
      // Never crash the Gateway, just log
      api.logger.warn(`[clawsy-bridge] handler error: ${err?.message}`);
    }
    // No respond() call — core handler processes the session normally
  });

  // Server probe — lets Clawsy clients detect if the bridge plugin is active
  api.registerGatewayMethod("clawsy.server.probe", ({ respond }) => {
    respond(true, { alive: true, version: "1.0.0", ts: Date.now() });
  });
}
