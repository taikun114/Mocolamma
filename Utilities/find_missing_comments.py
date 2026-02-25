import json
import os
import sys

# プロジェクト構造に合わせたLocalizable.xcstringsへの相対パス
# Utilitiesディレクトリから実行されることを想定
FILE_PATH = os.path.join(os.path.dirname(__file__), '../Mocolamma/Resources/Localizable.xcstrings')

def find_missing_comments():
    if not os.path.exists(FILE_PATH):
        print(f"Error: Localizable.xcstrings not found at {FILE_PATH}")
        sys.exit(1)

    with open(FILE_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    strings = data.get('strings', {})
    missing_comments = []
    
    for key, value in strings.items():
        # コメントがない、または空のものをチェック
        if 'comment' not in value or not value['comment']:
            # shouldTranslateがfalseの場合は除外（翻訳不要なもの）
            if value.get('shouldTranslate') is False:
                continue
            missing_comments.append(key)
    
    if missing_comments:
        print(f"Found {len(missing_comments)} items missing comments:")
        print(json.dumps(missing_comments, ensure_ascii=False, indent=2))
    else:
        print("All items have comments!")

if __name__ == "__main__":
    find_missing_comments()
