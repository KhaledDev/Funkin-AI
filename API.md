# Friday Night Funkin' AI - API Documentation

## Overview

This document provides a comprehensive guide to the AI integration API for Friday Night Funkin'. The API enables external AI applications to interact with the game, receive real-time game data, and send input commands to control gameplay.

## Table of Contents

1. [WebSocket Server](#websocket-server)
2. [Data Formats](#data-formats)
3. [AI Game Manager](#ai-game-manager)
4. [Note Data Reader](#note-data-reader)
5. [Integration Guide](#integration-guide)
6. [Troubleshooting](#troubleshooting)

## WebSocket Server

The WebSocket server acts as the communication channel between the game and external AI applications.

### Connection Details

- **Default Port**: 8765
- **Protocol**: WebSocket (ws://)
- **Address**: `ws://localhost:8765`

### Server Lifecycle

The server starts automatically when the game is launched and remains active throughout gameplay. It sends real-time game data and can receive input commands from connected clients.

## Data Formats

### Note Data

The primary data format sent from the game to AI clients:

```json
{
  "type": "noteData",
  "currentTime": 1500,
  "currentNotes": [
    {
      "direction": 0,
      "strumTime": 1600,
      "isHoldNote": false,
      "hasMissed": false,
      "mayHit": true,
      "tooEarly": false
    }
  ],
  "upcomingNotes": []
}
```

**Properties:**
- `currentTime`: Current song time in milliseconds
- `currentNotes`: Array of notes that are currently on screen
  - `direction`: Note direction (0-3, corresponding to left, down, up, right)
  - `strumTime`: Time when the note should be hit
  - `isHoldNote`: Whether the note is a sustained note
  - `hasMissed`: Whether the note has been missed
  - `mayHit`: Whether the note can currently be hit
  - `tooEarly`: Whether it's too early to hit the note
- `upcomingNotes`: Preview of notes that will appear soon

### Input Commands

Format for sending inputs from AI to the game:

```json
{
  "type": "input",
  "keyCode": 0,
  "pressed": true
}
```

**Properties:**
- `keyCode`: The key code for the input (0-3, corresponding to left, down, up, right)
- `pressed`: `true` for key press, `false` for key release

## AI Game Manager

The `AIGameManager` class handles the integration between the game and AI clients:

- Initializes the WebSocket server
- Manages the game state
- Reads note data from the current play session
- Transmits data to connected clients
- Processes incoming commands

### Key Methods

- `startPlaySession(playState)`: Initializes an AI session for a new song
- `endPlaySession()`: Cleans up when a song ends
- `onUpdate()`: Called each frame to update and send game data
- `onCommand(command)`: Processes incoming commands from AI clients

## Note Data Reader

The `NoteDataReader` class extracts and formats note data from the current gameplay:

- Reads the note chart
- Determines which notes are currently visible
- Formats note data for transmission
- Calculates timing information

## Integration Guide

### Connecting to the Game

1. Establish a WebSocket connection to `ws://localhost:8765`
2. Listen for incoming `noteData` messages
3. Process note data to determine optimal inputs
4. Send input commands using the input format

### Example Client (Python)

```python
import websockets
import json
import asyncio

async def connect_to_fnf():
    uri = "ws://localhost:8765"

    async with websockets.connect(uri) as websocket:
        print("Connected to Friday Night Funkin'")

        # Listen for incoming messages
        while True:
            data = await websocket.recv()
            game_data = json.loads(data)

            if game_data["type"] == "noteData":
                # Process note data
                current_notes = game_data["currentNotes"]
                for note in current_notes:
                    if note["mayHit"] and not note["hasMissed"]:
                        # Send input command
                        input_cmd = {
                            "type": "input",
                            "keyCode": note["direction"],
                            "pressed": True
                        }
                        await websocket.send(json.dumps(input_cmd))

                        # Send key release after 50ms
                        await asyncio.sleep(0.05)
                        input_cmd["pressed"] = False
                        await websocket.send(json.dumps(input_cmd))

# Run the client
asyncio.get_event_loop().run_until_complete(connect_to_fnf())
```

## Troubleshooting

### Common Issues

1. **Connection Refused**: Ensure the game is running and the WebSocket server is active
2. **No Data Received**: Make sure the current state is a gameplay state
3. **Input Not Working**: Check input format and ensure the correct key codes are used
4. **Null Reference Exceptions**: Wait for the music to fully load before expecting valid data

### Debugging Tips

- Enable debug mode in the game settings to see WebSocket traffic
- Check the game console for WebSocket-related log messages
- Use a WebSocket client tool to manually test the connection

## Further Development

The API is designed to be extensible. Future enhancements may include:

- Additional data streams (e.g., player health, score)
- More granular note information
- Game state management commands
- Training mode for AI development

## License

The Friday Night Funkin' AI API is covered under the same license as the main game. See LICENSE.md for details.
