import { L10n } from '../../core/localization/L10n';
import { AppRouter } from '../../router/AppRouter';
import { NavUtil } from '../../common/NavUtil';
import { AppImage } from '../../common/components/AppImage';
import { FileFormat } from '../../files/models/FileModels';
import { FileBrowserParam } from '../../files/views/FileBrowserPage';
import { ApiUrls } from '../../core/network/ApiUrls';
import { AppTheme } from '../../core/theme/AppTheme';
import { TimelineDetectedFaceItem } from '../../photo/models/PhotoModels';
import { GalleryController } from '../controllers/GalleryController';
import { GeoTileMap } from './GeoTileMap';

/** 人脸头像（URL 为 AES 加密异步构建，组件内自行解析） */
@ComponentV2
struct GalleryFaceAvatar {
  @Param faceId: number = 0;
  @Param fileHash: string = '';
  @Local url: string = '';

  aboutToAppear(): void {
    ApiUrls.getFaceImageUrl(this.faceId, 120, 85, this.fileHash).then((u: string): void => {
      this.url = u;
    }).catch((_e: Object): void => {
    });
  }

  build() {
    Stack() {
      AppImage({
        url: this.url,
        objectFit: ImageFit.Cover,
        imageRadius: 16,
        showLoadingSpin: false
      })
    }
    .width(34)
    .height(34)
    .borderRadius(17)
    .border({ width: 1, color: AppTheme.withAlpha('#FFFFFF', 0.12) })
    .clip(true)
  }
}

/** 分区标题（对齐 Flutter _InfoSectionTitle：13 / w600，无额外间距） */
@ComponentV2
struct InfoSectionTitle {
  @Param title: string = '';

  build() {
    Text(this.title)
      .fontSize(13)
      .fontWeight(600)
      .fontColor('#FFFFFF')
  }
}

/** 12dp 区间隔（对齐 Flutter SizedBox(height:12)） */
@Builder
function SectionGap12() {
  Column()
    .width(1)
    .height(12)
}

/** 8dp 区间隔（对齐 Flutter SizedBox(height:8)） */
@Builder
function SectionGap8() {
  Column()
    .width(1)
    .height(8)
}

/**
 * 图片信息面板（对齐 Flutter GalleryInfoPanel）：
 * 基础信息 / 拍摄参数 / EXIF / 人物 / 位置（瓦片地图）。
 * 桌面端为侧栏，手机端置于底部 sheet（黑 95% 圆角 16）。
 */
@ComponentV2
export struct GalleryInfoPanel {
  @Param ctrl: GalleryController = new GalleryController();
  /** 传入时（底部 sheet）显示关闭按钮，否则显示收起箭头 */
  @Param sheetMode: boolean = false;
  @Param onClose: () => void = (): void => {
  };

  private static fmtIso(v: Object | undefined | null): string {
    const s = `${v ?? ''}`.trim();
    if (s.length === 0) {
      return '';
    }
    const ts = Date.parse(s);
    if (Number.isNaN(ts)) {
      return s;
    }
    return FileFormat.formatFullTime(ts);
  }

  private static fmtNum(v: Object | undefined | null): string {
    const s = `${v ?? ''}`.trim();
    return s.length === 0 ? '' : s;
  }

  private static fmtFNumber(v: Object | undefined | null): string {
    const s = GalleryInfoPanel.fmtNum(v);
    if (s.length === 0) {
      return '';
    }
    if (s.startsWith('f/') || s.startsWith('F/')) {
      return s;
    }
    return `f/${s}`;
  }

  private static fmtFocalMm(v: Object | undefined | null): string {
    const s = GalleryInfoPanel.fmtNum(v);
    if (s.length === 0) {
      return '';
    }
    const n = Number(s);
    if (!Number.isFinite(n)) {
      return s;
    }
    const nice = Number.isInteger(n) ? n.toFixed(0) : n.toFixed(1);
    return `${nice}mm`;
  }

