const axios = require('axios');
const Logger = require('../../utils/logger');
const { filterUiDriverFields } = require('./openlistDriverUi');

class OpenlistApiClient {
  constructor() {
    this.baseUrl = '';
    this.token = '';
    this.tokenExpiresAt = 0;
    this.username = 'admin';
    this.password = '';
  }

  setBaseUrl(url) {
    if (url) this.baseUrl = String(url).replace(/\/$/, '');
  }

  setCredentials({ username, password }) {
    if (username) this.username = String(username);
    if (password !== undefined) this.password = String(password);
    this.token = '';
    this.tokenExpiresAt = 0;
  }

  setToken(token) {
    this.token = token ? String(token) : '';
    this.tokenExpiresAt = this.token ? Date.now() + 47 * 60 * 60 * 1000 : 0;
  }

  async login() {
    if (!this.baseUrl) throw new Error('openlistMount.BASE_URL_MISSING');
    const res = await axios.post(
      `${this.baseUrl}/api/auth/login`,
      { username: this.username, password: this.password },
      { timeout: 15000, validateStatus: () => true }
    );
    const body = res.data || {};
    const token = body.data && body.data.token ? String(body.data.token) : '';
    if (body.code === 200 && token) {
      this.setToken(token);
      return this.token;
    }
    const msg = body.message || `login_failed_${res.status}`;
    try {
      Logger.warn('[openlistApiClient] password login failed, use admin token CLI instead', {
        baseUrl: this.baseUrl,
        username: this.username,
        code: body.code,
        message: msg,
      });
    } catch (_) {}
    throw new Error(String(msg));
  }

  async ensureToken() {
    if (this.token && Date.now() < this.tokenExpiresAt) return this.token;
    return this.login();
  }

  async request(method, apiPath, { params, data } = {}) {
    await this.ensureToken();
    const res = await axios({
      method,
      url: `${this.baseUrl}${apiPath}`,
      params,
      data,
      headers: {
        Authorization: this.token,
        'Content-Type': 'application/json',
      },
      timeout: 30000,
      validateStatus: () => true,
    });
    const body = res.data || {};
    if (res.status === 401) {
      this.token = '';
      await this.login();
      return this.request(method, apiPath, { params, data });
    }
    if (res.status < 200 || res.status >= 300) {
      const msg = body.message || `http_${res.status}`;
      const err = new Error(String(msg));
      err.statusCode = res.status;
      err.responseBody = body;
      throw err;
    }
    return body;
  }

  /** OpenList 返回 data 为 { "Driver Name": { common, additional } }，转为前端可用的数组 */
  _normalizeDriverList(data) {
    if (Array.isArray(data)) return data;
    if (!data || typeof data !== 'object') return [];
    return Object.entries(data).map(([driverName, schema]) => {
      const item = schema && typeof schema === 'object' ? schema : {};
      const common = Array.isArray(item.common) ? item.common : [];
      const additional = Array.isArray(item.additional) ? item.additional : [];
      const uiFields = filterUiDriverFields(additional, driverName);
      return {
        driver: driverName,
        name: driverName,
        common,
        additional: uiFields,
      };
    });
  }

  async listDrivers() {
    const body = await this.request('get', '/api/admin/driver/list');
    const drivers = this._normalizeDriverList(body.data);
    try {
      Logger.info('[openlistApiClient] listDrivers', { count: drivers.length });
    } catch (_) {}
    return drivers;
  }

  async listStorages() {
    const body = await this.request('get', '/api/admin/storage/list', { params: { page: 1, per_page: 500 } });
    const content = body.data && body.data.content;
    return Array.isArray(content) ? content : [];
  }

  async createStorage(payload) {
    const body = await this.request('post', '/api/admin/storage/create', { data: payload });
    return body.data;
  }

  async updateStorage(payload) {
    const body = await this.request('post', '/api/admin/storage/update', { data: payload });
    return body.data;
  }

  async deleteStorage(id) {
    return this.request('post', '/api/admin/storage/delete', { data: { id } });
  }

  async ping() {
    const res = await axios.get(`${this.baseUrl}/ping`, { timeout: 3000, validateStatus: () => true });
    return res.status === 200;
  }
}

module.exports = { OpenlistApiClient };
