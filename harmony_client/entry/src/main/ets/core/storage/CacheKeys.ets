export class CacheKeys {
  static readonly USER_INFO: string = 'user_info';
  static readonly USER_APPS: string = 'user_apps';
  static readonly USER_WALLPAPER: string = 'user_wallpaper';
  static readonly TOKEN: string = 'auth_token';
  static readonly REFRESH_TOKEN: string = 'refresh_token';
  static readonly P2P_LAST_PAIR_CODE: string = 'p2p_last_pair_code';
  static readonly DEVICE_FINGERPRINT_SEED: string = 'device_fingerprint_seed';
  static readonly VIDEO_PLAYER_DEVICE_ID: string = 'video_player_device_id';
  static readonly SAVED_SERVERS: string = 'saved_servers';
  static readonly LAST_SELECTED_SERVER: string = 'last_selected_server';
  static readonly AUTH_BASE_URL: string = 'auth_baseUrl';
  static readonly AUTH_SERVER_ID: string = 'auth_serverId';
  static readonly AUTH_ACCESS_TOKEN: string = 'auth_accessToken';
  static readonly AUTH_REFRESH_TOKEN: string = 'auth_refreshToken';
  static readonly AUTH_EXPIRES_IN: string = 'auth_expiresIn';
  static readonly AUTH_SHELL_SUPPORTED: string = 'auth_shellSupported';
  static readonly AUTH_SERVER_VERSION: string = 'auth_serverVersion';
  static readonly PRIVACY_CONSENT_ACCEPTED: string = 'privacy_consent_accepted';
  static readonly SELECTED_LANGUAGE: string = 'selected_language';
  static readonly THEME_MODE: string = 'theme_mode';
  static readonly PHOTO_PREVIEW_WIFI_ORIGINAL: string = 'photo_preview_wifi_original';
  // ===== music 模块（对齐 Flutter CacheKeys） =====
  static readonly MUSIC_LIST_SELECTED_PATHS: string = 'musicListSelectedPaths';
  static readonly MUSIC_SUB_LIST_SORT_BY: string = 'musicSubListSortBy';
  static readonly MUSIC_SUB_LIST_SORT_ORDER: string = 'musicSubListSortOrder';
  static readonly MUSIC_VOLUME: string = 'musicVolume';
  static readonly MUSIC_VOLUME_BEFORE_MUTE: string = 'musicVolumeBeforeMute';
  static readonly MUSIC_LOOP_MODE_INDEX: string = 'musicLoopModeIndex';
  static readonly MUSIC_AUDIO_CACHE_ENABLED: string = 'musicAudioCacheEnabled';
  static readonly MUSIC_AUDIO_CACHE_MAX_ITEMS: string = 'musicAudioCacheMaxItems';
  static readonly MUSIC_FULL_SCREEN_SHOW_LYRICS: string = 'musicFullScreenShowLyrics';
  static readonly MUSIC_DISC_STYLE_INDEX: string = 'musicDiscStyleIndex';
  /** 列表排序持久化（带 scope 前缀：series_{type}|favorite|list_{id}|collection_{id}|lib_{type}|lib_all） */
  static readonly MUSIC_LIST_SORT_BY: string = 'musicListSortBy';
  static readonly MUSIC_LIST_SORT_ORDER: string = 'musicListSortOrder';
  // ===== book 模块（对齐 Flutter CacheKeys） =====
  static readonly BOOK_LIST_SORT_BY: string = 'bookListSortBy';
  static readonly BOOK_LIST_SORT_ORDER: string = 'bookListSortOrder';
  static readonly BOOK_LIST_SELECTED_PATHS: string = 'bookListSelectedPaths';
  static readonly BOOK_LIST_COVER_SCALE: string = 'book_list_cover_scale';
  static readonly BOOK_CUSTOM_LIST_SORT_FIELD: string = 'book_custom_list_sort_field';
  static readonly BOOK_CUSTOM_LIST_SORT_ORDER: string = 'book_custom_list_sort_order';
  static readonly BOOK_COLLECTION_SORT_FIELD: string = 'book_collection_sort_field';
  static readonly BOOK_COLLECTION_SORT_ORDER: string = 'book_collection_sort_order';
}
