import asyncio
import websockets
import json

async def send_clip():
    uri = "ws://localhost:8765"
    try:
        async with websockets.connect(uri) as websocket:
            # First, say hello so the server knows who we are (optional based on server.py but good manners)
            await websocket.send(json.dumps({"type": "hello", "hostname": "CyberClaw-Injector"}))
            
            # Now send the clipboard command (matching handle_message logic in NetworkManager.swift / server.py expectation)
            # wait, server.py just relays messages based on type "clipboard" usually from client?
            # actually server.py handles input_loop commands: "set <text>" -> sends {"command": "set_clipboard", "content": text} to CONNECTED_CLIENT
            
            # BUT: server.py listens for messages from client. It doesn't listen for admin commands on WS.
            # It only has an input_loop for stdin.
            
            # So if I connect here, I am treated as a CLIENT.
            # If I send {"type": "clipboard", "data": "..."} the server just prints it.
            # It does NOT relay it to other clients (the Mac).
            
            # The current server.py is a 1-to-1 bridge that assumes IT controls the client via stdin.
            # It does NOT support a second client sending commands to the first client.
            
            print("SKIPPING: Current server architecture prevents remote injection via WS. It only works via Server-STDIN.")
            
    except Exception as e:
        print(f"Error: {e}")

asyncio.run(send_clip())
