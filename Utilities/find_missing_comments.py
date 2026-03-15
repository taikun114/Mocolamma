#!/usr/bin/env python3
# Copyright © 2026 Taiga Imaura, under the MIT License

import json
import sys
import os
import argparse

def find_localizable_file():
    """Recursively search for Localizable.xcstrings in the current directory."""
    for root, dirs, files in os.walk("."):
        if "Localizable.xcstrings" in files:
            return os.path.join(root, "Localizable.xcstrings")
    return None

def find_missing_comments():
    file_path = find_localizable_file()
    
    if not file_path:
        print("Error: Localizable.xcstrings not found in the current directory or its subdirectories.")
        return

    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        print(f"Error reading JSON: {e}")
        return

    strings = data.get("strings", {})
    missing_items = []

    for key, value in strings.items():
        # Check if comment is missing or empty
        if "comment" not in value or not value["comment"]:
            # Skip if shouldTranslate is explicitly set to false
            if value.get("shouldTranslate") is False:
                continue
            missing_items.append(key)

    if not missing_items:
        print("All items have developer comments!")
    else:
        print(f"Found {len(missing_items)} items missing developer comments:\n")
        for key in missing_items:
            print(f"Key: {key}")
            print("-" * 40)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Find items missing developer comments in String Catalog.",
        epilog="Copyright © 2026 Taiga Imaura, under the MIT License"
    )
    parser.add_argument("-v", "--version", action="version", version="1.0.0")
    
    args = parser.parse_args()
    
    find_missing_comments()
