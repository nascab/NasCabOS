/** http.request 使用的请求头（字段名与 HTTP 头对应，通过 toMap 转换） */
export class HttpHeaders {
  acceptLanguage: string = '';
  userAgent: string = '';
  authorization: string = '';
  contentType: string = '';

  toMap(): Map<string, string> {
    const map = new Map<string, string>();
    if (this.acceptLanguage.length > 0) {
      map.set('Accept-Language', this.acceptLanguage);
    }
    if (this.userAgent.length > 0) {
      map.set('User-Agent', this.userAgent);
    }
    if (this.authorization.length > 0) {
      map.set('Authorization', this.authorization);
    }
    if (this.contentType.length > 0) {
      map.set('Content-Type', this.contentType);
    }
    return map;
  }
}

export class RefreshTokenBody {
  refreshToken: string = '';

  constructor(refreshToken: string) {
    this.refreshToken = refreshToken;
  }
}

export class LogoutBody {
  refreshToken: string = '';

  constructor(refreshToken: string) {
    this.refreshToken = refreshToken;
  }
}

export class HideAppsBody {
  uid: number = 0;
  hide_app: string[] = [];

  constructor(uid: number, hideApps: string[]) {
    this.uid = uid;
    this.hide_app = hideApps;
  }
}

export class SetAppsOrderBody {
  uid: number = 0;
  order_app: string[] = [];

  constructor(uid: number, orderApp: string[]) {
    this.uid = uid;
    this.order_app = orderApp;
  }
}

export class SetWallpaperBody {
  mode: string = 'fixed';
  name?: string;

  constructor(mode: string, name?: string) {
    this.mode = mode;
    this.name = name;
  }
}

export class DeleteWallpaperBody {
  name: string = '';

  constructor(name: string) {
    this.name = name;
  }
}
