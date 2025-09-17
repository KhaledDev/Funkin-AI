import socket
import json
import time
import os
from vision_system import FunkinVisionSystem

HOST = "127.0.0.1"  # localhost
PORT = 5000

# Vision system configuration
ENABLE_VISION = True  # Set to False to disable vision processing
SAVE_VISION_FRAMES = True  # Set to True to save vision frames to disk
VISION_SAVE_INTERVAL = 30  # Save every 30 frames (about 1 per second)
VISION_WIDTH = 400
VISION_HEIGHT = 600

# Game constants (from Haxe source)
HIT_WINDOW_MS = 160.0  # Same as Constants.HIT_WINDOW_MS in the game

# Vision system
vision_system = None
frame_counter = 0

# Initialize vision system if enabled
if ENABLE_VISION:
    try:
        vision_system = FunkinVisionSystem(VISION_WIDTH, VISION_HEIGHT)
        print(f"[AI Server] Vision system initialized ({VISION_WIDTH}x{VISION_HEIGHT})")

        # Create vision output directory if saving frames
        if SAVE_VISION_FRAMES:
            os.makedirs("vision_frames", exist_ok=True)
            print(f"[AI Server] Vision frames will be saved to 'vision_frames' directory")

        # Create initial empty vision window
        empty_state = {"mainState": "WAITING", "isPlaying": False, "notes": []}
        initial_image = vision_system.generate_vision(empty_state)
        vision_system.display_vision(initial_image, "Funkin AI Vision")
        print(f"[AI Server] Vision window opened - waiting for game connection...")

    except Exception as e:
        print(f"[AI Server] Failed to initialize vision system: {e}")
        vision_system = None
        ENABLE_VISION = False

# Track active hold notes
active_holds = {}  # direction -> {'start_time': time, 'end_time': time, 'note': note_data}

def get_key_for_direction(direction):
    """Convert note direction to key name"""
    direction_map = {
        0: "left",   # left arrow
        1: "down",   # down arrow
        2: "up",     # up arrow
        3: "right"   # right arrow
    }
    return direction_map.get(direction, "none")

def analyze_notes(notes_data, game_timestamp=None, full_game_state=None):
    """Analyze notes and determine which keys to press using game's timing logic"""
    global frame_counter

    if not notes_data or not isinstance(notes_data, list):
        return []

    # Use game timestamp if provided, otherwise fall back to system time
    current_conductor_time = game_timestamp if game_timestamp is not None else time.time() * 1000

    actions = []

    # First, check for expired hold notes and release them
    directions_to_release = []
    for direction, hold_data in active_holds.items():
        if current_conductor_time >= hold_data['end_time']:
            directions_to_release.append(direction)

    # Remove expired holds
    for direction in directions_to_release:
        del active_holds[direction]
        print(f"[AI Server] Hold note ended for direction {direction}")

    # Check each direction for notes that need to be hit
    for direction in [0, 1, 2, 3]:  # left, down, up, right
        # Skip if we're already holding this direction (for hold notes)
        if direction in active_holds:
            actions.append(get_key_for_direction(direction))  # Keep holding
            continue

        # Find ALL hitable notes in this direction using game's timing logic
        hitable_notes = []
        for note in notes_data:
            if (note.get('direction') == direction and
                not note.get('hasBeenHit', False) and
                not note.get('hasMissed', False) and
                note.get('mayHit', False)):

                strum_time = note.get('strumTime', 0)
                conductor_time = note.get('conductorTime', current_conductor_time)
                time_difference = strum_time - conductor_time

                # Use game's hit window logic: note can be hit if it's within HIT_WINDOW_MS
                # Positive time_difference means note is in the future
                # Negative time_difference means note is in the past
                hit_window_start = -HIT_WINDOW_MS  # Can hit notes up to 160ms early
                hit_window_end = HIT_WINDOW_MS     # Can hit notes up to 160ms late

                if hit_window_start <= time_difference <= hit_window_end:
                    # Note is within hit window, but let's prioritize notes closer to perfect timing
                    hitable_notes.append((note, abs(time_difference)))
                    print(f"[AI Server] Direction {direction}: Note at {strum_time:.1f}ms, conductor at {conductor_time:.1f}ms, diff: {time_difference:.1f}ms")

        # Sort by timing accuracy (closest to 0 difference = best timing)
        if hitable_notes:
            hitable_notes.sort(key=lambda x: x[1])  # Sort by absolute time difference
            best_note, best_timing_diff = hitable_notes[0]

            # Only hit if we're reasonably close to perfect timing (within 80ms for better stability)
            if best_timing_diff <= 80:
                key_name = get_key_for_direction(direction)
                if key_name != "none":
                    actions.append(key_name)
                    print(f"[AI Server] Hitting {key_name} (direction {direction}) - timing diff: {best_timing_diff:.1f}ms")

                    # If this is a hold note, track it
                    if best_note.get('isHoldNote', False):
                        note_length = best_note.get('length', 0)  # Length in milliseconds
                        # Use the note's actual length, but with a reasonable minimum
                        hold_duration_ms = max(note_length, 200)  # Reduced minimum to 200ms

                        active_holds[direction] = {
                            'start_time': current_conductor_time,
                            'end_time': current_conductor_time + hold_duration_ms,
                            'note': best_note
                        }
                        print(f"[AI Server] Starting hold note for direction {direction}, length: {note_length}ms, hold_duration: {hold_duration_ms}ms")

    return actions

