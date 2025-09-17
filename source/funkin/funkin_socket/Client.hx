package funkin.funkin_socket;

// haxe imports
import sys.net.Host;
import sys.net.Socket;
import sys.thread.Thread;
// FlxG imports
import flixel.FlxG;
// funkin imports
import funkin.play.PlayState;
import funkin.play.PauseSubState;
import funkin.play.GameOverSubState;
import funkin.ui.freeplay.FreeplayState;
import funkin.ui.story.StoryMenuState;
import funkin.ui.mainmenu.MainMenuState;
import funkin.ui.title.TitleState;
import funkin.input.PreciseInputManager;
import funkin.play.notes.NoteSprite;
import funkin.play.notes.NoteDirection;
import flixel.input.keyboard.FlxKey;
import funkin.input.Controls;
import funkin.PlayerSettings;
import flixel.FlxState;

// Add this structure for AI input events
typedef AIInputEvent =
{
  var noteDirection:NoteDirection;
  var isPressed:Bool;
  var timestamp:Float;
}

class Client
{
  private static var instance:Client;

  private var isConnected:Bool = false;
  private var socket:Socket;
  private var host:Host;
  private var receiveThread:Thread;

  // Track current AI input state
  private var aiInputs:Map<NoteDirection, Bool> = new Map();
  private var previousAiInputs:Map<NoteDirection, Bool> = new Map();

  // AI input queue
  private var aiInputQueue:Array<AIInputEvent> = [];

  // Debouncing system to prevent rapid input changes
  private var lastInputChangeTime:Map<NoteDirection, Float> = new Map();
  private var minInputDelay:Float = 50.0; // Minimum 50ms between input changes per direction

  // Hook into FlxG.state updates
  private var originalStateUpdate:FlxState->Void;
  private var isHooked:Bool = false;

  private function new()
  {
    host = new Host("127.0.0.1");
    socket = new Socket();

    // Initialize AI input tracking
    for (direction in [NoteDirection.LEFT, NoteDirection.DOWN, NoteDirection.UP, NoteDirection.RIGHT])
    {
      aiInputs.set(direction, false);
      previousAiInputs.set(direction, false);
      lastInputChangeTime.set(direction, 0.0);
    }

    // Hook into the state update system
    hookIntoStateUpdate();
  }

  public static function getInstance():Client
  {
    if (instance == null)
    {
      instance = new Client();
    }
    return instance;
  }

  private function hookIntoStateUpdate():Void
  {
    if (isHooked) return;

    // Use FlxG's signal system to hook into updates
    FlxG.signals.preStateSwitch.add(onStateSwitch);
    FlxG.signals.postStateSwitch.add(onStateSwitch);

    isHooked = true;
  }

  private function onStateSwitch():Void
  {
    // Clear input queue when switching states
    aiInputQueue = [];
  }

  // Override FlxG.update to inject our AI processing
  public function update():Void
  {
    // Process AI inputs if we're in PlayState
    if (isInGame() && !isPaused() && !isGameOver())
    {
      processAIInputQueue();
    }
    else
    {
      // Clear queue if not in playable state
      aiInputQueue = [];
    }
  }

  public function connect():Void
  {
    if (!isConnected)
    {
      Thread.create(awaitConnection);

      // Start update loop in main thread
      startUpdateLoop();
    }
  }

  private function startUpdateLoop():Void
  {
    // Use FlxG's update loop by adding to the state's update
    var timer = new haxe.Timer(33); // ~30 FPS instead of 60 for better stability
    timer.run = function() {
      if (FlxG.state != null)
      {
        update();
      }
    };
  }

  private function awaitConnection():Void
  {
    while (!isConnected)
    {
      try
      {
        trace("Attempting to connect to 127.0.0.1:5000..."); // Changed port to 5000
        socket.connect(host, 5000); // Changed from 8080 to 5000

        // Keep socket in blocking mode for stability
        socket.setBlocking(true);

        isConnected = true;
        trace("Connected to server!");

        // Start the communication loops
        Thread.create(start_send_loop);
        start_receive_loop(); // Run receive loop in this thread
      }
      catch (e)
      {
        trace("Failed to connect: " + e);
        Sys.sleep(1.0); // Wait 1 second before retrying
      }
    }
  }

