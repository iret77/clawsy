const WebSocket = require('ws');
const { spawn } = require('child_process');

const TOKEN = 'ZGTCL3DF1XNoqHVZ3aDCLw==';
const GATEWAY = 'ws://127.0.0.1:18789';

console.log('--- Clawsy Monitor (Role: Operator) ---');

function connect() {
  const ws = new WebSocket(GATEWAY);

  ws.on('open', () => {
    console.log('Connected.');
  });

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data);
      
      if (msg.event === 'connect.challenge') {
        console.log('Handshaking as Operator...');
        ws.send(JSON.stringify({
          type: 'req',
          id: 'auth-op',
          method: 'connect',
          params: {
            role: 'operator',
            minProtocol: 3,
            maxProtocol: 3,
            client: { id: 'cli', version: '2026.2.15', platform: 'linux', mode: 'cli' },
            auth: { token: TOKEN }
          }
        }));
      }

      if (msg.id === 'auth-op') {
        if (msg.result?.ok || msg.ok) {
          console.log('OPERATOR_CONNECTED - FULL VISIBILITY');
        } else {
          console.error('AUTH_FAILED:', JSON.stringify(msg));
        }
      }

      // DEBUG: Log everything that isn't a tick
      if (msg.method !== 'tick' && msg.event !== 'tick') {
        console.log('RAW_IN:', JSON.stringify(msg));
      }

      // Check for node.event in any form (broadcast or direct)
      if (msg.method === 'node.event' || msg.event === 'node.event') {
        console.log('GOT_EVENT:', JSON.stringify(msg));
        const p = msg.params || msg.payload || {};
        if (p.event === 'quick_send' && p.payload?.text) {
          console.log('!!! SUCCESS: GOT QUICK SEND:', p.payload.text);
          spawn('openclaw', ['gateway', 'call', 'system-event', '--params', JSON.stringify({ text: `[Clawsy] ${p.payload.text}` })]);
        }
      }
    } catch (e) {
      console.error('Parse error:', e);
    }
  });

  ws.on('close', () => setTimeout(connect, 3000));
}
connect();
