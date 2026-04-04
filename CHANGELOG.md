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

## 1.2.3
### New Features
- **Support audio model tag**

## 1.2.2
### New Features
- **Add a copy button to code blocks in the chat screen**
  - You can copy only the code within the code block.

### Bug Fixes and Improvements
- **Fix issues where text selection could not cross code blocks and where multiple word selection was not possible by holding down the double-click button in the chat screen ([#4](https://github.com/taikun114/Mocolamma/issues/4))**
- **Fix issue where text selection could not be released in the chat screen on platforms other than macOS**

## 1.2.1
### Bug Fixes and Improvements
- **Fix issue where insecure HTTP connections were being blocked**
  - This has resolved the issue ([**#3**](https://github.com/taikun114/Mocolamma/issues/3)) where connections to remote servers using VPNs, etc., were being blocked.
- **Fix padding in the model inspector**
  - An issue where the top and bottom padding was too tight on platforms other than visionOS has been fixed.
- **Fix issue where model lists could not be sorted in macOS**

## 1.2.0
### New Features
- **Revamping the Markdown rendering engine**
  - The Markdown rendering engine for chat has been updated from [**MarkdownUI**](https://github.com/gonzalezreal/swift-markdown-ui) to [**Textual**](https://github.com/gonzalezreal/textual), incorporating improvements such as enhanced performance and syntax highlighting for code blocks, resulting in a more user-friendly experience.
  - As a result, Mocolamma now requires **iOS / iPadOS 18.0 or later, macOS 15.0 or later, visionOS 2.0 or later**. Please note that users on older operating systems will need to perform a software update.
- **Native support for visionOS**
  - Mocolamma now runs natively on visionOS devices. On visionOS, the inspector and message input screens feature optimized displays, and the interface uses a native SwiftUI design that blends seamlessly into the space, improving usability.
- **Support for attaching images in chat**
  - Models with image recognition capabilities now allow you to attach images to receive responses. For image file compatibility, attached images are converted to PNG format and large images are resized to a maximum of 2048px × 2048px before being sent to the API.
  - Attached images can be rearranged by dragging and dropping them, and you can also drag and drop image files from other apps to attach them.
- **Support for Ollama's image generation feature (beta)**
  - As Ollama's image generation feature is currently in beta, future Ollama updates may introduce changes to its functionality (Ollama API), potentially causing the image generation feature to stop working in Mocolamma.
  - A demo of the image generation feature is available. Select `demo-image:0b` as the image generation model and send any prompt. This will perform a simulation advancing 0.2 seconds per step, finally outputting a test image.
- **Support image model tag**
  - Image model tag is now correctly displayed in the model inspector.
- **Add Image Preview feature**
  - You can preview attached images or generated images in a large enlarged view.
- **Add an unload model button to the server screen inspector**
  - This allows you to quickly unload (free from memory) models currently loaded into Ollama server memory.
- **Add an icon customization feature to the add/edit server screen**
  - You can now change each server's icon to any SF Symbols icon of your choice. This only changes the icon displayed on the server screen, but if you have multiple servers configured, you can now identify them by their icons as well as their names.
- **Add a tag filter to the model screen**
  - This makes it easier to find models that support specific capabilities. You can filter by selecting the desired items from the filter button on the toolbar or by tapping the tags displayed in the model inspector.
- **Add an auto-follow scroll feature to the chat screen and image generation screen**
  - When scrolled to the bottom, messages will now automatically scroll downward to follow as they become longer, such as during stream responses. Auto-follow scrolling is disabled by scrolling slightly upward and re-enables when scrolling back to the bottom.
- **Add a Keep Alive option to the chat and image generation screen inspectors**
  - This allows you to specify how long the model is kept in memory on the Ollama server.
- **Add a Seed option to the chat and image generation screen inspectors**
  - This enables reproducible generation.
- **Add a share button below the message bubble in the chat screen and image generation screen**
  - You can now quickly share the generated results.
- **Add many advanced options to custom settings for chat**
  - For advanced users who want to tweak model behavior and conduct tests, added the following options: “Seed,” “Repeat Last N,” “Repeat Penalty,” “Num Predict,” “Top-k,” “Top-p,” and “Min-p.”
- **Add model download simulation in demo mode**
  - When demo mode is enabled, pressing the Add button with `demo-dl` or `demo-dl:0b` entered as the model name in the add model sheet will simulate a one-minute model download.
- **Add a feature to request reviews on the App Store (App Store version only)**
  - A screen asking users to review the app on the App Store will now appear periodically (but very infrequently).
  - Please rest assured that you can completely disable this feature in the app settings if you do not want the review screen to appear.
  - Please refer to the [**README**](/README.md#app-store-review-requests) for details on when the review request screen appears.
- **Add an App Store review button to the app information screen (App Store version only)**
  - You can open the App Store review page directly from the button added to the “Support Developer” section.
- **Add Arabic (`ar`), Chinese (Hong Kong) (`zh-HK`), Chinese (Simplified) (`zh-Hans`), Chinese (Traditional) (`zh-Hant`), Korean (`ko`), Russian (`ru`), Ukrainian (`uk`) localization by generative AI**
  - Since I have no knowledge of languages other than Japanese and English, translations may contain strange translations. If you notice any translations that need correction, I would appreciate it if you could send feedback on what to change and how!

### Bug Fixes and Improvements
- **Fix to display image model details correctly**
- **Fix issue where model screen could be refreshed during model download**
- **Fix issue where the chat screen would freeze while scrolling**
- **Fix issue where selecting a model while the Inspector is open does not focus the input field**
- **Fix issue where the scroll edge effect might not display correctly in chat and image generation screens on macOS**
  - Fixed an issue where, on macOS 26.0 or later, the scroll edge effect on the toolbar would display incorrectly (appearing as a hard style instead of a soft style) when showing the Chat or Image Generation screen, until the Inspector was opened/closed or the window size was changed. The beautiful blur effect now displays correctly.
- **Improve the Inspector button icon to display a more understandable one**
  - When the inspector is displayed in sheet style (e.g., on iPhone or iPad in compact view), the `info.circle` icon is now shown. When displayed in sidebar style, it remains unchanged.
- **Improve API timeout alert messages**
  - Added an advisory message about changing the timeout duration in settings when loading large models takes a long time.
- **Improve the appearance of swipe actions**
  - When swiping a list item on the server and model screens, the action displayed now always shows only the icon, regardless of the item's height.
- **Improve to prevent the add server and model sheet from closing when swiping down on iOS / iPadOS**
- **Improve the style of the Add and Complete buttons on the add server and model sheet on iOS / iPadOS 26**
  - The Complete button now uses the system native design, and the Add button now uses a design very close to the system native design.
- **Improve error handling when adding servers**
  - When a connection to a server fails, detailed error information is now displayed. Additionally, if a server with the same hostname is already registered, you can no longer register it.
- **Improve download progress display performance on the model screen**
- **Improve tag display in the model inspector**
- **Improve the model inspector to display a specific license when a license title is missing but the license body exists**
  - If the license body contains `MIT License`, it will display `MIT License` as the license title. If the license body contains both `Apache License` and `Version 2.0`, it will display `Apache License 2.0` as the license title.
- **Improve the appearance of model download progress display on iOS / iPadOS 26 and later**
  - On iOS / iPadOS 26.0 or later, the model download progress display is now positioned as a `safeAreaBar`, applying a beautiful, blended blur effect created by the scroll edge effect.
- **Improve to also show an alert when an error occurs during model download**
- **Improve to allow download even when the model name is entered in the `ollama` command format**
  - Model names can now be properly extracted and downloaded even when the model name is entered in the input field in a format such as `ollama run model_name` or `ollama pull model_name`.
- **Improve the model picker in the chat screen and image generation screen to display icons for models loaded into memory**
- **Improve the appearance of the model picker in the chat screen and image generation screen on iOS / iPadOS**
  - A divider line has been added between options, and model names are now displayed when the model picker is within an overflow menu.
- **Improve to show an error when selecting an image-only model in the chat screen**
- **Improve to display an action sheet requesting confirmation on the New Chat button**
- **Improve message bubble display on iOS / iPadOS when the display size is large**
  - When using an iPad with a wider window or a large-screen iPhone in landscape mode, message bubbles now have a slightly reduced maximum width just like on macOS, making them easier to read.
- **Improve to display a checkmark icon when message copying is successful**
- **Improve to display the language above the code block**
- **Improve the chat screen to enhance error handling**
- **Add an icon to the refresh button in the context menu for the number of running models in the server inspector**
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