  public function getCurrentGameState():String
  {
    var currentState = FlxG.state;

    if (Std.isOfType(currentState, PlayState))
    {
      var playState = cast(currentState, PlayState);

      // Check if we're in a substate (paused, game over, etc.)
      if (playState.subState != null)
      {
        if (Std.isOfType(playState.subState, PauseSubState)) return "PAUSED";
        else if (Std.isOfType(playState.subState, GameOverSubState)) return "GAME_OVER";
        else
          return "PLAYING_SUBSTATE";
      }

      return "PLAYING";
    }
    else if (Std.isOfType(currentState, FreeplayState)) return "FREEPLAY_MENU";
    else if (Std.isOfType(currentState, StoryMenuState)) return "STORY_MENU";
    else if (Std.isOfType(currentState, MainMenuState)) return "MAIN_MENU";
    else if (Std.isOfType(currentState, TitleState)) return "TITLE_SCREEN";
    else
      return "UNKNOWN_STATE";
  }

  public function isInGame():Bool
  {
    return PlayState.instance != null && Std.isOfType(FlxG.state, PlayState);
  }

  public function isPaused():Bool
  {
    return isInGame() && PlayState.instance.subState != null && Std.isOfType(PlayState.instance.subState, PauseSubState);
  }

  public function isGameOver():Bool
  {
    return isInGame() && PlayState.instance.subState != null && Std.isOfType(PlayState.instance.subState, GameOverSubState);
  }

  public function getDetailedGameState():Dynamic
  {
    var state =
      {
        mainState: getCurrentGameState(),
        isPlaying: isInGame(),
        isPaused: isPaused(),
        isGameOver: isGameOver(),
        health: 0.0,
        score: 0,
        songName: "",
        difficulty: "",
        timestamp: isInGame() ? Conductor.instance.songPosition : Date.now().getTime(), // Use conductor time when in game
        notes: [] // Add notes array
      };

    if (isInGame() && PlayState.instance != null)
    {
      state.health = PlayState.instance.health;
      state.score = PlayState.instance.songScore;
      state.songName = PlayState.instance.currentSong?.songName ?? "";
      state.difficulty = PlayState.instance.currentDifficulty ?? "";

      // Add note data when playing
      if (getCurrentGameState() == "PLAYING")
      {
        state.notes = getPlayerNotesData();
      }
    }

    return state;
  }

  // Add this new function to get player notes data
  private function getPlayerNotesData():Array<Dynamic>
  {
    var notesData = [];

    if (PlayState.instance != null && PlayState.instance.playerStrumline != null)
    {
      var playerStrumline = PlayState.instance.playerStrumline;
      var strumLineY = playerStrumline.y;
      var currentConductorTime = Conductor.instance.songPosition;

      for (note in playerStrumline.notes.members)
      {
        if (note != null && note.alive && note.visible)
        {
          // Calculate screen position (0 = top of screen, 1 = strum line)
          var screenPos = (note.y - 0) / (strumLineY - 0);

          notesData.push(
            {
              direction: note.direction, // 0=left, 1=down, 2=up, 3=right
              screenPosition: screenPos, // 0-1 scale where 1 is hit zone
              strumTime: note.strumTime, // The exact time this note should be hit
              conductorTime: currentConductorTime, // Current conductor position
              timeDifference: note.strumTime - currentConductorTime, // How far away the note is in time
              length: note.length,
              isHoldNote: note.isHoldNote,
              mayHit: note.mayHit,
              tooEarly: note.tooEarly,
              hasMissed: note.hasMissed,
              hasBeenHit: note.hasBeenHit,
              x: note.x,
              y: note.y,
              kind: note.kind
            });
        }
      }
    }

    return notesData;
  }

