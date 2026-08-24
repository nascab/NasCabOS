// 导入多语言翻译
import { I18N_DICT } from './languages/index.js';

// Toast 提示（不阻塞、不抢焦点），每个 toast 独立定时自动消失
function showToast(message, type = 'success') {
  const container = document.getElementById('toast-container');
  if (!container) return;
  const el = document.createElement('div');
  el.className = `toast toast-${type}`;
  el.textContent = message;
  container.appendChild(el);
  setTimeout(() => {
    el.remove();
  }, 2500);
}

// 日志处理：接收推送的日志并去重追加到日志容器
const logContainer = document.getElementById('log-container');
let lastLogSeq = 0;
function appendLog(log) {
  if (!log || log.level === 'debug') return;
  const seq = log.seq || 0;
  if (seq && seq <= lastLogSeq) return;
  lastLogSeq = seq || lastLogSeq;
  const entry = document.createElement('div');
  entry.className = 'log-entry';
  let levelClass = 'log-info';
  if (log.level === 'warn') levelClass = 'log-warn';
  if (log.level === 'error') levelClass = 'log-error';
  const timeSpan = `<span class="log-time">[${log.timestamp}]</span>`;
  const levelSpan = `<span class="${levelClass}">[${log.level.toUpperCase()}]</span>`;
  entry.innerHTML = `${timeSpan} ${levelSpan} ${log.message}`;
  if (log.meta && Object.keys(log.meta).length > 0) {
    entry.innerHTML += ` <span style="color: #888">${JSON.stringify(log.meta)}</span>`;
  }
  logContainer.appendChild(entry);
  logContainer.scrollTop = logContainer.scrollHeight;
  const MAX_LOG_LINES = 1000;
  while (logContainer.children.length > MAX_LOG_LINES) {
    logContainer.removeChild(logContainer.firstChild);
  }
}

if (window.electronAPI.onLogs) {
  window.electronAPI.onLogs(logs => {
    (logs || []).forEach(appendLog);
  });
} else {
  window.electronAPI.onLog(log => {
    appendLog(log);
  });
}

const macFullDiskAccessModal = document.getElementById('mac-full-disk-access-modal');
const openFullDiskAccessSettingsBtn = document.getElementById('open-full-disk-access-settings');
const closeFullDiskAccessModalBtn = document.getElementById('close-full-disk-access-modal');
const uiLanguageModal = document.getElementById('ui-language-modal');
const confirmUiLanguageBtn = document.getElementById('confirm-ui-language');
const aboutUpdateStatusEl = document.getElementById('about-update-status');
const aboutUpdateGoDownloadBtn = document.getElementById('about-update-go-download-btn');
const featureAccessDirectorySection = document.getElementById('feature-access-directory-section');
const featureAccessDirectoryList = document.getElementById('feature-access-directory-list');
const featureAccessAddBtn = document.getElementById('feature-access-add-btn');
const featureAccessSaveBtn = document.getElementById('feature-access-save-btn');
const featureTerminalEnabledCheckbox = document.getElementById('feature-terminal-enabled');
const featureTerminalSaveBtn = document.getElementById('feature-terminal-save-btn');
let featureAccessState = { mode: 'all', dirs: [], terminalEnabled: true };

function showMacFullDiskAccessModal() {
  if (!macFullDiskAccessModal) return;
  macFullDiskAccessModal.classList.remove('hidden');
}

function hideMacFullDiskAccessModal() {
  if (!macFullDiskAccessModal) return;
  macFullDiskAccessModal.classList.add('hidden');
}

if (openFullDiskAccessSettingsBtn) {
  openFullDiskAccessSettingsBtn.addEventListener('click', e => {
    e.preventDefault();
    window.electronAPI.openLink('x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles');
  });
}

if (closeFullDiskAccessModalBtn) {
  closeFullDiskAccessModalBtn.addEventListener('click', e => {
    e.preventDefault();
    hideMacFullDiskAccessModal();
  });
}

function getSystemPreferredLanguage() {
  const sys = (navigator && navigator.language) || 'en-US';
  const lang = sys.toLowerCase();
  if (lang.startsWith('en')) return 'en-US';
  if (lang.startsWith('zh')) return 'zh-CN';
  if (lang.startsWith('ja')) return 'ja-JP';
  if (lang.startsWith('ko')) return 'ko-KR';
  if (lang.startsWith('es')) return 'es-ES';
  if (lang.startsWith('pt')) return 'pt-BR';
  if (lang.startsWith('fr')) return 'fr-FR';
  if (lang.startsWith('de')) return 'de-DE';
  if (lang.startsWith('ru')) return 'ru-RU';
  if (lang.startsWith('id')) return 'id-ID';
  if (lang.startsWith('vi')) return 'vi-VN';
  if (lang.startsWith('th')) return 'th-TH';
  if (lang.startsWith('ar')) return 'ar-SA';
  return 'en-US';
}

function showUiLanguageModal(defaultLang) {
  if (!uiLanguageModal) return;
  const initSelect = document.getElementById('ui-language-init-select');
  if (initSelect) {
    const valid = [...initSelect.options].some(o => o.value === defaultLang);
    initSelect.value = valid ? defaultLang : 'en-US';
  }
  uiLanguageModal.classList.remove('hidden');
}

function hideUiLanguageModal() {
  if (!uiLanguageModal) return;
  uiLanguageModal.classList.add('hidden');
}


async function checkMacFullDiskAccessOnStart() {
  try {
    if (!window.nascab || typeof window.nascab.getMacFullDiskAccessStatus !== 'function') return;
    const status = await window.nascab.getMacFullDiskAccessStatus();
    if (status && status.platform === 'darwin' && status.granted === false) {
      showMacFullDiskAccessModal();
    }
  } catch {}
}

function renderServiceAddressList(containerId, addresses) {
  const container = document.getElementById(containerId);
  if (!container) return;
  container.replaceChildren();
  if (!Array.isArray(addresses) || addresses.length === 0) {
    container.textContent = '—';
    return;
  }
  addresses.forEach((address, index) => {
    const link = document.createElement('a');
    link.href = '#';
    link.className = 'status-address-link';
    link.textContent = address;
    link.onclick = e => {
      e.preventDefault();
      window.electronAPI.openLink(address);
    };
    if (index > 0) {
      container.appendChild(document.createElement('br'));
    }
    container.appendChild(link);
  });
}

