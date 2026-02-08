import asyncio
import websockets
import json
import time
import nacl.signing
import nacl.encoding
import hashlib
import base64

# Helper for Base64Url (RFC 4648)
def base64url_encode(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('utf-8')

# Configuration
GATEWAY_WS = "ws://127.0.0.1:18789" # Correct port

async def run_node_handshake():
    # 1. Identity (Ed25519)
    signing_key = nacl.signing.SigningKey.generate()
    verify_key = signing_key.verify_key
    
    # Raw bytes of public key (32 bytes)
    pub_key_bytes = verify_key.encode(encoder=nacl.encoding.RawEncoder)
    
    # Device ID = SHA256(raw_public_key)
    device_id = hashlib.sha256(pub_key_bytes).hexdigest()
    
    # Public Key for JSON = Base64Url(raw_public_key)
    pub_key_b64url = base64url_encode(pub_key_bytes)
    
    print(f"🦞 Clawsy Node ID: {device_id}")
    print(f"🔑 Public Key (B64): {pub_key_b64url}")
    
    async with websockets.connect(GATEWAY_WS) as websocket:
        print("Connected to Gateway...")
        
        # 2. Receive Challenge
        challenge_msg = await websocket.recv()
        challenge = json.loads(challenge_msg)
        print(f"📥 Challenge received: {challenge}")
        
        if challenge.get("event") != "connect.challenge":
            print("❌ Unexpected first message")
            return

        nonce = challenge["payload"]["nonce"]
        
        ts_ms = int(time.time() * 1000)
        
        token = "e8d547922b7775237f0b3d4cfbd9f44c8aaa9061023e4ef8"
        
        # Build payload string for signature
        # Version | DeviceID | ClientID | ClientMode | Role | Scopes | SignedAtMs | Token | Nonce
        
        payload_str = f"v2|{device_id}|openclaw-macos|node|node||{ts_ms}|{token}|{nonce}"
        
        signature_bytes = signing_key.sign(payload_str.encode('utf-8')).signature
        signature_b64url = base64url_encode(signature_bytes)
        
        print(f"📝 Payload to sign: {payload_str}")
        
        # 4. Send Connect
        connect_req = {
            "type": "req",
            "id": "1",
            "method": "connect",
            "params": {
                "minProtocol": 3,
                "maxProtocol": 3,
                "client": {
                    "id": "openclaw-macos",
                    "version": "0.2.0",
                    "platform": "macos",
                    "mode": "node"
                },
                "role": "node",
                "scopes": [],
                "caps": ["clipboard", "screen"],
                "commands": ["clipboard.read", "clipboard.write", "screen.capture"],
                # "permissions": { "clipboard.read": True, "clipboard.write": True }, # Don't send permissions if not requested? Or send as map?
                # Usually permissions are boolean map.
                "permissions": { "clipboard.read": True, "clipboard.write": True },
                "auth": { "token": "e8d547922b7775237f0b3d4cfbd9f44c8aaa9061023e4ef8" },
                "device": {
                    "id": device_id,
                    "publicKey": pub_key_b64url,
                    "signature": signature_b64url,
                    "signedAt": ts_ms,
                    "nonce": nonce
                }
            }
        }
        
        print(f"bi📤 Sending Connect: {json.dumps(connect_req, indent=2)}")
        await websocket.send(json.dumps(connect_req))
        
        # 5. Receive Result
        response_msg = await websocket.recv()
        response = json.loads(response_msg)
        print(f"📥 Response: {json.dumps(response, indent=2)}")
        
        if response.get("ok"):
            print("✅ Handshake SUCCESS! We are connected as a Node.")
            # Keep alive for a bit
            while True:
                msg = await websocket.recv()
                print(f"📩 Received: {msg}")
        else:
            print("❌ Handshake FAILED.")

if __name__ == "__main__":
    try:
        asyncio.run(run_node_handshake())
    except Exception as e:
        print(f"Error: {e}")
