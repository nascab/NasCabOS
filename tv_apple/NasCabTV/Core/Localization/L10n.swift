import Foundation

enum L10n {
    // MARK: - Language

    static var systemLanguageCode: String {
        let preferred = (Locale.preferredLanguages.first ?? "en").lowercased()
        if preferred.hasPrefix("en") { return "en_US" }
        if preferred.hasPrefix("zh") { return "zh_CN" }
        if preferred.hasPrefix("ja") { return "ja_JP" }
        if preferred.hasPrefix("ko") { return "ko_KR" }
        if preferred.hasPrefix("es") { return "es_ES" }
        if preferred.hasPrefix("pt") { return "pt_BR" }
        if preferred.hasPrefix("fr") { return "fr_FR" }
        if preferred.hasPrefix("de") { return "de_DE" }
        if preferred.hasPrefix("ru") { return "ru_RU" }
        if preferred.hasPrefix("id") { return "id_ID" }
        if preferred.hasPrefix("vi") { return "vi_VN" }
        if preferred.hasPrefix("th") { return "th_TH" }
        if preferred.hasPrefix("ar") { return "ar_SA" }
        return "en_US"
    }

    static var currentLanguageCode: String {
        let stored = UserDefaults.standard.string(forKey: "selected_language") ?? ""
        if stored.isEmpty { return systemLanguageCode }
        return stored
    }

    static func setLanguage(_ code: String) {
        UserDefaults.standard.set(code, forKey: "selected_language")
    }

    static let supportedLocales: [(code: String, name: String)] = [
        // Language order: en-US, zh-CN, ja-JP, ko-KR, es-ES, pt-BR, fr-FR, de-DE, ru-RU, id-ID, vi-VN, th-TH, ar-SA
        ("en_US", "English"),
        ("zh_CN", "简体中文"),
        ("ja_JP", "日本語"),
        ("ko_KR", "한국어"),
        ("es_ES", "Español"),
        ("pt_BR", "Português (Brasil)"),
        ("fr_FR", "Français"),
        ("de_DE", "Deutsch"),
        ("ru_RU", "Русский"),
        ("id_ID", "Bahasa Indonesia"),
        ("vi_VN", "Tiếng Việt"),
        ("th_TH", "ไทย"),
        ("ar_SA", "العربية"),
    ]

    private static func dict(for code: String) -> [String: String] {
        switch code {
        case "en_US", "en-US": return L10n_enUS.dict
        case "zh_CN", "zh-CN": return L10n_zhCN.dict
        case "ja_JP", "ja-JP": return L10n_jaJP.dict
        case "ko_KR", "ko-KR": return L10n_koKR.dict
        case "es_ES", "es-ES": return L10n_esES.dict
        case "pt_BR", "pt-BR": return L10n_ptBR.dict
        case "fr_FR", "fr-FR": return L10n_frFR.dict
        case "de_DE", "de-DE": return L10n_deDE.dict
        case "ru_RU", "ru-RU": return L10n_ruRU.dict
        case "id_ID", "id-ID": return L10n_idID.dict
        case "vi_VN", "vi-VN": return L10n_viVN.dict
        case "th_TH", "th-TH": return L10n_thTH.dict
        case "ar_SA", "ar-SA": return L10n_arSA.dict
        default:
            if code.hasPrefix("zh") { return L10n_zhCN.dict }
            return L10n_enUS.dict
        }
    }

    static func tr(_ key: String) -> String {
        let lang = currentLanguageCode
        return dict(for: lang)[key] ?? L10n_enUS.dict[key] ?? key
    }

    static func tr(_ key: String, params: [String: String]) -> String {
        var result = tr(key)
        for (k, v) in params {
            result = result.replacingOccurrences(of: "@\(k)", with: v)
        }
        return result
    }

    // MARK: - Common

    static var ok: String { tr("ok") }
    static var cancel: String { tr("cancel") }
    static var delete: String { tr("delete") }
    static var edit: String { tr("edit") }
    static var save: String { tr("save") }
    static var error: String { tr("error") }
    static var loading: String { tr("loading") }
    static var username: String { tr("username") }
    static var password: String { tr("password") }
    static var setting: String { tr("setting") }
    static var language: String { tr("language") }
    static var login: String { tr("login") }
    static var clear: String { tr("clear") }

