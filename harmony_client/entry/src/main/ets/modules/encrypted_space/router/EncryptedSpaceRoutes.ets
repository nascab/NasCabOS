/**
 * 加密空间模块路由参数（对齐 Flutter Get.to 路由：
 * AppEncryptedSpaceView / AppEncryptedSpaceDetailPage / 图片查看器）。
 * 页面名常量供主线程统一接线（AppRouter + Index.pageMap）。
 */
export class EncryptedSpaceRoutes {
  static readonly MAIN: string = 'EncryptedSpaceMainPage';
  static readonly DETAIL: string = 'EncryptedSpaceDetailPage';
  static readonly VIEWER: string = 'EncryptedSpaceViewerPage';
}

export class EncryptedSpaceMainPageParam {
  title: string = '';
}

/** 加密空间文件列表页参数（对齐 EncryptedSpaceActiveSpace 传入的字段） */
export class EncryptedSpaceDetailPageParam {
  spaceId: number = 0;
  token: string = '';
  name: string = '';
  path: string = '';
}

/** 图片查看器条目（对齐 Flutter _openImage 构造的 gallery Map） */
export class EncryptedViewerItem {
  indexId: number = 0;
  name: string = '';
  /** 预览/原图 URL（getDecodeFile） */
  url: string = '';
  /** 下载 URL（download=1&fileName=...） */
  downloadUrl: string = '';
}

export class EncryptedSpaceViewerPageParam {
  items: EncryptedViewerItem[] = [];
  initialIndex: number = 0;
  /** 删除成功回调（返回 true 表示已删除，查看器自行关闭）；对齐 Flutter deleteHandler */
  onDeleted: (indexId: number) => Promise<boolean> = (_indexId: number): Promise<boolean> => {
    return Promise.resolve(false);
  };
}
