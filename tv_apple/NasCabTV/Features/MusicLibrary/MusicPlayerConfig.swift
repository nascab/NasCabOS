import Foundation

/// 音乐播放器配置：是否使用 VLC 本地解码（true）或 AVPlayer + 服务端转码（false）
enum MusicPlayerConfig {
    private static let key = "music_player_use_vlc"

    /// true: 使用 TVVLCKit 本地解码原始文件，起播快
    /// false: 使用 AVPlayer 播放服务端转码 MP3，格式兼容依赖服务端
    static var useVLCForMusic: Bool = true;
}
