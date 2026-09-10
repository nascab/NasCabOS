import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { DialogUtil } from '../../../common/DialogUtil';
import { GlassCard } from '../../../common/components/GlassCard';
import { EmptyState } from '../../../common/components/EmptyState';
import { ShareRootPath, ShareServerConfigRecord } from '../models/ShareServerModels';
import { ShareServerController } from '../controllers/ShareServerController';
import { ShareConfigDialog } from './parts/ShareConfigDialog';

/**
 * 文件服务面板（对齐 Flutter _TypePanel，WebDav/FTP/SFTP 三类复用）：
 * 服务状态头卡（状态/端口/开关）+ 用户权限配置卡（添加配置）+ 配置卡片列表。
 * 配置弹窗复用 ShareConfigDialog（对齐 _ConfigDialog）。
 */
@ComponentV2
export struct ShareTypePanel {
  @Param ctrl: ShareServerController = new ShareServerController();
  /** WebDav / FTP / SFTP */
  @Param serverType: string = 'WebDav';
  /** 主题变化刷新计数（主页传入，驱动本面板重渲染换色） */
  @Param themeTick: number = 0;
  @Local dialogOpen: boolean = false;
  /** 编辑目标；undefined 表示新建 */
  @Local dialogItem: ShareServerConfigRecord | undefined = undefined;

  private palette() {
    return AppTheme.current();
  }

  private typeName(): string {
    if (this.serverType === 'FTP') {
      return L10n.t('file_share_server_ftp', 'FTP');
    }
    if (this.serverType === 'SFTP') {
      return L10n.t('file_share_server_sftp', 'SFTP');
    }
    return L10n.t('file_share_server_webdav', 'WebDAV');
  }

  private statusText(): string {
    const s = this.ctrl.getStatus(this.serverType);
    if (s === 'running') {
      return L10n.t('file_share_server_status_running', '运行中');
    }
    if (s === 'stopped') {
      return L10n.t('file_share_server_status_stopped', '已停止');
    }
    return s;
  }

  private portsText(): string {
    const ports = this.ctrl.getDisplayPorts(this.serverType);
    const http = ports.httpPort.length > 0 ? ports.httpPort : '-';
    const https = ports.httpsPort.length > 0 ? ports.httpsPort : '-';
    return `${L10n.t('file_share_server_http', 'HTTP')}: ${http}  ${L10n.t('file_share_server_https', 'HTTPS')}: ${https}`;
  }

  private configs(): ShareServerConfigRecord[] {
    return this.ctrl.configsFor(this.serverType);
  }

  private openAdd(): void {
    this.dialogItem = undefined;
    this.dialogOpen = true;
  }

  private openEdit(item: ShareServerConfigRecord): void {
    this.dialogItem = item;
    this.dialogOpen = true;
  }

  private confirmDelete(item: ShareServerConfigRecord): void {
    DialogUtil.showConfirmDialog(L10n.confirm,
      L10n.t('file_share_server_delete_confirm', '确定删除该配置吗？'),
      (): void => {
        void this.ctrl.deleteConfig(item.uid, this.serverType);
      });
  }

  /** 权限标签（对齐 Flutter _permLabel：[读取/写入/修改/删除]） */
  private permLabel(row: ShareRootPath): string {
    const list: string[] = [L10n.t('file_share_server_perm_read', '读取')];
    if (row.write) {
      list.push(L10n.t('file_share_server_perm_write', '写入'));
    }
    if (row.update) {
      list.push(L10n.t('file_share_server_perm_update', '修改'));
    }
    if (row.delete) {
      list.push(L10n.t('file_share_server_perm_delete', '删除'));
    }
    return `[${list.join('/')}]`;
  }

