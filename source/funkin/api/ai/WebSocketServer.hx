package funkin.api.ai;

import haxe.Json;
import haxe.io.Bytes;
import flixel.FlxG;
import funkin.input.PreciseInputManager;
import funkin.play.notes.NoteDirection;
import funkin.Conductor; // Add missing conductor import
#if sys
import sys.net.Host;
import sys.net.Socket;
import sys.thread.Thread;
#end

/**
 * WebSocket server for AI integration with Friday Night Funkin'
 * Allows external AI clients to:
 * 1. Receive note data and game state
 * 2. Send input commands back to the game
 */
class WebSocketServer
{
  /**
   * Singleton instance of the WebSocket server
   */
  public static var instance(get, null):WebSocketServer;

  /**
   * Whether the server is currently running
   */
  public var isRunning(default, null):Bool = false;

  /**
   * The port on which the server listens
   */
  public static inline final DEFAULT_PORT:Int = 8765; // Changed to match API.md documentation

  /**
   * Socket for the server
   */
  #if sys
  private var serverSocket:Socket;
  private var clientSockets:Array<Socket> = [];
  private var serverThread:Thread;
  #end

  /**
   * Currently connected clients
   */
  private var clientCount:Int = 0;

  /**
   * The singleton getter
   */
  private static function get_instance():WebSocketServer
  {
    if (instance == null)
    {
      instance = new WebSocketServer();
    }
    return instance;
  }

  /**
   * Private constructor for singleton pattern
   */
  private function new() {}

  /**
   * Starts the WebSocket server
   * @param port The port to listen on (default: 8765)
   */
  public function start(port:Int = DEFAULT_PORT):Void
  {
    if (isRunning)
    {
      trace('WebSocket server is already running');
      return;
    }

    try
    {
      #if sys
      // Create server socket
      serverSocket = new Socket();
      serverSocket.bind(new Host("0.0.0.0"), port); // Bind to all interfaces
      serverSocket.listen(10); // Allow up to 10 pending connections

      // Start server in a separate thread
      serverThread = Thread.create(function() {
        serverLoop();
      });

      trace('WebSocket server started on port ${port}');
      isRunning = true;
      #else
      // For non-sys targets, just simulate the server
      trace('WebSocket server simulated on port ${port} (no real server available on this platform)');
      isRunning = true;
      #end
    }
    catch (e)
    {
      trace('Failed to start WebSocket server: ${e}');
    }
  }

  #if sys
  /**
   * Main server loop that accepts connections
   */
  private function serverLoop():Void
  {
    trace('WebSocket server loop started');
    while (isRunning)
    {
      try
      {
        trace('Waiting for client connections on port ${DEFAULT_PORT}...');
        // Accept new connections
        var client = serverSocket.accept();
        trace('New client connected from ${client.peer().host}:${client.peer().port}');

        clientSockets.push(client);
        clientCount++;

        trace('AI client connected (${clientCount} total)');

        // Start a thread to handle this client
        Thread.create(function() {
          handleClient(client);
        });
      }
      catch (e)
      {
        if (isRunning)
        {
          trace('Error accepting connection: ${e}');
        }
        // If server was stopped, this is expected, so no need to log
      }

      // Small delay to prevent tight loop
      Sys.sleep(0.01);
    }
  }

  /**
   * Handle communication with a specific client
   */
  private function handleClient(client:Socket):Void
  {
    trace('Client handler thread started');
    var buffer = Bytes.alloc(4096);

    while (isRunning)
    {
      try
      {
        // Non-blocking read
        client.setBlocking(false);
        var bytesRead = client.input.readBytes(buffer, 0, buffer.length);

        if (bytesRead > 0)
        {
          // Process the received data
          var data = buffer.getString(0, bytesRead);
          // trace('Received data from client: ${data}');

          try
          {
            var parsedData = Json.parse(data);
            processAIInput(parsedData);
          }
          catch (e)
          {
            trace('Error parsing input: ${e}');
          }
        }
      }
      catch (e)
      {
        // Check if client disconnected
        if (Std.string(e).indexOf("Eof") >= 0)
        {
          trace('Client disconnected (EOF)');
          break; // Client disconnected
        }

        // Ignore would-block errors (no data available)
        if (Std.string(e).indexOf("Blocking") < 0 && Std.string(e).indexOf("Resource temporarily unavailable") < 0)
        {
          // trace('Error reading from client: ${e}');
        }
      }

      // Small delay to prevent tight loop
      Sys.sleep(0.01);
    }

    // Clean up when client disconnects
    clientCount--;
    clientSockets.remove(client);
    client.close();
    trace('AI client disconnected (${clientCount} remaining)');
  }
  #end

