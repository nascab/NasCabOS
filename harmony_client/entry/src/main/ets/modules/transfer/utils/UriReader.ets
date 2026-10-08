import { fileIo } from '@kit.CoreFileKit';

/**
 * 本地文件 URI 读取工具（相册/文档选择器返回的 file:// URI 均可读）。
 */
export class UriReader {
  /** 文件大小（字节），不可访问时返回 -1 */
  static statSize(uri: string): number {
    try {
      return fileIo.statSync(uri).size;
    } catch (_e) {
      return -1;
    }
  }

  /** 文件修改时间（毫秒），不可访问时返回 0 */
  static statMtimeMs(uri: string): number {
    try {
      return fileIo.statSync(uri).mtime * 1000;
    } catch (_e) {
      return 0;
    }
  }

  /** 文件是否存在 */
  static exists(uri: string): boolean {
    try {
      fileIo.statSync(uri);
      return true;
    } catch (_e) {
      return false;
    }
  }

  /** 读取 [start, start+length) 区间字节 */
  static readRange(uri: string, start: number, length: number): Uint8Array {
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const buf = new ArrayBuffer(length);
      const readLen = fileIo.readSync(file.fd, buf, { offset: start, length: length });
      if (readLen === length) {
        return new Uint8Array(buf);
      }
      return new Uint8Array(buf.slice(0, readLen));
    } finally {
      fileIo.closeSync(file);
    }
  }
}
