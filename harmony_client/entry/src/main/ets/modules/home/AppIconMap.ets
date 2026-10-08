/**
 * 应用图标映射：对应 Flutter 'assets/app_icons/$app.webp'。
 * 图标资源位于 resources/base/media/app_icon_<appId>.webp。
 */
export class AppIconMap {
  static getIcon(appId: string): Resource {
    switch (appId) {
      case 'folder':
        return $r('app.media.app_icon_folder');
      case 'photo':
        return $r('app.media.app_icon_photo');
      case 'movie':
        return $r('app.media.app_icon_movie');
      case 'music':
        return $r('app.media.app_icon_music');
      case 'book':
        return $r('app.media.app_icon_book');
      case 'note':
        return $r('app.media.app_icon_note');
      case 'notes':
        return $r('app.media.app_icon_note');
      case 'backup':
        return $r('app.media.app_icon_backup');
      case 'monitor':
        return $r('app.media.app_icon_monitor');
      case 'docker':
        return $r('app.media.app_icon_docker');
      case 'process':
        return $r('app.media.app_icon_process');
      case 'nascab_service':
        return $r('app.media.app_icon_nascab_service');
      case 'security':
        return $r('app.media.app_icon_security');
      case 'user':
        return $r('app.media.app_icon_user');
      case 'task_center':
        return $r('app.media.app_icon_task_center');
      case 'setting':
        return $r('app.media.app_icon_setting');
      case 'terminal':
        return $r('app.media.app_icon_terminal');
      case 'media_tool':
        return $r('app.media.app_icon_media_tool');
      case 'encrypted':
        return $r('app.media.app_icon_encrypted');
      case 'mounts':
        return $r('app.media.app_icon_mounts');
      case 'share':
        return $r('app.media.app_icon_share');
      case 'file_share_server':
        return $r('app.media.app_icon_share');
      case 'image_view':
        return $r('app.media.app_icon_image_view');
      case 'transmission':
        return $r('app.media.app_icon_transmission');
      case 'editor':
        return $r('app.media.app_icon_editor');
      default:
        return $r('app.media.app_icon_folder');
    }
  }

  /** 服务器平台图标：对应 Flutter assets/home/server_<platform>.png */
  static getServerPlatformIcon(platform: string): Resource {
    const p = platform.toLowerCase();
    if (p.includes('win')) {
      return $r('app.media.server_windows');
    }
    if (p.includes('mac') || p.includes('darwin')) {
      return $r('app.media.server_mac');
    }
    return $r('app.media.server_linux');
  }
}