function applyServiceAddressUi(status) {
  const ipAddresses = Array.isArray(status.ipAddresses) ? status.ipAddresses : [];
  const fallbackIp = ipAddresses[0] || status.ip || '127.0.0.1';
  const httpAddresses = Array.isArray(status.httpAddresses) && status.httpAddresses.length > 0
    ? status.httpAddresses
    : (status.port && fallbackIp ? [`http://${fallbackIp}:${status.port}`] : []);
  const httpsAddresses = Array.isArray(status.httpsAddresses) && status.httpsAddresses.length > 0
    ? status.httpsAddresses
    : (status.httpsPort && fallbackIp ? [`https://${fallbackIp}:${status.httpsPort}`] : []);
  renderServiceAddressList('status-server-link', httpAddresses);
  renderServiceAddressList('status-server-link-https', httpsAddresses);
}

async function loadStatus() {
  try {
    const status = await window.electronAPI.getServiceStatus();
    const expressEl = document.getElementById('status-express');
    expressEl.textContent = status.express ? t('status.expressRunning') : t('status.expressStopped');
    expressEl.className = status.express ? 'status-value status-badge status-running' : 'status-value status-badge status-stopped';
    applyServiceAddressUi(status);
    applyDatabaseTotalBytesFromStatus(status);
    return status;
  } catch {}
  return null;
}

let initialAdminPasswordVisible = false;
let initialAdminCache = { isInitialAdmin: false, username: null, password: null };

function renderInitialAdmin(info) {
  const block = document.getElementById('initial-admin-block');
  if (!block) return;
  if (!info || !info.isInitialAdmin) {
    block.classList.add('hidden');
    return;
  }
  block.classList.remove('hidden');
  const u = document.getElementById('initial-admin-username');
  const p = document.getElementById('initial-admin-password');
  const toggle = document.getElementById('initial-admin-toggle-password');
  if (u) u.textContent = info.username || '-';
  if (p) p.textContent = initialAdminPasswordVisible ? info.password || '' : '******';
  if (toggle) toggle.textContent = initialAdminPasswordVisible ? t('common.hide') : t('common.show');
}

async function loadInitialAdmin() {
  try {
    if (!window.electronAPI.getInitialAdminInfo) return;
    const info = await window.electronAPI.getInitialAdminInfo();
    initialAdminCache = info || { isInitialAdmin: false, username: null, password: null };
    if (!initialAdminCache.isInitialAdmin) initialAdminPasswordVisible = false;
    renderInitialAdmin(initialAdminCache);
  } catch {}
}

// 管理员信息：未设置管理员时隐藏修改密码卡片
async function loadAdmin() {
  const admin = await window.electronAPI.getAdminInfo();
  document.getElementById('admin-username').textContent = admin.username || 'Not set';
  const input = document.getElementById('admin-username-input');
  if (input) input.value = admin.username || '';
}

