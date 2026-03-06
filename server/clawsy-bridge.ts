// Clawsy Bridge Plugin — OpenClaw Gateway Extension
// Intercepts clawsy-service events and responds to server probes

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";

const CONTEXT_FILE = "clawsy-context.json";
const MAX_ENTRIES = 50;

function readContext(path: string) {
  try { return JSON.parse(readFileSync(path, "utf8")); }
  catch { return { clipboard: null, screenshots: [], quickSend: [], shares: [], raw: [] }; }
}

function writeContext(path: string, data: any) {
  try { writeFileSync(path, JSON.stringify(data, null, 2), "utf8"); }
  catch (err: any) { console.error("[clawsy-bridge] writeContext failed:", err?.message); }
}

function ring(arr: any[], max: number) {
  return arr.length > max ? arr.slice(arr.length - max) : arr;
}

function parseEnvelope(message: string) {
  if (!message || typeof message !== "string") return null;
  try { const p = JSON.parse(message); return p?.clawsy_envelope ?? null; }
  catch { return null; }
}

export default function (api: any) {
  const workspaceDir = api.config?.workspace?.dir ?? process.env.OPENCLAW_WORKSPACE ?? "";
  const contextPath = join(workspaceDir, CONTEXT_FILE);
  try { mkdirSync(workspaceDir, { recursive: true }); } catch {}

  api.logger.info(`[clawsy-bridge] active — ${contextPath}`);

  api.registerGatewayMethod("node.event", ({ params }: any) => {
    try {
      if (params.event !== "agent.request") return;
      const payload = (() => { try { return JSON.parse(params.payloadJSON); } catch { return null; } })();
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
      switch (type) {
        case "clipboard": ctx.clipboard = entry; break;
        case "screenshot": ctx.screenshots = ring([...ctx.screenshots, entry], MAX_ENTRIES); break;
        case "quick_send": case "quick_send_trigger": ctx.quickSend = ring([...ctx.quickSend, entry], MAX_ENTRIES); break;
        case "share": ctx.shares = ring([...ctx.shares, entry], MAX_ENTRIES); break;
        default: ctx.raw = ring([...ctx.raw, entry], MAX_ENTRIES);
      }
      writeContext(contextPath, ctx);
    } catch (err: any) {
      api.logger.warn(`[clawsy-bridge] error: ${err?.message}`);
    }
  });

  api.registerGatewayMethod("clawsy.server.probe", ({ respond }: any) => {
    respond(true, { alive: true, version: "1.0.0", ts: Date.now() });
  });
}
