package funkin.api.ai;

import funkin.play.PlayState;
import funkin.play.notes.NoteSprite;

/**
 * Class responsible for reading note data from the current gameplay
 * and providing it in a format suitable for AI processing
 */
class NoteDataReader
{
  /**
   * Reference to the current play state
   */
  private var playState:PlayState;

  /**
   * Time window for upcoming notes (in ms)
   */
  public static inline final UPCOMING_NOTES_WINDOW:Float = 10.0;

  public function new(playState:PlayState)
  {
    this.playState = playState;
  }

  /**
   * Get information about the currently active notes (those that should be hit now)
   * @return Array of note data objects
   */
  public function getCurrentNotes():Array<Dynamic>
  {
    var result:Array<Dynamic> = [];

    if (playState == null || playState.playerStrumline == null) return result;

    // Check player strumline notes
    for (note in playState.playerStrumline.notes.members)
    {
      if (note == null) continue;
      if (note.mayHit && !note.hasBeenHit && !note.handledMiss && note.alive)
      {
        result.push(convertNoteToData(note));
      }
    }

    return result;
  }

  /**
   * Get information about upcoming notes (within the next 10ms)
   * @return Array of note data objects
   */
  public function getUpcomingNotes():Array<Dynamic>
  {
    var result:Array<Dynamic> = [];

    if (playState == null || playState.playerStrumline == null) return result;

    var currentTime = Conductor.instance.songPosition;
    var futureTime = currentTime + UPCOMING_NOTES_WINDOW;

    // Check player strumline notes
    for (note in playState.playerStrumline.notes.members)
    {
      if (note == null) continue;
      var noteTime = note.strumTime;

      // Check if the note is in the upcoming window and hasn't been hit yet
      if (!note.hasBeenHit && !note.handledMiss && note.alive && noteTime > currentTime && noteTime <= futureTime)
      {
        result.push(convertNoteToData(note));
      }
    }

    return result;
  }

  /**
   * Convert a Note object to a simplified data structure for transmission
   * @param note The note to convert
   * @return A simplified note data object
   */
  private function convertNoteToData(note:NoteSprite):Dynamic
  {
    return {
      direction: note.direction,
      strumTime: note.strumTime,
      isHoldNote: note.isHoldNote,
      mayHit: note.mayHit,
      tooEarly: note.tooEarly,
      hasMissed: note.hasMissed
    };
  }
}