  public function start_send_loop():Void
  {
    trace("Starting game state monitoring loop");

    while (isConnected)
    {
      try
      {
        var gameState = getDetailedGameState();

        // Send game state to server
        var data = haxe.Json.stringify(gameState);
        socket.output.writeString(data + "\n");
        socket.output.flush();
      }
      catch (e)
      {
        trace("Failed to send game state: " + e);
        isConnected = false;
      }

      Sys.sleep(1 / 30); // send data every 30 fps instead of 60 for better stability
    }
  }

  public function start_receive_loop():Void
  {
    trace("Starting input receive loop");

    while (isConnected)
    {
      try
      {
        // Read byte by byte to build complete messages
        var inputBuffer = "";
        var currentByte = "";

        while (isConnected)
        {
          try
          {
            currentByte = socket.input.readString(1);
            if (currentByte == "\n")
            {
              // Complete message received
              if (inputBuffer.length > 0)
              {
                var trimmedCommand = StringTools.trim(inputBuffer);
                if (trimmedCommand.length > 0)
                {
                  trace('[AI] Received input: ${trimmedCommand}');
                  processAIInput(trimmedCommand);
                }
                inputBuffer = ""; // Reset buffer
              }
            }
            else if (currentByte.length > 0)
            {
              inputBuffer += currentByte;
            }
          }
          catch (e:Dynamic)
          {
            // Handle read timeouts/errors
            if (Std.string(e).indexOf("Blocking") != -1 || Std.string(e).indexOf("timeout") != -1)
            {
              // These are normal for blocking sockets, continue
              Sys.sleep(0.001);
              continue;
            }
            else
            {
              trace("Read error: " + e);
              throw e; // Re-throw non-timeout errors
            }
          }
        }
      }
      catch (e:Dynamic)
      {
        trace("Error in receive loop: " + e);
        isConnected = false;
        break;
      }
    }

    trace("Receive loop ended");
  }

  private function processAIInput(inputString:String):Void
  {
    // Use the conductor's song position instead of PlayState instance timing
    var currentTime = Conductor.instance.songPosition;

    // Store previous state before changes
    for (direction in [NoteDirection.LEFT, NoteDirection.DOWN, NoteDirection.UP, NoteDirection.RIGHT])
    {
      previousAiInputs.set(direction, aiInputs.get(direction));
    }

    // Parse comma-separated inputs and determine new state
    var newInputState:Map<NoteDirection, Bool> = new Map();
    for (direction in [NoteDirection.LEFT, NoteDirection.DOWN, NoteDirection.UP, NoteDirection.RIGHT])
    {
      newInputState.set(direction, false);
    }

    var inputs = inputString.split(",");
    for (input in inputs)
    {
      var trimmedInput = StringTools.trim(input);
      var direction = stringToDirection(trimmedInput);

      if (direction != null)
      {
        newInputState.set(direction, true);
      }
    }

    // Apply debouncing: only allow changes if enough time has passed
    var hasChanges = false;
    for (direction in [NoteDirection.LEFT, NoteDirection.DOWN, NoteDirection.UP, NoteDirection.RIGHT])
    {
      var currentPressed = aiInputs.get(direction);
      var wantedPressed = newInputState.get(direction);
      var lastChangeTime = lastInputChangeTime.get(direction);

      // Only change input if:
      // 1. The desired state is different from current state
      // 2. Enough time has passed since last change for this direction
      if (currentPressed != wantedPressed && (currentTime - lastChangeTime) >= minInputDelay)
      {
        aiInputs.set(direction, wantedPressed);
        lastInputChangeTime.set(direction, currentTime);
        hasChanges = true;
        trace('[AI] ${direction} changed to ${wantedPressed} at time ${currentTime}');
      }
    }

    // Only queue changes if we actually have changes to make
    if (hasChanges)
    {
      queueAIInputChanges(currentTime);

      // If we're in game, process the queue immediately too
      if (isInGame() && !isPaused() && !isGameOver())
      {
        processAIInputQueue();
      }
    }
  }

