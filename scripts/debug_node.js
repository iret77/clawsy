const WebSocket = require('ws');
const crypto = require('crypto');

const GATEWAY = 'ws://127.0.0.1:18789';
const TOKEN = 'ZGTCL3DF1XNoqHVZ3aDCLw=='; 

// Generate Ed25519 KeyPair
const keyPair = crypto.generateKeyPairSync('ed25519');

// Extract RAW public key bytes (32 bytes)
// In Node, export as JWK is the easiest way to get raw x coordinate
const jwk = keyPair.publicKey.export({ format: 'jwk' });
const rawPubKey = Buffer.from(jwk.x, 'base64'); // JWK uses base64url, but standard base64 often works or needs url-safe handling

// Calculate Device ID (SHA256 of raw public key)
const deviceId = crypto.createHash('sha256').update(rawPubKey).digest('hex');

function base64Url(buf) {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

const ws = new WebSocket(GATEWAY);

ws.on('open', () => {
  console.log('Node connecting...');
});

ws.on('message', (data) => {
  const msg = JSON.parse(data);
  console.log('IN:', msg);

  if (msg.event === 'connect.challenge') {
    const nonce = msg.payload.nonce;
    const ts = Date.now().toString();
    
    // Sign payload
    // "v2|deviceId|client_id|role|role|reserved|ts|token|nonce"
    const payloadStr = ['v2', deviceId, 'openclaw-macos', 'node', 'node', '', ts, TOKEN, nonce].join('|');
    console.log('SIG_BASE:', payloadStr);
    
    const sig = crypto.sign(null, Buffer.from(payloadStr), keyPair.privateKey);
    
    const connectReq = {
      type: 'req', id: '1', method: 'connect',
      params: {
        minProtocol: 3, maxProtocol: 3,
        client: { id: 'openclaw-macos', version: '1.0', platform: 'macos', mode: 'node' },
        role: 'node',
        auth: { token: TOKEN },
        device: {
          id: deviceId,
          publicKey: base64Url(rawPubKey),
          signature: base64Url(sig),
          signedAt: parseInt(ts),
          nonce: nonce
        }
      }
    };
    
    console.log('Sending connect...');
    ws.send(JSON.stringify(connectReq));
  }

  if (msg.id === '1' && (msg.result || msg.payload?.type === 'hello-ok')) {
    console.log('CONNECTED! Sending Event...');
    
    const frame = {
      type: 'req',
      id: 'event-DEBUG',
      method: 'node.event',
      params: {
        event: 'quick_send',
        payload: { text: 'SIMULATION_SUCCESS' }
      }
    };
    
    console.log('SENDING:', JSON.stringify(frame));
    ws.send(JSON.stringify(frame));
  }
  
  if (msg.id === 'event-DEBUG') {
      console.log('RESPONSE:', msg);
      process.exit(0);
  }
});