  /**
   * Stops the WebSocket server
   */
  public function stop():Void
  {
    if (!isRunning) return;

    try
    {
      isRunning = false;

      #if sys
      // Close all client connections
      for (client in clientSockets)
      {
        client.close();
      }
      clientSockets = [];

      // Close the server socket
      if (serverSocket != null)
      {
        serverSocket.close();
        serverSocket = null;
      }
      #end

      clientCount = 0;
      trace('WebSocket server stopped');
    }
    catch (e)
    {
      trace('Error stopping WebSocket server: ${e}');
    }
  }

  /**
   * Process input commands from the AI
   * @param data The input data
   */
  public function processAIInput(data:Dynamic):Void
  {
    // Input can be a single key press or multiple keys
    if (data.keys != null && Std.isOfType(data.keys, Array))
    {
      var keys:Array<String> = data.keys;
      var timestamp = PreciseInputManager.getCurrentTimestamp();

      // Process each key in the input
      for (key in keys)
      {
        var direction:Null<NoteDirection> = null;
        switch (key.toLowerCase())
        {
          case "left":
            direction = NoteDirection.LEFT;
          case "down":
            direction = NoteDirection.DOWN;
          case "up":
            direction = NoteDirection.UP;
          case "right":
            direction = NoteDirection.RIGHT;
          default: // Ignore other keys
        }

        if (direction != null)
        {
          // Dispatch the onInputPressed signal to simulate the key press
          PreciseInputManager.instance.onInputPressed.dispatch(
            {
              noteDirection: direction,
              timestamp: timestamp
            });
        }
      }
    }
    // Handle the input command format from API.md
    else if (data.type == "input" && data.keyCode != null)
    {
      var timestamp = PreciseInputManager.getCurrentTimestamp();
      var direction:Null<NoteDirection> = null;

      // Convert keyCode (0-3) to note direction
      switch (data.keyCode)
      {
        case 0:
          direction = NoteDirection.LEFT;
        case 1:
          direction = NoteDirection.DOWN;
        case 2:
          direction = NoteDirection.UP;
        case 3:
          direction = NoteDirection.RIGHT;
      }

      if (direction != null)
      {
        if (data.pressed == true)
        {
          // Key press event
          PreciseInputManager.instance.onInputPressed.dispatch(
            {
              noteDirection: direction,
              timestamp: timestamp
            });
        }
        else
        {
          // Key release event (if needed in the future)
          // Currently not implemented in PreciseInputManager
        }
      }
    }
  }

  /**
   * Send game state data to all connected clients
   * @param data The data to send
   */
  public function sendGameData(data:Dynamic):Void
  {
    if (!isRunning)
    {
      trace('Not sending data: Server not running');
      return;
    }

    if (clientCount == 0)
    {
      // Only log occasionally to avoid spam
      if (Math.random() < 0.01) trace('Not sending data: No clients connected');
      return;
    }

    try
    {
      var jsonString:String = Json.stringify(data);

      #if sys
      // Send to all connected clients
      var deadClients = [];

      for (client in clientSockets)
      {
        try
        {
          // Simple protocol: Send the JSON string followed by a newline
          client.output.writeString(jsonString + "\n");
          client.output.flush();
        }
        catch (e)
        {
          // Mark client for removal
          deadClients.push(client);
          trace('Error sending to client: ${e}');
        }
      }

      // Clean up any dead clients
      for (client in deadClients)
      {
        clientSockets.remove(client);
        clientCount--;
        trace('AI client disconnected (${clientCount} remaining)');
      }

      if (clientCount > 0)
      {
        // trace('Sending data to ${clientCount} clients: ${jsonString}');
      }
      #else
      // In simulation mode, just log the message
      trace('Sending data to ${clientCount} clients: ${jsonString}');
      #end
    }
    catch (e)
    {
      trace('Error sending game data: ${e}');
    }
  }

  /**
   * Send note data to all connected clients
   * @param currentNotes Array of current notes
   * @param upcomingNotes Array of notes coming in the next 10ms
   */
  public function sendNoteData(currentNotes:Array<Dynamic>, upcomingNotes:Array<Dynamic>):Void
  {
    var data =
      {
        type: "noteData",
        currentTime: Conductor.instance.songPosition,
        currentNotes: currentNotes,
        upcomingNotes: upcomingNotes
      };

    sendGameData(data);
  }
}