  private static fmtExposureFromSeconds(seconds: number): string {
    if (!Number.isFinite(seconds) || seconds <= 0) {
      return '';
    }
    if (seconds >= 1) {
      const s = Number.isInteger(seconds) ? seconds.toFixed(0) : seconds.toFixed(2);
      return `${s}s`;
    }
    const denom = Math.round(1 / seconds);
    if (denom <= 0) {
      return '';
    }
    return `1/${denom}`;
  }

  private static fmtExposure(exposureTime: Object | undefined | null,
    shutterSpeedValue: Object | undefined | null): string {
    const et = GalleryInfoPanel.fmtNum(exposureTime);
    if (et.length > 0) {
      if (et.includes('/') || et.endsWith('s')) {
        return et;
      }
      const n = Number(et);
      if (Number.isFinite(n)) {
        const f = GalleryInfoPanel.fmtExposureFromSeconds(n);
        if (f.length > 0) {
          return f;
        }
      }
      return et;
    }
    const sv = GalleryInfoPanel.fmtNum(shutterSpeedValue);
    if (sv.length === 0) {
      return '';
    }
    if (sv.includes('/') || sv.endsWith('s')) {
      return sv;
    }
    const n = Number(sv);
    if (!Number.isFinite(n)) {
      return sv;
    }
    return GalleryInfoPanel.fmtExposureFromSeconds(Math.pow(2, -n));
  }

  private exif(): Record<string, Object> {
    const d = this.ctrl.infoData;
    const e = d !== undefined ? d['exif'] : undefined;
    return (e !== undefined && e !== null && typeof e === 'object') ? e as Record<string, Object> : {};
  }

  private infoStr(key: string): string {
    const d = this.ctrl.infoData;
    return d !== undefined ? `${d[key] ?? ''}`.trim() : '';
  }

  private infoNum(key: string): number {
    const d = this.ctrl.infoData;
    if (d === undefined) {
      return 0;
    }
    const n = Number(d[key]);
    return Number.isFinite(n) ? n : 0;
  }

  /** 拍摄参数一行：f/x 快门 焦距 ISO:x（对齐 Flutter _shootingParamsLine） */
  private shootingLine(): string {
    const exif = this.exif();
    const parts: string[] = [];
    const f = GalleryInfoPanel.fmtFNumber(exif['fNumber'] ?? exif['apertureValue']);
    if (f.length > 0) {
      parts.push(f);
    }
    const exp = GalleryInfoPanel.fmtExposure(exif['exposureTime'], exif['shutterSpeedValue']);
    if (exp.length > 0) {
      parts.push(exp);
    }
    const focal = GalleryInfoPanel.fmtFocalMm(exif['focalLength']);
    if (focal.length > 0) {
      parts.push(focal);
    }
    const iso = GalleryInfoPanel.fmtNum(exif['iso']);
    if (iso.length > 0) {
      parts.push(`ISO:${iso}`);
    }
    return parts.join(' ');
  }

  private dimensionText(): string {
    const w = this.infoNum('width');
    const h = this.infoNum('height');
    return w > 0 && h > 0 ? `${w} × ${h}` : '';
  }

  private hasGps(): boolean {
    const lat = this.infoNum('latitude');
    const lng = this.infoNum('longitude');
    return lat !== 0 && lng !== 0;
  }

  /** 基础区任一字段存在（对齐 Flutter baseRows.isNotEmpty 再统一出标题） */
  private hasBasic(): boolean {
    return this.infoStr('fullpath').length > 0
      || this.infoNum('size') > 0
      || this.dimensionText().length > 0
      || GalleryInfoPanel.fmtIso(this.ctrl.infoData?.['mtime']).length > 0
      || GalleryInfoPanel.fmtIso(this.ctrl.infoData?.['createTime']).length > 0
      || GalleryInfoPanel.fmtIso(this.ctrl.infoData?.['originalTime']).length > 0;
  }

