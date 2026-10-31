import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { SheetHandle, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { ArchiveEntryData, FileFormat } from '../models/FileModels';

/** 压缩包预览行（目录或文件） */
class ArchiveRow {
  name: string = '';
  isDir: boolean = false;
  size: number = 0;
  /** 目录行的完整路径（点击进入） */
  dirPath: string = '';
}

class ArchiveSheetParams extends SheetParamsBase {
  title: string = '';
  archiveSize: number = 0;
  entries: ArchiveEntryData[] = [];
}

@Builder
function ArchiveSheetContent(p: ArchiveSheetParams) {
  ArchiveSheetBody({ p: p })
}

/**
 * 压缩包内容预览（对齐 Flutter _ArchivePreviewDialog）：
 * 按包内路径逐级展开目录（archive_up 返回上级），文件行展示解压后大小。
 */
@ComponentV2
struct ArchiveSheetBody {
  @Param p: ArchiveSheetParams = new ArchiveSheetParams();
  @Local currentDir: string = '';

  /** 当前目录下的行（目录优先，名称升序） */
  private rows(): ArchiveRow[] {
    const prefix = this.currentDir.length > 0 ? `${this.currentDir}/` : '';
    const dirNames: string[] = [];
    const files: ArchiveRow[] = [];
    for (const e of this.p.entries) {
      const full = e.path.trim();
      if (full.length === 0 || (prefix.length > 0 && !full.startsWith(prefix))) {
        continue;
      }
      const rest = prefix.length > 0 ? full.substring(prefix.length) : full;
      if (rest.length === 0) {
        continue;
      }
      const slash = rest.indexOf('/');
      if (slash >= 0) {
        const dirName = rest.substring(0, slash);
        if (dirName.length > 0 && !dirNames.includes(dirName)) {
          dirNames.push(dirName);
        }
      } else {
        const row = new ArchiveRow();
        row.name = rest;
        row.size = e.size;
        files.push(row);
      }
    }
    dirNames.sort((a: string, b: string): number => a.localeCompare(b));
    files.sort((a: ArchiveRow, b: ArchiveRow): number => a.name.localeCompare(b.name));
    const out: ArchiveRow[] = [];
    for (const d of dirNames) {
      const row = new ArchiveRow();
      row.name = d;
      row.isDir = true;
      row.dirPath = prefix.length > 0 ? `${prefix}${d}` : d;
      out.push(row);
    }
    for (const f of files) {
      out.push(f);
    }
    return out;
  }

  private goUp(): void {
    const idx = this.currentDir.lastIndexOf('/');
    this.currentDir = idx >= 0 ? this.currentDir.substring(0, idx) : '';
  }

  build() {
    Column() {
      SheetHandle()
      Row() {
        if (this.currentDir.length > 0) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(18)
            .fontColor([AppTheme.current().onSurface])
            .margin({ right: 6 })
            .onClick(() => {
              this.goUp();
            })
        }
        Column() {
          Text(this.p.title)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.current().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${L10n.t('archive_preview_title', '压缩包内容')} · ${this.p.entries.length}`
            + (this.p.archiveSize > 0 ? ` · ${FileFormat.formatSize(this.p.archiveSize)}` : ''))
            .fontSize(12)
            .fontColor(AppTheme.current().subText)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 4, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      Divider()
        .color(AppTheme.current().divider)

      if (this.rows().length === 0) {
        Column() {
          Text(L10n.t('archive_empty', '没有可显示的文件'))
            .fontSize(14)
            .fontColor(AppTheme.current().subText)
        }
        .width('100%')
        .height(240)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.rows(), (row: ArchiveRow) => {
            ListItem() {
              Row({ space: 10 }) {
                SymbolGlyph(row.isDir ? $r('sys.symbol.folder') : $r('sys.symbol.doc'))
                  .fontSize(20)
                  .fontColor([row.isDir ? AppTheme.current().primary : AppTheme.current().subText])
                Column({ space: 2 }) {
                  Text(row.name)
                    .fontSize(14)
                    .fontColor(AppTheme.current().onSurface)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  if (!row.isDir) {
                    Text(FileFormat.formatSize(row.size))
                      .fontSize(11)
                      .fontColor(AppTheme.current().hint)
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 20, right: 20, top: 12, bottom: 12 })
            }
            .onClick(() => {
              if (row.isDir) {
                this.currentDir = row.dirPath;
              }
            })
          }, (row: ArchiveRow, idx: number) => `${this.currentDir}#${idx}#${row.name}`)
        }
        .width('100%')
        .height(440)
        .divider({ strokeWidth: 0.5, color: AppTheme.current().divider, startMargin: 20, endMargin: 20 })
        .scrollBar(BarState.Off)
      }
    }
    .padding({ bottom: 20 })
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

/** 展示压缩包内容预览弹层 */
export function showArchivePreviewSheet(title: string, archiveSize: number, entries: ArchiveEntryData[]): void {
  const p = new ArchiveSheetParams();
  p.title = title;
  p.archiveSize = archiveSize;
  p.entries = entries;
  SheetUtil.present(p, wrapBuilder(ArchiveSheetContent));
}
