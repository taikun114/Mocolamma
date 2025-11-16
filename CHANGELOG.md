# Mocolamma Changelog
**English** | [日本語](docs/CHANGELOG-ja.md)

<!--
The order of listing is as follows.
- New Features
  - Notable Information
  - Support
  - Additions
- Bug Fixes and Improvements
  - Fixes
  - Improvements
  - Changes
  - Additions
  - Removals

Notes
- Make the first level of the list bold
- Make links bold
- When linking to Issues, Pull Requests, or Discussions, include the full URL
-->

## 1.0.3 (under development)
### New Features
- **Add French localization by generated AI**
  - Since I have no knowledge of French, the translations may contain strange translations. If you notice any translations that need correction, I would appreciate it if you could send feedback on what to change and how!

### Bug Fixes and Improvements
- **Fix “Click” to “Click or tap”**
- **Fix issue where network requests could fail when launching the app**

## 1.0.2
### Bug Fixes and Improvements
- **Fix issue where the icon size for the about this app screen was incorrect on macOS Sequoia or earlier**
- **Fix issue where the model list did not display correctly when models with the same digest as the `latest` tag existed simultaneously**
- **Fix issue that text conversion couldn't be confirmed while typing in languages requiring text conversion within the message edit field on the chat screen**
- **Improve chat screen to automatically scroll after sending a message**
- **Improve the size of the chat send button on iOS / iPadOS versions**

## 1.0.1
### Bug Fixes and Improvements
- **Fix issue where opening the inspector at small window sizes caused layout issues or crashes**
- **Fix issue that text conversion couldn't be confirmed while typing in languages requiring it within the chat screen's message input field**
- **Fix issue that picker could become empty in the chat screen's model picker when the last selected model couldn't be found after switching servers**
- **Improve to perform a network check when launching the app**
  - When you open the app for the first time, a message requesting local network permission will now show automatically.

## 1.0.0
Initial Release!
