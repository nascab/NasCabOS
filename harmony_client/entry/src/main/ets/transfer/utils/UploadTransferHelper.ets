import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { L10n } from '../../core/localization/L10n';
import { TransferStatus, TransferTask } from '../models/TransferModels';

/** 传输辅助工具（对齐 Flutter upload_transfer_helper.dart） */
export class UploadTransferHelper {
  /** 从可能为 JSON 的错误串中提取 message 字段 */
  static getDisplayMessage(error: string): string {
    const trimmed = error.trim();
    if (trimmed.length === 0) {
      return '';
    }
    try {
      const decoded = JSON.parse(trimmed) as Record<string, Object>;
      const msg = decoded['message'];
      if (msg !== undefined && msg !== null) {
        const s = `${msg}`.trim();
        if (s.length > 0) {
          return s;
        }
      }
    } catch (_e) {
      // 非 JSON，原样返回
    }
    return trimmed;
  }

  /** 判断是否为“文件已存在”错误（409 / code 含 EXIST / message 含 exist 或 已存在） */
  static isFileExistsError(statusCode: number, message: string): boolean {
    if (statusCode === 409) {
      return true;
    }
    const raw = message ?? '';
    try {
      const decoded = JSON.parse(raw.trim()) as Record<string, Object>;
      const code = decoded['code'];
      if (code !== undefined && `${code}`.toUpperCase().includes('EXIST')) {
        return true;
      }
      const msg = decoded['message'];
      if (msg !== undefined) {
        const l = `${msg}`.toLowerCase();
        if (l.includes('exist') || `${msg}`.includes('已存在')) {
          return true;
        }
      }
    } catch (_e) {
      // 非 JSON 继续
    }
    const lower = raw.toLowerCase();
    return lower.includes('exist') || raw.includes('已存在');
  }

  /** 系统垃圾文件过滤（对齐 Flutter shouldIgnore） */
  static shouldIgnore(name: string): boolean {
    const lower = name.toLowerCase();
    if (lower === '.ds_store' || lower === 'thumbs.db' || lower === 'desktop.ini') {
      return true;
    }
    if (lower.startsWith('._')) {
      return true;
    }
    if (lower === '.spotlight-v100' || lower === '.trashes' || lower === '.fseventsd') {
      return true;
    }
    return false;
  }

  /** 队列中是否已存在同名同目标的未完成任务 */
  static isTaskAlreadyExists(tasks: TransferTask[], name: string, remotePath: string): boolean {
    return tasks.some((task: TransferTask) =>
      task.status !== TransferStatus.COMPLETED &&
      task.name === name && task.remotePath === remotePath
    );
  }

  /** 根据文件大小计算分块大小（对齐 Flutter calculateChunkSize） */
  static calculateChunkSize(fileSize: number): number {
    const mb = 1024 * 1024;
    if (fileSize < 200 * mb) {
      return 5 * mb;
    } else if (fileSize < 500 * mb) {
      return 10 * mb;
    } else if (fileSize < 1000 * mb) {
      return 15 * mb;
    } else if (fileSize < 2000 * mb) {
      return 20 * mb;
    } else if (fileSize < 3000 * mb) {
      return 25 * mb;
    }
    return 30 * mb;
  }

  /** 字节格式化（对齐 Flutter formatBytes） */
  static formatBytes(bytes: number): string {
    if (bytes <= 0) {
      return '0B';
    }
    const suffixes: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
    let i = 0;
    let d = bytes;
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return `${d.toFixed(1)}${suffixes[i]}`;
  }

  /** 对字符串做 sha256，返回 hex（对齐 Flutter sha256.convert） */
  static async sha256Hex(input: string): Promise<string> {
    const encoder = new util.TextEncoder();
    const bytes = encoder.encodeInto(input);
    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data: bytes });
    const blob = await md.digest();
    return UploadTransferHelper.toHex(blob.data);
  }

  private static toHex(bytes: Uint8Array): string {
    let out = '';
    for (let i = 0; i < bytes.length; i++) {
      out += (bytes[i] < 16 ? '0' : '') + bytes[i].toString(16);
    }
    return out;
  }

  /** 构造 multipart/form-data 请求体（对齐 Flutter _buildMultipartBody） */
  static buildMultipartBody(boundary: string, fields: Array<[string, string]>,
    fileField: string, filename: string, fileBytes: Uint8Array): Uint8Array {
    const encoder = new util.TextEncoder();
    const parts: Uint8Array[] = [];
    const pushStr = (s: string): void => {
      parts.push(encoder.encodeInto(s));
    };
    const boundaryLine = `--${boundary}\r\n`;
    for (const kv of fields) {
      pushStr(boundaryLine);
      pushStr(`Content-Disposition: form-data; name="${kv[0]}"\r\n\r\n`);
      pushStr(kv[1]);
      pushStr('\r\n');
    }
    pushStr(boundaryLine);
    pushStr(`Content-Disposition: form-data; name="${fileField}"; filename="${filename}"\r\n`);
    pushStr('Content-Type: application/octet-stream\r\n\r\n');
    parts.push(fileBytes);
    pushStr('\r\n');
    pushStr(`--${boundary}--\r\n`);

    let total = 0;
    for (const p of parts) {
      total += p.length;
    }
    const out = new Uint8Array(total);
    let offset = 0;
    for (const p of parts) {
      out.set(p, offset);
      offset += p.length;
    }
    return out;
  }

  /** 组装上传分块 multipart 的文本字段（对齐 Flutter chunk 字段集） */
  static chunkFields(sessionHash: string, remotePath: string, chunkSize: number, fileName: string,
    totalChunks: number, nameStrategy: string, index: number, mtimeMs: number,
    saveType: string): Array<[string, string]> {
    const fields: Array<[string, string]> = [
      ['hash', sessionHash],
      ['targetDir', remotePath],
      ['chunkSize', `${chunkSize}`],
      ['fileName', fileName],
      ['totalChunks', `${totalChunks}`],
      ['nameStrategy', nameStrategy],
      ['index', `${index}`]
    ];
    if (mtimeMs > 0) {
      fields.push(['mtimeMs', `${mtimeMs}`]);
    }
    if (saveType.length > 0) {
      fields.push(['saveType', saveType]);
    }
    return fields;
  }

  /** 上传检查请求体（对齐 Flutter check body） */
  static checkBody(sessionHash: string, targetDir: string, chunkSize: number, fileName: string,
    totalChunks: number, nameStrategy: string, mtimeMs: number, saveType: string): Record<string, Object> {
    const body: Record<string, Object> = {
      'hash': sessionHash,
      'targetDir': targetDir,
      'chunkSize': chunkSize,
      'fileName': fileName,
      'nameStrategy': nameStrategy,
      'totalChunks': totalChunks
    };
    if (mtimeMs > 0) {
      body['mtimeMs'] = mtimeMs;
    }
    if (saveType.length > 0) {
      body['saveType'] = saveType;
    }
    return body;
  }

  /** 任务状态文案（对齐 Flutter _statusText） */
  static statusText(status: TransferStatus): string {
    switch (status) {
      case TransferStatus.PENDING:
        return L10n.t('task_waitting', '等待中');
      case TransferStatus.UPLOADING:
        return L10n.t('task_uploading', '上传中');
      case TransferStatus.PAUSED:
        return L10n.t('pause', '暂停');
      case TransferStatus.ERROR:
        return L10n.t('error', '错误');
      case TransferStatus.COMPLETED:
        return L10n.t('task_completed', '已完成');
      default:
        return '';
    }
  }
}
