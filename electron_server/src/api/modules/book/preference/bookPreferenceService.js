const BookListService = require('../list/bookListService');

class BookPreferenceService {
  constructor(knexBook) {
    this.knexBook = knexBook;
    this.tableName = 'book_preference';
  }

  async getIndexByFileHash(fileHash) {
    const fh = fileHash === undefined || fileHash === null ? '' : String(fileHash).trim();
    if (!fh) return null;
    return await this.knexBook('book_index')
      .where({ file_hash: fh, is_file: 1 })
      .first('id', 'path', 'filename', 'file_hash', 'type', 'ext', 'total_page')
      .catch(() => null);
  }

  async canUserAccessIndex(user, indexRow) {
    const service = new BookListService(this.knexBook);
    return await service.canUserAccessIndex({ user, indexRow });
  }

  async getPreference({ uid, fileHash }) {
    const u = Number(uid || 0) || 0;
    const fh = fileHash === undefined || fileHash === null ? '' : String(fileHash).trim();
    if (!u || !fh) return null;
    return await this.knexBook(this.tableName)
      .where({ uid: u, file_hash: fh })
      .first('uid', 'file_hash', 'font_size', 'spacing', 'flow', 'theme', 'updated_at')
      .catch(() => null);
  }

  async upsertPreference({ uid, fileHash, fontSize, spacing, flow, theme }) {
    const u = Number(uid || 0) || 0;
    const fh = fileHash === undefined || fileHash === null ? '' : String(fileHash).trim();
    if (!u || !fh) return null;

    const fs = Math.max(12, Math.min(28, Number(fontSize || 0) || 16));
    const sp = Math.max(1.0, Math.min(2.4, Number(spacing || 0) || 1.4));
    const fl = String(flow || '').trim() === 'scrolled' ? 'scrolled' : 'paginated';
    const th = String(theme || '').trim() === 'dark' ? 'dark' : 'light';

    const row = {
      uid: u,
      file_hash: fh,
      font_size: fs,
      spacing: sp,
      flow: fl,
      theme: th,
      updated_at: new Date(),
    };

    await this.knexBook(this.tableName).insert(row).onConflict(['uid', 'file_hash']).merge(row);
    return await this.getPreference({ uid: u, fileHash: fh });
  }
}

module.exports = BookPreferenceService;
