import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { DialogUtil } from '../../../common/DialogUtil';
import { GlassCard } from '../../../common/components/GlassCard';
import { EmptyState } from '../../../common/components/EmptyState';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { DockerController } from '../controllers/DockerController';
import { DockerImage } from '../models/DockerModels';
import { DockerActionButton, DockerMetaLine, DockerSectionHeader } from './parts/DockerSharedWidgets';
import { showDockerPullImageDialog, showDockerImportImageDialog, showDockerTagImageDialog } from '../components/DockerDialogs';

/**
 * Docker 镜像页签（对齐 Flutter _ImagesTab 移动端形态）：
 * 区块标题 + 刷新/拉取/导入操作，镜像卡片含引用、ID 与元信息，
 * 更多操作（复制拉取命令/修改标签/删除）通过选项弹层选择。
 */
@ComponentV2
export struct DockerImagesTab {
  @Param ctrl: DockerController = new DockerController();

  private referenceOf(item: DockerImage): string {
    const reference = item.reference.trim();
    if (reference.length > 0) {
      return reference;
    }
    return item.id.length > 0 ? item.id : '--';
  }

  private async confirmDelete(item: DockerImage): Promise<void> {
    const ok = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('docker_delete_image_confirm', '确认删除该镜像吗？'),
      (): void => {
        void this.ctrl.deleteImage(item.id, item.reference);
      },
      L10n.t('delete', '删除'), L10n.t('cancel', '取消'));
    // 回调式 onConfirm 已处理删除；此处仅消化 Promise
    if (ok !== true) {
      return;
    }
  }

  private showImageActions(item: DockerImage): void {
    const options: PickOption[] = [
      new PickOption('copy', L10n.t('docker_copy_pull_command', '复制拉取命令')),
      new PickOption('retag', L10n.t('docker_change_tag', '修改标签')),
      new PickOption('delete', L10n.t('delete', '删除'))
    ];
    showOptionPickSheet(L10n.t('docker_tab_images', '镜像'), options, '', (key: string): void => {
      if (key === 'copy') {
        const source = item.reference.trim().length > 0 ? item.reference : item.id;
        void this.ctrl.copyCommand(`docker pull ${source}`);
      } else if (key === 'retag') {
        showDockerTagImageDialog(this.ctrl, item);
      } else if (key === 'delete') {
        void this.confirmDelete(item);
      }
    });
  }

  @Builder
  ImageCard(item: DockerImage) {
    GlassCard({ padValue: 16, cornerRadius: 16 }) {
      Column() {
        Row() {
          Column() {
            Text(this.referenceOf(item))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.current().onSurface)
              .copyOption(CopyOptions.InApp)
              .width('100%')
            Text(item.id.length > 0 ? item.id : '--')
              .fontSize(11)
              .fontColor(AppTheme.current().subText)
              .copyOption(CopyOptions.InApp)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 6 })
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          BorderedIconButton({
            icon: $r('sys.symbol.ellipsis_circle'),
            iconColor: AppTheme.current().subText,
            onTap: (): void => {
              this.showImageActions(item);
            }
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        Column() {
          DockerMetaLine({
            label: L10n.t('name', '名称'),
            value: item.repository.length > 0 ? item.repository : '--'
          })
          DockerMetaLine({
            label: L10n.t('docker_tag', '标签'),
            value: item.tag.length > 0 ? item.tag : '--'
          })
          DockerMetaLine({
            label: L10n.t('size', '大小'),
            value: item.size.length > 0 ? item.size : '--'
          })
          DockerMetaLine({
            label: L10n.t('create_time', '创建时间'),
            value: item.createdAt.length > 0 ? item.createdAt : '--'
          })
        }
        .margin({ top: 12 })
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  build() {
    Scroll() {
      Column() {
        DockerSectionHeader({
          title: L10n.t('docker_tab_images', '镜像'),
          subtitle: L10n.t('docker_images_subtitle', '查看本地镜像、删除镜像，或发起新的拉取与导入任务')
        }) {
          Row({ space: 8 }) {
            DockerActionButton({
              label: L10n.t('refresh', '刷新'),
              icon: $r('sys.symbol.arrow_clockwise'),
              onTap: (): void => {
                void this.ctrl.refreshImages(false);
              }
            })
            DockerActionButton({
              label: L10n.t('docker_pull_image', '拉取镜像'),
              icon: $r('sys.symbol.download'),
              kind: 'primary',
              onTap: (): void => {
                showDockerPullImageDialog(this.ctrl);
              }
            })
            DockerActionButton({
              label: L10n.t('docker_import_image', '导入镜像'),
              icon: $r('sys.symbol.square_and_arrow_down'),
              onTap: (): void => {
                showDockerImportImageDialog(this.ctrl);
              }
            })
          }
        }
        if (this.ctrl.images.length === 0) {
          Column() {
            GlassCard({ padValue: 20, cornerRadius: 16 }) {
              Column() {
                EmptyState()
              }
              .width('100%')
            }
          }
          .margin({ top: 12 })
          .width('100%')
        } else {
          ForEach(this.ctrl.images, (item: DockerImage): void => {
            Column() {
              this.ImageCard(item)
            }
            .margin({ top: 12 })
            .width('100%')
          }, (item: DockerImage, idx: number): string => `${idx}_${item.id}_${item.reference}`)
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .align(Alignment.Top)
  }
}
