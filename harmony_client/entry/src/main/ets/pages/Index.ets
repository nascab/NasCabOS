import { AppRouter } from '../router/AppRouter';
import { AppEventBus } from '../common/AppEventBus';
import { DialogUtil } from '../common/DialogUtil';
import { SheetUtil } from '../common/SheetUtil';
import { ServerListPage } from '../auth/views/ServerListPage';
import { ServerListViewModel } from '../auth/views/server_list/ServerListViewModel';
import { LoginPage } from '../auth/views/login/LoginPage';
import { RecoverPasswordView } from '../auth/views/recover_password/RecoverPasswordView';
import { ServerAddPage } from '../auth/views/server_add/ServerAddPage';
import { HomePage } from './HomePage';
import { SettingsPage } from '../settings/SettingsPage';
import { LegalPage, LegalPageParam } from './LegalPage';
import { FileBrowserPage, FileBrowserParam } from '../files/views/FileBrowserPage';
import { UploadCenterPage, UploadCenterParam } from '../transfer/views/UploadCenterPage';
import { PhotoTimelinePage, PhotoTimelinePageParam } from '../photo/views/timeline/PhotoTimelinePage';
import { PhotoMainPage, PhotoMainPageParam } from '../photo/views/main/PhotoMainPage';
import { PhotoTrashPage, PhotoTrashPageParam } from '../photo/views/trash/PhotoTrashPage';
import { PhotoAlbumListPage, PhotoAlbumListPageParam } from '../photo/views/album/PhotoAlbumListPage';
import {
  PhotoSmartAlbumListPage, PhotoSmartAlbumListPageParam
} from '../photo/views/smartalbum/PhotoSmartAlbumListPage';
import {
  PhotoCollectionListPage, PhotoCollectionListPageParam
} from '../photo/views/collection/PhotoCollectionListPage';
import { PhotoAiFacesPage, PhotoAiFacesPageParam } from '../photo/views/ai/PhotoAiFacesPage';
import { PhotoAiScenesPage, PhotoAiScenesPageParam } from '../photo/views/ai/PhotoAiScenesPage';
import { PhotoAiSimilarPage, PhotoAiSimilarPageParam } from '../photo/views/ai/PhotoAiSimilarPage';
import { PhotoSettingsPage, PhotoSettingsPageParam } from '../photo/views/settings/PhotoSettingsPage';
import { VideoMainPage, VideoMainPageParam } from '../video/views/VideoMainPage';
import { VideoListPage } from '../video/views/VideoListPage';
import { VideoAlbumVideosPage } from '../video/views/VideoAlbumVideosPage';
import { VideoSettingsPage } from '../video/views/VideoSettingsPage';
import { VideoPlayerPage } from '../video_player/views/VideoPlayerPage';
import { VideoPlayerPageParam } from '../video_player/router/PlayerRoutes';
import { VideoDetailPage } from '../video/views/VideoDetailPage';
import { VideoAlbumListPage } from '../video/views/VideoAlbumListPage';
import { VideoSmartAlbumListPage } from '../video/views/VideoSmartAlbumListPage';
import { VideoCollectionListPage } from '../video/views/VideoCollectionListPage';
import {
  VideoAlbumVideosPageParam, VideoDetailPageParam, VideoListPageParam,
  VideoAlbumListPageParam, VideoSmartAlbumListPageParam, VideoCollectionListPageParam
} from '../video/router/VideoRoutes';
import { GalleryPage, PanoramaPageParam } from '../gallery/views/GalleryPage';
import { PanoramaPage } from '../gallery/views/PanoramaPage';
import { GalleryPageParam } from '../gallery/models/GalleryModels';
import { MusicMainPage } from '../modules/music/views/MusicMainPage';
import { MusicMainPageParam } from '../modules/music/router/MusicRoutes';
import { MusicSubListPage } from '../modules/music/views/MusicSubListPage';
import { MusicSubListPageParam } from '../modules/music/router/MusicRoutes';
import { MusicSubListPayload } from '../modules/music/controllers/MusicSubListController';
import { MusicPlayerPage, MusicPlayerPageParam } from '../modules/music/views/MusicPlayerPage';
import { MusicSettingsPage } from '../modules/music/views/MusicSettingsPage';
import { NavUtil } from '../common/NavUtil';