function base64EncodeUtf8(input) {
  const bytes = new TextEncoder().encode(String(input));
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

// 与 createSuperAdmin 接口对齐：全同字符、连续数字、与用户名相同
function isAllSameChars(value) {
  const s = String(value || '');
  if (!s || s.length < 2) return false;
  const c = s[0];
  for (let i = 1; i < s.length; i++) {
    if (s[i] !== c) return false;
  }
  return true;
}

function isConsecutiveDigits(value) {
  const s = String(value || '');
  if (s.length < 3 || !/^\d+$/.test(s)) return false;
  let dir = 0;
  for (let i = 1; i < s.length; i++) {
    const diff = Number(s[i]) - Number(s[i - 1]);
    if (diff !== 1 && diff !== -1) return false;
    if (dir === 0) dir = diff;
    else if (diff !== dir) return false;
  }
  return true;
}

function isWeakPassword(value, username) {
  if (!value || value.length < 6) return true;
  if (isAllSameChars(value)) return true;
  if (isConsecutiveDigits(value)) return true;
  if (username && String(value) === String(username).trim()) return true;
  return false;
}

function validateAdminUsername(username) {
  const s = typeof username === 'string' ? username.trim() : '';
  if (!s) return 'admin.usernameRequired';
  if (s.length < 3 || s.length > 20) return 'admin.usernameLengthInvalid';
  if (!/^[a-zA-Z0-9_]+$/.test(s)) return 'admin.usernameFormatInvalid';
  return null;
}

function validateAdminPassword(password, username) {
  const p = typeof password === 'string' ? password : '';
  if (!p) return null;
  if (p.length < 6) return 'admin.passwordTooShort';
  if (isAllSameChars(p)) return 'admin.passwordRepeatedChar';
  if (isConsecutiveDigits(p)) return 'admin.passwordConsecutiveNumbers';
  if (username && p === String(username).trim()) return 'admin.passwordSameAsUsername';
  return null;
}

// 服务端返回的错误码 -> 前端 i18n key（国际化提示）
const ADMIN_ERROR_I18N_KEYS = {
  USERNAME_REQUIRED: 'admin.usernameRequired',
  USERNAME_LENGTH_INVALID: 'admin.usernameLengthInvalid',
  USERNAME_FORMAT_INVALID: 'admin.usernameFormatInvalid',
  USERNAME_EXISTS: 'admin.usernameExists',
  PASSWORD_REQUIRED: 'admin.passwordRequired',
  PASSWORD_TOO_SHORT: 'admin.passwordTooShort',
  'validation.PASSWORD_REPEATED_CHAR': 'admin.passwordRepeatedChar',
  'validation.PASSWORD_CONSECUTIVE_NUMBERS': 'admin.passwordConsecutiveNumbers',
  'validation.PASSWORD_SAME_AS_USERNAME': 'admin.passwordSameAsUsername',
  NO_CHANGES: 'admin.noChanges',
  ADMIN_NOT_FOUND: 'admin.updateFailed',
  FAILED: 'admin.updateFailed',
};

async function loadAdminSecurity() {
  try {
    if (!window.electronAPI.getAdminSecurity) return;
    const r = await window.electronAPI.getAdminSecurity();
    const enabled = !!(r && r.twofaEnabled);
    const statusEl = document.getElementById('admin-2fa-status');
    if (statusEl) statusEl.textContent = enabled ? t('admin.twofaEnabled') : t('admin.twofaDisabled');
    const btn = document.getElementById('admin-2fa-reset-btn');
    if (btn) btn.classList.toggle('hidden', !enabled);
  } catch {}
}

const adminUpdateForm = document.getElementById('admin-update-form');
if (adminUpdateForm) {
  adminUpdateForm.addEventListener('submit', async e => {
    e.preventDefault();
    const usernameRaw = document.getElementById('admin-username-input').value;
    const password = document.getElementById('admin-new-password').value;
    const usernameTrimmed = typeof usernameRaw === 'string' ? usernameRaw.trim() : '';
    const passwordTrimmed = typeof password === 'string' ? password.trim() : '';

    if (usernameTrimmed) {
      const usernameErr = validateAdminUsername(usernameTrimmed);
      if (usernameErr) {
        showToast(t(usernameErr), 'error');
        return;
      }
    }
    if (passwordTrimmed) {
      const pwdErr = validateAdminPassword(passwordTrimmed, usernameTrimmed);
      if (pwdErr) {
        showToast(t(pwdErr), 'error');
        return;
      }
    }

    const payload = {};
    if (usernameTrimmed) payload.username = usernameTrimmed;
    if (passwordTrimmed) payload.password = `b64:${base64EncodeUtf8(passwordTrimmed)}`;
    try {
      const result = await window.electronAPI.updateAdmin(payload);
      if (result && result.success) {
        showToast(t('admin.updateSuccess'), 'success');
        document.getElementById('admin-new-password').value = '';
        await loadAdmin();
        await loadInitialAdmin();
        await loadAdminSecurity();
      } else {
        const code = (result && result.error) || 'FAILED';
        const i18nKey = ADMIN_ERROR_I18N_KEYS[code] || 'admin.updateFailed';
        showToast(t(i18nKey), 'error');
      }
    } catch (err) {
      showToast(t('admin.updateFailed'), 'error');
    }
  });
}

const reset2faBtn = document.getElementById('admin-2fa-reset-btn');
if (reset2faBtn) {
  reset2faBtn.addEventListener('click', async e => {
    e.preventDefault();
    const ok = confirm(t('admin.reset2faConfirm'));
    if (!ok) return;
    const result = await window.electronAPI.resetAdmin2fa();
    if (result && result.success) {
      alert(t('admin.reset2faSuccess'));
      await loadAdminSecurity();
    } else {
      alert(t('admin.reset2faFailed'));
    }
  });
}

// 设置：读取启动选项与版本，并处理语言选择
async function loadSettings() {
  const settings = await window.electronAPI.getSettings();
  document.getElementById('start-on-boot').checked = settings.startOnBoot;
  document.getElementById('minimize-on-start').checked = settings.minimizeOnStart;
  document.getElementById('auto-discover-server').checked = settings.autoDiscoverServer !== false;

  const version = await window.electronAPI.getVersion();
  document.getElementById('app-version').textContent = version;

  // 语言初始化：获取当前语言并应用
  const langSetting = await window.nascab.getLanguage();
  // 支持所有语言（含韩语、越南语、印尼语）
  const validLanguages = ['en-US', 'zh-CN', 'ja-JP', 'ko-KR', 'es-ES', 'pt-BR', 'fr-FR', 'de-DE', 'ru-RU', 'id-ID', 'vi-VN', 'th-TH', 'ar-SA'];
  let lang = validLanguages.includes(langSetting) ? langSetting : null;
  const systemLang = getSystemPreferredLanguage();
  const select = document.getElementById('ui-language');
  const appliedLang = lang || systemLang;
  if (select) select.value = appliedLang;
  applyI18n(appliedLang);
  if (!lang) {
    showUiLanguageModal(systemLang);
  }

  await loadFeatureAccessSettings();
}

document.getElementById('save-settings-btn').addEventListener('click', async () => {
  const settings = {
    startOnBoot: document.getElementById('start-on-boot').checked,
    minimizeOnStart: document.getElementById('minimize-on-start').checked,
    autoDiscoverServer: document.getElementById('auto-discover-server').checked,
  };
  const ok = await window.electronAPI.saveSettings(settings);
  if (ok) {
    showToast(t('settings.savedTip'), 'success');
  } else {
    showToast(t('admin.updateFailed'), 'error');
  }
});

function normalizeFeatureAccessDirs(pathList) {
  return [...new Set((Array.isArray(pathList) ? pathList : []).map(item => String(item || '').trim()).filter(Boolean))];
}

function setFeatureAccessState(nextState) {
  featureAccessState = {
    mode: nextState && nextState.mode === 'specified' ? 'specified' : 'all',
    dirs: normalizeFeatureAccessDirs(nextState && Array.isArray(nextState.dirs) ? nextState.dirs : []),
    terminalEnabled: !(nextState && Object.prototype.hasOwnProperty.call(nextState, 'terminalEnabled')) || !!nextState.terminalEnabled,
  };
  renderFeatureAccessSettings();
}

function renderFeatureAccessSettings() {
  const mode = featureAccessState.mode === 'specified' ? 'specified' : 'all';
  document.querySelectorAll('input[name="feature-access-mode"]').forEach(input => {
    input.checked = input.value === mode;
  });
  if (featureTerminalEnabledCheckbox) {
    featureTerminalEnabledCheckbox.checked = featureAccessState.terminalEnabled !== false;
  }

  if (featureAccessDirectorySection) {
    featureAccessDirectorySection.classList.toggle('hidden', mode !== 'specified');
  }
  if (!featureAccessDirectoryList) return;

  if (mode !== 'specified') {
    featureAccessDirectoryList.innerHTML = '';
    return;
  }

  if (!featureAccessState.dirs.length) {
    featureAccessDirectoryList.innerHTML = `<div class="feature-access-empty">${t('featureSettings.empty')}</div>`;
    return;
  }

  featureAccessDirectoryList.innerHTML = featureAccessState.dirs
    .map((dirPath, index) => {
      return `
        <div class="feature-access-directory-item">
          <div class="feature-access-directory-path">${escapeHtml(dirPath)}</div>
          <button
            type="button"
            class="btn btn-secondary btn-small feature-access-remove-btn"
            data-feature-access-remove="${index}"
          >${escapeHtml(t('common.remove'))}</button>
        </div>
      `;
    })
    .join('');
}

async function loadFeatureAccessSettings() {
  try {
    if (!window.electronAPI.getFeatureAccessScope) return;
    const data = await window.electronAPI.getFeatureAccessScope();
    setFeatureAccessState(data || { mode: 'all', dirs: [], terminalEnabled: true });
  } catch (_) {
    setFeatureAccessState({ mode: 'all', dirs: [], terminalEnabled: true });
  }
}

document.querySelectorAll('input[name="feature-access-mode"]').forEach(input => {
  input.addEventListener('change', e => {
    setFeatureAccessState({
      ...featureAccessState,
      mode: e.target && e.target.value === 'specified' ? 'specified' : 'all',
    });
  });
});

if (featureAccessDirectoryList) {
  featureAccessDirectoryList.addEventListener('click', e => {
    const button = e.target && e.target.closest('[data-feature-access-remove]');
    if (!button) return;
    const index = Number(button.getAttribute('data-feature-access-remove'));
    if (!Number.isInteger(index) || index < 0) return;
    const nextDirs = featureAccessState.dirs.filter((_, itemIndex) => itemIndex !== index);
    setFeatureAccessState({ ...featureAccessState, dirs: nextDirs });
  });
}

if (featureAccessAddBtn) {
  featureAccessAddBtn.addEventListener('click', async () => {
    try {
      const selected = await window.electronAPI.selectDirectories();
      if (!Array.isArray(selected) || selected.length === 0) return;
      setFeatureAccessState({
        ...featureAccessState,
        dirs: normalizeFeatureAccessDirs(featureAccessState.dirs.concat(selected)),
      });
    } catch (_) {
      showToast(t('featureSettings.selectFailed'), 'error');
    }
  });
}

if (featureAccessSaveBtn) {
  featureAccessSaveBtn.addEventListener('click', async () => {
    if (featureTerminalEnabledCheckbox) {
      featureAccessState.terminalEnabled = !!featureTerminalEnabledCheckbox.checked;
    }
    if (featureAccessState.mode === 'specified' && featureAccessState.dirs.length === 0) {
      showToast(t('featureSettings.specifiedEmpty'), 'error');
      return;
    }
    try {
      const ok = await window.electronAPI.saveFeatureAccessScope(featureAccessState);
      if (ok) {
        showToast(t('featureSettings.saved'), 'success');
      } else {
        showToast(t('admin.updateFailed'), 'error');
      }
    } catch (_) {
      showToast(t('admin.updateFailed'), 'error');
    }
  });
}

if (featureTerminalSaveBtn) {
  featureTerminalSaveBtn.addEventListener('click', async () => {
    if (featureTerminalEnabledCheckbox) {
      featureAccessState.terminalEnabled = !!featureTerminalEnabledCheckbox.checked;
    }
    try {
      const ok = await window.electronAPI.saveFeatureAccessScope(featureAccessState);
      if (ok) {
        showToast(t('featureSettings.saved'), 'success');
      } else {
        showToast(t('admin.updateFailed'), 'error');
      }
    } catch (_) {
      showToast(t('admin.updateFailed'), 'error');
    }
  });
}

// 语言选择变更：保存到配置并应用到页面
document.getElementById('ui-language').addEventListener('change', async e => {
  const val = e.target.value;
  await window.nascab.setLanguage(val);
  applyI18n(val);
});

// Links
document.getElementById('official-site-link').addEventListener('click', e => {
  e.preventDefault();
  window.electronAPI.openLink('https://nas.cab');
});

// 将当前界面语言转为外链用的 language 参数（如 ja-JP -> ja）
function getLanguageParamForUrl() {
  const lang = (CURRENT_LANG || 'en-US').toLowerCase();
  if (lang.startsWith('zh')) return 'zh';
  if (lang.startsWith('ja')) return 'ja';
  if (lang.startsWith('ko')) return 'ko';
  if (lang.startsWith('en')) return 'en';
  if (lang.startsWith('es')) return 'es';
  if (lang.startsWith('pt')) return 'pt';
  if (lang.startsWith('fr')) return 'fr';
  if (lang.startsWith('de')) return 'de';
  if (lang.startsWith('ru')) return 'ru';
  if (lang.startsWith('id')) return 'id';
  if (lang.startsWith('vi')) return 'vi';
  if (lang.startsWith('th')) return 'th';
  if (lang.startsWith('ar')) return 'ar';
  return 'en';
}

// 设置：用户协议与隐私政策（系统浏览器新标签页打开）
function openLegalDocumentInBrowser(baseUrl) {
  const lang = getLanguageParamForUrl();
  const sep = baseUrl.includes('?') ? '&' : '?';
  const url = `${baseUrl}${sep}language=${encodeURIComponent(lang)}`;
  window.electronAPI.openLink(url);
}

document.getElementById('settings-open-user-agreement')?.addEventListener('click', e => {
  e.preventDefault();
  openLegalDocumentInBrowser('https://nas.cab/others/agreement.html');
});

document.getElementById('settings-open-privacy-policy')?.addEventListener('click', e => {
  e.preventDefault();
  openLegalDocumentInBrowser('https://nas.cab/others/privacy.html');
});

// Tutorial cards: open external links with current UI language as query param
document.querySelectorAll('.tutorial-card').forEach(el => {
  el.addEventListener('click', e => {
    e.preventDefault();
    const baseUrl = el.getAttribute('data-url');
    if (!baseUrl) return;
    const lang = getLanguageParamForUrl();
    const sep = baseUrl.includes('?') ? '&' : '?';
    const url = `${baseUrl}${sep}language=${encodeURIComponent(lang)}`;
    window.electronAPI.openLink(url);
  });
});

// 自动更新：仅检测，有更新时在「关于」卡片显示状态 +「去下载」按钮，点击用浏览器打开 https://nas.cab#download
if (window.nascab && typeof window.nascab.onUpdateAvailable === 'function') {
  window.nascab.onUpdateAvailable(info => {
    if (aboutUpdateStatusEl) {
      aboutUpdateStatusEl.textContent = t('about.updateStatusNew') || 'New version available';
    }
    if (aboutUpdateGoDownloadBtn) {
      aboutUpdateGoDownloadBtn.classList.remove('hidden');
    }
  });
}

if (window.nascab && typeof window.nascab.onUpdateStatus === 'function') {
  window.nascab.onUpdateStatus(status => {
    if (!status) return;
    if (aboutUpdateStatusEl) {
      if (status.status === 'checking') {
        aboutUpdateStatusEl.textContent = t('about.updateChecking');
      } else if (status.status === 'no-update') {
        aboutUpdateStatusEl.textContent = t('about.updateStatusText');
      } else if (status.status === 'error') {
        aboutUpdateStatusEl.textContent = t('about.updateError');
      }
      if (status.status !== 'checking' && aboutUpdateGoDownloadBtn) {
        aboutUpdateGoDownloadBtn.classList.add('hidden');
      }
    }
  });
}

if (aboutUpdateGoDownloadBtn) {
  aboutUpdateGoDownloadBtn.addEventListener('click', e => {
    e.preventDefault();
    window.electronAPI.openLink('https://nas.cab#download');
  });
}

if (confirmUiLanguageBtn) {
  confirmUiLanguageBtn.addEventListener('click', async e => {
    e.preventDefault();
    if (!uiLanguageModal) return;
    const initSelect = document.getElementById('ui-language-init-select');
    const lang =
      initSelect && initSelect.value ? initSelect.value : getSystemPreferredLanguage();
    await window.nascab.setLanguage(lang);
    const select = document.getElementById('ui-language');
    if (select) select.value = lang;
    applyI18n(lang);
    hideUiLanguageModal();
  });
}

// 简单i18n：定义文案字典并根据data-i18n属性替换文本
let CURRENT_LANG = 'en-US';
let lastDatabaseTotalBytes = null;

function formatByteSize(bytes) {
  if (bytes == null || !Number.isFinite(bytes)) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let v = bytes;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i += 1;
  }
  const nf = new Intl.NumberFormat(CURRENT_LANG, { maximumFractionDigits: i === 0 ? 0 : 2 });
  return `${nf.format(v)} ${units[i]}`;
}

