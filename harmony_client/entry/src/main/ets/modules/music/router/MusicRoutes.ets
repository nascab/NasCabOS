/** 音乐主页路由参数（对齐 Flutter AppMusicMainFrameView） */
export class MusicMainPageParam {
}

/** 子列表路由参数（对齐 MusicSubListMobilePage） */
export class MusicSubListPageParam {
  keyType: string = '';
  name: string = '';
  isFavorite: boolean = false;
  isHistory: boolean = false;
  listId: number = 0;
  seriesIndexId: number = 0;
  collectionId: number = 0;
  listType: string = '';
  initialSortBy: string = '';
  initialSortOrder: string = '';
}
