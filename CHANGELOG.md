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

## 1.2.0 (under development)
### New Features
- **Revamping the Markdown rendering engine**
  - The Markdown rendering engine for chat has been updated from [**MarkdownUI**](https://github.com/gonzalezreal/swift-markdown-ui) to [**Textual**](https://github.com/gonzalezreal/textual), incorporating improvements such as enhanced performance and syntax highlighting for code blocks, resulting in a more user-friendly experience.
  - As a result, Mocolamma now requires **iOS / iPadOS 18.0 or later, macOS 15.0 or later, visionOS 2.0 or later**. Please note that users on older operating systems will need to perform a software update.
- **Support for Ollama's image generation feature (beta)**
  - As Ollama's image generation feature is currently in beta, future Ollama updates may introduce changes to its functionality (Ollama API), potentially causing the image generation feature to stop working in Mocolamma.
  - A demo of the image generation feature is available. Select `demo-image:0b` as the image generation model and send any prompt. This will perform a simulation advancing 0.2 seconds per step, finally outputting a test image.
- **Support image model tag**
  - Image model tag is now correctly displayed in the model inspector.
- **Add model download simulation in demo mode**
  - When demo mode is enabled, pressing the Add button with `demo-dl` or `demo-dl:0b` entered as the model name in the add model sheet will simulate a one-minute model download.

### Bug Fixes and Improvements
- **Fix to display image model details correctly**
- **Fix issue where the chat screen would freeze while scrolling**
- **Improve to show an error when selecting an image-only model in the chat screen**
- **Improve to prevent the add server and model sheet from closing when swiping down on iOS / iPadOS**
- **Improve the style of the Add and Complete buttons on the add server and model sheet on iOS / iPadOS 26**
  - The Complete button now uses the system native design, and the Add button now uses a design very close to the system native design.
- **Improve to display an action sheet requesting confirmation on the New Chat button**
- **Improve the Inspector button icon to display a more understandable one**
  - When the inspector is displayed in sheet style (e.g., on iPhone or iPad in compact view), the `info.circle` icon is now shown. When displayed in sidebar style, it remains unchanged.
- **Improve message bubble display on iOS / iPadOS when the display size is large**
  - When using an iPad with a wider window or a large-screen iPhone in landscape mode, message bubbles now have a slightly reduced maximum width just like on macOS, making them easier to read.
- **Improve to display a checkmark icon when message copying is successful**
- **Improve the model inspector to display a specific license when a license title is missing but the license body exists**
  - If the license body contains `MIT License`, it will display `MIT License` as the license title. If the license body contains both `Apache License` and `Version 2.0`, it will display `Apache License 2.0` as the license title.
- **Improve API timeout alert messages**
  - Added an advisory message about changing the timeout duration in settings when loading large models takes a long time.
- **Improve to display the language above the code block**
- **Improve download progress display performance on the model screen**
- **Improve the appearance of model download progress display on iOS / iPadOS 26 and later**
  - On iOS / iPadOS 26.0 or later, the model download progress display is now positioned as a `safeAreaBar`, applying a beautiful, blended blur effect created by the scroll edge effect.
- **Add filtering to the model picker in the chat screen to prevent models that do not support chat from being displayed**

## 1.1.0
### New Features
- **Add German (`de`), Spanish (`es`) localization by generative AI**
  - Since I have no knowledge of languages other than Japanese and English, translations may contain strange translations. If you notice any translations that need correction, I would appreciate it if you could send feedback on what to change and how!
- **Add access to each tab in the “View” menu**
  - Added menu items to the “View” menu in the menu bar to open the “Server,” “Model,” and “Chat” tabs. Press `⌘ (Command)` + `1` to open the “Server” tab, `⌘ (Command)` + `2` for the ‘Model’ tab, and `⌘ (Command)` + `3` for the “Chat” tab.
- **Add demo mode**
  - I implemented a demo mode that allows testing the app's basic functionality for App Store review.
  - You can access demo mode by adding a server with hostname `demo-mode` (server name is optional) and selecting it.

### Bug Fixes and Improvements
- **Fix issue that `scrollEdgeEffect` did not work in chat view**
  - On iOS / iPadOS 26 and macOS 26 and later, the chat input field background now blurs to blend in.
- **Fix issue where network requests could fail when launching the app**
  - Since this issue occasionally occurred in the previous fix, I added a retry function to the network check performed when the app launches to ensure this issue is resolved.
- **Fix issue where the copy button and retry button icons were not displayed in the chat screen on iOS / iPadOS 17 and macOS 14**
- **Fix issue where the stop button could not be pressed when “Select Model” was chosen in the model picker of the chat screen**

## 1.0.3
### New Features
- **Add French localization by generative AI**
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