function refreshDatabaseTotalSizeLabel() {
  const el = document.getElementById('database-total-size');
  if (!el) return;
  el.textContent = formatByteSize(lastDatabaseTotalBytes);
}

function applyDatabaseTotalBytesFromStatus(statusData) {
  if (statusData && typeof statusData.databaseTotalBytes === 'number' && Number.isFinite(statusData.databaseTotalBytes)) {
    lastDatabaseTotalBytes = statusData.databaseTotalBytes;
    refreshDatabaseTotalSizeLabel();
  }
}

function t(key) {
  const dict = I18N_DICT[CURRENT_LANG] || I18N_DICT['en-US'];
  const fallback = I18N_DICT['en-US'] || {};
  return dict[key] || fallback[key] || key;
}

function applyI18n(lang) {
  CURRENT_LANG = I18N_DICT[lang] ? lang : 'en-US';
  const dict = I18N_DICT[lang] || I18N_DICT['en-US'];
  const fallback = I18N_DICT['en-US'] || {};
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const key = el.getAttribute('data-i18n');
    if (dict[key]) {
      el.textContent = dict[key];
    }
  });
  document.querySelectorAll('[data-i18n-title]').forEach(el => {
    const key = el.getAttribute('data-i18n-title');
    const text = String(dict[key] || fallback[key] || '').trim();
    if (text) el.setAttribute('title', text);
  });
  document.querySelectorAll('[data-i18n-aria-label]').forEach(el => {
    const key = el.getAttribute('data-i18n-aria-label');
    const text = String(dict[key] || fallback[key] || '').trim();
    if (text) el.setAttribute('aria-label', text);
  });
  renderInitialAdmin(initialAdminCache);
  renderFeatureAccessSettings();
  loadAdminSecurity();
  refreshDatabaseTotalSizeLabel();
  if (document.getElementById('process-tab') && document.getElementById('process-tab').classList.contains('active')) {
    loadProcessList();
  }
}

