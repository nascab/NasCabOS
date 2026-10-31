/**
 * 文件模块路由参数（文本编辑器 / Office 预览）
 */

/** 文本编辑器路由参数（对齐 Flutter TextEditorPage(filePath)） */
export class TextEditorPageParam {
  title: string = '';
  /** 服务器文件路径（/api/editor/open、/api/editor/save 使用） */
  path: string = '';
}

/** Office 预览路由参数（docx/xlsx，对齐 Flutter _openOfficeFromItem） */
export class OfficeViewerPageParam {
  title: string = '';
  /** 'docx' | 'xlsx' */
  officeType: string = '';
  /** 本地缓存文件路径（Web 侧经拦截器 fd 直供） */
  localPath: string = '';
}
