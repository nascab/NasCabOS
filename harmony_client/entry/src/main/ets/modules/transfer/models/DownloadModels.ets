import { request } from '@kit.BasicServicesKit';
import { TransferStatus } from './TransferModels';

/**
 * 下载模型（对齐 Flutter transfer_task.dart / download_history 相关结构）。
 */

/** 下载入口目标（path 为服务端完整路径，isDirHint 由调用方依据列表项给出） */
export interface DownloadTarget {
  path: string;
  isDirHint: boolean;
}

/** 递归展开后的远端文件节点（relativePath 相对于被下载文件夹根，使用 / 分隔） */
export interface RemoteFileNode {
  remotePath: string;
  relativePath: string;
  size: number;
}

/**
 * 下载任务（内存态，对应 Flutter TransferTask 的下载侧）。
 * @Trace 字段供 @ComponentV2 页面响应式刷新进度/状态。
 */
@ObservedV2
export class DownloadTaskItem {
  @Trace id: string = '';
  @Trace name: string = '';
  @Trace remotePath: string = '';
  @Trace localPath: string = '';
  @Trace status: TransferStatus = TransferStatus.PENDING;
  @Trace totalSize: number = 0;
  @Trace processedSize: number = 0;
  @Trace error: string = '';
  createdTime: number = 0;
  /** 文件夹下载根名（空串=单文件任务），任务名以 根名/相对路径 展示 */
  rootName: string = '';
  /** 文件夹展开失败时的占位任务（重试需重新递归列举，非单文件重下） */
  isFolderRoot: boolean = false;
  /** 系统下载代理句柄（非响应式字段，不参与 UI 观察） */
  sysTask: request.DownloadTask | undefined = undefined;

  constructor(id: string, name: string, remotePath: string, localPath: string,
    status: TransferStatus, createdTime: number) {
    this.id = id;
    this.name = name;
    this.remotePath = remotePath;
    this.localPath = localPath;
    this.status = status;
    this.createdTime = createdTime;
  }

  get progress(): number {
    return this.totalSize <= 0 ? 0 : this.processedSize / this.totalSize;
  }
}

/** 已下载文件记录（对应 Flutter DownloadedFileEntry） */
@ObservedV2
export class DownloadedFileEntry {
  @Trace id: number = 0;
  @Trace path: string = '';
  @Trace name: string = '';
  @Trace remotePath: string = '';
  @Trace size: number = 0;
  @Trace completedTimeMs: number = 0;
  /** 本地文件是否已不存在（展示红字提示） */
  @Trace fileMissing: boolean = false;
}