const PROCESS_UNKNOWN_NAME_KEY = 'process.worker.unknown.name';

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/** 未知进程时附带 workerPath / role，便于对照实际脚本 */
function formatProcessDisplayName(row) {
  const nameKey = row && row.nameKey ? String(row.nameKey) : '';
  const base = t(nameKey || '');
  if (nameKey === PROCESS_UNKNOWN_NAME_KEY) {
    const raw = String((row && row.workerPath) || (row && row.role) || '').trim();
    if (raw) {
      return `${base}（${escapeHtml(raw)}）`;
    }
  }
  return base;
}

function renderProcessList(list) {
  const container = document.getElementById('process-list-container');
  if (!container) return;
  const rows = Array.isArray(list) ? list : [];
  if (!rows.length) {
    container.innerHTML = `<div class="status-item"><span class="status-label">${t('process.empty')}</span></div>`;
    return;
  }
  container.innerHTML = rows
    .map(row => {
      return `
        <div class="process-item">
          <div class="process-item-row">
            <div class="process-item-label">${t('process.name')}</div>
            <div class="process-item-value">${formatProcessDisplayName(row)}</div>
          </div>
          <div class="process-item-row">
            <div class="process-item-label">${t('process.purpose')}</div>
            <div class="process-item-value">${t(row.purposeKey || '')}</div>
          </div>
        </div>
      `;
    })
    .join('');
}

async function loadProcessList() {
  try {
    if (!window.electronAPI.getProcessList) return;
    const list = await window.electronAPI.getProcessList();
    renderProcessList(list);
  } catch (_) {}
}

/** 仅在「进程」页内轮询；离开页面即停止 */
let processListPollTimer = null;
const PROCESS_LIST_POLL_MS = 2000;

function stopProcessListPolling() {
  if (processListPollTimer != null) {
    clearInterval(processListPollTimer);
    processListPollTimer = null;
  }
}

function startProcessListPolling() {
  stopProcessListPolling();
  loadProcessList();
  processListPollTimer = setInterval(loadProcessList, PROCESS_LIST_POLL_MS);
}

// Tab 切换：根据侧边栏点击切换内容面板；进入「进程」才开始拉取并轮询，离开则停止
const tabs = document.querySelectorAll('.sidebar-menu li');
const contents = document.querySelectorAll('.tab-content');
tabs.forEach(tab => {
  tab.addEventListener('click', () => {
    tabs.forEach(t => t.classList.remove('active'));
    contents.forEach(c => c.classList.remove('active'));
    tab.classList.add('active');
    const target = tab.getAttribute('data-target');
    document.getElementById(target).classList.add('active');
    if (target === 'admin-tab') {
      loadAdmin();
      loadAdminSecurity();
    }
    if (target === 'process-tab') {
      startProcessListPolling();
    } else {
      stopProcessListPolling();
    }
  });
});

// Initialize
loadStatus();
loadAdmin();
loadSettings();
loadInitialAdmin();
loadAdminSecurity();
checkMacFullDiskAccessOnStart();
// 稳妥刷新：未启动时短轮询（500ms），启动后 1s；配合主进程 API 启动成功后的即时推送，确保界面必能刷新
function scheduleStatusPoll() {
  loadStatus().then(status => {
    const nextMs = (status && status.express) ? 1000 : 500;
    setTimeout(scheduleStatusPoll, nextMs);
  });
}
setTimeout(scheduleStatusPoll, 500);
setInterval(loadInitialAdmin, 2000);

const initialAdminTogglePwd = document.getElementById('initial-admin-toggle-password');
if (initialAdminTogglePwd) {
  initialAdminTogglePwd.addEventListener('click', e => {
    e.preventDefault();
    initialAdminPasswordVisible = !initialAdminPasswordVisible;
    renderInitialAdmin(initialAdminCache);
  });
}

const goAdminLink = document.getElementById('initial-admin-go-admin');
if (goAdminLink) {
  goAdminLink.addEventListener('click', e => {
    e.preventDefault();
    const targetTab = document.querySelector('.sidebar-menu li[data-target="admin-tab"]');
    if (targetTab) targetTab.click();
  });
}

// 初始化时也加载路径信息
window.electronAPI.getServiceStatus().then(loadPaths);

// 如果支持推送服务状态事件，则订阅并直接更新状态（主进程 API 启动成功会立即推送，确保界面必刷新）
if (window.nascab && typeof window.nascab.onServiceStatus === 'function') {
  window.nascab.onServiceStatus(data => {
    const express = !!data.expressStarted;
    const expressEl = document.getElementById('status-express');
    expressEl.textContent = express ? t('status.expressRunning') : t('status.expressStopped');
    expressEl.className = express ? 'status-value status-badge status-running' : 'status-value status-badge status-stopped';
    applyServiceAddressUi(data);
    loadPaths(data);
  });
}

