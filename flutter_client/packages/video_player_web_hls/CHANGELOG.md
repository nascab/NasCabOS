## 1.3.0
* Bump web to ">=1.0.0 <2.0.0" 
* Bump min sdk to 3.4.0 and min flutter to 3.22.0
## 1.2.2
* Fallback to hlsjs when native player fails
* Fixed some m3u8 files that could not be played normally
## 1.2.1
* Fixes web options not being exposed by the library
## 1.2.0
* Migrates package and tests to `package:web``.
* Fixes infinite event loop caused by `seekTo` when the video ends.
* Add set options support
## 1.1.1
* Fixed video buffering crashing on slow networks (#53)
* Updated js dependency
## 1.1.0
* Updated http dependency
## 1.0.0+3
* Fix video_player_platform_interface version
## 1.0.0+2
* Added inline attribute to video player
## 1.0.0+1
* Fixed correct data not passed in video player events
## 1.0.0
* Supports null safety
## 0.1.11+6
* Added fix for infinite videos
## 0.1.11+5
* Fixed video not playing on ios devices
## 0.1.11+4
* Made linter happy
* Fixed height and width of platform view is not set warning
* Not sending error event if there is a non fatal event from hls.js
* Removed ios and macos folders*
## 0.1.11+3
* Improved m3u8 detection
* Fix subsequent xhr requests withCredentials
## 0.1.11+2
* Fix Changelog
## 0.1.11
* Fixed hls stream loading even after dispose is called
## 0.1.10
* Added Headers Support
## 0.1.9
* Migrated to Null Safety
## 0.1.8
* Fixed playback speed( Don't use 0.1.7)
## 0.1.7
* Added option to set the video playback speed on the video controller.
## 0.1.6
* Fixed video does not play on ios Safari.
## 0.1.5
* Removed android & web folder and changed ios folder
## 0.1.4
* Handled some errors
## 0.1.3
* Changed ends with to contains
## 0.1.2
* Added example
## 0.1.1
* Updated Readme
## 0.1.0
* Initial release

