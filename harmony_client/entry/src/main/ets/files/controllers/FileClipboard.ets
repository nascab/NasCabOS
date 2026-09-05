/**
 * 文件复制/剪切剪贴板（对齐 Flutter file_clipboard_controller.dart 的 GetxService 单例）
 */
export class FileClipboard {
  private static instance: FileClipboard | undefined = undefined;
  /** 待粘贴的路径列表 */
  items: string[] = [];
  /** copy / cut / 空 */
  action: string = '';

  static getInstance(): FileClipboard {
    if (!FileClipboard.instance) {
      FileClipboard.instance = new FileClipboard();
    }
    return FileClipboard.instance;
  }

  isEmpty(): boolean {
    return this.items.length === 0;
  }

  clear(): void {
    this.items = [];
    this.action = '';
  }
}