if (window.nascab && typeof window.nascab.onMacFullDiskAccessStatus === 'function') {
  window.nascab.onMacFullDiskAccessStatus(status => {
    if (status && status.platform === 'darwin' && status.granted === false) {
      showMacFullDiskAccessModal();
    }
  });
}

// 其他信息：加载数据库与缓存目录并可点击打开
async function loadPaths(statusData) {
  try {
    const db = statusData && statusData.databaseDir ? statusData.databaseDir : '';
    const cache = statusData && statusData.cacheDir ? statusData.cacheDir : '';
    const dbLink = document.getElementById('open-db-dir-link');
    const cacheLink = document.getElementById('open-cache-dir-link');
    dbLink.textContent = db ? db : 'N/A';
    cacheLink.textContent = cache ? cache : 'N/A';
    dbLink.onclick = e => {
      window.electronAPI.openPath(db);
    };
    cacheLink.onclick = e => {
      window.electronAPI.openPath(cache);
    };
    applyDatabaseTotalBytesFromStatus(statusData);
  } catch (e) {
    console.log('e', e);
  }
}

const databaseVacuumModal = document.getElementById('database-vacuum-modal');
const databaseVacuumBtn = document.getElementById('database-vacuum-btn');
const databaseVacuumCancelBtn = document.getElementById('database-vacuum-cancel-btn');
const databaseVacuumConfirmBtn = document.getElementById('database-vacuum-confirm-btn');

function showDatabaseVacuumModal() {
  if (databaseVacuumModal) databaseVacuumModal.classList.remove('hidden');
}

function hideDatabaseVacuumModal() {
  if (databaseVacuumModal) databaseVacuumModal.classList.add('hidden');
}

if (databaseVacuumBtn) {
  databaseVacuumBtn.addEventListener('click', e => {
    e.preventDefault();
    showDatabaseVacuumModal();
  });
}

if (databaseVacuumCancelBtn) {
  databaseVacuumCancelBtn.addEventListener('click', e => {
    e.preventDefault();
    hideDatabaseVacuumModal();
  });
}

if (databaseVacuumConfirmBtn) {
  databaseVacuumConfirmBtn.addEventListener('click', async e => {
    e.preventDefault();
    hideDatabaseVacuumModal();
    const btn = databaseVacuumBtn;
    if (btn) btn.disabled = true;
    try {
      const vacuumFn = window.nascab && window.nascab.vacuumAllDatabases ? window.nascab.vacuumAllDatabases : window.electronAPI.vacuumAllDatabases;
      const result = typeof vacuumFn === 'function' ? await vacuumFn() : null;
      if (result && result.success) {
        showToast(t('status.databaseVacuumSuccess'), 'success');
        try {
          const s = await window.electronAPI.getServiceStatus();
          applyDatabaseTotalBytesFromStatus(s);
        } catch (_) {}
      } else {
        showToast(t('status.databaseVacuumFailed'), 'error');
      }
    } catch (_) {
      showToast(t('status.databaseVacuumFailed'), 'error');
    } finally {
      if (btn) btn.disabled = false;
    }
  });
}

// ==================== Cache Statistics & Cleanup ====================

const CACHE_FOLDERS = [
  { key: 'tinyCache', i18n: 'cache.folder.tinyCache' },
  { key: 'musicInnerCover', i18n: 'cache.folder.musicInnerCover' },
  { key: 'nfoAvatar', i18n: 'cache.folder.nfoAvatar' },
  { key: 'nfoPoster', i18n: 'cache.folder.nfoPoster' },
  { key: 'subtitleUpload', i18n: 'cache.folder.subtitleUpload' },
  { key: 'subtitleVtt', i18n: 'cache.folder.subtitleVtt' },
  { key: 'transcode', i18n: 'cache.folder.transcode' },
  { key: 'mapTiles', i18n: 'cache.folder.mapTiles' },
];

const CACHE_TTL_MS = 10 * 60 * 1000; // 10 minutes

let cacheStatsState = {
  visible: false,
  scanning: false,
  cleaning: false,
  scanJobId: null,
  unsubScanProgress: null,
  unsubScanComplete: null,
  unsubCleanProgress: null,
  unsubCleanComplete: null,
  // In-memory cache: { folderKey: { fileCount, totalSize, timestamp } }
  folderCache: {},
  // Current scan results for the list display
  folderResults: {},
  // Completion tracking
  scannedCount: 0,
  lastCacheDir: null,
  // Checked state for folders (preserved across re-renders)
  checkedFolders: {},
};

function resetCacheStatsState() {
  cacheStatsState.scanning = false;
  cacheStatsState.cleaning = false;
  cacheStatsState.scanJobId = null;
  cacheStatsState.scannedCount = 0;
  cacheStatsState.folderResults = {};
  cacheStatsState.checkedFolders = {};
}

function getCacheStatsApi() {
  return window.nascab && typeof window.nascab.scanCacheFolders === 'function'
    ? window.nascab
    : window.electronAPI;
}

function buildCacheStatsListHtml() {
  const { folderResults, scanning, cleaning, folderCache } = cacheStatsState;
  const now = Date.now();
  return CACHE_FOLDERS.map(f => {
    const result = folderResults[f.key];
    const cached = folderCache[f.key];
    const hasCached = cached && (now - cached.timestamp) < CACHE_TTL_MS;
    const isScanning = scanning && !result;
    const isDone = !!result;
    const isPending = scanning && !isDone && !isScanning;

    let metaHtml = '';
    if (isDone) {
      metaHtml = `<span class="cache-stats-item-count">${result.fileCount.toLocaleString()}</span> ${t('cache.fileCount')} &middot; <span class="cache-stats-item-size">${formatByteSize(result.totalSize)}</span>`;
    } else if (isScanning) {
      metaHtml = `<span class="cache-stats-item-scanning">${t('cache.scanning')}</span>`;
    } else if (hasCached) {
      metaHtml = `<span class="cache-stats-item-count">${cached.fileCount.toLocaleString()}</span> ${t('cache.fileCount')} &middot; <span class="cache-stats-item-size">${formatByteSize(cached.totalSize)}</span>`;
    } else {
      metaHtml = `<span class="cache-stats-item-scanning" style="color:var(--text-muted)">—</span>`;
    }

    const disabled = scanning || cleaning || (!isDone && !hasCached);
    const checked = cacheStatsState.checkedFolders[f.key] ? 'checked' : '';
    const baseDir = cacheStatsState.lastCacheDir || '';
    const fullPath = baseDir ? `${baseDir.replace(/\/+$/, '')}/${f.key}` : f.key;
    return `
      <div class="cache-stats-item">
        <input type="checkbox" id="cache-cb-${f.key}" value="${f.key}" ${disabled ? 'disabled' : ''} ${checked} />
        <label class="cache-stats-item-label" for="cache-cb-${f.key}">
          <a href="#" class="cache-stats-item-name" data-cache-path="${escapeHtml(fullPath)}" title="${escapeHtml(fullPath)}">${escapeHtml(fullPath)}</a>
          <span class="cache-stats-item-desc">${t(f.i18n)}</span>
        </label>
        <span class="cache-stats-item-meta">${metaHtml}</span>
      </div>
    `;
  }).join('');
}