    // MARK: - Network

    static var networkFailure: String { tr("network_failure") }
    static var serviceSessionExpired: String { tr("service_nascab_session_expired") }

    // MARK: - Server List

    static var serverListTitle: String { tr("server_listTitle") }
    static var serverSaved: String { tr("server_saved") }
    static var serverScanned: String { tr("server_scanned") }
    static var serverAdd: String { tr("server_add") }
    static var serverLocalServer: String { tr("server_localServer") }
    static var serverConnectFail: String { tr("server_connect_fail") }
    static var serverInit: String { tr("server_init") }
    static var serverInitContent: String { tr("server_init_content") }
    static var serverConnecting: String { tr("server_connecting") }
    static var serverDeleteConfirm: String { tr("server_delete_confirm_message") }

    // MARK: - Server Add

    static var serverAddTitle: String { tr("server_add_title") }
    static var serverAddUrl: String { tr("server_add_url") }
    static var serverAddUrlHint: String { tr("server_add_url_hint") }
    static var serverAddName: String { tr("server_add_name") }
    static var serverAddNameHint: String { tr("server_add_name_hint") }
    static var serverAddUsername: String { tr("server_add_username") }
    static var serverAddUsernameHint: String { tr("server_add_username_hint") }
    static var serverAddPassword: String { tr("server_add_password") }
    static var serverAddPasswordHint: String { tr("server_add_password_hint") }
    static var serverAddRequirePasswordEveryLogin: String { tr("server_add_require_password_every_login") }
    static var serverRequirePasswordPromptMessage: String { tr("server_require_password_prompt_message") }

    // MARK: - Pair Code

    static var serverAddByPairCodeTitle: String { tr("server_add_by_pair_code_title") }
    static var serverAddByPairCodeContent: String { tr("server_add_by_pair_code_content") }
    static var serverPairCodePlaceholder: String { tr("server_pair_code_placeholder") }
    static var serverPairCodeEmpty: String { tr("server_pair_code_empty") }
    static var serverPairCodeInvalid: String { tr("server_pair_code_invalid") }
    static var serverPairCodeDisplay: String { tr("server_pair_code_display") }
    static var serverEditPairCodeTitle: String { tr("server_edit_pair_code_title") }
    static var serverEditPairCodeContent: String { tr("server_edit_pair_code_content") }
    static var serverMenuEditPairCode: String { tr("server_menu_edit_pair_code") }
    static var serverPairCodeHowTitle: String { tr("server_pair_code_how_title") }
    static var serverPairCodeHowContent: String { tr("server_pair_code_how_content") }
    static var serverPairCodeHelpDetail: String { tr("server_pair_code_help_detail") }
    static var serverP2pSessionInvalid: String { tr("server_p2p_session_invalid") }

    // MARK: - Auth

    static var authLoginLoading: String { tr("auth_login_loading") }
    static var authLoginFailure: String { tr("auth_login_failure") }
    static var authTokenRefreshFailure: String { tr("auth_token_refresh_failure") }
    static var authPasswordError: String { tr("auth_password_error") }
    static var authPasswordErrorMessage: String { tr("auth_password_error_message") }
    static var authPasswordHint: String { tr("auth_password_hint") }
    static var authForgotPassword: String { tr("auth_forgot_password") }
    static var adminCreateFailure: String { tr("admin_create_failure") }
    static var auth2faTitle: String { tr("auth_2fa_title") }
    static var auth2faCodeLabel: String { tr("auth_2fa_code_label") }
    static var authLogoutSuccess: String { tr("auth_logout_success") }

    // MARK: - Home

    static var homeAppTitle: String { tr("home_app_title") }
    static var homeMediaLibrary: String { tr("home_media_library") }
    static var homePhotoManagement: String { tr("home_photo_management") }
    static var homeMusicLibrary: String { tr("home_music_library") }
    static var homeFileManagement: String { tr("home_file_management") }
    static var homeLogout: String { tr("home_logout") }
    static var homeLogoutConfirmTitle: String { tr("home_logout_confirm_title") }
    static var homeLogoutConfirmMessage: String { tr("home_logout_confirm_message") }

