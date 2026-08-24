export class AppIconMap {
  static getSymbol(appId: string): Resource {
    switch (appId) {
      case 'files':
        return $r('sys.symbol.folder');
      case 'photo':
        return $r('sys.symbol.camera');
      case 'video':
        return $r('sys.symbol.play_circle');
      case 'music':
        return $r('sys.symbol.headphones');
      case 'book':
        return $r('sys.symbol.book');
      case 'notes':
        return $r('sys.symbol.doc_text');
      case 'backup':
        return $r('sys.symbol.externaldrive');
      case 'monitor':
        return $r('sys.symbol.waveform');
      case 'docker':
        return $r('sys.symbol.archivebox');
      case 'process':
        return $r('sys.symbol.display');
      case 'service':
        return $r('sys.symbol.gearshape');
      case 'security':
        return $r('sys.symbol.lock_shield');
      case 'user':
        return $r('sys.symbol.person');
      case 'task_center':
        return $r('sys.symbol.list_bullet');
      default:
        return $r('sys.symbol.folder');
    }
  }
}
