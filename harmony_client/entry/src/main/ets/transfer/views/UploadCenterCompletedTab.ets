import { L10n } from '../../core/localization/L10n';
import { EmptyState } from '../../common/components/EmptyState';
import { TransferTask } from '../models/TransferModels';
import { UploadController } from '../controllers/UploadController';
import { UploadCompletedCard, joinUploadRemotePath } from './UploadTaskCard';

/** 已完成 Tab（对齐 Flutter upload_center_completed_tab.dart） */
@ComponentV2
export struct UploadCenterCompletedTab {
  @Param ctrl: UploadController = UploadController.getInstance();

  private get completedItems(): TransferTask[] {
    return this.ctrl.completedTasks();
  }

  build() {
    if (this.completedItems.length === 0) {
      Column() {
        EmptyState({ message: L10n.t('task_empty', '暂无任务') })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 0 }) {
        ForEach(this.completedItems, (task: TransferTask): void => {
          ListItem() {
            UploadCompletedCard({
              task: task,
              ctrl: this.ctrl,
              savedPath: joinUploadRemotePath(task.remotePath, task.name)
            })
          }
          .margin({ bottom: 10 })
        }, (task: TransferTask): string => `${task.id}_${task.createdTime}`)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .padding(12)
    }
  }
}