  private function queueAIInputChanges(timestamp:Float):Void
  {
    for (direction in [NoteDirection.LEFT, NoteDirection.DOWN, NoteDirection.UP, NoteDirection.RIGHT])
    {
      var currentPressed = aiInputs.get(direction);
      var previousPressed = previousAiInputs.get(direction);

      // If input just got pressed
      if (currentPressed && !previousPressed)
      {
        aiInputQueue.push(
          {
            noteDirection: direction,
            isPressed: true,
            timestamp: timestamp
          });
        trace('[AI] Queued press: ${direction} at ${timestamp}');
      }
      // If input just got released
      else if (!currentPressed && previousPressed)
      {
        aiInputQueue.push(
          {
            noteDirection: direction,
            isPressed: false,
            timestamp: timestamp
          });
        trace('[AI] Queued release: ${direction} at ${timestamp}');
      }
    }
  }

  private function processAIInputQueue():Void
  {
    var playState = PlayState.instance;
    if (playState == null) return;

    if (aiInputQueue.length > 0)
    {
      trace('[AI] Processing ${aiInputQueue.length} queued inputs');

      // Process all queued inputs
      for (inputEvent in aiInputQueue)
      {
        trace('[AI] Processing input: ${inputEvent.noteDirection}, pressed: ${inputEvent.isPressed}, time: ${inputEvent.timestamp}');

        if (inputEvent.isPressed)
        {
          simulateNotePress(playState, inputEvent.noteDirection, inputEvent.timestamp);
        }
        else
        {
          simulateNoteRelease(playState, inputEvent.noteDirection, inputEvent.timestamp);
        }
      }

      // Clear processed inputs
      aiInputQueue = [];
    }
  }

  private function simulateNotePress(playState:PlayState, direction:NoteDirection, timestamp:Float):Void
  {
    try
    {
      trace('[AI] Simulating note press for direction: ${direction} at time: ${timestamp}');

      // Create a fake input event with the SAME timestamp system as real inputs
      var fakeInputEvent:PreciseInputEvent =
        {
          noteDirection: direction,
          timestamp: PreciseInputManager.getCurrentTimestamp(), // Use the same timestamp system as real inputs!
        };

      // Add to the input press queue just like real inputs
      @:privateAccess playState.inputPressQueue.push(fakeInputEvent);

      trace('[AI] Added press input to queue for direction: ${direction}');
    }
    catch (e:Dynamic)
    {
      trace('[AI] Overall error in simulateNotePress: ${e}');
      trace('[AI] Stack trace: ${haxe.CallStack.toString(haxe.CallStack.callStack())}');
    }
  }

  private function simulateNoteRelease(playState:PlayState, direction:NoteDirection, timestamp:Float):Void
  {
    try
    {
      trace('[AI] Simulating note release for direction: ${direction} at time: ${timestamp}');

      // Create a fake input event with the SAME timestamp system as real inputs
      var fakeInputEvent:PreciseInputEvent =
        {
          noteDirection: direction,
          timestamp: PreciseInputManager.getCurrentTimestamp(), // Use the same timestamp system as real inputs!
        };

      // Add to the input release queue just like real inputs
      @:privateAccess playState.inputReleaseQueue.push(fakeInputEvent);

      trace('[AI] Added release input to queue for direction: ${direction}');
    }
    catch (e:Dynamic)
    {
      trace('[AI] Overall error in simulateNoteRelease: ${e}');
    }
  }

  private function stringToDirection(input:String):Null<NoteDirection>
  {
    return switch (input.toLowerCase())
    {
      case "left": NoteDirection.LEFT;
      case "down": NoteDirection.DOWN;
      case "up": NoteDirection.UP;
      case "right": NoteDirection.RIGHT;
      case "none" | "": null;
      default: null;
    };
  }

  public function isClientConnected():Bool
  {
    return isConnected;
  }

  public function disconnect():Void
  {
    if (isConnected && socket != null)
    {
      socket.close();
      isConnected = false;
      trace("Disconnected from server!");
    }
  }

  static function main():Void
  {
    var client = Client.getInstance();
    client.connect();
  }
}