  /** 点击路径打开文件浏览（无扩展名打开本路径，否则打开其目录） */
  private openPathInFileBrowser(targetPath: string): void {
    const target = targetPath.trim();
    if (target.length === 0) {
      return;
    }
    const dot = target.lastIndexOf('.');
    const slash = target.lastIndexOf('/');
    const hasExt = dot > slash + 1;
    const openTarget = hasExt ? target.substring(0, slash) : target;
    const p = new FileBrowserParam();
    p.initialPath = openTarget;
    NavUtil.push(AppRouter.FILES, p);
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      if (label.length > 0) {
        Text(label)
          .fontSize(12)
          .fontColor(AppTheme.withAlpha('#FFFFFF', 0.8))
          .width(70)
          .margin({ right: 8 })
      }
      Text(value)
        .fontSize(12)
        .fontColor('#FFFFFF')
        .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Center)
    .margin({ top: 6 })
  }

  @Builder
  PathRow(fullpath: string) {
    Row() {
      Text(L10n.t('path', '路径'))
        .fontSize(12)
        .fontColor(AppTheme.withAlpha('#FFFFFF', 0.8))
        .width(70)
        .margin({ right: 8 })
      Text(fullpath)
        .fontSize(12)
        .fontColor('#2196F3')
        .layoutWeight(1)
        .onClick((): void => {
          this.openPathInFileBrowser(fullpath);
        })
    }
    .alignItems(VerticalAlign.Center)
    .margin({ top: 6 })
  }

  @Builder
  FaceRow(face: TimelineDetectedFaceItem, fileHash: string) {
    Row({ space: 10 }) {
      GalleryFaceAvatar({ faceId: face.faceId, fileHash: fileHash })
      Column({ space: 2 }) {
        Text(face.name.trim().length > 0 ? face.name.trim() : `(${L10n.t('face_unnamed', '未命名')})`)
          .fontSize(12)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${L10n.t('total_count', '共 @count 张', L10n.paramsOf('count', `${face.faceCount}`))}` +
          `${face.isHide ? ` · ${L10n.t('face_action_hide', '隐藏')}` : ''}`)
          .fontSize(12)
          .fontColor(AppTheme.withAlpha('#FFFFFF', 0.72))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .margin({ bottom: 8 })
  }

  @Builder
  BasicSection() {
    if (this.hasBasic()) {
      InfoSectionTitle({ title: L10n.t('gallery_info_basic', '基本信息') })
      if (this.infoStr('fullpath').length > 0) {
        this.PathRow(this.infoStr('fullpath'))
      }
      if (this.infoNum('size') > 0) {
        this.InfoRow(L10n.t('size', '大小'), FileFormat.formatSize(this.infoNum('size')))
      }
      if (this.dimensionText().length > 0) {
        this.InfoRow(L10n.t('gallery_info_dimensions', '尺寸'), this.dimensionText())
      }
      if (GalleryInfoPanel.fmtIso(this.ctrl.infoData?.['mtime']).length > 0) {
        this.InfoRow(L10n.t('modified_at', '修改于'),
          GalleryInfoPanel.fmtIso(this.ctrl.infoData?.['mtime']))
      }
      if (GalleryInfoPanel.fmtIso(this.ctrl.infoData?.['createTime']).length > 0) {
        this.InfoRow(L10n.t('create_time', '创建时间'),
          GalleryInfoPanel.fmtIso(this.ctrl.infoData?.['createTime']))
      }
      if (GalleryInfoPanel.fmtIso(this.ctrl.infoData?.['originalTime']).length > 0) {
        this.InfoRow(L10n.t('gallery_info_taken_time', '拍摄时间'),
          GalleryInfoPanel.fmtIso(this.ctrl.infoData?.['originalTime']))
      }
      SectionGap12()
    }
  }

  @Builder
  ShootingSection() {
    if (this.shootingLine().length > 0) {
      InfoSectionTitle({ title: L10n.t('gallery_info_shooting_params', '拍摄参数') })
      this.InfoRow('', this.shootingLine())
      SectionGap12()
    }
  }

  @Builder
  ExifSection() {
    if (this.deviceText().length > 0 || this.lensText().length > 0) {
      InfoSectionTitle({ title: L10n.t('gallery_info_exif', 'EXIF') })
      if (this.deviceText().length > 0) {
        this.InfoRow(L10n.t('gallery_info_device', '设备'), this.deviceText())
      }
      if (this.lensText().length > 0) {
        this.InfoRow(L10n.t('gallery_info_lens', '镜头'), this.lensText())
      }
      SectionGap12()
    }
  }

  @Builder
  PeopleSection() {
    if (this.ctrl.infoFaces().length > 0 && this.photoFileHash().length > 0) {
      InfoSectionTitle({ title: L10n.t('gallery_info_people', '人物') })
      SectionGap8()
      ForEach(this.ctrl.infoFaces(), (face: TimelineDetectedFaceItem) => {
        this.FaceRow(face, this.photoFileHash())
      }, (face: TimelineDetectedFaceItem): string => `${face.faceId}_${face.name}_${face.faceCount}`)
      SectionGap12()
    }
  }

  @Builder
  LocationSection() {
    if (this.hasGps()) {
      InfoSectionTitle({ title: L10n.t('location', '位置') })
      if (this.infoStr('geo').length > 0) {
        this.InfoRow('', this.infoStr('geo'))
      }
      SectionGap8()
      Stack() {
        GeoTileMap({
          lat: this.infoNum('latitude'),
          lng: this.infoNum('longitude')
        })
      }
      .width('100%')
      .height(220)
      .borderRadius(10)
      .clip(true)
      SectionGap12()
    }
  }

  build() {
    Column() {
      // 顶栏：对齐 Flutter SizedBox(6) + 48dp 点击区的关闭 IconButton
      Row() {
        Blank()
        SymbolGlyph(this.sheetMode ? $r('sys.symbol.xmark') : $r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor(['#FFFFFF'])
          .padding(12)
          .onClick((): void => {
            if (this.sheetMode) {
              this.onClose();
            } else {
              this.ctrl.toggleInfoPanel();
            }
          })
      }
      .width('100%')
      .margin({ top: 6 })

      if (this.ctrl.infoLoading) {
        Row() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color('#FFFFFF')
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 8, bottom: 8 })
      }
      if (!this.ctrl.infoLoading && this.ctrl.infoErrorText.length > 0) {
        Text(this.ctrl.infoErrorText)
          .fontSize(12)
          .fontColor('#FFFFFF')
          .margin({ bottom: 8 })
      }
      if (this.ctrl.infoData !== undefined) {
        Scroll() {
          Column() {
            this.BasicSection()
            this.ShootingSection()
            this.ExifSection()
            this.PeopleSection()
            this.LocationSection()
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        .scrollBar(BarState.Auto)
        .align(Alignment.TopStart)
        .layoutWeight(1)
      } else {
        Blank()
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#D9000000')
    // 对齐 Flutter fromLTRB(12,24,12,12)；sheet 模式上方已有拖拽手柄，取 12
    .padding({ left: 12, right: 12, top: this.sheetMode ? 12 : 24, bottom: 12 })
  }

  private deviceText(): string {
    const exif = this.exif();
    return `${exif['make'] ?? ''} ${exif['model'] ?? ''}`.trim();
  }

  private lensText(): string {
    return GalleryInfoPanel.fmtNum(this.exif()['lensModel']);
  }

  private photoFileHash(): string {
    const d = this.ctrl.infoData;
    const idx = d !== undefined ? d['photoIndex'] as Record<string, Object> | undefined : undefined;
    const h = `${idx?.['fileHash'] ?? ''}`.trim();
    return h;
  }
}
