/**
 * 传输任务模型（对齐 Flutter transfer_task.dart，仅上传端）。
 * @Trace 字段供 @ComponentV2 页面响应式刷新进度/状态。
 */
export enum TransferStatus {
  PENDING = 0,
  UPLOADING = 1,
  PAUSED = 2,
  COMPLETED = 3,
  ERROR = 4
}

@ObservedV2
export class TransferTask {
  @Trace id: string = '';
  @Trace name: string = '';
  @Trace localUri: string = '';
  /** 上传目标目录 */
  @Trace remotePath: string = '';
  @Trace status: TransferStatus = TransferStatus.PENDING;
  @Trace totalSize: number = 0;
  @Trace processedSize: number = 0;
  @Trace error: string = '';
  createdTime: number = Date.now();
  /** 会话哈希（文件名|大小|mtime 的 sha256），断点续传 key */
  fileHash: string = '';
  /** 动态分块大小 */
  chunkSize: number = 0;

  constructor(id: string, name: string, localUri: string, remotePath: string,
    totalSize: number, status: TransferStatus, chunkSize: number) {
    this.id = id;
    this.name = name;
    this.localUri = localUri;
    this.remotePath = remotePath;
    this.totalSize = totalSize;
    this.status = status;
    this.chunkSize = chunkSize;
    this.createdTime = Date.now();
  }

  get progress(): number {
    return this.totalSize <= 0 ? 0 : this.processedSize / this.totalSize;
  }
}
