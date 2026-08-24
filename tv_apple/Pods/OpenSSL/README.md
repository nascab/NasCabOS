# FFmpegKit ![GitHub release](https://img.shields.io/badge/release-v5.1-blue.svg) ![CocoaPods](https://img.shields.io/cocoapods/v/ffmpeg-kit-ios-min) 

`FFmpegKit` is a collection of tools to use `FFmpeg` in `iOS`, `macOS`, `tvOS`, `xrOS`, `visionOS`  applications.

It includes scripts to build `FFmpeg` native libraries, three executable product `ffplay`/`ffmpeg`/`ffprobe` in macos

### Features
- Scripts to build FFmpeg native libraries
- three executable product `ffplay`/`ffmpeg`/`ffprobe` in macos
- Supports native platforms: `iOS`, `macOS`, `tvOS`, `visionOS`
- Build MPV

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/kingslay/FFmpegKit.git", .branch("main"))
]
```

## Build Scripts
```bash
swift package --disable-sandbox BuildFFmpeg

```

## Run ffmpeg ffprobe in code(Features of the lgpl version)

```swift
var arguments = ["ffmpeg", "-i", "file1.mp4", "-c:v", "mpeg4", "file2.mp4"]
var argv = arguments.map {
    UnsafeMutablePointer(mutating: ($0 as NSString).utf8String)
}
ffmpeg_execute(Int32(arguments.count), &argv)

arguments = ["ffprobe", "-h"]
argv = arguments.map {
    UnsafeMutablePointer(mutating: ($0 as NSString).utf8String)
}
ffprobe_execute(Int32(arguments.count), &argv)
```

## Executable product
```bash
swift run ffplay
swift run ffmpeg
swift run ffprobe
```

## Help 
```bash
swift package BuildFFmpeg -h
```

```bash
        Usage: swift package BuildFFmpeg [OPTION]...
        Default Build: swift package --disable-sandbox BuildFFmpeg enable-libshaderc enable-vulkan enable-lcms2 enable-libdav1d enable-libplacebo enable-gmp enable-nettle enable-gnutls enbale-readline enable-libsmbclient enable-libsrt enable-libzvbi enable-libfreetype enable-libfribidi enable-libharfbuzz enable-libass enable-FFmpeg enable-libmpv

        Options:
            h, -h, --help       display this help and exit
            notRecompile        If there is a library, then there is no need to recompile
            gitCloneAll         git clone not add --depth 1
            enable-debug,       build ffmpeg with debug information
            platforms=xros      deployment platform: macos,ios,isimulator,tvos,tvsimulator,xros,xrsimulator,maccatalyst,watchos,watchsimulator
            --xx                add ffmpeg Configuers

        Libraries:
            enable-libshaderc   build with libshaderc
            enable-vulkan       depend enable-libshaderc
            enable-libdav1d     build with libdav1d
            enable-libplacebo   depend enable-libshaderc enable-vulkan enable-lcms2 enable-libdav1d
            enable-nettle       depend enable-gmp
            enable-gnutls       depend enable-gmp enable-nettle
            enable-libsmbclient depend enable-gmp enable-nettle enable-gnutls enbale-readline
            enable-libsrt       depend enable-openssl or enable-gnutls
            enable-libfreetype  build with libfreetype
            enable-libharfbuzz  depend enable-libfreetype
            enable-libass       depend enable-libfreetype enable-libfribidi enable-libharfbuzz
            enable-libzvbi      build with libzvbi
            enable-FFmpeg       build with FFmpeg
            enable-libmpv       depend enable-libass enable-FFmpeg
            enable-openssl      build with openssl [no]
```
## License
Because FFmpegKit includes libsmbclient by default, and the GPL is turned on when compiling FFmepg and mpv. So FFmpegKit uses the GPL license.
 
Additionally, there is a paid version that adopts the LGPL license (contact us).  
