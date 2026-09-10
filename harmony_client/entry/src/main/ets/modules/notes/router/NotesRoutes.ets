/**
 * 笔记模块路由参数（对齐 Flutter Get.to 路由：NotesView(appMode: true) 与 _NotesMobileEditorPage）。
 * 编辑器与主页面共享同一个 NotesController 单例，页面本身无需携带数据参数。
 */
export class NotesMainPageParam {
  title: string = '';
}

export class NotesEditorPageParam {
  title: string = '';
}
