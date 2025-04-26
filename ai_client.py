import socket
import json
import time
import sys
import traceback
import threading

def connect_to_fnf(host="localhost", port=8765):
    """
    Connect to Friday Night Funkin' WebSocket server
    """
    print(f"Connecting to FNF server at {host}:{port}...")

    # Create TCP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

    try:
        sock.connect((host, port))
        print("Connected successfully!")

        # Buffer to store incomplete messages
        buffer = ""

        while True:
            # Receive data
            try:
                data = sock.recv(4096)
                if not data:
                    print("Connection closed by server")
                    break

                # Decode UTF-8 data
                text = data.decode('utf-8')
                print(f"Raw data received: {text[:100]}...")

                # Add to buffer and process complete messages
                buffer += text
                lines = buffer.split('\n')
                buffer = lines.pop()  # Keep the last incomplete line in the buffer

                for line in lines:
                    if line.strip():  # Only process non-empty lines
                        try:
                            # Parse JSON message
                            message = json.loads(line)
                            process_message(message, sock)
                        except json.JSONDecodeError:
                            print(f"Invalid JSON: {line}")
            except socket.error as e:
                print(f"Socket error: {e}")
                break

            time.sleep(0.01)  # Small delay to prevent CPU spinning
    except KeyboardInterrupt:
        print("Client stopped by user")
    except Exception as e:
        print(f"Error: {e}")
        traceback.print_exc()
    finally:
        sock.close()
        print("Connection closed")

# Global dictionary to keep track of notes that are scheduled to be pressed
scheduled_notes = {}

def process_message(message, sock):
    """
    Process messages from the server and respond appropriately
    """
    if message.get("type") == "noteData":
        current_time = message.get("currentTime", 0)
        current_notes = message.get("currentNotes", [])

        print(f"Time: {current_time}, Notes: {len(current_notes)}")

        # Clean up any scheduled notes that are no longer in the current notes
        current_note_ids = [note.get("strumTime", 0) * 10 + note.get("direction", 0) for note in current_notes]
        keys_to_remove = []
        for note_id in scheduled_notes:
            if note_id not in current_note_ids:
                keys_to_remove.append(note_id)

        for key in keys_to_remove:
            scheduled_notes.pop(key, None)

        # Process each note
        for note in current_notes:
            if note.get("mayHit", False) and not note.get("hasMissed", False) and not note.get("tooEarly", True):
                direction = note.get("direction", 0)
                strum_time = note.get("strumTime", 0)
                note_id = strum_time * 10 + direction  # Create a unique ID for this note

                # If we haven't scheduled this note yet
                if note_id not in scheduled_notes:
                    # Calculate the optimal time to hit the note
                    time_until_hit = strum_time - current_time

                    # Only schedule if the note is within a reasonable time frame
                    # Don't schedule notes that are too far in the future
                    if 0 <= time_until_hit <= 150:
                        # Use a slight offset to account for network delay
                        hit_delay = max(0, time_until_hit - 30)  # 30ms earlier to account for latency

                        print(f"Scheduling note direction {direction} in {hit_delay}ms (strum_time={strum_time}, current_time={current_time})")

                        # Schedule the note press
                        scheduled_notes[note_id] = True

                        # Use a thread to hit the note at the right time
                        threading.Thread(
                            target=hit_note,
                            args=(sock, direction, hit_delay),
                            daemon=True
                        ).start()

def hit_note(sock, direction, delay_ms):
    """
    Hit a note after a specified delay
    """
    # Convert milliseconds to seconds
    delay_sec = delay_ms / 1000.0

    # Wait until it's time to hit the note
    time.sleep(delay_sec)

    # Press the key
    press_command = {
        "type": "input",
        "keyCode": direction,
        "pressed": True
    }
    send_command(sock, press_command)

    # Release the key after a brief hold
    time.sleep(0.06)  # Hold the key for 60ms

    release_command = {
        "type": "input",
        "keyCode": direction,
        "pressed": False
    }
    send_command(sock, release_command)

def send_command(sock, command):
    """
    Send a command to the server
    """
    try:
        message = json.dumps(command) + "\n"
        sock.sendall(message.encode('utf-8'))
        print(f"Sent command: {message.strip()}")
    except Exception as e:
        print(f"Error sending command: {e}")

if __name__ == "__main__":
    try:
        if len(sys.argv) > 2:
            connect_to_fnf(host=sys.argv[1], port=int(sys.argv[2]))
        elif len(sys.argv) > 1:
            connect_to_fnf(port=int(sys.argv[1]))
        else:
            connect_to_fnf()
    except ConnectionRefusedError:
        print("Connection refused. Make sure the game is running and the server is started.")
    except Exception as e:
        print(f"Connection error: {e}")
        traceback.print_exc()
