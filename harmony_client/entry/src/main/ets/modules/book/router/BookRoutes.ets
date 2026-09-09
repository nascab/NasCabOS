import { BookListItem } from '../models/BookModels';

/** 图书馆主页路由参数（对齐 Flutter AppBookMainView） */
export class BookMainPageParam {
}

/** 子列表路由参数（对齐 Flutter AppBookSubListPage：系列 / 书单 / 合集三形态） */
export class BookSubListPageParam {
  /** 自建书单 id（>0 时为书单子列表） */
  listId: number = 0;
  /** 合集 id（>0 时为合集子列表） */
  collectionId: number = 0;
  /** 系列索引 id（>0 时为系列子列表） */
  seriesId: number = 0;
  title: string = '';
  type: string = '';
  sourcePath: string = '';
}

/** 阅读历史路由参数 */
export class BookHistoryPageParam {
}

/** 漫画阅读器路由参数（对齐 Flutter BookComicReaderPage） */
export class BookComicReaderParam {
  fileHash: string = '';
  title: string = '';
  initialPage: number = 0;

  static fromItem(item: BookListItem): BookComicReaderParam {
    const p = new BookComicReaderParam();
    p.fileHash = item.fileHash;
    p.title = item.displayTitle;
    p.initialPage = item.currentPage > 0 ? item.currentPage - 1 : 0;
    return p;
  }
}

/** TXT 阅读器路由参数（对齐 Flutter BookTxtReaderPage） */
export class BookTxtReaderParam {
  title: string = '';
  fileHash: string = '';
  localFilePath: string = '';

  static fromItem(item: BookListItem, localFilePath: string): BookTxtReaderParam {
    const p = new BookTxtReaderParam();
    p.title = item.displayTitle;
    p.fileHash = item.fileHash;
    p.localFilePath = localFilePath;
    return p;
  }
}

/** Web 阅读器（epub/mobi 等）路由参数（对齐 Flutter BookWebReaderPage） */
export class BookWebReaderParam {
  title: string = '';
  fileHash: string = '';
  /** 服务器文件路径（创建 scoped token 与 rawFile URL 用） */
  filePath: string = '';
  filename: string = '';
  /** 本地缓存路径（对齐 Flutter app 端：先下载后打开本地文件，经拦截器 fd 供页） */
  localPath: string = '';
  /** 暂存 scoped token（阅读器上报进度用） */
  url: string = '';

  static fromItem(item: BookListItem, filePath: string): BookWebReaderParam {
    const p = new BookWebReaderParam();
    p.title = item.displayTitle;
    p.fileHash = item.fileHash;
    p.filePath = filePath;
    p.filename = item.filename;
    return p;
  }
}