  build() {
    Stack() {
      Column() {
        this.ServiceHeader()
        // 用户权限配置卡
        Column() {
          GlassCard({
            padValue: { left: 12, right: 12, top: 10, bottom: 10 }
          }) {
            Row() {
              Text(L10n.t('file_share_server_user_permission_rules', '用户权限配置'))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette().onSurface)
                .layoutWeight(1)
              this.TextIconButton($r('sys.symbol.plus'),
                L10n.t('file_share_server_add_config', '添加配置'), (): void => {
                  this.openAdd();
                })
            }
            .width('100%')
          }
        }
        .width('100%')
        .margin({ top: 12 })

        // 配置列表
        if (this.configs().length === 0) {
          Column() {
            EmptyState({ message: L10n.t('no_data', '暂无数据') })
          }
          .width('100%')
          .layoutWeight(1)
          .margin({ top: 12 })
        } else {
          List({ space: 8 }) {
            ForEach(this.configs(), (item: ShareServerConfigRecord) => {
              ListItem() {
                this.ConfigCard(item)
              }
            }, (item: ShareServerConfigRecord) => `${item.uid}_${item.rootPath.length}_${item.status}`)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .margin({ top: 12 })
        }
      }
      .padding(12)
      .width('100%')
      .height('100%')

      if (this.dialogOpen) {
        ShareConfigDialog({
          ctrl: this.ctrl,
          serverType: this.serverType,
          initialItem: this.dialogItem,
          onSubmit: (uid: number, rootPath: ShareRootPath[]): Promise<boolean> => {
            return this.ctrl.upsertConfig(uid, this.serverType, rootPath);
          },
          onDismiss: (): void => {
            this.dialogOpen = false;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
    .opacity(this.themeTick >= 0 ? 1 : 1)
  }

  /** 文字+图标按钮（对齐 Flutter CustomButton text+icon） */
  @Builder
  TextIconButton(icon: Resource, label: string, onTap: () => void) {
    Row({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(15)
        .fontColor([this.palette().primary])
      Text(label)
        .fontSize(13)
        .fontColor(this.palette().primary)
        .maxLines(1)
    }
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .borderRadius(10)
    .border({ width: 1, color: this.palette().divider })
    .onClick(() => {
      onTap();
    })
  }

  /** 服务状态头卡（对齐 _ServiceHeader） */
  @Builder
  ServiceHeader() {
    GlassCard({
      padValue: 12
    }) {
      Row() {
        Column() {
          Row({ space: 10 }) {
            Text(this.statusText())
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().onSurface)
            Text(this.portsText())
              .fontSize(12)
              .fontColor(this.palette().subText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          Text(this.ctrl.getStatus(this.serverType) === 'running'
            ? L10n.t('file_share_server_enabled', '已开启')
            : L10n.t('file_share_server_disabled', '已关闭'))
            .fontSize(12)
            .fontColor(this.ctrl.getStatus(this.serverType) === 'running'
              ? this.palette().primary : this.palette().subText)
            .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.ctrl.isOpLoading(this.serverType)) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.palette().primary)
            .margin({ right: 10 })
        }

        Toggle({ type: ToggleType.Switch,
          isOn: this.ctrl.getStatus(this.serverType) === 'running' })
          .selectedColor(this.palette().primary)
          .enabled(!this.ctrl.isOpLoading(this.serverType))
          .onChange((on: boolean) => {
            if (this.ctrl.isOpLoading(this.serverType)) {
              return;
            }
            if (on) {
              void this.ctrl.start(this.serverType);
            } else {
              void this.ctrl.stop(this.serverType);
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  /** 配置卡片（对齐 _ConfigCard） */
  @Builder
  ConfigCard(item: ShareServerConfigRecord) {
    GlassCard({
      padValue: 12
    }) {
      Column() {
        Row({ space: 4 }) {
          Text(this.usernameOf(item))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(18)
            .fontColor([this.palette().onSurface])
            .padding(4)
            .onClick(() => {
              this.openEdit(item);
            })
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(18)
            .fontColor([this.palette().error])
            .padding(4)
            .onClick(() => {
              this.confirmDelete(item);
            })
        }
        .width('100%')

        if (item.rootPath.length === 0) {
          Text(L10n.t('file_share_server_no_path_selected', '未选择路径'))
            .fontSize(12)
            .fontColor(this.palette().subText)
            .margin({ top: 8 })
        } else {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(item.rootPath.slice(0, 12), (row: ShareRootPath) => {
              Text(`${row.path} ${this.permLabel(row)}`)
                .fontSize(12)
                .fontColor(this.palette().onSurface)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 340 })
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(999)
                .backgroundColor(this.palette().cardBg)
                .border({ width: 1, color: this.palette().divider })
                .margin({ right: 8, bottom: 8 })
            }, (row: ShareRootPath) => `${row.path}_${row.write}_${row.update}_${row.delete}`)
          }
          .width('100%')
          .margin({ top: 8 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  private usernameOf(item: ShareServerConfigRecord): string {
    const name = this.ctrl.usernameForUid(item.uid);
    return name.length > 0 ? name : `${item.uid}`;
  }
}