    // MARK: - Media Library / Video

    static var videoTabMovie: String { tr("video_home_type_movie") }
    static var videoTabTv: String { tr("video_home_type_tv") }
    static var videoTabRecentPlay: String { tr("video_tab_recent_play") }
    static var videoTabFavorite: String { tr("video_tab_favorite") }
    static var videoTabCustomAlbum: String { tr("video_custom_album_title") }
    static var videoTabSmartAlbum: String { tr("video_smart_album_title") }
    static var videoTabCollection: String { tr("video_collection_title") }

    static var videoSearchHint: String { tr("video_list_search_hint") }
    static var videoFilterYears: String { tr("video_list_filter_years") }
    static var videoFilterGenres: String { tr("video_list_filter_genres") }
    static var videoFilterRegions: String { tr("video_list_filter_regions") }

    static var videoSortTitle: String { tr("sort") }
    static var videoFilterTitle: String { tr("filter") }
    static var videoSourceTitle: String { tr("source") }

    static var allLabel: String { tr("all") }
    static var noData: String { tr("no_data") }
    static var reset: String { tr("reset") }

    static var videoSortFavoriteTimeDesc: String { tr("video_list_sort_favorite_time_desc") }
    static var videoSortFavoriteTimeAsc: String { tr("video_list_sort_favorite_time_asc") }
    static var videoSortViewTimeDesc: String { tr("video_list_sort_view_time_desc") }
    static var videoSortViewTimeAsc: String { tr("video_list_sort_view_time_asc") }
    static var videoSortYearDesc: String { tr("video_list_sort_year_desc") }
    static var videoSortYearAsc: String { tr("video_list_sort_year_asc") }
    static var videoSortScoreDesc: String { tr("video_list_sort_score_desc") }
    static var videoSortScoreAsc: String { tr("video_list_sort_score_asc") }
    static var videoSortCreateTimeDesc: String { tr("create_time_desc") }
    static var videoSortCreateTimeAsc: String { tr("create_time_asc") }
    static var videoSortNameAsc: String { tr("name_asc") }
    static var videoSortNameDesc: String { tr("name_desc") }

    static var videoComingSoonTitle: String { tr("video_tv_coming_soon_title") }
    static var videoComingSoonDescription: String { tr("video_tv_coming_soon_desc") }

    // MARK: - Photo Timeline

    static var photoTimelineTabTimeline: String { tr("photo_timeline_tab_timeline") }
    static var photoTimelineTabYear: String { tr("photo_timeline_tab_year") }
    static var photoTimelineTabToday: String { tr("photo_timeline_tab_today") }
    static var photoTimelineSearchHint: String { tr("photo_timeline_search_hint") }
    static var photoTimelineSortTitle: String { tr("photo_timeline_sort_title") }
    static var photoTimelineSortDesc: String { tr("photo_timeline_sort_desc") }
    static var photoTimelineSortAsc: String { tr("photo_timeline_sort_asc") }
    static var photoTimelineFilterFileType: String { tr("photo_timeline_filter_file_type") }
    static var photoTimelineFilterSource: String { tr("photo_timeline_filter_source") }
    static var photoTimelineFilterMonth: String { tr("photo_timeline_filter_month") }
    static var photoTimelineAllTime: String { tr("photo_timeline_all_time") }
    static var photoTimelineAllSource: String { tr("photo_timeline_all_source") }
    static var photoTimelineYearsTitle: String { tr("photo_timeline_years_title") }
    static var photoTimelinePhotosCount: (Int) -> String { { tr("photo_timeline_photos_count", params: ["count": "\($0)"]) } }
    static var photoTabAlbum: String { tr("photo_tab_album") }
    static var photoTabSmartAlbum: String { tr("photo_tab_smart_album") }
    static var photoTabCollection: String { tr("photo_tab_collection") }
    static var photoAlbumSearchHint: String { tr("photo_album_search_hint") }
    static var timelinePhotos: String { tr("timeline_photos") }
    static var timelineVideos: String { tr("timeline_videos") }
    static var timelineLivePhotos: String { tr("timeline_live_photos") }