function renderCacheStatsList() {
  const listEl = document.getElementById('cache-stats-list');
  if (!listEl) return;
  listEl.innerHTML = buildCacheStatsListHtml();
  updateCacheCleanBtnState();
  updateCacheSummary();
}

function updateCacheCleanBtnState() {
  const cleanBtn = document.getElementById('cache-stats-clean-btn');
  if (!cleanBtn) return;
  const { scanning, cleaning, folderResults, folderCache, checkedFolders } = cacheStatsState;
  const now = Date.now();
  const anyChecked = CACHE_FOLDERS.some(f => {
    if (!checkedFolders[f.key]) return false;
    const result = folderResults[f.key];
    const cached = folderCache[f.key];
    const hasCached = cached && (now - cached.timestamp) < CACHE_TTL_MS;
    return result || hasCached;
  });
  cleanBtn.disabled = scanning || cleaning || !anyChecked;
}

function updateCacheSummary() {
  const totalEl = document.getElementById('cache-stats-total-size');
  const checkedEl = document.getElementById('cache-stats-checked-size');
  const { folderResults, folderCache, checkedFolders } = cacheStatsState;
  const now = Date.now();

  let totalSize = 0;
  let checkedSize = 0;

  for (const f of CACHE_FOLDERS) {
    const result = folderResults[f.key];
    const cached = folderCache[f.key];
    const hasCached = cached && (now - cached.timestamp) < CACHE_TTL_MS;
    const size = result ? result.totalSize : (hasCached ? cached.totalSize : null);

    if (size != null) {
      totalSize += size;
      if (checkedFolders[f.key]) {
        checkedSize += size;
      }
    }
  }

  // Show "—" when no folders have been scanned yet
  const allUnscanned = CACHE_FOLDERS.every(f => {
    const result = folderResults[f.key];
    const cached = folderCache[f.key];
    return !result && (!cached || (now - cached.timestamp) >= CACHE_TTL_MS);
  });

  if (totalEl) totalEl.textContent = allUnscanned ? '—' : formatByteSize(totalSize);
  if (checkedEl) checkedEl.textContent = allUnscanned && checkedSize === 0 ? '—' : formatByteSize(checkedSize);
}

function updateCacheProgressBar() {
  const progressFill = document.getElementById('cache-stats-progress-fill');
  const progressText = document.getElementById('cache-stats-progress-text');
  const total = CACHE_FOLDERS.length;
  const done = cacheStatsState.scannedCount;
  if (!progressFill || !progressText) return;

  if (cacheStatsState.scanning) {
    const pct = total > 0 ? Math.round((done / total) * 100) : 0;
    progressFill.style.width = pct + '%';
    progressText.textContent = `${t('cache.progress')}: ${done}/${total} (${pct}%)`;
  } else if (cacheStatsState.cleaning) {
    progressText.textContent = t('cache.cleaning');
  } else if (done >= total && total > 0) {
    progressFill.style.width = '100%';
    progressText.textContent = t('cache.scanComplete');
  } else {
    progressFill.style.width = '0%';
    progressText.textContent = '';
  }
}

function applyCachedResultsToFolderResults() {
  const now = Date.now();
  const { folderCache } = cacheStatsState;
  for (const f of CACHE_FOLDERS) {
    const cached = folderCache[f.key];
    if (cached && (now - cached.timestamp) < CACHE_TTL_MS) {
      if (!cacheStatsState.folderResults[f.key]) {
        cacheStatsState.folderResults[f.key] = { fileCount: cached.fileCount, totalSize: cached.totalSize };
        cacheStatsState.scannedCount++;
      }
    }
  }
}

async function startCacheScan(cacheDir) {
  const api = getCacheStatsApi();
  if (!api || typeof api.scanCacheFolders !== 'function') return;

  // Unsubscribe previous listeners
  unsubscribeCacheEvents();

  resetCacheStatsState();
  cacheStatsState.scanning = true;
  cacheStatsState.lastCacheDir = cacheDir;
  const jobId = 'cache-scan-' + Date.now();
  cacheStatsState.scanJobId = jobId;

  // Apply cached results first for folders that are already cached
  applyCachedResultsToFolderResults();
  renderCacheStatsList();
  updateCacheProgressBar();

  // Determine which folders need scanning (not cached)
  const now = Date.now();
  const foldersToScan = CACHE_FOLDERS
    .filter(f => {
      const cached = cacheStatsState.folderCache[f.key];
      return !cached || (now - cached.timestamp) >= CACHE_TTL_MS;
    })
    .map(f => f.key);

  if (foldersToScan.length === 0) {
    // All cached, mark as done
    cacheStatsState.scanning = false;
    updateCacheProgressBar();
    renderCacheStatsList();
    return;
  }

  // Subscribe to progress events
  cacheStatsState.unsubScanProgress = api.onCacheScanProgress(data => {
    if (data.jobId !== jobId) return;
    if (data.phase === 'done' && data.folder) {
      cacheStatsState.folderResults[data.folder] = { fileCount: data.fileCount, totalSize: data.totalSize };
      cacheStatsState.folderCache[data.folder] = { fileCount: data.fileCount, totalSize: data.totalSize, timestamp: Date.now() };
      cacheStatsState.scannedCount++;
      renderCacheStatsList();
      updateCacheProgressBar();
    } else if (data.phase === 'scanning' && data.folder) {
      updateCacheProgressBar();
    } else if (data.phase === 'error') {
      cacheStatsState.scanning = false;
      updateCacheProgressBar();
      renderCacheStatsList();
    }
  });

  cacheStatsState.unsubScanComplete = api.onCacheScanComplete(data => {
    if (data.jobId !== jobId) return;
    cacheStatsState.scanning = false;
    updateCacheProgressBar();
    renderCacheStatsList();
    unsubscribeCacheEvents();
  });

  // Start scan
  api.scanCacheFolders(cacheDir, foldersToScan, jobId);
}

function unsubscribeCacheEvents() {
  if (cacheStatsState.unsubScanProgress) { cacheStatsState.unsubScanProgress(); cacheStatsState.unsubScanProgress = null; }
  if (cacheStatsState.unsubScanComplete) { cacheStatsState.unsubScanComplete(); cacheStatsState.unsubScanComplete = null; }
  if (cacheStatsState.unsubCleanProgress) { cacheStatsState.unsubCleanProgress(); cacheStatsState.unsubCleanProgress = null; }
  if (cacheStatsState.unsubCleanComplete) { cacheStatsState.unsubCleanComplete(); cacheStatsState.unsubCleanComplete = null; }
}

