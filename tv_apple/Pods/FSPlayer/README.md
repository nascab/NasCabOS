<div align="center">
<!--   <img alt="fsplayer" src="./primary-wide.png"> -->
  <h1>FSPlayer</h1>
  <img src="https://github.com/debugly/fsplayer/actions/workflows/apple.yml/badge.svg">
  <img src="https://img.shields.io/badge/Platform-%20iOS%20macOS%20tvOS%20-blue.svg">
</div>

[![Stargazers repo roster for @debugly/fsplayer](https://reporoster.com/stars/debugly/fsplayer)](https://github.com/debugly/fsplayer/stargazers)

## 功能&特点

- [x] FFmpeg 7.1.1
- [x] 支持透传 FFmpeg option 参数
- [x] 支持获取下载速度
- [x] 支持获取预加载进度
- [x] 获取基本信息（音频：采样率、声道数、时长等，视频：宽、高、fps、时长等）
- [x] 支持获取首帧解码时间、渲染时间
- [x] 支持 file、http、https、udp、rtmp、rtp、rtsp、bluray、smb、ftp 等协议
- [x] 支持设置 HTTP 超时、错误重试、UA、Cookie、Referer、Origin 等，如果是 m3u8 支持透传给 ts 请求
- [x] 支持 HLS 直播或者点播
- [x] 支持 AV1、uavs3 解码器
- [x] 支持播放音频时显示内置封面
- [x] 支持播放图片
- [x] 支持精准 seek
- [x] 支持软硬解设置
- [x] 支持多实例播放
- [x] 支持播放完成（EOF）后，重新seek继续播放
- [x] 优化了 file 协议 seek 后起播慢问题
- [x] 音视频加密播放
- [x] 强大的字幕功能
  - 文本字幕(srt/vtt/ass)
  - 图形字幕(dvbsub/dvdsub/pgssub/idx+sub)
  - 同时支持内嵌和外挂
  - 支持设置字幕延迟
  - 支持 ASS 字幕的特效
  - 支持设置文本字幕的样式
- [x] 支持循环播放
- [x] 支持切换音轨
- [x] 支持设置音轨延迟
- [x] 支持随时截屏（jpg、png、tiff）
- [x] 支持设置视频显示比例
- [x] 支持设置旋转角度设置（0,90,180,270）
- [x] 支持设置视频镜像模式
- [x] 支持设置视频背景颜色（默认黑色）
- [x] 支持设置画面饱和度、亮度、对比度
- [x] 支持将画面同时渲染到多个 View 上
- [x] 支持实时获取音频 PCM 数据
- [x] 支持自定义渲染 View
- [x] 支持 4K/HDR/HDR10/HDR10+/Dolby Vision，不支持 Dolby Vision P5
- [x] 智能识别 iso (blury、dvd、普通视频)
- [x] mpegts 视频快进不花屏
- [x] 支持网络协议播放 iso 镜像和 BDMV 文件夹
- [x] 双声道音频可强制指定声道播放
- [x] 获取当前显示的视频帧
- [x] 录制视频
- [x] 支持播放webp动画
- [x] 支持自定义音频渲染器
- [x] 缓冲进度通知
- [x] 支持异步销毁，即使不调用 shutdown 也能正常销毁
- [x] 支持设定播放器不管理 AudioSession 状态
- [x] 优化播放器 View 旋转时的动画效果

最近支持

调研中

- [ ] AV1 可以硬解，但个别视频会崩溃
- [ ] 直播回放
- [ ] 音视频可变速变调
- [ ] 支持透明视频
- [ ] 画中画
- [ ] Dolby Vision P5

如果之前使用的 ijkplayer，可以轻松迁移到 fsplayer，请参考 [迁移指南](./doc/migration.md) 。

## 构建环境

- macOS Sequoia(15.5)
- Xcode Version 16.4 (16F6)

| 最低支持平台  | 架构                                     |
| ----------- | --------------------------------------- |
| iOS 11.0    | arm64、arm64_simulator、x86_64_simulator |
| macOS 10.11 | arm64、x86_64                            |
| tvOS 12.0   | arm64、arm64_simulator、x86_64_simulator |

## 更新记录

- [CHANGELOG.md](CHANGELOG.md)

## 集成

FSPlayer 完全免费，使用 [LGPLv3](./COPYING.LGPLv3) 许可协议发布，感觉不错可以 [请作者喝咖啡](./Donate.md) 。

- 通过 Swift Package Manger 集成: [FSPlayer-SPM.git](https://github.com/debugly/FSPlayer-SPM.git)

- 通过 Cocoapods 集成:

```
pod "FSPlayer", :podspec => 'https://github.com/debugly/fsplayer/releases/download/1.0.4/FSPlayer.spec.json'
```

### 调用

```
FSOptions *options = [FSOptions optionsByDefault];
//创建播放器
self.player = [[FSPlayer alloc] initWithContent:url options:options];
//创建播放器渲染view
NSView <FSVideoRenderingProtocol>*playerView = self.player.view;
playerView.frame = self.playerContainer.bounds;
playerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
[self.playerContainer addSubview:playerView positioned:NSWindowBelow relativeTo:self.playerCtrlPanel];
//加载完毕自动播放
self.player.shouldAutoplay = YES;
//异步加载
[self.player prepareToPlay];
```

更详细的使用[说明文档](https://fsplayer.debugly.cn/manuals/getting-started.html)

## 编译步骤

源码完全开放，可以自己编译 Framework：

```bash
# Build iOS Framework
./FFToolChain/main.sh install -p ios -l 'ass ffmpeg'
./examples/ios/build-framework.sh
# Build macOS Framework
./FFToolChain/main.sh install -p macos -l 'ass ffmpeg'
./examples/macos/build-framework.sh
# Build tvOS Framework
./FFToolChain/main.sh install -p tvos -l 'ass ffmpeg'
./examples/tvos/build-framework.sh
```

## FSPlayer-Pro

在 FSPlayer 的基础上提供了更加强劲的功能，以动态库的形式提供。

- HLS 点播边播边缓存，已经缓存的 seek 回去播放不再耗流量，起播速度更快
- 可无缝切换音轨，避免了普通方式切换后需要seek到当前位置，播放器重新加载短暂没有声音并且黑屏的问题
- 播放网络 iso 镜像和 BDMV 文件夹时，首帧起播速度提升x倍，Seek 后首帧起播速度提升x倍

邮件联系：[debugly@icloud.com](mailto:debugly@icloud.com)
