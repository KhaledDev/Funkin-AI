#!/usr/bin/env python3
"""
Test script for the Funkin Vision System.
This script tests the vision generation with various game states.
"""

from vision_system import FunkinVisionSystem
import json
import os

def test_basic_vision():
    """Test basic vision generation with sample data."""
    print("Testing basic vision generation...")

    # Create sample game state with various note types
    sample_game_state = {
        "mainState": "PLAYING",
        "isPlaying": True,
        "health": 1.0,
        "score": 12345,
        "songName": "Test Song",
        "difficulty": "hard",
        "timestamp": 1000,
        "notes": [
            # Note approaching from top (early)
            {
                "direction": 0,  # Left
                "screenPosition": 0.2,
                "strumTime": 1200,
                "conductorTime": 1000,
                "timeDifference": 200,
                "isHoldNote": False,
                "mayHit": False,
                "tooEarly": True,
                "hasMissed": False,
                "hasBeenHit": False,
                "length": 0
            },
            # Note in hit zone (can be hit)
            {
                "direction": 1,  # Down
                "screenPosition": 0.95,
                "strumTime": 1050,
                "conductorTime": 1000,
                "timeDifference": 50,
                "isHoldNote": False,
                "mayHit": True,
                "tooEarly": False,
                "hasMissed": False,
                "hasBeenHit": False,
                "length": 0
            },
            # Hold note at hit zone
            {
                "direction": 2,  # Up
                "screenPosition": 1.0,
                "strumTime": 1000,
                "conductorTime": 1000,
                "timeDifference": 0,
                "isHoldNote": True,
                "mayHit": True,
                "tooEarly": False,
                "hasMissed": False,
                "hasBeenHit": False,
                "length": 800
            },
            # Missed note (below hit zone)
            {
                "direction": 3,  # Right
                "screenPosition": 1.3,
                "strumTime": 800,
                "conductorTime": 1000,
                "timeDifference": -200,
                "isHoldNote": False,
                "mayHit": False,
                "tooEarly": False,
                "hasMissed": True,
                "hasBeenHit": False,
                "length": 0
            },
            # Another regular note approaching
            {
                "direction": 1,  # Down
                "screenPosition": 0.4,
                "strumTime": 1300,
                "conductorTime": 1000,
                "timeDifference": 300,
                "isHoldNote": False,
                "mayHit": False,
                "tooEarly": True,
                "hasMissed": False,
                "hasBeenHit": False,
                "length": 0
            }
        ]
    }

    # Create vision system
    vision_system = FunkinVisionSystem(400, 600)

    # Generate vision
    image = vision_system.generate_vision(sample_game_state)

    # Save test image
    os.makedirs("test_output", exist_ok=True)
    filename = "test_output/basic_vision_test.png"

    if vision_system.save_vision(image, filename):
        print(f"✓ Basic vision test saved as '{filename}'")
        print(f"  Image shape: {image.shape}")
        print(f"  Pixel value range: {image.min()}-{image.max()}")
        return True
    else:
        print("✗ Failed to save basic vision test")
        return False

def test_empty_state():
    """Test vision with no notes."""
    print("\nTesting empty game state...")

    empty_state = {
        "mainState": "PLAYING",
        "isPlaying": True,
        "notes": []
    }

    vision_system = FunkinVisionSystem(400, 600)
    image = vision_system.generate_vision(empty_state)

    filename = "test_output/empty_state_test.png"

    if vision_system.save_vision(image, filename):
        print(f"✓ Empty state test saved as '{filename}'")
        return True
    else:
        print("✗ Failed to save empty state test")
        return False

def test_different_sizes():
    """Test vision with different image sizes."""
    print("\nTesting different image sizes...")

    sample_state = {
        "mainState": "PLAYING",
        "isPlaying": True,
        "notes": [
            {
                "direction": 0,
                "screenPosition": 0.5,
                "strumTime": 1000,
                "conductorTime": 1000,
                "isHoldNote": False,
                "mayHit": True,
                "hasMissed": False,
                "hasBeenHit": False
            }
        ]
    }

    sizes = [(200, 300), (800, 1200), (100, 150)]

    for i, (width, height) in enumerate(sizes):
        vision_system = FunkinVisionSystem(width, height)
        image = vision_system.generate_vision(sample_state)

        filename = f"test_output/size_test_{width}x{height}.png"

        if vision_system.save_vision(image, filename):
            print(f"✓ Size test {width}x{height} saved as '{filename}'")
        else:
            print(f"✗ Failed to save size test {width}x{height}")
            return False

    return True

def test_normalized_array():
    """Test getting normalized arrays for ML processing."""
    print("\nTesting normalized array output...")

    sample_state = {
        "mainState": "PLAYING",
        "isPlaying": True,
        "notes": [
            {"direction": 0, "screenPosition": 0.8, "mayHit": True, "isHoldNote": False, "hasMissed": False, "hasBeenHit": False},
            {"direction": 1, "screenPosition": 1.0, "mayHit": True, "isHoldNote": False, "hasMissed": False, "hasBeenHit": False},
            {"direction": 2, "screenPosition": 1.2, "mayHit": False, "isHoldNote": False, "hasMissed": True, "hasBeenHit": False}
        ]
    }

    vision_system = FunkinVisionSystem(128, 192)  # Smaller size for ML
    normalized_array = vision_system.get_vision_array(sample_state)

    print(f"✓ Normalized array shape: {normalized_array.shape}")
    print(f"  Data type: {normalized_array.dtype}")
    print(f"  Value range: {normalized_array.min():.3f} - {normalized_array.max():.3f}")

    return True

def main():
    """Run all vision system tests."""
    print("=== Funkin Vision System Tests ===\n")

    # Check if required packages are available
    try:
        import cv2
        import numpy as np
        print(f"✓ OpenCV version: {cv2.__version__}")
        print(f"✓ NumPy version: {np.__version__}\n")
    except ImportError as e:
        print(f"✗ Missing required package: {e}")
        print("Please install requirements: pip install -r requirements.txt")
        return False

    tests = [
        test_basic_vision,
        test_empty_state,
        test_different_sizes,
        test_normalized_array
    ]

    passed = 0
    total = len(tests)

    for test_func in tests:
        try:
            if test_func():
                passed += 1
            else:
                print(f"Test {test_func.__name__} failed!")
        except Exception as e:
            print(f"✗ Test {test_func.__name__} crashed: {e}")

    print(f"\n=== Test Results ===")
    print(f"Passed: {passed}/{total}")

    if passed == total:
        print("🎉 All tests passed! Vision system is working correctly.")
        print("\nTo use with the socket server:")
        print("1. Set ENABLE_VISION = True in test_socket_server.py")
        print("2. Set SAVE_VISION_FRAMES = True to save frames during gameplay")
        print("3. Run the server and start playing to generate vision data")
        return True
    else:
        print("❌ Some tests failed. Please check the errors above.")
        return False

if __name__ == "__main__":
    main()
