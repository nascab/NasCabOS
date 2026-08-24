/** HTTP 头 Map，替代索引签名字典 */
export class HeaderMap {
  private entries: Map<string, string> = new Map();

  set(key: string, value: string): void {
    this.entries.set(key, value);
  }

  get(key: string): string | undefined {
    return this.entries.get(key);
  }

  remove(key: string): void {
    this.entries.delete(key);
  }

  removeProxyHeaders(): HeaderMap {
    const out = new HeaderMap();
    this.entries.forEach((value: string, key: string) => {
      const lower = key.toLowerCase();
      if (lower === 'host' || lower === 'content-length') {
        return;
      }
      out.set(key, value);
    });
    return out;
  }

  static fromMap(source: Map<string, string>): HeaderMap {
    const out = new HeaderMap();
    source.forEach((value: string, key: string) => {
      out.set(key, value);
    });
    return out;
  }

  static fromPlain(source: HeaderMap): HeaderMap {
    return HeaderMap.fromMap(source.entries);
  }

  forEach(fn: (value: string, key: string) => void): void {
    this.entries.forEach(fn);
  }

  toMap(): Map<string, string> {
    return this.entries;
  }
}
