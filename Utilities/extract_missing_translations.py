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

def extract_missing_translations(lang_code, show_ja=True):
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
        # Skip if shouldTranslate is explicitly set to false
        if value.get("shouldTranslate") is False:
            continue
            
        localizations = value.get("localizations", {})
        
        # Check for developer comment
        comment = value.get("comment")
        if not comment:
            # Skip items without a comment as per requirement
            continue
            
        # Extract Japanese translation as reference
        original_ja = None
        ja_data = localizations.get("ja")
        if not ja_data:
            # Skip items without Japanese translation as per requirement
            continue
            
        if "stringUnit" in ja_data:
            original_ja = ja_data["stringUnit"].get("value")
        elif "variations" in ja_data:
            # For plural variations, use "other" as the representative value
            plural_other = ja_data.get("variations", {}).get("plural", {}).get("other", {})
            original_ja = plural_other.get("stringUnit", {}).get("value")

        if not original_ja:
            # Skip if Japanese value is empty
            continue

        # Check translation status for the target language
        is_missing = False
        if lang_code not in localizations:
            is_missing = True
        else:
            lang_data = localizations[lang_code]
            
            # Check standard stringUnit
            if "stringUnit" in lang_data:
                state = lang_data.get("stringUnit", {}).get("state")
                if state != "translated":
                    is_missing = True
            # Check plural variations
            elif "variations" in lang_data:
                plural = lang_data.get("variations", {}).get("plural", {})
                if not plural:
                    is_missing = True
                else:
                    # Mark as missing if any variation is not yet translated
                    for p_key, p_value in plural.items():
                        if p_value.get("stringUnit", {}).get("state") != "translated":
                            is_missing = True
                            break
            else:
                is_missing = True
        
        if is_missing:
            missing_items.append((key, comment, original_ja))

    if not missing_items:
        print(f"All items are translated for language: {lang_code}")
    else:
        print(f"Missing translations for '{lang_code}': {len(missing_items)} items found.\n")
        for key, comment, original_ja in missing_items:
            print(f"Key: {key}")
            # Show Original (ja) if enabled and the target language is not Japanese
            if show_ja and lang_code != "ja":
                print(f"Original (ja): {original_ja}")
            print(f"Comment: {comment}")
            print("-" * 40)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Extract missing translations from String Catalog.",
        epilog="Copyright © 2026 Taiga Imaura, under the MIT License"
    )
    # lang argument is optional to allow showing help by default
    parser.add_argument("lang", nargs="?", help="Language code to check (e.g., ja, en, zh-Hans)")
    parser.add_argument("--no-ja", action="store_false", dest="show_ja", help="Do not output original Japanese localization")
    parser.add_argument("-v", "--version", action="version", version="1.0.0")
    
    args = parser.parse_args()
    
    if not args.lang:
        parser.print_help()
    else:
        extract_missing_translations(args.lang, show_ja=args.show_ja)