@Entry
@Component
struct Index {
  @State pageStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    // 初始化全局弹窗工具（DialogUtil 依赖 UIContext）
    DialogUtil.init(this.getUIContext());
    SheetUtil.init(this.getUIContext());
    // 初始化全局导航栈（NavUtil 供无参视图与弹层回调推入路由页）
    NavUtil.init(this.pageStack);
    AppEventBus.onAuthSessionExpired(() => {
      this.pageStack.clear();
    });
  }

  @Builder
  pageMap(name: string, param: object) {
    if (name === AppRouter.HOME) {
      HomePageBuilder(
        () => {
          this.pageStack.clear();
        },
        (name: string, param?: object) => {
          this.pageStack.pushPathByName(name, param ?? new Object());
        }
      )
    } else if (name === AppRouter.LOGIN) {
      LoginPageBuilder(() => {
        this.pageStack.clear();
      })
    } else if (name === AppRouter.RECOVER) {
      RecoverPageBuilder(() => {
        this.pageStack.pop();
      })
    } else if (name === AppRouter.SERVER_ADD) {
      ServerAddPageBuilder(
        param instanceof ServerListViewModel ? param : new ServerListViewModel(),
        () => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.SETTINGS) {
      SettingsPageBuilder(
        () => {
          this.pageStack.pop();
        },
        (legalParam: LegalPageParam) => {
          this.pageStack.pushPathByName(AppRouter.LEGAL, legalParam);
        }
      )
    } else if (name === AppRouter.FILES) {
      FileBrowserPageBuilder(
        param instanceof FileBrowserParam ? param : new FileBrowserParam(),
        (n: string, p?: object): void => {
          this.pageStack.pushPathByName(n, p ?? new Object());
        },
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.UPLOAD_CENTER) {
      UploadCenterPageBuilder(
        param instanceof UploadCenterParam ? param : new UploadCenterParam(),
        (n: string, p?: object): void => {
          this.pageStack.pushPathByName(n, p ?? new Object());
        },
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.PHOTO_TIMELINE) {
      PhotoTimelinePageBuilder(
        param instanceof PhotoTimelinePageParam ? param : new PhotoTimelinePageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.PHOTO_MAIN) {
      PhotoMainPageBuilder(
        param instanceof PhotoMainPageParam ? param : new PhotoMainPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.PHOTO_TRASH) {
      PhotoTrashPageBuilder(
        param instanceof PhotoTrashPageParam ? param : new PhotoTrashPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.PHOTO_ALBUM_LIST) {
      PhotoAlbumListPageBuilder(
        param instanceof PhotoAlbumListPageParam ? param : new PhotoAlbumListPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.PHOTO_SMART_ALBUM_LIST) {
      PhotoSmartAlbumListPageBuilder(
        param instanceof PhotoSmartAlbumListPageParam ? param : new PhotoSmartAlbumListPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.PHOTO_COLLECTION_LIST) {
      PhotoCollectionListPageBuilder(
        param instanceof PhotoCollectionListPageParam ? param : new PhotoCollectionListPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.PHOTO_AI_FACES) {
      PhotoAiFacesPageBuilder(
        param instanceof PhotoAiFacesPageParam ? param : new PhotoAiFacesPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.PHOTO_AI_SCENES) {
      PhotoAiScenesPageBuilder(
        param instanceof PhotoAiScenesPageParam ? param : new PhotoAiScenesPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.PHOTO_AI_SIMILAR) {
      PhotoAiSimilarPageBuilder(
        param instanceof PhotoAiSimilarPageParam ? param : new PhotoAiSimilarPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.PHOTO_SETTINGS) {
      PhotoSettingsPageBuilder(
        param instanceof PhotoSettingsPageParam ? param : new PhotoSettingsPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.LEGAL) {
      LegalPageBuilder(
        param instanceof LegalPageParam ? param : new LegalPageParam(),
        () => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.VIDEO_MAIN) {
      VideoMainPageBuilder(
        param instanceof VideoMainPageParam ? param : new VideoMainPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.VIDEO_LIST) {
      VideoListPageBuilder(
        param instanceof VideoListPageParam ? param : new VideoListPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.VIDEO_DETAIL) {
      VideoDetailPageBuilder(
        param instanceof VideoDetailPageParam ? param : new VideoDetailPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.VIDEO_ALBUM_VIDEOS) {
      VideoAlbumVideosPageBuilder(
        param instanceof VideoAlbumVideosPageParam ? param : new VideoAlbumVideosPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.VIDEO_ALBUM_LIST) {
      VideoAlbumListPageBuilder(
        param instanceof VideoAlbumListPageParam ? param : new VideoAlbumListPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.VIDEO_SMART_ALBUM_LIST) {
      VideoSmartAlbumListPageBuilder(
        param instanceof VideoSmartAlbumListPageParam ? param : new VideoSmartAlbumListPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.VIDEO_COLLECTION_LIST) {
      VideoCollectionListPageBuilder(
        param instanceof VideoCollectionListPageParam ? param : new VideoCollectionListPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.VIDEO_SETTINGS) {
      VideoSettingsPageBuilder((): void => {
        this.pageStack.pop();
      })
    } else if (name === AppRouter.VIDEO_PLAYER) {
      VideoPlayerPageBuilder(
        param instanceof VideoPlayerPageParam ? param : new VideoPlayerPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.PHOTO_GALLERY) {
      GalleryPageBuilder(
        param instanceof GalleryPageParam ? param : new GalleryPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.PHOTO_PANORAMA) {
      PanoramaPageBuilder(
        param instanceof PanoramaPageParam ? param : new PanoramaPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.MUSIC_MAIN) {
      MusicMainPageBuilder(
        param instanceof MusicMainPageParam ? param : new MusicMainPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.MUSIC_SUB_LIST) {
      MusicSubListPageBuilder(
        param instanceof MusicSubListPageParam ? param : new MusicSubListPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.MUSIC_PLAYER) {
      MusicPlayerPageBuilder(
        param instanceof MusicPlayerPageParam ? param : new MusicPlayerPageParam(),
        (): void => {
          this.pageStack.pop();
        }
      )
    } else if (name === AppRouter.MUSIC_SETTINGS) {
      MusicSettingsPageBuilder((): void => {
        this.pageStack.pop();
      })
    }
  }

  build() {
    Navigation(this.pageStack) {
      ServerListPage({
        onNavigateHome: () => {
          this.pageStack.pushPathByName(AppRouter.HOME, new Object());
        },
        pageStack: this.pageStack
      })
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
  }
}

@Builder
function HomePageBuilder(onNavigateServerList: () => void, pushPage: (name: string, param?: object) => void) {
  HomePage({ onNavigateServerList: onNavigateServerList, pushPage: pushPage })
}

@Builder
export function LoginPageBuilder(onNavigateHome: () => void) {
  LoginPage({ onNavigateHome: onNavigateHome })
}

@Builder
export function RecoverPageBuilder(onBack: () => void) {
  RecoverPasswordView({ onBack: onBack })
}

@Builder
export function ServerAddPageBuilder(listVm: ServerListViewModel, onBack: () => void) {
  ServerAddPage({ listVm: listVm, onBack: onBack })
}

@Builder
function SettingsPageBuilder(onBack: () => void, pushLegal: (param: LegalPageParam) => void) {
  SettingsPage({ onBack: onBack, pushLegal: pushLegal })
}

@Builder
function LegalPageBuilder(param: LegalPageParam, onBack: () => void) {
  LegalPage({ param: param, onBack: onBack })
}

@Builder
function FileBrowserPageBuilder(param: FileBrowserParam, pushPage: (name: string, param?: object) => void,
  popPage: () => void) {
  FileBrowserPage({ param: param, pushPage: pushPage, popPage: popPage })
}

@Builder
function UploadCenterPageBuilder(param: UploadCenterParam, pushPage: (name: string, param?: object) => void,
  popPage: () => void) {
  UploadCenterPage({ param: param, pushPage: pushPage, popPage: popPage })
}

@Builder
function PhotoTimelinePageBuilder(param: PhotoTimelinePageParam, popPage: () => void) {
  PhotoTimelinePage({ param: param, popPage: popPage })
}

@Builder
function PhotoMainPageBuilder(param: PhotoMainPageParam, popPage: () => void) {
  PhotoMainPage({ param: param, popPage: popPage })
}

@Builder
function PhotoTrashPageBuilder(param: PhotoTrashPageParam, popPage: () => void) {
  PhotoTrashPage({ param: param, popPage: popPage })
}

@Builder
function PhotoAlbumListPageBuilder(param: PhotoAlbumListPageParam, popPage: () => void) {
  PhotoAlbumListPage({ param: param, popPage: popPage })
}

@Builder
function PhotoSmartAlbumListPageBuilder(param: PhotoSmartAlbumListPageParam, popPage: () => void) {
  PhotoSmartAlbumListPage({ param: param, popPage: popPage })
}

@Builder
function PhotoCollectionListPageBuilder(param: PhotoCollectionListPageParam, popPage: () => void) {
  PhotoCollectionListPage({ param: param, popPage: popPage })
}

@Builder
function PhotoAiFacesPageBuilder(param: PhotoAiFacesPageParam, popPage: () => void) {
  PhotoAiFacesPage({ param: param, popPage: popPage })
}

@Builder
function PhotoAiScenesPageBuilder(param: PhotoAiScenesPageParam, popPage: () => void) {
  PhotoAiScenesPage({ param: param, popPage: popPage })
}

@Builder
function PhotoAiSimilarPageBuilder(param: PhotoAiSimilarPageParam, popPage: () => void) {
  PhotoAiSimilarPage({ param: param, popPage: popPage })
}

@Builder
function PhotoSettingsPageBuilder(param: PhotoSettingsPageParam, popPage: () => void) {
  PhotoSettingsPage({ param: param, popPage: popPage })
}

@Builder
function GalleryPageBuilder(param: GalleryPageParam, popPage: () => void) {
  GalleryPage({ param: param, popPage: popPage })
}

@Builder
function PanoramaPageBuilder(param: PanoramaPageParam, popPage: () => void) {
  PanoramaPage({ param: param, popPage: popPage })
}

@Builder
function VideoMainPageBuilder(param: VideoMainPageParam, popPage: () => void) {
  VideoMainPage({ param: param, popPage: popPage })
}

@Builder
function VideoListPageBuilder(param: VideoListPageParam, popPage: () => void) {
  VideoListPage({ param: param, popPage: popPage })
}

@Builder
function VideoDetailPageBuilder(param: VideoDetailPageParam, popPage: () => void) {
  VideoDetailPage({ param: param, popPage: popPage })
}

@Builder
function VideoAlbumVideosPageBuilder(param: VideoAlbumVideosPageParam, popPage: () => void) {
  VideoAlbumVideosPage({ param: param, popPage: popPage })
}

@Builder
function VideoAlbumListPageBuilder(param: VideoAlbumListPageParam, popPage: () => void) {
  VideoAlbumListPage({ param: param, popPage: popPage })
}

@Builder
function VideoSmartAlbumListPageBuilder(param: VideoSmartAlbumListPageParam, popPage: () => void) {
  VideoSmartAlbumListPage({ param: param, popPage: popPage })
}

@Builder
function VideoCollectionListPageBuilder(param: VideoCollectionListPageParam, popPage: () => void) {
  VideoCollectionListPage({ param: param, popPage: popPage })
}

@Builder
function VideoSettingsPageBuilder(popPage: () => void) {
  VideoSettingsPage({ popPage: popPage })
}

@Builder
function VideoPlayerPageBuilder(param: VideoPlayerPageParam, popPage: () => void) {
  VideoPlayerPage({ param: param, popPage: popPage })
}

@Builder
function MusicMainPageBuilder(param: MusicMainPageParam, popPage: () => void) {
  MusicMainPage({ param: param, popPage: popPage })
}

@Builder
function MusicSubListPageBuilder(param: MusicSubListPageParam, popPage: () => void) {
  MusicSubListPage({ payload: new MusicSubListPayload(
    param.keyType, param.name, param.seriesIndexId, param.listId,
    param.listType, param.collectionId, param.isFavorite, param.isHistory
  ) })
}

@Builder
function MusicPlayerPageBuilder(param: MusicPlayerPageParam, popPage: () => void) {
  MusicPlayerPage({ param: param, popPage: popPage })
}

@Builder
function MusicSettingsPageBuilder(popPage: () => void) {
  MusicSettingsPage({ popPage: popPage })
}
