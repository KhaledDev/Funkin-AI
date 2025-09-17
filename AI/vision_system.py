import numpy as np
import cv2
from typing import List, Dict, Optional, Tuple
import json

class FunkinVisionSystem:
    """
    Creates a visual representation of the Friday Night Funkin game state
    for AI processing. Shows a grayscale strumline with notes as circles.
    """

    def __init__(self, width: int = 400, height: int = 600):
        """
        Initialize the vision system.

        Args:
            width: Width of the output image
            height: Height of the output image
        """
        self.width = width
        self.height = height

        # Lane configuration (4 lanes: left, down, up, right)
        self.num_lanes = 4
        self.lane_width = width // self.num_lanes

        # Hit zone configuration
        self.hit_zone_y = int(height * 0.85)  # Hit zone at 85% down the screen
        self.hit_zone_height = 20

        # Note rendering configuration
        self.note_radius = 15
        self.hold_note_width = 8

        # Colors (grayscale values 0-255)
        self.background_color = 0      # Black background
        self.lane_line_color = 64      # Dark gray lane lines
        self.hit_zone_color = 128      # Medium gray hit zone
        self.note_color = 200          # Light gray notes
        self.hold_note_color = 160     # Medium-light gray hold notes
        self.missed_note_color = 80    # Dark gray missed notes
        self.hit_note_color = 255      # White for notes that can be hit

    def create_base_strumline(self) -> np.ndarray:
        """
        Create the base strumline visualization with lanes and hit zone.

        Returns:
            Base strumline image as numpy array
        """
        # Create blank image
        image = np.full((self.height, self.width), self.background_color, dtype=np.uint8)

        # Draw lane separator lines
        for i in range(1, self.num_lanes):
            x = i * self.lane_width
            cv2.line(image, (x, 0), (x, self.height), self.lane_line_color, 2)

        # Draw hit zone
        hit_zone_top = self.hit_zone_y - self.hit_zone_height // 2
        hit_zone_bottom = self.hit_zone_y + self.hit_zone_height // 2

        # Draw hit zone background
        cv2.rectangle(image, (0, hit_zone_top), (self.width, hit_zone_bottom),
                     self.hit_zone_color, -1)

        # Draw hit zone markers for each lane
        for i in range(self.num_lanes):
            lane_center_x = i * self.lane_width + self.lane_width // 2
            cv2.circle(image, (lane_center_x, self.hit_zone_y),
                      self.note_radius + 2, self.background_color, 2)

        return image

    def screen_position_to_y(self, screen_pos: float) -> int:
        """
        Convert game screen position (0-1 scale) to image Y coordinate.

        Args:
            screen_pos: Screen position where 1.0 is the hit zone

        Returns:
            Y coordinate in the image
        """
        # Clamp screen position to reasonable bounds
        screen_pos = max(-1.0, min(2.0, screen_pos))

        # Convert to Y coordinate (1.0 = hit zone, 0.0 = top, values > 1 go below hit zone)
        if screen_pos <= 1.0:
            # Above or at hit zone
            y = int(self.hit_zone_y - (1.0 - screen_pos) * self.hit_zone_y)
        else:
            # Below hit zone
            y = int(self.hit_zone_y + (screen_pos - 1.0) * (self.height - self.hit_zone_y))

        return max(0, min(self.height - 1, y))

    def direction_to_lane_x(self, direction: int) -> int:
        """
        Convert note direction to lane center X coordinate.

        Args:
            direction: Note direction (0=left, 1=down, 2=up, 3=right)

        Returns:
            X coordinate for the lane center
        """
        if 0 <= direction <= 3:
            return direction * self.lane_width + self.lane_width // 2
        return self.width // 2  # Default to center if invalid direction

    def render_note(self, image: np.ndarray, note_data: Dict) -> None:
        """
        Render a single note on the image.

        Args:
            image: Image to render on
            note_data: Dictionary containing note information
        """
        direction = note_data.get('direction', 0)
        screen_pos = note_data.get('screenPosition', 0.0)
        is_hold = note_data.get('isHoldNote', False)
        may_hit = note_data.get('mayHit', False)
        has_missed = note_data.get('hasMissed', False)
        has_been_hit = note_data.get('hasBeenHit', False)
        too_early = note_data.get('tooEarly', False)

        # Skip already hit notes
        if has_been_hit:
            return

        # Calculate position
        x = self.direction_to_lane_x(direction)
        y = self.screen_position_to_y(screen_pos)

        # Determine color based on note state
        if has_missed:
            color = self.missed_note_color
        elif may_hit:
            color = self.hit_note_color
        else:
            color = self.note_color

        if is_hold:
            # Render hold note as a rectangle
            length = note_data.get('length', 0)
            # Convert length from milliseconds to pixels (rough approximation)
            # Assuming notes move at about 1 pixel per ms at normal speed
            hold_height = max(10, int(length * 0.1))  # Scale down for visibility

            # Draw hold note body
            rect_top = max(0, y - hold_height)
            cv2.rectangle(image,
                         (x - self.hold_note_width // 2, rect_top),
                         (x + self.hold_note_width // 2, y),
                         color, -1)

            # Draw hold note head
            cv2.circle(image, (x, y), self.note_radius, color, -1)
            cv2.circle(image, (x, y), self.note_radius, self.background_color, 2)
        else:
            # Render regular note as a circle
            cv2.circle(image, (x, y), self.note_radius, color, -1)
            cv2.circle(image, (x, y), self.note_radius, self.background_color, 2)

    def generate_vision(self, game_state: Dict) -> np.ndarray:
        """
        Generate the complete vision for the current game state.

        Args:
            game_state: Game state dictionary from the socket server

        Returns:
            Grayscale image as numpy array
        """
        # Create base strumline
        image = self.create_base_strumline()

        # Get notes data
        notes = game_state.get('notes', [])

        # Render each note
        for note in notes:
            self.render_note(image, note)

        return image

    def save_vision(self, image: np.ndarray, filename: str) -> bool:
        """
        Save the vision image to a file.

        Args:
            image: Image to save
            filename: Output filename

        Returns:
            True if successful, False otherwise
        """
        try:
            cv2.imwrite(filename, image)
            return True
        except Exception as e:
            print(f"Error saving vision image: {e}")
            return False

    def get_vision_array(self, game_state: Dict) -> np.ndarray:
        """
        Get the vision as a normalized numpy array suitable for ML processing.

        Args:
            game_state: Game state dictionary

        Returns:
            Normalized array with values 0-1
        """
        image = self.generate_vision(game_state)
        return image.astype(np.float32) / 255.0

    def display_vision(self, image: np.ndarray, window_name: str = "Funkin AI Vision") -> None:
        """
        Display the vision in a window (for debugging).

        Args:
            image: Image to display
            window_name: Window title
        """
        try:
            cv2.imshow(window_name, image)
            cv2.waitKey(1)  # Non-blocking wait
        except Exception as e:
            print(f"Error displaying vision: {e}")

# Utility functions for easy integration
def create_vision_from_json(json_data: str, width: int = 400, height: int = 600) -> Optional[np.ndarray]:
    """
    Create a vision image from JSON game state data.

    Args:
        json_data: JSON string containing game state
        width: Image width
        height: Image height

    Returns:
        Vision image or None if error
    """
    try:
        game_state = json.loads(json_data)
        vision_system = FunkinVisionSystem(width, height)
        return vision_system.generate_vision(game_state)
    except Exception as e:
        print(f"Error creating vision from JSON: {e}")
        return None

def save_vision_from_json(json_data: str, filename: str, width: int = 400, height: int = 600) -> bool:
    """
    Create and save a vision image from JSON game state data.

    Args:
        json_data: JSON string containing game state
        filename: Output filename
        width: Image width
        height: Image height

    Returns:
        True if successful, False otherwise
    """
    image = create_vision_from_json(json_data, width, height)
    if image is not None:
        vision_system = FunkinVisionSystem(width, height)
        return vision_system.save_vision(image, filename)
    return False

if __name__ == "__main__":
    # Test the vision system with sample data
    sample_game_state = {
        "mainState": "PLAYING",
        "isPlaying": True,
        "notes": [
            {
                "direction": 0,
                "screenPosition": 0.2,
                "strumTime": 1000,
                "conductorTime": 800,
                "isHoldNote": False,
                "mayHit": False,
                "hasMissed": False,
                "hasBeenHit": False
            },
            {
                "direction": 1,
                "screenPosition": 0.5,
                "strumTime": 1200,
                "conductorTime": 800,
                "isHoldNote": False,
                "mayHit": True,
                "hasMissed": False,
                "hasBeenHit": False
            },
            {
                "direction": 2,
                "screenPosition": 1.0,
                "strumTime": 800,
                "conductorTime": 800,
                "isHoldNote": True,
                "length": 500,
                "mayHit": True,
                "hasMissed": False,
                "hasBeenHit": False
            },
            {
                "direction": 3,
                "screenPosition": 1.2,
                "strumTime": 600,
                "conductorTime": 800,
                "isHoldNote": False,
                "mayHit": False,
                "hasMissed": True,
                "hasBeenHit": False
            }
        ]
    }

    # Create and test the vision system
    vision_system = FunkinVisionSystem(400, 600)
    image = vision_system.generate_vision(sample_game_state)

    print("Vision system test completed!")
    print(f"Generated image shape: {image.shape}")

    # Save test image
    if vision_system.save_vision(image, "test_vision.png"):
        print("Test vision saved as 'test_vision.png'")
    else:
        print("Failed to save test vision")
