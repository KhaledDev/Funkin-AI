package funkin.api.ai;

import flixel.FlxG;
import flixel.util.FlxTimer;
import funkin.play.PlayState;

/**
 * Main manager class for AI integration with FNF
 * This class coordinates the WebSocket server and note data reading
 */
class AIGameManager
{
  /**
   * Singleton instance of the AI game manager
   */
  public static var instance(get, null):AIGameManager;

  /**
   * The WebSocket server instance
   */
  private var server:WebSocketServer;

  /**
   * The note data reader
   */
  private var noteReader:NoteDataReader;

  /**
   * Whether the AI integration is enabled
   */
  public var isEnabled:Bool = true;

  /**
   * The update interval in seconds for sending data to AI clients
   */
  public static inline final UPDATE_INTERVAL:Float = 0.016; // ~60fps

  /**
   * Current play state reference
   */
  public var currentPlayState(default, null):PlayState;

  /**
   * Whether the game is currently in play
   */
  public var isPlaying(default, null):Bool = false;

  /**
   * The timer used for regular updates
   */
  private var updateTimer:FlxTimer;

  /**
   * The singleton getter
   */
  private static function get_instance():AIGameManager
  {
    if (instance == null)
    {
      instance = new AIGameManager();
    }
    return instance;
  }

  /**
   * Private constructor for singleton pattern
   */
  private function new()
  {
    server = WebSocketServer.instance;
  }

  /**
   * Initialize the AI integration
   */
  public function initialize():Void
  {
    if (!isEnabled) return;

    trace("Initializing AI Game Manager");

    // Start the WebSocket server
    server.start();

    trace("AI Game Manager: WebSocket server started");
  }

  /**
   * Shutdown the AI integration
   */
  public function shutdown():Void
  {
    stopPlaySession();

    if (server != null && server.isRunning)
    {
      server.stop();
    }
  }

  /**
   * Start tracking a play session
   * @param playState The current PlayState instance
   */
  public function startPlaySession(playState:PlayState):Void
  {
    if (!isEnabled || server == null || !server.isRunning) return;

    this.currentPlayState = playState;
    this.noteReader = new NoteDataReader(playState);
    this.isPlaying = true;

    trace("AI Game Manager: Play session started");

    // Start the update timer
    if (updateTimer != null)
    {
      updateTimer.cancel();
    }

    updateTimer = new FlxTimer().start(UPDATE_INTERVAL, onUpdate, 0);
  }

  /**
   * Stop tracking the current play session
   */
  public function stopPlaySession():Void
  {
    if (!isPlaying) return;

    this.isPlaying = false;
    this.currentPlayState = null;
    this.noteReader = null;

    if (updateTimer != null)
    {
      updateTimer.cancel();
      updateTimer = null;
    }

    trace("AI Game Manager: Play session stopped");
  }

  /**
   * Regular update callback
   */
  private function onUpdate(timer:FlxTimer):Void
  {
    if (!isPlaying)
    {
      // Occasionally log (to avoid console spam)
      if (Math.random() < 0.001) trace("AI Manager: Not sending - game not playing");
      return;
    }

    if (currentPlayState == null)
    {
      trace("AI Manager: Not sending - currentPlayState is null");
      return;
    }

    if (noteReader == null)
    {
      trace("AI Manager: Not sending - noteReader is null");
      return;
    }

    // Only send data if we're actually playing (not paused, etc.)
    if (FlxG.sound.music == null)
    {
      // Occasionally log
      if (Math.random() < 0.01) trace("AI Manager: Not sending - music is null");
      return;
    }

    if (!FlxG.sound.music.playing)
    {
      // Occasionally log
      if (Math.random() < 0.01) trace("AI Manager: Not sending - music not playing");
      return;
    }

    // Get current and upcoming notes
    var currentNotes = noteReader.getCurrentNotes();
    var upcomingNotes = noteReader.getUpcomingNotes();

    // Occasionally log note data
    if (Math.random() < 0.05 || (currentNotes.length > 0))
    {
      // trace('AI Manager: Sending note data, current notes: ${currentNotes.length}, upcoming: ${upcomingNotes.length}');
    }

    // Send the note data to connected clients
    server.sendNoteData(currentNotes, upcomingNotes);
  }
}