def update_vision(full_game_state):
    """Update the vision display with current game state"""
    global frame_counter

    if not ENABLE_VISION or not vision_system:
        return

    try:
        # Generate the vision image
        vision_image = vision_system.generate_vision(full_game_state)

        # Display the vision in real-time
        vision_system.display_vision(vision_image, "Funkin AI Vision")

        # Save vision frames if enabled
        if SAVE_VISION_FRAMES and frame_counter % VISION_SAVE_INTERVAL == 0:
            frame_filename = f"vision_frames/frame_{frame_counter:06d}.png"
            vision_system.save_vision(vision_image, frame_filename)
            print(f"[AI Server] Saved vision frame: {frame_filename}")

        frame_counter += 1

    except Exception as e:
        print(f"[AI Server] Vision processing error: {e}")

def format_actions(actions):
    """Format actions for sending to client"""
    if not actions:
        return "none"

    # Remove duplicates while preserving order
    unique_actions = []
    for action in actions:
        if action not in unique_actions:
            unique_actions.append(action)

    return ",".join(unique_actions)

# create TCP socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
# Disable Nagle's algorithm for faster small packet transmission
s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
s.bind((HOST, PORT))
s.listen(1)

print(f"[AI Server] Listening on {HOST}:{PORT}")

try:
    conn, addr = s.accept()
    print(f"[AI Server] Connected by {addr}")

    # Set a longer timeout and enable keepalive
    conn.settimeout(5.0)  # 5 second timeout instead of 1
    conn.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)

    buffer = ""
    while True:
        try:
            data = conn.recv(1024).decode('utf-8', errors='ignore')
            if not data:
                print("[AI Server] Client disconnected (no data)")
                break

            buffer += data
            # Debug: show first 50 chars of received data
            preview = data[:50] + "..." if len(data) > 50 else data
            print(f"[AI Server] Received {len(data)} bytes: {repr(preview)}")

            # Process complete JSON messages (separated by newlines)
            while '\n' in buffer:
                line, buffer = buffer.split('\n', 1)
                if line.strip():
                    try:
                        game_state = json.loads(line.strip())

                        # Always update vision display regardless of game state
                        update_vision(game_state)

                        # Only process if we're in playing state
                        if game_state.get('mainState') == 'PLAYING' and game_state.get('isPlaying'):
                            notes = game_state.get('notes', [])
                            game_timestamp = game_state.get('timestamp', time.time() * 1000)
                            actions = analyze_notes(notes, game_timestamp, game_state)  # Pass full game state
                            action_string = format_actions(actions)

                            # Always send the current action state (including holds)
                            response = action_string + "\n"
                            conn.sendall(response.encode('utf-8'))

                            # Only print when actions change or are not "none"
                            if action_string != "none":
                                print(f"[AI Server] Current actions: {action_string}")
                        else:
                            # Send "none" when not playing and clear any active holds
                            active_holds.clear()
                            conn.sendall("none\n".encode('utf-8'))

                    except json.JSONDecodeError as e:
                        print(f"[AI Server] JSON decode error: {e}")
                        print(f"[AI Server] Problematic line: {repr(line[:100])}")
                        conn.sendall("none\n".encode('utf-8'))
                    except Exception as e:
                        print(f"[AI Server] Error processing data: {e}")
                        conn.sendall("none\n".encode('utf-8'))

        except socket.timeout:
            continue  # Keep trying
        except ConnectionResetError:
            print("[AI Server] Connection was reset by client")
            break
        except Exception as e:
            print(f"[AI Server] Connection error: {e}")
            break

except KeyboardInterrupt:
    print("\n[AI Server] Shutting down...")
except Exception as e:
    print(f"[AI Server] Server error: {e}")
finally:
    try:
        conn.close()
    except:
        pass
    s.close()
    print("[AI Server] Server closed")