async function cancelCacheScan() {
  if (!cacheStatsState.scanJobId) return;
  const api = getCacheStatsApi();
  if (api && typeof api.cancelCacheScan === 'function') {
    await api.cancelCacheScan(cacheStatsState.scanJobId);
  }
}

async function startCacheClean(cacheDir) {
  const api = getCacheStatsApi();
  if (!api || typeof api.cleanCacheFolders !== 'function') return;
  if (cacheStatsState.scanning) {
    showToast(t('cache.scanningInProgress'), 'error');
    return;
  }

  const checkedFolders = CACHE_FOLDERS
    .filter(f => cacheStatsState.checkedFolders[f.key])
    .map(f => f.key);

  if (checkedFolders.length === 0) {
    showToast(t('cache.noFoldersSelected'), 'error');
    return;
  }

  unsubscribeCacheEvents();

  cacheStatsState.cleaning = true;
  const jobId = 'cache-clean-' + Date.now();
  updateCacheProgressBar();
  renderCacheStatsList();

  cacheStatsState.unsubCleanProgress = api.onCacheCleanProgress(data => {
    if (data.jobId !== jobId) return;
    if (data.phase === 'done' && data.folder) {
      // Remove from cache and results
      delete cacheStatsState.folderResults[data.folder];
      delete cacheStatsState.folderCache[data.folder];
      delete cacheStatsState.checkedFolders[data.folder];
      renderCacheStatsList();
      updateCacheProgressBar();
    }
  });

  cacheStatsState.unsubCleanComplete = api.onCacheCleanComplete(data => {
    if (data.jobId !== jobId) return;
    cacheStatsState.cleaning = false;
    updateCacheProgressBar();
    renderCacheStatsList();
    unsubscribeCacheEvents();
    showToast(t('cache.cleanComplete'), 'success');
  });

  updateCacheProgressBar();
  api.cleanCacheFolders(cacheDir, checkedFolders, jobId);
}

function showCacheStatsModal() {
  const modal = document.getElementById('cache-stats-modal');
  if (!modal) return;
  modal.classList.remove('hidden');
  cacheStatsState.visible = true;
  resetCacheStatsState();
  renderCacheStatsList();
  updateCacheProgressBar();

  // Get cacheDir and start scan
  window.electronAPI.getServiceStatus().then(status => {
    const cacheDir = status && status.cacheDir;
    if (cacheDir && cacheStatsState.visible) {
      startCacheScan(cacheDir);
    }
  });
}

function hideCacheStatsModal() {
  const modal = document.getElementById('cache-stats-modal');
  if (!modal) return;
  modal.classList.add('hidden');
  cacheStatsState.visible = false;
  cancelCacheScan();
  unsubscribeCacheEvents();
  resetCacheStatsState();
}

// Button to open modal
const cacheStatsBtn = document.getElementById('cache-stats-btn');
if (cacheStatsBtn) {
  cacheStatsBtn.addEventListener('click', e => {
    e.preventDefault();
    showCacheStatsModal();
  });
}

// Cancel button
const cacheStatsCancelBtn = document.getElementById('cache-stats-cancel-btn');
if (cacheStatsCancelBtn) {
  cacheStatsCancelBtn.addEventListener('click', e => {
    e.preventDefault();
    hideCacheStatsModal();
  });
}

// Clean button
const cacheStatsCleanBtn = document.getElementById('cache-stats-clean-btn');
if (cacheStatsCleanBtn) {
  cacheStatsCleanBtn.addEventListener('click', e => {
    e.preventDefault();
    if (cacheStatsState.scanning) {
      showToast(t('cache.scanningInProgress'), 'error');
      return;
    }
    const cacheDir = cacheStatsState.lastCacheDir;
    if (cacheDir) {
      startCacheClean(cacheDir);
    }
  });
}

// Force refresh button
const cacheStatsRefreshBtn = document.getElementById('cache-stats-refresh-btn');
if (cacheStatsRefreshBtn) {
  cacheStatsRefreshBtn.addEventListener('click', e => {
    e.preventDefault();
    // Clear entire cache
    cacheStatsState.folderCache = {};
    cacheStatsState.folderResults = {};
    cacheStatsState.scannedCount = 0;
    if (cacheStatsState.scanning) {
      cancelCacheScan();
      cacheStatsState.scanning = false;
    }
    renderCacheStatsList();
    updateCacheProgressBar();
    // Restart scan
    const cacheDir = cacheStatsState.lastCacheDir;
    if (cacheDir) {
      startCacheScan(cacheDir);
    }
  });
}

// Select all / deselect all
const cacheStatsSelectAll = document.getElementById('cache-stats-select-all');
if (cacheStatsSelectAll) {
  cacheStatsSelectAll.addEventListener('click', e => {
    e.preventDefault();
    CACHE_FOLDERS.forEach(f => {
      const cb = document.getElementById('cache-cb-' + f.key);
      if (cb && !cb.disabled) {
        cb.checked = true;
        cacheStatsState.checkedFolders[f.key] = true;
      }
    });
    updateCacheCleanBtnState();
    updateCacheSummary();
  });
}

const cacheStatsDeselectAll = document.getElementById('cache-stats-deselect-all');
if (cacheStatsDeselectAll) {
  cacheStatsDeselectAll.addEventListener('click', e => {
    e.preventDefault();
    CACHE_FOLDERS.forEach(f => {
      const cb = document.getElementById('cache-cb-' + f.key);
      if (cb) cb.checked = false;
      cacheStatsState.checkedFolders[f.key] = false;
    });
    updateCacheCleanBtnState();
    updateCacheSummary();
  });
}

// Delegate checkbox changes in the list
document.getElementById('cache-stats-list')?.addEventListener('change', e => {
  if (e.target && e.target.type === 'checkbox') {
    cacheStatsState.checkedFolders[e.target.value] = e.target.checked;
    updateCacheCleanBtnState();
    updateCacheSummary();
  }
});

// Delegate path link clicks on folder name
document.getElementById('cache-stats-list')?.addEventListener('click', e => {
  const nameLink = e.target && e.target.closest('.cache-stats-item-name');
  if (nameLink) {
    e.preventDefault();
    e.stopPropagation();
    const p = nameLink.getAttribute('data-cache-path');
    if (p) window.electronAPI.openPath(p);
  }
});

// Close modal on overlay click
document.getElementById('cache-stats-modal')?.addEventListener('click', e => {
  if (e.target === e.currentTarget) {
    hideCacheStatsModal();
  }
});