    // MARK: - Video Detail

    static var videoDetailPageTitle: String { tr("video_detail_page_title") }
    static var videoDetailStoryline: String { tr("video_detail_storyline") }
    static var videoDetailStorylineEmpty: String { tr("video_detail_storyline_empty") }
    static var videoDetailPeople: String { tr("video_detail_people") }
    static var videoDetailDirectors: String { tr("video_detail_directors") }
    static var videoDetailActors: String { tr("video_detail_actors") }
    static var videoDetailGenres: String { tr("video_detail_genres") }
    static var videoDetailRegions: String { tr("video_detail_regions") }
    static var videoDetailSeasonListTitle: String { tr("video_detail_season_list_title") }
    static var videoDetailEpisodes: String { tr("video_detail_episodes") }
    static var videoDetailEpisodesTotal: String { tr("video_detail_episodes_total") }
    static var videoDetailEpisodeNo: String { tr("video_detail_episode_no") }
    static var videoDetailSortAsc: String { tr("video_detail_sort_asc") }
    static var videoDetailSortDesc: String { tr("video_detail_sort_desc") }
    static var videoDetailViewIntro: String { tr("video_detail_view_intro") }
    static var videoDetailWatched: String { tr("video_detail_watched") }
    static var videoDetailWatchedEpisode: String { tr("video_detail_watched_episode") }
    static var videoDetailContinuePlay: String { tr("video_detail_continue_play") }
    static var videoDetailRefresh: String { tr("video_detail_refresh") }
    static var videoDetailOperation: String { tr("video_detail_operation") }
    static var videoDetailScanChanges: String { tr("video_item_scan_changes") }
    static var videoDetailScanSuccess: String { tr("video_detail_scan_success") }
    static var videoDetailDuration: String { tr("video_detail_duration") }
    static var videoDetailFileSize: String { tr("video_detail_file_size") }
    static var playLabel: String { tr("play") }
    static var favoriteAdd: String { tr("folder_add_favorite") }
    static var favoriteRemove: String { tr("unfavorite") }

    // MARK: - Dev Connect Mode (开发模式连接通道)

    static var serverConnectChannel: String { tr("server_connect_channel") }
    static var devConnectModeDirect: String { tr("dev_connect_mode_direct") }
    static var devConnectModeP2pDirect: String { tr("dev_connect_mode_p2p_direct") }
    static var devConnectModeP2pRelay: String { tr("dev_connect_mode_p2p_relay") }
    static var connectivityStatus: String { tr("connectivity_status") }
    static var connectivityOk: String { tr("connectivity_ok") }
    static var connectivityFail: String { tr("connectivity_fail") }
    static var connectivityChecking: String { tr("connectivity_checking") }

    // MARK: - Music Library

    static var musicTabSongs: String { tr("music_tab_songs") }
    static var musicTabAlbums: String { tr("music_tab_albums") }
    static var musicTabArtists: String { tr("music_tab_artists") }
    static var musicTabPlaylists: String { tr("music_tab_playlists") }
    static var musicTabCollections: String { tr("music_tab_collections") }
    static var musicSearchHint: String { tr("music_search_hint") }
    static var musicSearchTitleHint: String { tr("music_search_title_hint") }
    static var musicSearchAlbumHint: String { tr("music_search_album_hint") }
    static var musicSearchArtistHint: String { tr("music_search_artist_hint") }
    static var musicItemCount: (Int) -> String { { tr("music_item_count", params: ["count": "\($0)"]) } }
    static var musicNowPlaying: String { tr("music_now_playing") }
    static var musicNoTrack: String { tr("music_no_track") }
    static var musicNoLyrics: String { tr("music_no_lyrics") }
    static var musicLyricSearchInvalid: String { tr("music_lyric_search_invalid") }
    static var musicSearchLyric: String { tr("music_search_lyric") }
    static var search: String { tr("search") }
}
