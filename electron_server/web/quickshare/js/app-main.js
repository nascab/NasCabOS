import { connectP2pByEncPairCode } from './p2p-connect.js';
import {
  qsbEncodeAuthReq,
  qsbDecodeAuthRes,
  qsbDecodeListRes,
} from './qsb-codec.js';
import { sha256Hex } from './crypto-util.js';
import { buildUrl, urlToPath } from './url-utils.js';
import { isP2pRetryableFailure, isP2pTransportError } from './p2p-retry.js';

const qs = new URLSearchParams(location.search);
const token = (qs.get('qt') || '').trim();
const initLang = (qs.get('language') || 'zh').trim().toLowerCase();
const encPairCode = (qs.get('pc') || '').trim();

const state = {
  token,
  lang: initLang === 'en' || initLang === 'en-us' ? 'en-US' : 'zh-CN',
  encPairCode,
  rel: '',
  qsat: '',
  p2p: null,
  _p2pHooks: null,
  _p2pConnectingTextKey: '',
  /** 非空时用 t(key) 显示错误，便于切换语言后刷新 */
  errorI18nKey: null,
  welcomeText: '',
  shareRemark: '',
  endTime: null,
  items: [],
};

const I18N = {
  zh: {
    title: '快速分享',
    welcome: '欢迎使用NasCab OS',
    sub: '无需登录，通过链接访问文件',
    name: '名称',
    time: '时间',
    size: '大小',
    copy: '复制链接',
    download: '下载',
    folder: '文件夹',
    copied: '已复制',
    noToken: '缺少分享凭证（qt）',
    needPwdTitle: '请输入访问密码',
    pwdHint: '请输入分享密码后继续',
    pwdWrong: '密码错误，请重试',
    pwdSubmit: '继续访问',
    themeLight: '浅色',
    themeDark: '深色',
    langZh: '中文',
    langEn: 'English',
    expire: '截止：',
    neverExpire: '无期限',
    downloads: '下载任务',
    noDownloads: '暂无下载任务',
    queued: '排队中',
    downloading: '下载中',
    done: '已完成',
    clearDone: '清理已完成',
    failed: '失败',
    canceled: '已取消',
    cancel: '取消',
    close: '关闭',
    prev: '上一张',
    next: '下一张',
    wechatTip: '微信浏览器内无法实现下载，如需下载，点击右上角"在浏览器中打开"',
    p2pConnecting: '正在连接…',
    p2pReconnecting: '连接已断开，正在重连…',
    shareExpired: '此分享已过期',
  },
  en: {
    title: 'Quick Share',
    welcome: 'Welcome to NasCab OS',
    sub: 'Access files by link without login',
    name: 'Name',
    time: 'Time',
    size: 'Size',
    copy: 'Copy link',
    download: 'Download',
    folder: 'Folder',
    copied: 'Copied',
    noToken: 'Missing share token (qt)',
    needPwdTitle: 'Password required',
    pwdHint: 'Enter the share password to continue',
    pwdWrong: 'Incorrect password, try again',
    pwdSubmit: 'Continue',
    themeLight: 'Light',
    themeDark: 'Dark',
    langZh: '中文',
    langEn: 'English',
    expire: 'Expire: ',
    neverExpire: 'Never',
    downloads: 'Downloads',
    noDownloads: 'No downloads',
    queued: 'Queued',
    downloading: 'Downloading',
    done: 'Done',
    clearDone: 'Clear done',
    failed: 'Failed',
    canceled: 'Canceled',
    cancel: 'Cancel',
    close: 'Close',
    prev: 'Prev',
    next: 'Next',
    wechatTip: 'Cannot download in WeChat browser. Tap "Open in Browser" from the top-right menu to download.',
    p2pConnecting: 'Connecting…',
    p2pReconnecting: 'Disconnected, reconnecting…',
    shareExpired: 'This share has expired',
  },
};

const $ = sel => document.querySelector(sel);
const elWelcome = $('#welcomeText');
const elCrumbs = $('#crumbs');
const elList = $('#list');
const elError = $('#errorBox');
const elToast = $('#toast');
const elDlToggle = $('#dlToggle');
const elThemeToggle = $('#themeToggle');
const elLangToggle = $('#langToggle');
const elThemeMenu = $('#themeMenu');
const elLangMenu = $('#langMenu');
const elViewerDownloadFab = $('#viewerDownloadFab');
const elViewerPrev = $('#viewerPrev');
const elViewerNext = $('#viewerNext');
const elPwdModal = $('#pwdModal');
const elDlModal = $('#dlModal');
const elDlTitle = $('#dlTitle');
const elDlClear = $('#dlClear');
const elDlClose = $('#dlClose');
const elDlList = $('#dlList');
const elMemoryDownloadModal = $('#memoryDownloadModal');
const elMemoryDownloadTitle = $('#memoryDownloadTitle');
const elMemoryDownloadText = $('#memoryDownloadText');
const elMemoryDownloadCancel = $('#memoryDownloadCancel');
const elMemoryDownloadConfirm = $('#memoryDownloadConfirm');
const elPwdTitle = $('#pwdTitle');
const elPwdHint = $('#pwdHint');
const elPwdInput = $('#pwdInput');
const elPwdSubmit = $('#pwdSubmit');
const elExpiredModal = $('#expiredModal');
const elExpiredTitle = $('#expiredTitle');
const elExpiredClose = $('#expiredClose');
const elColName = $('#colName');
const elColTime = $('#colTime');
const elColSize = $('#colSize');
const elExpireText = $('#expireText');
const elP2pConnecting = $('#p2pConnecting');
const elP2pConnectingText = $('#p2pConnectingText');
let viewer = null;
if (elViewerDownloadFab) elViewerDownloadFab.target = '_blank';
if (elViewerPrev) elViewerPrev.type = 'button';
if (elViewerNext) elViewerNext.type = 'button';
const p2pObjectUrls = new Map();
const p2pFileFetchState = {
  maxConcurrent: 2,
  gen: 0,
  activeJobs: new Set(),
  queue: [],
};
let p2pTinyObserver = null;
let p2pTinyObserverGen = 0;
let thumbObserver = null;
let thumbObserverGen = 0;
const listRenderState = {
  mode: 'full',
  items: [],
  gen: 0,
  rowHeight: 72,
  overscan: 8,
  rafScheduled: false,
  spacerEl: null,
  contentEl: null,
  pool: [],
  lastRange: { start: -1, end: -1 },
  scrollHandler: null,
  resizeObserver: null,
  lastClientHeight: 0,
};

function t(k) {
  if (window.QS_I18N && typeof window.QS_I18N.t === 'function') {
    return window.QS_I18N.t(k);
  }
  const fallback = {
    title: '快速分享',
    welcome: '欢迎使用 NasCab OS',
    sub: '无需登录，通过链接访问文件',
    name: '名称',
    time: '时间',
    size: '大小',
    copy: '复制链接',
    download: '下载',
    folder: '文件夹',
    copied: '已复制',
    noToken: '缺少分享凭证（qt）',
    needPwdTitle: '请输入访问密码',
    pwdHint: '请输入分享密码后继续',
    pwdWrong: '密码错误，请重试',
    pwdSubmit: '继续访问',
    themeLight: '浅色',
    themeDark: '深色',
    langZh: '中文',
    langEn: 'English',
    expire: '截止：',
    neverExpire: '无期限',
    downloads: '下载任务',
    noDownloads: '暂无下载任务',
    queued: '排队中',
    downloading: '下载中',
    done: '已完成',
    clearDone: '清理已完成',
    failed: '失败',
    canceled: '已取消',
    cancel: '取消',
    close: '关闭',
    prev: '上一张',
    next: '下一张',
    wechatTip: '微信浏览器内无法实现下载，如需下载，点击右上角"在浏览器中打开"',
    p2pConnecting: '正在连接…',
    p2pReconnecting: '连接已断开，正在重连…',
    shareExpired: '此分享已过期',
    memoryDownloadTitle: '是否下载文件？',
    memoryDownloadMessage:
      '您当前的浏览器不支持流式下载，建议您使用Chrome浏览器，当前浏览器下载1G以上的文件可能导致浏览器异常退出。',
  };
  return fallback[k] || k;
}

function svgIcon(name) {
  if (name === 'copy') {
    return `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M16 1H6a2 2 0 0 0-2 2v10h2V3h10V1Zm3 4H10a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2Zm0 16h-9V7h9v14Z"/></svg>`;
  }
  if (name === 'download') {
    return `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3a1 1 0 0 1 1 1v9.59l2.3-2.3a1 1 0 1 1 1.4 1.42l-4 4a1 1 0 0 1-1.4 0l-4-4a1 1 0 1 1 1.4-1.42l2.3 2.3V4a1 1 0 0 1 1-1Zm-7 16a1 1 0 0 1 1 1v1h12v-1a1 1 0 1 1 2 0v2a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-2a1 1 0 0 1 1-1Z"/></svg>`;
  }
  if (name === 'theme') {
    return `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2a1 1 0 0 1 1 1v1.2a1 1 0 1 1-2 0V3a1 1 0 0 1 1-1Zm0 18.8a1 1 0 0 1 1 1V23a1 1 0 1 1-2 0v-1.2a1 1 0 0 1 1-1ZM4.22 4.22a1 1 0 0 1 1.41 0l.85.85a1 1 0 0 1-1.41 1.41l-.85-.85a1 1 0 0 1 0-1.41Zm14.7 14.7a1 1 0 0 1 1.41 0l.85.85a1 1 0 1 1-1.41 1.41l-.85-.85a1 1 0 0 1 0-1.41ZM2 12a1 1 0 0 1 1-1h1.2a1 1 0 1 1 0 2H3a1 1 0 0 1-1-1Zm18.8 0a1 1 0 0 1 1-1H23a1 1 0 1 1 0 2h-1.2a1 1 0 0 1-1-1ZM4.22 19.78a1 1 0 0 1 0-1.41l.85-.85a1 1 0 1 1 1.41 1.41l-.85.85a1 1 0 0 1-1.41 0Zm14.7-14.7a1 1 0 0 1 0-1.41l.85-.85a1 1 0 1 1 1.41 1.41l-.85.85a1 1 0 0 1-1.41 0ZM12 6.5a5.5 5.5 0 1 0 0 11 5.5 5.5 0 0 0 0-11Z"/></svg>`;
  }
  if (name === 'lang') {
    return `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm7.7 9H16.9a15.6 15.6 0 0 0-1.3-6 8.02 8.02 0 0 1 4.1 6ZM12 4c.9 0 2.6 2 3.5 7H8.5C9.4 6 11.1 4 12 4ZM4.3 13h2.8a15.6 15.6 0 0 0 1.3 6 8.02 8.02 0 0 1-4.1-6Zm2.8-2H4.3a8.02 8.02 0 0 1 4.1-6 15.6 15.6 0 0 0-1.3 6ZM12 20c-.9 0-2.6-2-3.5-7h7c-.9 5-2.6 7-3.5 7Zm3.6-1a15.6 15.6 0 0 0 1.3-6h2.8a8.02 8.02 0 0 1-4.1 6Z"/></svg>`;
  }
  if (name === 'check') {
    return `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9.2 16.6 4.9 12.3a1 1 0 1 1 1.4-1.4l2.9 2.9 8.5-8.5a1 1 0 1 1 1.4 1.4l-9.9 9.9a1 1 0 0 1-1.4 0Z"/></svg>`;
  }
  if (name === 'close') {
    return `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18.3 5.71a1 1 0 0 1 0 1.41L13.41 12l4.89 4.88a1 1 0 1 1-1.41 1.42L12 13.41 7.12 18.3a1 1 0 1 1-1.42-1.41L10.59 12 5.7 7.12A1 1 0 0 1 7.12 5.7L12 10.59l4.88-4.89a1 1 0 0 1 1.42.01Z"/></svg>`;
  }
  if (name === 'trash') {
    return `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 3a1 1 0 0 0-1 1v1H5a1 1 0 1 0 0 2h1v13a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7h1a1 1 0 1 0 0-2h-3V4a1 1 0 0 0-1-1H9Zm1 2h4v0H10v0Zm-2 2h8v13H8V7Zm2 3a1 1 0 0 1 1 1v7a1 1 0 1 1-2 0v-7a1 1 0 0 1 1-1Zm5 0a1 1 0 0 1 1 1v7a1 1 0 1 1-2 0v-7a1 1 0 0 1 1-1Z"/></svg>`;
  }
  if (name === 'left') {
    return `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M15.7 5.3a1 1 0 0 1 0 1.4L10.4 12l5.3 5.3a1 1 0 1 1-1.4 1.4l-6-6a1 1 0 0 1 0-1.4l6-6a1 1 0 0 1 1.4 0Z"/></svg>`;
  }
  if (name === 'right') {
    return `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8.3 18.7a1 1 0 0 1 0-1.4l5.3-5.3-5.3-5.3a1 1 0 1 1 1.4-1.4l6 6a1 1 0 0 1 0 1.4l-6 6a1 1 0 0 1-1.4 0Z"/></svg>`;
  }
  return '';
}

function applyErrorDom() {
  if (state.errorI18nKey) {
    elError.textContent = t(state.errorI18nKey);
    elError.classList.remove('hidden');
    return;
  }
  elError.classList.add('hidden');
  elError.textContent = '';
}

/** 固定文案错误（如 P2P），不参与语言切换刷新 */
function setError(msg) {
  state.errorI18nKey = null;
  if (!msg) {
    applyErrorDom();
    return;
  }
  elError.textContent = msg;
  elError.classList.remove('hidden');
}

/** 走 i18n 的提示；切换语言时会在 setLang 里自动刷新 */
function setErrorI18n(key) {
  if (!key) {
    state.errorI18nKey = null;
    applyErrorDom();
    return;
  }
  state.errorI18nKey = key;
  applyErrorDom();
}

function setP2pConnecting(show, textKey) {
  if (!elP2pConnecting || !elP2pConnectingText) return;
  if (!show) {
    state._p2pConnectingTextKey = '';
    elP2pConnecting.classList.add('hidden');
    elP2pConnectingText.textContent = '';
    return;
  }
  state._p2pConnectingTextKey = textKey ? String(textKey) : 'p2pConnecting';
  elP2pConnectingText.textContent = t(state._p2pConnectingTextKey);
  elP2pConnecting.classList.remove('hidden');
  setError('');
}

let toastTimer = null;
function toast(msg) {
  elToast.textContent = msg;
  elToast.classList.remove('hidden');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => elToast.classList.add('hidden'), 1400);
}

const downloadsState = {
  maxConcurrent: 3,
  active: 0,
  list: [],
  queue: [],
};

function initStreamSaver() {
  const ss = window.streamSaver;
  if (!ss || typeof ss !== 'object') return null;
  if (typeof ss.createWriteStream !== 'function') return null;
  try {
    ss.mitm = './assets/vendor/streamsaver/mitm.html';
  } catch (_) {}
  return ss;
}

function isMobileBrowserLike() {
  const ua = String((navigator && navigator.userAgent) || '').toLowerCase();
  if (!ua) return false;
  if (/android|iphone|ipad|ipod|mobile|harmonyos/.test(ua)) return true;
  try {
    if (navigator.maxTouchPoints > 1 && window.matchMedia && window.matchMedia('(pointer: coarse)').matches) return true;
  } catch (_) {}
  return false;
}

function shouldAvoidStreamSaver() {
  // Mobile browsers often prompt for download confirmation after the
  // stream has already started, which makes StreamSaver unreliable there.
  if (isMobileBrowserLike()) return true;
  return false;
}

let memoryDownloadConfirmResolver = null;

function hideMemoryDownloadModal(result) {
  if (elMemoryDownloadModal) elMemoryDownloadModal.classList.add('hidden');
  const resolver = memoryDownloadConfirmResolver;
  memoryDownloadConfirmResolver = null;
  if (typeof resolver === 'function') resolver(result === true);
}

function renderMemoryDownloadModalText() {
  if (elMemoryDownloadTitle) elMemoryDownloadTitle.textContent = t('memoryDownloadTitle');
  if (elMemoryDownloadText) elMemoryDownloadText.textContent = t('memoryDownloadMessage');
  if (elMemoryDownloadCancel) elMemoryDownloadCancel.textContent = t('cancel');
  if (elMemoryDownloadConfirm) elMemoryDownloadConfirm.textContent = t('download');
}

function confirmMemoryDownload() {
  renderMemoryDownloadModalText();
  if (!elMemoryDownloadModal) {
    return Promise.resolve(window.confirm(t('memoryDownloadMessage')));
  }
  if (memoryDownloadConfirmResolver) {
    memoryDownloadConfirmResolver(false);
    memoryDownloadConfirmResolver = null;
  }
  elMemoryDownloadModal.classList.remove('hidden');
  return new Promise(resolve => {
    memoryDownloadConfirmResolver = resolve;
  });
}

let downloadsUiScheduled = false;
let downloadsUiLastMs = 0;
let downloadsUiTimer = null;
function scheduleDownloadsUiUpdate({ immediate } = {}) {
  if (immediate === true) {
    downloadsUiLastMs = Date.now();
    updateDownloadsButton();
    if (elDlModal && !elDlModal.classList.contains('hidden')) renderDownloadsModal();
    return;
  }
  if (downloadsUiScheduled) return;
  downloadsUiScheduled = true;
  const now = Date.now();
  const waitMs = Math.max(0, 1000 - (now - downloadsUiLastMs));
  clearTimeout(downloadsUiTimer);
  downloadsUiTimer = setTimeout(() => {
    downloadsUiScheduled = false;
    downloadsUiLastMs = Date.now();
    updateDownloadsButton();
    if (elDlModal && !elDlModal.classList.contains('hidden')) renderDownloadsModal();
  }, waitMs);
}

function showDownloadsModal(show) {
  if (!elDlModal) return;
  if (show) {
    elDlModal.classList.remove('hidden');
    renderDownloadsModal();
    return;
  }
  elDlModal.classList.add('hidden');
}

function calcOverallDownloadProgress() {
  const active = downloadsState.list.filter(it => it && (it.status === 'queued' || it.status === 'downloading'));
  if (!active.length) return { hasActive: false, percentText: '' };
  let total = 0;
  let received = 0;
  let hasUnknown = false;
  for (const it of active) {
    received += Number(it.receivedBytes) || 0;
    const t = it.totalBytes;
    if (Number.isFinite(t) && t > 0) total += t;
    else hasUnknown = true;
  }
  if (total > 0) {
    const pct = Math.max(0, Math.min(100, Math.floor((received / total) * 100)));
    return { hasActive: true, percentText: `${pct}%` };
  }
  return { hasActive: true, percentText: hasUnknown ? '...' : '0%' };
}

function updateDownloadsButton() {
  if (!elDlToggle) return;
  if (!state.p2p) {
    elDlToggle.classList.add('hidden');
    return;
  }
  const prog = calcOverallDownloadProgress();
  if (!prog.hasActive) {
    elDlToggle.classList.add('hidden');
    elDlToggle.textContent = '';
    return;
  }
  elDlToggle.classList.remove('hidden');
  elDlToggle.title = t('downloads');
  if (prog.percentText === '...' || prog.percentText === '0%') {
    elDlToggle.innerHTML = `<span class="dlLoadingIcon"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2a1 1 0 0 1 1 1v1a1 1 0 1 1-2 0V3a1 1 0 0 1 1-1Zm0 18a1 1 0 0 1 1 1v1a1 1 0 1 1-2 0v-1a1 1 0 0 1 1-1Zm9-9a1 1 0 0 1-1 1h-1a1 1 0 1 1 0-2h1a1 1 0 0 1 1 1ZM5 12a1 1 0 0 1-1 1H3a1 1 0 1 1 0-2h1a1 1 0 0 1 1 1Zm14.07-6.36a1 1 0 0 1 0 1.41l-.7.71a1 1 0 1 1-1.42-1.41l.71-.71a1 1 0 0 1 1.41 0ZM7.05 17.66a1 1 0 0 1 0 1.41l-.7.7a1 1 0 1 1-1.42-1.4l.71-.71a1 1 0 0 1 1.41 0Zm12.02 2.1a1 1 0 0 1-1.41 0l-.71-.7a1 1 0 1 1 1.41-1.42l.71.71a1 1 0 0 1 0 1.41ZM7.05 6.34a1 1 0 0 1-1.41 0l-.71-.7a1 1 0 1 1 1.41-1.42l.71.71a1 1 0 0 1 0 1.41Z"/></svg></span>`;
  } else {
    elDlToggle.textContent = prog.percentText;
  }
}

function renderDownloadsModal() {
  if (!elDlList || !elDlTitle) return;
  elDlTitle.textContent = t('downloads');
  elDlList.innerHTML = '';

  if (elDlClear) {
    const hasDone = downloadsState.list.some(it => it && it.status === 'done');
    elDlClear.disabled = !hasDone;
  }

  const list = downloadsState.list.slice().reverse();
  if (!list.length) {
    const empty = document.createElement('div');
    empty.className = 'muted';
    empty.textContent = t('noDownloads');
    elDlList.appendChild(empty);
    return;
  }

  const statusText = s => {
    if (s === 'queued') return t('queued');
    if (s === 'downloading') return t('downloading');
    if (s === 'done') return t('done');
    if (s === 'failed') return t('failed');
    if (s === 'canceled') return t('canceled');
    return String(s || '-');
  };

  for (const it of list) {
    const card = document.createElement('div');
    card.className = 'dlItem';

    const top = document.createElement('div');
    top.className = 'dlItemTop';

    const name = document.createElement('div');
    name.className = 'dlName';
    name.textContent = it.name || it.relPath || '-';

    const meta = document.createElement('div');
    meta.className = 'dlMeta';
    const pct = it.totalBytes && it.totalBytes > 0 ? Math.floor((it.receivedBytes / it.totalBytes) * 100) : 0;
    const pctText = it.status === 'downloading' && it.totalBytes ? `${Math.max(0, Math.min(100, pct))}%` : '';
    const sizeText = it.totalBytes && it.totalBytes > 0 ? `${formatSize(it.receivedBytes)} / ${formatSize(it.totalBytes)}` : formatSize(it.receivedBytes);
    meta.textContent = `${statusText(it.status)}${pctText ? ` · ${pctText}` : ''} · ${sizeText}`;

    top.appendChild(name);
    top.appendChild(meta);

    const bar = document.createElement('div');
    bar.className = 'dlBar';
    const fill = document.createElement('div');
    fill.className = 'dlBarFill';
    const percent = it.totalBytes && it.totalBytes > 0 ? Math.max(0, Math.min(100, (it.receivedBytes / it.totalBytes) * 100)) : 0;
    fill.style.width = `${percent}%`;
    bar.appendChild(fill);

    const actions = document.createElement('div');
    actions.className = 'dlActions';
    if (it.status === 'queued' || it.status === 'downloading') {
      const cancelBtn = document.createElement('button');
      cancelBtn.type = 'button';
      cancelBtn.className = 'btnGhost';
      cancelBtn.textContent = t('cancel');
      let handled = false;
      const onCancel = e => {
        if (handled) return;
        handled = true;
        e.preventDefault();
        e.stopPropagation();
        cancelDownload(it.id);
      };
      cancelBtn.addEventListener('pointerdown', onCancel);
      cancelBtn.addEventListener('click', onCancel);
      actions.appendChild(cancelBtn);
    }

    card.appendChild(top);
    card.appendChild(bar);
    card.appendChild(actions);
    elDlList.appendChild(card);
  }
}

function cancelDownload(id) {
  const it = downloadsState.list.find(x => x && x.id === id);
  if (!it) return;
  if (it.status === 'queued') {
    it.status = 'canceled';
    downloadsState.queue = downloadsState.queue.filter(x => x && x.id !== id);
    try {
      if (it.writer && typeof it.writer.abort === 'function') it.writer.abort();
    } catch (_) {}
    it.writer = null;
    scheduleDownloadsUiUpdate({ immediate: true });
    pumpDownloads();
    return;
  }
  if (it.status === 'downloading') {
    it.cancelRequested = true;
    it.status = 'canceled';
    try {
      if (it.stream && typeof it.stream.abort === 'function') it.stream.abort();
    } catch (_) {}
    try {
      if (it.writable && typeof it.writable.abort === 'function') it.writable.abort();
    } catch (_) {}
    try {
      if (it.writer && typeof it.writer.abort === 'function') it.writer.abort();
    } catch (_) {}
    scheduleDownloadsUiUpdate({ immediate: true });
  }
}

function clearDoneDownloads() {
  const before = downloadsState.list.length;
  downloadsState.list = downloadsState.list.filter(it => it && it.status !== 'done');
  if (downloadsState.list.length !== before) scheduleDownloadsUiUpdate({ immediate: true });
}

async function createP2pDownloadTask({ relPath, name, isDir }) {
  if (!state.p2p) return;
  if (relPath == null) return;
  let filename = String(name || '').trim() || 'download';
  if (isDir) filename = ensureZipName(filename);
  // 与 Flutter Web 一致：有 showSaveFilePicker 时先选保存位置再拉流，避免用户停在对话框里时 P2P 已开始推数据、缓冲堆积。
  // 目录在上方已 ensureZipName，另存为建议名为 *.zip；无 File System Access 时仍走 StreamSaver / 整包下载。
  const useFilePicker = typeof window.showSaveFilePicker === 'function';

  if (!useFilePicker) {
    if (shouldAvoidStreamSaver()) {
      const confirmed = await confirmMemoryDownload();
      if (!confirmed) return;
      downloadByRelPath(relPath, filename, { isDir: !!isDir }).catch(() => toast('Error'));
      return;
    }
    const ss = initStreamSaver();
    if (!ss) {
      downloadByRelPath(relPath, filename, { isDir: !!isDir }).catch(() => toast('Error'));
      return;
    }
    let writer = null;
    try {
      const ws = ss.createWriteStream(filename);
      writer = ws.getWriter();
    } catch (_) {
      downloadByRelPath(relPath, filename, { isDir: !!isDir }).catch(() => toast('Error'));
      return;
    }
    const task = {
      id: `${Date.now()}_${Math.random().toString(16).slice(2)}`,
      relPath: String(relPath),
      name: filename,
      status: 'queued',
      receivedBytes: 0,
      totalBytes: null,
      saveHandle: null,
      writable: null,
      stream: null,
      writer,
    };
    downloadsState.list.push(task);
    downloadsState.queue.push(task);
    scheduleDownloadsUiUpdate({ immediate: true });
    showDownloadsModal(true);
    pumpDownloads();
    return;
  }
  let handle = null;
  try {
    handle = await window.showSaveFilePicker({ suggestedName: filename });
  } catch (_) {
    return;
  }
  if (!handle) return;
  const savedAs = handle.name && String(handle.name).trim() ? String(handle.name).trim() : filename;
  const task = {
    id: `${Date.now()}_${Math.random().toString(16).slice(2)}`,
    relPath: String(relPath),
    name: savedAs,
    status: 'queued',
    receivedBytes: 0,
    totalBytes: null,
    saveHandle: handle,
    writable: null,
    stream: null,
    writer: null,
  };
  downloadsState.list.push(task);
  downloadsState.queue.push(task);
  scheduleDownloadsUiUpdate({ immediate: true });
  showDownloadsModal(true);
  pumpDownloads();
}

function pumpDownloads() {
  if (!state.p2p) return;
  while (downloadsState.active < downloadsState.maxConcurrent && downloadsState.queue.length) {
    const next = downloadsState.queue.shift();
    if (!next || next.status !== 'queued') continue;
    startP2pDownload(next).catch(() => {});
  }
  scheduleDownloadsUiUpdate();
}

async function startP2pDownload(task) {
  if (!state.p2p) return;
  if (!task || task.status !== 'queued') return;
  downloadsState.active += 1;
  task.status = 'downloading';
  scheduleDownloadsUiUpdate({ immediate: true });

  let writable = null;
  try {
    if (task.saveHandle) {
      writable = await task.saveHandle.createWritable();
      task.writable = writable;
    }
    if (task.status === 'canceled' || task.cancelRequested === true) {
      try {
        if (writable && typeof writable.abort === 'function') await writable.abort();
      } catch (_) {}
      try {
        if (task.writer && typeof task.writer.abort === 'function') await task.writer.abort();
      } catch (_) {}
      throw new Error('canceled');
    }

    const path = urlToPath(buildDownloadUrl(task.relPath));
    const req = state.p2p.file.requestStream({
      method: 'GET',
      path,
      headers: {},
      timeoutMs: 60 * 60 * 1000,
      onBegin: ({ length }) => {
        if (task.status === 'canceled' || task.cancelRequested === true) throw new Error('canceled');
        if (Number.isFinite(length) && length >= 0) task.totalBytes = length;
        scheduleDownloadsUiUpdate();
      },
      onChunk: async chunk => {
        if (task.status === 'canceled' || task.cancelRequested === true) throw new Error('canceled');
        if (task.writer) await task.writer.write(chunk);
        else await writable.write(chunk);
        task.receivedBytes += chunk.length;
        scheduleDownloadsUiUpdate();
      },
      onEnd: async () => {
        if (task.status === 'canceled' || task.cancelRequested === true) throw new Error('canceled');
        if (task.writer) await task.writer.close();
        else await writable.close();
      },
    });
    task.stream = req;
    await req.promise;
    if (task.status !== 'canceled') {
      const received = Number(task.receivedBytes) || 0;
      const total = Number(task.totalBytes);
      if (Number.isFinite(total) && total > 0 && received > 0 && received !== total) {
        task.status = 'failed';
        task.totalBytes = total;
      } else {
        task.status = 'done';
        if (!Number.isFinite(total) || total <= 0) task.totalBytes = received;
      }
    }
  } catch (_) {
    if (task.status !== 'canceled') task.status = 'failed';
    try {
      if (writable && typeof writable.abort === 'function') await writable.abort();
    } catch (_) {}
    try {
      if (task.writer && typeof task.writer.abort === 'function') await task.writer.abort();
    } catch (_) {}
  } finally {
    downloadsState.active = Math.max(0, downloadsState.active - 1);
    task.stream = null;
    task.writable = null;
    task.writer = null;
    scheduleDownloadsUiUpdate();
    pumpDownloads();
  }
}

function formatSize(n) {
  const v = Number(n);
  if (!Number.isFinite(v) || v <= 0) return '-';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let idx = 0;
  let cur = v;
  while (cur >= 1024 && idx < units.length - 1) {
    cur /= 1024;
    idx += 1;
  }
  const digits = idx === 0 ? 0 : cur >= 10 ? 1 : 2;
  return `${cur.toFixed(digits)} ${units[idx]}`;
}

function formatTime(ms) {
  const v = Number(ms);
  if (!Number.isFinite(v) || v <= 0) return '-';
  const d = new Date(v);
  try {
    return d.toLocaleString(state.lang === 'en' ? 'en-US' : 'zh-CN', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch (_) {
    return d.toISOString();
  }
}

function ensureZipName(name) {
  const n = String(name || '').trim() || 'download';
  if (/\.zip$/i.test(n)) return n;
  return `${n}.zip`;
}

function getTheme() {
  return 'dark';
}

function setTheme(theme) {
  const v = theme === 'light' ? 'light' : 'dark';
  document.documentElement.dataset.theme = v;
  localStorage.setItem('qs_theme', v);
  if (elThemeToggle) {
    elThemeToggle.innerHTML = `<span class="btnIcon">${svgIcon('theme')}</span>`;
    elThemeToggle.title = t(v === 'light' ? 'themeDark' : 'themeLight');
  }
  renderMenus();
}

function closeMenus() {
  if (elThemeMenu) elThemeMenu.classList.add('hidden');
  if (elLangMenu) elLangMenu.classList.add('hidden');
  if (elThemeToggle) elThemeToggle.setAttribute('aria-expanded', 'false');
  if (elLangToggle) elLangToggle.setAttribute('aria-expanded', 'false');
}

function toggleMenu(kind) {
  if (kind === 'theme') {
    const nextOpen = elThemeMenu && elThemeMenu.classList.contains('hidden');
    closeMenus();
    if (elThemeMenu && nextOpen) {
      elThemeMenu.classList.remove('hidden');
      if (elThemeToggle) elThemeToggle.setAttribute('aria-expanded', 'true');
    }
    return;
  }
  if (kind === 'lang') {
    const nextOpen = elLangMenu && elLangMenu.classList.contains('hidden');
    closeMenus();
    if (elLangMenu && nextOpen) {
      elLangMenu.classList.remove('hidden');
      if (elLangToggle) elLangToggle.setAttribute('aria-expanded', 'true');
    }
  }
}

function renderMenus() {
  if (elThemeMenu) {
    const cur = getTheme();
    elThemeMenu.innerHTML = '';
    const makeItem = (label, value) => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'menuItem';
      btn.setAttribute('role', 'menuitem');
      btn.innerHTML = `<span>${label}</span><span class="menuItemHint">${cur === value ? svgIcon('check') : ''}</span>`;
      btn.addEventListener('click', e => {
        e.stopPropagation();
        setTheme(value);
        closeMenus();
      });
      return btn;
    };
    elThemeMenu.appendChild(makeItem(t('themeLight'), 'light'));
    elThemeMenu.appendChild(makeItem(t('themeDark'), 'dark'));
  }

  if (elLangMenu) {
    elLangMenu.innerHTML = '';
    const makeItem = (label, value) => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'menuItem';
      btn.setAttribute('role', 'menuitem');
      btn.innerHTML = `<span>${label}</span><span class="menuItemHint">${state.lang === value ? svgIcon('check') : ''}</span>`;
      btn.addEventListener('click', async e => {
        e.stopPropagation();
        await setLang(value);
        closeMenus();
      });
      return btn;
    };
    const locales = window.QSLocales ? window.QSLocales.getAvailableLocales() : ['zh-CN', 'en-US'];
    for (const locale of locales) {
      let label = locale;
      if (locale === 'zh-CN') label = '中文';
      else if (locale === 'en-US') label = 'English';
      else if (locale === 'ja-JP') label = '日本語';
      else if (locale === 'ko-KR') label = '한국어';
      else if (locale === 'vi-VN') label = 'Tiếng Việt';
      else if (locale === 'id-ID') label = 'Bahasa Indonesia';
      else if (locale === 'de-DE') label = 'Deutsch';
      else if (locale === 'es-ES') label = 'Español';
      else if (locale === 'pt-BR') label = 'Português';
      else if (locale === 'ru-RU') label = 'Русский';
      else if (locale === 'ar-SA') label = 'العربية';
      else if (locale === 'th-TH') label = 'ไทย';
      elLangMenu.appendChild(makeItem(label, locale));
    }
  }
}

async function setLang(lang) {
  if (window.QS_I18N) {
    await window.QS_I18N.setLocale(lang);
  }
  state.lang = window.QS_I18N ? window.QS_I18N.locale : lang === 'en' ? 'en' : 'zh';
  document.documentElement.lang = state.lang === 'en' ? 'en' : 'zh';
  document.title = t('title');
  elColName.textContent = t('name');
  elColTime.textContent = t('time');
  elColSize.textContent = t('size');
  if (elLangToggle) {
    elLangToggle.innerHTML = `<span class="btnIcon">${svgIcon('lang')}</span>`;
    elLangToggle.title = state.lang === 'en' ? t('langZh') : t('langEn');
  }
  elPwdTitle.textContent = t('needPwdTitle');
  elPwdHint.textContent = t('pwdHint');
  elPwdSubmit.textContent = t('pwdSubmit');
  if (elViewerDownloadFab) {
    elViewerDownloadFab.innerHTML = svgIcon('download');
    elViewerDownloadFab.title = t('download');
  }
  if (elViewerPrev) {
    elViewerPrev.innerHTML = svgIcon('left');
    elViewerPrev.title = t('prev');
    elViewerPrev.setAttribute('aria-label', t('prev'));
  }
  if (elViewerNext) {
    elViewerNext.innerHTML = svgIcon('right');
    elViewerNext.title = t('next');
    elViewerNext.setAttribute('aria-label', t('next'));
  }
  if (elDlClear) {
    elDlClear.innerHTML = `<span class="btnIcon">${svgIcon('trash')}</span>`;
    elDlClear.title = t('clearDone');
    elDlClear.setAttribute('aria-label', t('clearDone'));
  }
  if (elDlClose) {
    elDlClose.innerHTML = `<span class="btnIcon">${svgIcon('close')}</span>`;
    elDlClose.title = t('close');
    elDlClose.setAttribute('aria-label', t('close'));
  }
  if (elDlTitle) elDlTitle.textContent = t('downloads');
  renderMemoryDownloadModalText();
  setTheme(getTheme());
  updateHeaderText();
  renderExpire();
  renderMenus();
  updateDownloadsButton();
  renderDownloadsModal();
  if (elP2pConnecting && !elP2pConnecting.classList.contains('hidden')) {
    elP2pConnectingText.textContent = t(state._p2pConnectingTextKey || 'p2pConnecting');
  }
  if (state.errorI18nKey) {
    elError.textContent = t(state.errorI18nKey);
  }
}

function updateHeaderText() {
  const primary = state.shareRemark || state.welcomeText || t('welcome');
  elWelcome.textContent = primary;
}

function renderExpire() {
  if (!state.endTime) {
    elExpireText.textContent = '';
    return;
  }
  const endMs = new Date(state.endTime).getTime();
  const now = Date.now();
  if (Number.isFinite(endMs) && endMs > now + 80 * 365 * 24 * 3600 * 1000) {
    elExpireText.textContent = `${t('expire')}${t('neverExpire')}`;
    return;
  }
  elExpireText.textContent = `${t('expire')}${formatTime(endMs)}`;
}

function iconFor(item) {
  if (!item) return './assets/file/file.png';
  if (item.type === 'dir') return './assets/file/folder.png';
  const ext = (item.ext || '').toLowerCase();
  if (['.mp3'].includes(ext)) return './assets/file/mp3.png';
  if (['.wav', '.flac', '.aac', '.m4a', '.ogg'].includes(ext)) return './assets/file/audio.png';
  if (['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.webm', '.flv', '.m4v'].includes(ext)) return './assets/file/video.png';
  if (['.txt'].includes(ext)) return './assets/file/txt.png';
  if (['.md', '.markdown'].includes(ext)) return './assets/file/md.png';
  if (['.log'].includes(ext)) return './assets/file/log.png';
  if (['.xml'].includes(ext)) return './assets/file/xml.png';
  if (['.xls'].includes(ext)) return './assets/file/xls.png';
  if (['.xlsx'].includes(ext)) return './assets/file/xlsx.png';
  if (['.ppt'].includes(ext)) return './assets/file/ppt.png';
  if (['.pptx'].includes(ext)) return './assets/file/pptx.png';
  if (['.doc'].includes(ext)) return './assets/file/doc.png';
  if (['.docx'].includes(ext)) return './assets/file/docx.png';
  if (['.epub', '.mobi', '.azw3', '.pdf'].includes(ext)) return './assets/file/ebook.png';
  return './assets/file/file.png';
}

function isImageItem(item) {
  if (!item || item.type === 'dir') return false;
  if (item.type === 'image') return true;
  const ext = (item.ext || '').toLowerCase();
  return ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.heif', '.avif'].includes(ext);
}

function buildDownloadUrl(relPath) {
  return buildUrl('/api/quickShare/public/download', { qt: state.token, p: relPath || '', qsat: state.qsat || '' });
}

function buildTinyUrl(relPath) {
  return buildUrl('/api/quickShare/public/tiny', { qt: state.token, p: relPath || '', qsat: state.qsat || '' });
}

function buildRawUrl(relPath) {
  return buildUrl('/api/quickShare/public/raw', { qt: state.token, p: relPath || '', qsat: state.qsat || '' });
}

function showPwdModal(show, hintText) {
  if (show) {
    elPwdModal.classList.remove('hidden');
    elPwdHint.textContent = hintText || t('pwdHint');
    elPwdInput.value = '';
    setTimeout(() => elPwdInput.focus(), 50);
    return;
  }
  elPwdModal.classList.add('hidden');
  elPwdHint.textContent = '';
}

function showExpiredModal(show) {
  if (!elExpiredModal || !elExpiredTitle || !elExpiredClose) return;
  if (show) {
    elExpiredTitle.textContent = t('shareExpired');
    elExpiredClose.textContent = t('close');
    elExpiredModal.classList.remove('hidden');
    return;
  }
  elExpiredModal.classList.add('hidden');
}

async function copyText(text) {
  const raw = String(text || '');
  if (!raw) return false;
  try {
    await navigator.clipboard.writeText(raw);
    return true;
  } catch (_) {}
  try {
    const ta = document.createElement('textarea');
    ta.value = raw;
    ta.style.position = 'fixed';
    ta.style.left = '-9999px';
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    document.body.removeChild(ta);
    return true;
  } catch (_) {
    return false;
  }
}

function renderCrumbs(segments) {
  elCrumbs.innerHTML = '';
  const segs = Array.isArray(segments) && segments.length ? segments : [{ name: '/', relPath: '' }];
  for (const seg of segs) {
    const btn = document.createElement('div');
    btn.className = 'crumb';
    btn.textContent = seg && seg.name ? String(seg.name) : '/';
    btn.addEventListener('click', () => {
      state.rel = (seg && seg.relPath) || '';
      fetchList();
    });
    elCrumbs.appendChild(btn);
  }
}

function showViewerDownloadFab(show, href) {
  if (!elViewerDownloadFab) return;
  if (!show) {
    elViewerDownloadFab.classList.add('hidden');
    elViewerDownloadFab.href = '#';
    elViewerDownloadFab.onclick = null;
    return;
  }
  elViewerDownloadFab.href = href || '#';
  elViewerDownloadFab.classList.remove('hidden');
}

function getPreviewImages() {
  if (viewer && viewer.images && viewer.images.length) return Array.from(viewer.images);
  return elList ? Array.from(elList.querySelectorAll('img.qs-preview-img')) : [];
}

function syncViewerWithListDom() {
  if (!window.Viewer || !elList) return;
  try {
    if (viewer) viewer.update();
    else setupViewer();
  } catch (_) {}
}

function updateViewerDownloadFab() {
  if (!viewer || !elViewerDownloadFab) return;
  const idx = Number(viewer.index);
  const imgs = getPreviewImages();
  const src = Number.isFinite(idx) && idx >= 0 ? imgs[idx] : null;
  if (state.p2p) {
    const relPath = src && src.dataset ? String(src.dataset.relPath || '') : '';
    const name = src && src.dataset ? String(src.dataset.name || '') : '';
    showViewerDownloadFab(true, '#');
    elViewerDownloadFab.onclick = e => {
      e.preventDefault();
      e.stopPropagation();
      if (relPath == null) return;
      createP2pDownloadTask({ relPath, name }).catch(() => {});
    };
    return;
  }
  const href = src && src.dataset ? src.dataset.download : '';
  showViewerDownloadFab(true, href);
  elViewerDownloadFab.onclick = null;
}

function showViewerNav(show) {
  if (elViewerPrev) elViewerPrev.classList.toggle('hidden', !show);
  if (elViewerNext) elViewerNext.classList.toggle('hidden', !show);
}

function setupViewer() {
  if (!window.Viewer || !elList) return null;
  try {
    if (viewer) {
      viewer.destroy();
      viewer = null;
    }
  } catch (_) {
    viewer = null;
  }

  const isPcPointer = window.matchMedia && window.matchMedia('(hover: hover) and (pointer: fine)').matches;

  viewer = new window.Viewer(elList, {
    backdrop: true,
    navbar: false,
    title: false,
    tooltip: false,
    keyboard: true,
    transition: true,
    movable: !isPcPointer,
    zoomable: true,
    rotatable: true,
    scalable: true,
    fullscreen: false,
    toolbar: {
      zoomIn: 1,
      zoomOut: 1,
      oneToOne: 1,
      reset: 1,
      prev: 1,
      play: 0,
      next: 1,
      rotateLeft: 1,
      rotateRight: 1,
      flipHorizontal: 1,
      flipVertical: 1,
    },
    filter(image) {
      return image && image.classList && image.classList.contains('qs-preview-img');
    },
    url(image) {
      return (image && image.dataset && image.dataset.original) || (image && image.src) || '';
    },
    shown() {
      updateViewerDownloadFab();
      showViewerNav(true);
    },
    hidden() {
      showViewerDownloadFab(false);
      showViewerNav(false);
    },
    viewed() {
      if (state.p2p) upgradeP2pViewerImage().catch(() => {});
      updateViewerDownloadFab();
      showViewerNav(true);
    },
  });

  if (elViewerPrev) {
    elViewerPrev.onclick = e => {
      e.preventDefault();
      e.stopPropagation();
      if (viewer) viewer.prev();
    };
  }
  if (elViewerNext) {
    elViewerNext.onclick = e => {
      e.preventDefault();
      e.stopPropagation();
      if (viewer) viewer.next();
    };
  }

  return viewer;
}

function openImageViewerByRelPath(relPath) {
  const v = viewer || setupViewer();
  if (!v) {
    if (state.p2p) {
      downloadByRelPath(relPath).catch(() => toast('Error'));
      return;
    }
    window.open(buildRawUrl(relPath), '_blank', 'noopener');
    return;
  }
  const imgs = getPreviewImages();
  const idx = imgs.findIndex(img => img && img.dataset && img.dataset.relPath === relPath);
  if (idx < 0) {
    if (state.p2p) {
      downloadByRelPath(relPath).catch(() => toast('Error'));
      return;
    }
    window.open(buildRawUrl(relPath), '_blank', 'noopener');
    return;
  }
  v.view(idx);
  updateViewerDownloadFab();
}

function parseFilenameFromContentDisposition(value) {
  const raw = String(value || '').trim();
  if (!raw) return '';
  const m1 = raw.match(/filename\*=UTF-8''([^;]+)/i);
  if (m1 && m1[1]) {
    try {
      return decodeURIComponent(m1[1].trim().replace(/^"+|"+$/g, ''));
    } catch (_) {}
  }
  const m2 = raw.match(/filename=([^;]+)/i);
  if (m2 && m2[1]) return m2[1].trim().replace(/^"+|"+$/g, '');
  return '';
}

async function downloadByRelPath(relPath, fallbackName, opts) {
  const isDirDownload = opts && opts.isDir === true;
  const hooks = state._p2pHooks;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const path = urlToPath(buildDownloadUrl(relPath));
    try {
      const res = await state.p2p.file.request({ method: 'GET', path, headers: {}, timeoutMs: 10 * 60 * 1000 });
      if (!res || !res.blob) throw new Error('download_failed');
      if (Number(res.status) !== 200) {
        const text = res.bytes ? new TextDecoder().decode(res.bytes) : await res.blob.text().catch(() => '');
        if (attempt === 0 && isP2pRetryableFailure({ status: res.status, text })) {
          if (hooks && typeof hooks.reconnectNow === 'function') await hooks.reconnectNow('file_http_error');
          continue;
        }
        throw new Error(text || `http_${res.status}`);
      }
      const cd = res.headers && res.headers['content-disposition'] ? res.headers['content-disposition'] : '';
      let filename = parseFilenameFromContentDisposition(cd) || String(fallbackName || '').trim() || 'download';
      if (isDirDownload) filename = ensureZipName(filename);
      const objectUrl = URL.createObjectURL(res.blob);
      const a = document.createElement('a');
      a.href = objectUrl;
      a.download = filename;
      a.rel = 'noopener';
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(() => URL.revokeObjectURL(objectUrl), 2000);
      return;
    } catch (err) {
      if (attempt === 0 && isP2pTransportError(err)) {
        if (hooks && typeof hooks.reconnectNow === 'function') await hooks.reconnectNow('file_transport_error');
        continue;
      }
      throw err;
    }
  }
}

function revokeAllP2pObjectUrls() {
  for (const url of p2pObjectUrls.values()) {
    try {
      URL.revokeObjectURL(url);
    } catch (_) {}
  }
  p2pObjectUrls.clear();
}

function stopP2pTinyObserver() {
  if (!p2pTinyObserver) return;
  try {
    p2pTinyObserver.disconnect();
  } catch (_) {}
  p2pTinyObserver = null;
  p2pTinyObserverGen += 1;
}

function stopThumbObserver() {
  if (!thumbObserver) return;
  try {
    thumbObserver.disconnect();
  } catch (_) {}
  thumbObserver = null;
  thumbObserverGen += 1;
}

function loadLazySrcIntoImg(img) {
  if (!img || !img.dataset) return;
  if (img.dataset.lazyLoaded === '1' || img.dataset.lazyLoading === '1') return;
  const src = String(img.dataset.lazySrc || '');
  if (!src) return;
  img.dataset.lazyLoading = '1';
  img.onerror = () => {
    img.onerror = null;
    const fallback = img.dataset ? String(img.dataset.fallbackSrc || '') : '';
    if (fallback) img.src = fallback;
    if (img.dataset) img.dataset.lazyLoaded = '1';
    if (img.dataset) img.dataset.lazyLoading = '0';
  };
  img.onload = () => {
    img.onload = null;
    if (img.dataset) img.dataset.lazyLoaded = '1';
    if (img.dataset) img.dataset.lazyLoading = '0';
  };
  img.src = src;
}

function ensureThumbObserver() {
  if (thumbObserver) return thumbObserver;
  if (!window.IntersectionObserver) return null;
  const myGen = (thumbObserverGen += 1);
  thumbObserver = new IntersectionObserver(
    entries => {
      if (myGen !== thumbObserverGen) return;
      if (document.hidden) return;
      for (const entry of entries) {
        if (!entry || !entry.isIntersecting) continue;
        const img = entry.target;
        if (!img || !img.dataset) continue;
        if (img.dataset.lazyLoaded === '1' || img.dataset.lazyLoading === '1') {
          try {
            thumbObserver.unobserve(img);
          } catch (_) {}
          continue;
        }
        loadLazySrcIntoImg(img);
        try {
          thumbObserver.unobserve(img);
        } catch (_) {}
      }
    },
    { root: elList || null, rootMargin: '240px 0px', threshold: 0.01 }
  );
  return thumbObserver;
}

function observeThumb(img) {
  if (!img || !img.dataset) return;
  if (img.dataset.lazyLoaded === '1') return;
  const obs = ensureThumbObserver();
  if (obs) {
    try {
      obs.observe(img);
      return;
    } catch (_) {}
  }
  if (document.hidden) return;
  loadLazySrcIntoImg(img);
}

function cancelAllP2pFileFetches() {
  p2pFileFetchState.gen += 1;
  const pending = p2pFileFetchState.queue.splice(0, p2pFileFetchState.queue.length);
  for (const job of pending) {
    try {
      if (job && typeof job.reject === 'function') job.reject(new Error('p2p_abort'));
    } catch (_) {}
  }
  for (const handle of Array.from(p2pFileFetchState.activeJobs)) {
    try {
      if (handle) handle.canceled = true;
    } catch (_) {}
    try {
      if (handle && typeof handle.abort === 'function') handle.abort();
    } catch (_) {}
    p2pFileFetchState.activeJobs.delete(handle);
  }
  pumpP2pFileFetchQueue();
}

function pumpP2pFileFetchQueue() {
  if (!state.p2p) return;
  while (p2pFileFetchState.activeJobs.size < p2pFileFetchState.maxConcurrent && p2pFileFetchState.queue.length) {
    const job = p2pFileFetchState.queue.shift();
    if (!job) continue;
    if (job.gen !== p2pFileFetchState.gen) {
      try {
        job.reject(new Error('p2p_abort'));
      } catch (_) {}
      continue;
    }
    const handle = { abort: null, canceled: false };
    p2pFileFetchState.activeJobs.add(handle);
    Promise.resolve()
      .then(() => job.run(handle))
      .then(job.resolve)
      .catch(job.reject)
      .finally(() => {
        p2pFileFetchState.activeJobs.delete(handle);
        pumpP2pFileFetchQueue();
      });
  }
}

async function queueP2pFileFetch(run) {
  if (!state.p2p) throw new Error('p2p_not_connected');
  const gen = p2pFileFetchState.gen;
  return await new Promise((resolve, reject) => {
    p2pFileFetchState.queue.push({ gen, run, resolve, reject });
    pumpP2pFileFetchQueue();
  });
}

async function fetchP2pBlobByUrl(url, timeoutMs) {
  const hooks = state._p2pHooks;
  const effectiveTimeout = timeoutMs || 60000;
  const jobGen = p2pFileFetchState.gen;
  return await queueP2pFileFetch(async handle => {
    for (let attempt = 0; attempt < 2; attempt += 1) {
      if (handle && handle.canceled) throw new Error('p2p_abort');
      if (jobGen !== p2pFileFetchState.gen) throw new Error('p2p_abort');
      const path = urlToPath(url);
      try {
        const chunks = [];
        let status = 0;
        let respHeaders = {};
        const req = state.p2p.file.requestStream({
          method: 'GET',
          path,
          headers: {},
          timeoutMs: effectiveTimeout,
          onBegin: ({ status: s, headers }) => {
            status = Number(s) || 0;
            respHeaders = headers || {};
          },
          onChunk: chunk => {
            if (!chunk || !chunk.length) return;
            chunks.push(chunk);
          },
        });
        if (handle) {
          handle.abort = () => {
            try {
              req.abort();
            } catch (_) {}
          };
          if (handle.canceled) handle.abort();
        }
        await req.promise;
        if (Number(status) !== 200) {
          let text = '';
          try {
            const parts = [];
            let take = 0;
            for (const c of chunks) {
              if (!c || !c.length) continue;
              const left = 4096 - take;
              if (left <= 0) break;
              parts.push(c.length > left ? c.subarray(0, left) : c);
              take += Math.min(left, c.length);
            }
            if (parts.length) text = new TextDecoder().decode(parts.length === 1 ? parts[0] : new Uint8Array(await new Blob(parts).arrayBuffer()));
          } catch (_) {
            text = '';
          }
          if (attempt === 0 && isP2pRetryableFailure({ status, text })) {
            if (hooks && typeof hooks.reconnectNow === 'function') await hooks.reconnectNow('file_http_error');
            continue;
          }
          throw new Error(text || `http_${status || 0}`);
        }
        return new Blob(chunks, { type: (respHeaders && respHeaders['content-type']) || '' });
      } catch (err) {
        if (handle && handle.canceled) throw new Error('p2p_abort');
        if (attempt === 0 && isP2pTransportError(err)) {
          if (hooks && typeof hooks.reconnectNow === 'function') await hooks.reconnectNow('file_transport_error');
          continue;
        }
        throw err;
      }
    }
    throw new Error('p2p_blob_failed');
  });
}

async function getP2pObjectUrl(key, url, timeoutMs) {
  if (p2pObjectUrls.has(key)) return p2pObjectUrls.get(key);
  const blob = await fetchP2pBlobByUrl(url, timeoutMs);
  const objectUrl = URL.createObjectURL(blob);
  p2pObjectUrls.set(key, objectUrl);
  return objectUrl;
}

async function loadP2pTinyIntoImg(imgEl, relPath) {
  const img = imgEl;
  if (!img || relPath == null) return;
  if (img.dataset && img.dataset.p2pTinyLoaded === '1') return;
  const gen = img.dataset ? String(img.dataset.p2pListGen || '') : '';
  const key = `tiny:${relPath}`;
  try {
    const objectUrl = await getP2pObjectUrl(key, buildTinyUrl(relPath), 20000);
    if (!objectUrl) return;
    if (!img.isConnected) return;
    if (img.dataset && String(img.dataset.relPath || '') !== String(relPath || '')) return;
    if (img.dataset && String(img.dataset.p2pListGen || '') !== gen) return;
    if (img.dataset) img.dataset.p2pTinyLoaded = '1';
    if (img.dataset) img.dataset.original = objectUrl;
    img.src = objectUrl;
  } catch (_) {}
}

function ensureP2pTinyObserver() {
  if (p2pTinyObserver) return p2pTinyObserver;
  if (!window.IntersectionObserver) return null;
  const myGen = (p2pTinyObserverGen += 1);
  p2pTinyObserver = new IntersectionObserver(
    entries => {
      if (myGen !== p2pTinyObserverGen) return;
      if (!state.p2p) return;
      if (document.hidden) return;
      for (const entry of entries) {
        if (!entry || !entry.isIntersecting) continue;
        const img = entry.target;
        if (!img || !img.dataset) continue;
        if (img.dataset.p2pTinyLoaded === '1' || img.dataset.p2pTinyLoading === '1') {
          try {
            p2pTinyObserver.unobserve(img);
          } catch (_) {}
          continue;
        }
        const relPath = String(img.dataset.relPath || '');
        if (relPath == null) continue;
        img.dataset.p2pTinyLoading = '1';
        try {
          p2pTinyObserver.unobserve(img);
        } catch (_) {}
        loadP2pTinyIntoImg(img, relPath).finally(() => {
          try {
            if (img && img.dataset) img.dataset.p2pTinyLoading = '0';
          } catch (_) {}
        });
      }
    },
    { root: elList || null, rootMargin: '240px 0px', threshold: 0.01 }
  );
  return p2pTinyObserver;
}

function observeP2pTiny(img) {
  if (!img || !img.dataset) return;
  if (img.dataset.p2pTinyLoaded === '1') return;
  const obs = ensureP2pTinyObserver();
  if (obs) {
    try {
      obs.observe(img);
      return;
    } catch (_) {}
  }
  const relPath = String(img.dataset.relPath || '');
  if (relPath == null) return;
  if (document.hidden) return;
  loadP2pTinyIntoImg(img, relPath).catch(() => {});
}

async function ensureP2pRawUrlForRelPath(relPath) {
  if (relPath == null) return '';
  const key = `raw:${relPath}`;
  try {
    return await getP2pObjectUrl(key, buildRawUrl(relPath), 10 * 60 * 1000);
  } catch (_) {
    return '';
  }
}

async function upgradeP2pViewerImage() {
  if (!state.p2p || !viewer || !elList) return;
  const idx = Number(viewer.index);
  if (!Number.isFinite(idx) || idx < 0) return;
  const imgs = getPreviewImages();
  const thumb = imgs[idx];
  const relPath = thumb && thumb.dataset ? String(thumb.dataset.relPath || '') : '';
  if (relPath == null) return;
  const rawUrl = await ensureP2pRawUrlForRelPath(relPath);
  if (!rawUrl) return;
  if (thumb && thumb.dataset) thumb.dataset.original = rawUrl;
  try {
    if (viewer.image) {
      const img = viewer.image;
      const onDone = () => {
        img.removeEventListener('load', onDone);
        img.removeEventListener('error', onDone);
        try {
          if (viewer && viewer.image === img && viewer.reset) viewer.reset();
        } catch (_) {}
      };
      img.addEventListener('load', onDone, { once: true });
      img.addEventListener('error', onDone, { once: true });
      img.src = rawUrl;
    }
  } catch (_) {}
}

function destroyViewer() {
  if (!viewer) return;
  try {
    viewer.destroy();
  } catch (_) {}
  viewer = null;
}

function getListItemByIndex(idx) {
  const i = Number(idx);
  if (!Number.isFinite(i) || i < 0) return null;
  const list = listRenderState.items;
  if (!Array.isArray(list) || i >= list.length) return null;
  return list[i];
}

function ensureVirtualHandlers() {
  if (!elList) return;
  if (!listRenderState.scrollHandler) {
    listRenderState.scrollHandler = () => {
      if (listRenderState.mode !== 'virtual') return;
      scheduleVirtualUpdate();
    };
    elList.addEventListener('scroll', listRenderState.scrollHandler, { passive: true });
  }
  if (!listRenderState.resizeObserver && window.ResizeObserver) {
    listRenderState.resizeObserver = new ResizeObserver(() => {
      if (listRenderState.mode !== 'virtual') return;
      scheduleVirtualUpdate();
    });
    try {
      listRenderState.resizeObserver.observe(elList);
    } catch (_) {}
  }
}

function scheduleVirtualUpdate() {
  if (listRenderState.rafScheduled) return;
  listRenderState.rafScheduled = true;
  requestAnimationFrame(() => {
    listRenderState.rafScheduled = false;
    updateVirtualRange();
  });
}

function ensureVirtualDom() {
  if (!elList) return;
  if (listRenderState.spacerEl && listRenderState.contentEl && listRenderState.spacerEl.isConnected) return;
  elList.innerHTML = '';
  const spacer = document.createElement('div');
  spacer.className = 'vlistSpacer';
  const content = document.createElement('div');
  content.className = 'vlistContent';
  spacer.appendChild(content);
  elList.appendChild(spacer);
  listRenderState.spacerEl = spacer;
  listRenderState.contentEl = content;
  listRenderState.pool = [];
  listRenderState.lastRange = { start: -1, end: -1 };
  listRenderState.lastClientHeight = 0;
  ensureVirtualHandlers();
}

function createRowElement() {
  const row = document.createElement('div');
  row.className = 'row';

  const cellName = document.createElement('div');
  cellName.className = 'cellName';

  const thumb = document.createElement('div');
  thumb.className = 'thumb';
  const img = document.createElement('img');
  img.decoding = 'async';
  thumb.appendChild(img);

  const nameWrap = document.createElement('div');
  nameWrap.className = 'nameWrap';
  const name = document.createElement('div');
  name.className = 'name';
  const meta = document.createElement('div');
  meta.className = 'meta';
  const metaExt = document.createElement('span');
  metaExt.className = 'metaExt';
  const metaInfo = document.createElement('span');
  metaInfo.className = 'metaInfo';
  meta.appendChild(metaExt);
  meta.appendChild(metaInfo);
  nameWrap.appendChild(name);
  nameWrap.appendChild(meta);

  cellName.appendChild(thumb);
  cellName.appendChild(nameWrap);

  const cellTime = document.createElement('div');
  cellTime.className = 'rowTime muted';

  const cellSize = document.createElement('div');
  cellSize.className = 'rowSize muted';

  const cellActions = document.createElement('div');
  cellActions.className = 'actions';

  const copyBtn = document.createElement('button');
  copyBtn.className = 'btnGhost actionBtn iconOnly hasTooltip';
  copyBtn.type = 'button';
  copyBtn.innerHTML = `<span class="btnIcon">${svgIcon('copy')}</span><span class="btnText">${t('copy')}</span>`;
  copyBtn.addEventListener('click', async e => {
    e.stopPropagation();
    const it = getListItemByIndex(row.dataset.idx);
    if (!it) return;
    const ok = await copyText(buildDownloadUrl(it.relPath));
    if (ok) toast(t('copied'));
  });

  const dlLink = document.createElement('a');
  dlLink.className = 'btn actionBtn iconOnly linkBtn hasTooltip';
  dlLink.innerHTML = `<span class="btnIcon">${svgIcon('download')}</span><span class="btnText">${t('download')}</span>`;
  dlLink.rel = 'noopener';
  dlLink.addEventListener('click', e => {
    e.stopPropagation();
    if (!state.p2p) return;
    e.preventDefault();
    e.stopPropagation();
    const it = getListItemByIndex(row.dataset.idx);
    if (!it) return;
    createP2pDownloadTask({ relPath: it.relPath, name: it.name, isDir: it.type === 'dir' }).catch(() => {});
  });

  cellActions.appendChild(copyBtn);
  cellActions.appendChild(dlLink);

  row.appendChild(cellName);
  row.appendChild(cellTime);
  row.appendChild(cellSize);
  row.appendChild(cellActions);

  row.addEventListener('click', e => {
    // 缩略图上的点击交给 Viewer（挂在 #list 上）处理，避免与 openImageViewerByRelPath 双重 view 导致错位
    if (e.target.closest && e.target.closest('.thumb img')) return;
    const it = getListItemByIndex(row.dataset.idx);
    if (!it) return;
    if (it.type === 'dir') {
      state.rel = it.relPath || '';
      fetchList();
      return;
    }

    if (state.p2p) {
      if (isImageItem(it)) {
        openImageViewerByRelPath(it.relPath);
        return;
      }
      createP2pDownloadTask({ relPath: it.relPath, name: it.name, isDir: false }).catch(() => {});
      return;
    }
    if (isImageItem(it)) {
      openImageViewerByRelPath(it.relPath);
      return;
    }
    window.open(buildRawUrl(it.relPath), '_blank', 'noopener');
  });

  row.__qs = { thumb, img, name, metaExt, metaInfo, cellTime, cellSize, copyBtn, dlLink };
  return row;
}

function updateRowElement(row, idx, it, { observeThumbs, observeP2pThumbs } = {}) {
  row.dataset.idx = String(idx);
  const refs = row.__qs;
  if (!refs) return;

  if (thumbObserver) {
    try {
      thumbObserver.unobserve(refs.img);
    } catch (_) {}
  }
  if (p2pTinyObserver) {
    try {
      p2pTinyObserver.unobserve(refs.img);
    } catch (_) {}
  }

  refs.img.onload = null;
  refs.img.onerror = null;
  delete refs.img.dataset.lazySrc;
  delete refs.img.dataset.lazyLoaded;
  delete refs.img.dataset.lazyLoading;
  delete refs.img.dataset.fallbackSrc;
  delete refs.img.dataset.original;
  delete refs.img.dataset.download;
  delete refs.img.dataset.relPath;
  delete refs.img.dataset.name;
  delete refs.img.dataset.p2pListGen;
  delete refs.img.dataset.p2pTinyLoaded;
  delete refs.img.dataset.p2pTinyLoading;
  refs.img.classList.remove('qs-preview-img');

  const isDir = it && it.type === 'dir';
  row.classList.toggle('isDir', isDir);
  refs.thumb.classList.toggle('isDir', isDir);

  refs.name.textContent = (it && it.name) || '-';
  refs.metaExt.textContent = it && it.type === 'dir' ? t('folder') : String((it && it.ext) || '').toUpperCase();
  const infoLeft = it && it.type === 'dir' ? t('folder') : formatSize(it && it.size);
  const infoRight = formatTime((it && (it.mtimeMs || it.ctimeMs)) || 0);
  refs.metaInfo.textContent = `${infoLeft} · ${infoRight}`;

  refs.cellTime.textContent = formatTime((it && (it.mtimeMs || it.ctimeMs)) || 0);
  refs.cellSize.textContent = it && it.type === 'dir' ? '-' : formatSize(it && it.size);

  refs.copyBtn.classList.toggle('hidden', !!state.p2p);
  refs.copyBtn.title = t('copy');
  refs.copyBtn.dataset.tooltip = t('copy');

  refs.dlLink.title = t('download');
  refs.dlLink.dataset.tooltip = t('download');

  const downloadName = it && it.type === 'dir' ? ensureZipName(it.name) : String((it && it.name) || '');
  if (state.p2p) {
    refs.dlLink.href = '#';
    refs.dlLink.removeAttribute('download');
  } else {
    refs.dlLink.href = buildDownloadUrl(it && it.relPath);
    if (it && it.type === 'dir') refs.dlLink.download = downloadName;
    else refs.dlLink.removeAttribute('download');
  }

  const fallback = iconFor(it);
  refs.img.src = fallback;
  refs.img.dataset.fallbackSrc = fallback;

  const isPreviewable = !state.p2p && it && (it.type === 'image' || it.type === 'video' || it.type === 'raw');
  if (isPreviewable) {
    refs.img.dataset.lazySrc = buildTinyUrl(it.relPath);
    refs.img.dataset.lazyLoaded = '0';
    refs.img.dataset.lazyLoading = '0';
    if (observeThumbs !== false) observeThumb(refs.img);
  }

  if (state.p2p && isImageItem(it)) {
    refs.img.classList.add('qs-preview-img');
    refs.img.dataset.relPath = it.relPath || '';
    refs.img.dataset.name = it.name || '';
    refs.img.dataset.p2pListGen = String(p2pFileFetchState.gen);
    refs.img.dataset.p2pTinyLoaded = '0';
    refs.img.dataset.p2pTinyLoading = '0';
    if (observeP2pThumbs !== false) observeP2pTiny(refs.img);
  }
  if (!state.p2p && isImageItem(it)) {
    refs.img.classList.add('qs-preview-img');
    refs.img.dataset.relPath = it.relPath || '';
    refs.img.dataset.original = buildRawUrl(it.relPath);
    refs.img.dataset.download = buildDownloadUrl(it.relPath);
  }
}

function measureRowHeight(sampleItem) {
  if (!elList || !sampleItem) return;
  const row = createRowElement();
  row.style.position = 'absolute';
  row.style.visibility = 'hidden';
  row.style.pointerEvents = 'none';
  row.style.left = '0';
  row.style.right = '0';
  row.style.top = '0';
  elList.appendChild(row);
  updateRowElement(row, 0, sampleItem, { observeThumbs: false, observeP2pThumbs: false });
  const h = row.getBoundingClientRect().height;
  row.remove();
  if (Number.isFinite(h) && h > 0) listRenderState.rowHeight = Math.max(40, Math.round(h));
}

function renderFullList(list) {
  if (!elList) return;
  elList.innerHTML = '';
  const frag = document.createDocumentFragment();
  for (let i = 0; i < list.length; i += 1) {
    const row = createRowElement();
    updateRowElement(row, i, list[i]);
    frag.appendChild(row);
  }
  elList.appendChild(frag);
  setupViewer();
}

function updateVirtualRange() {
  if (listRenderState.mode !== 'virtual') return;
  if (!elList || !listRenderState.spacerEl || !listRenderState.contentEl) return;
  const list = listRenderState.items;
  if (!Array.isArray(list) || !list.length) {
    listRenderState.spacerEl.style.height = '0px';
    listRenderState.contentEl.style.transform = 'translateY(0px)';
    listRenderState.contentEl.innerHTML = '';
    listRenderState.pool = [];
    listRenderState.lastRange = { start: -1, end: -1 };
    return;
  }

  const clientHeight = elList.clientHeight || 0;
  if (clientHeight !== listRenderState.lastClientHeight) {
    listRenderState.lastClientHeight = clientHeight;
    listRenderState.lastRange = { start: -1, end: -1 };
  }

  const rowH = listRenderState.rowHeight || 72;
  const scrollTop = elList.scrollTop || 0;
  const start = Math.max(0, Math.floor(scrollTop / rowH) - listRenderState.overscan);
  const end = Math.min(list.length, Math.ceil((scrollTop + clientHeight) / rowH) + listRenderState.overscan);
  if (start === listRenderState.lastRange.start && end === listRenderState.lastRange.end) return;
  listRenderState.lastRange = { start, end };

  listRenderState.spacerEl.style.height = `${list.length * rowH}px`;
  listRenderState.contentEl.style.transform = `translateY(${start * rowH}px)`;

  const need = Math.max(0, end - start);
  while (listRenderState.pool.length < need) {
    const row = createRowElement();
    listRenderState.pool.push(row);
    listRenderState.contentEl.appendChild(row);
  }
  while (listRenderState.pool.length > need) {
    const row = listRenderState.pool.pop();
    if (row) row.remove();
  }
  for (let i = 0; i < need; i += 1) {
    const idx = start + i;
    updateRowElement(listRenderState.pool[i], idx, list[idx]);
  }
  syncViewerWithListDom();
}

function renderVirtualList(list) {
  ensureVirtualDom();
  if (!elList || !listRenderState.spacerEl || !listRenderState.contentEl) return;
  if (list && list[0]) measureRowHeight(list[0]);
  listRenderState.spacerEl.style.height = `${list.length * (listRenderState.rowHeight || 72)}px`;
  scheduleVirtualUpdate();
}

function renderList(items) {
  listRenderState.gen += 1;
  listRenderState.items = Array.isArray(items) ? items : [];
  listRenderState.lastRange = { start: -1, end: -1 };

  destroyViewer();
  if (state.p2p) revokeAllP2pObjectUrls();
  if (state.p2p) cancelAllP2pFileFetches();
  stopP2pTinyObserver();
  stopThumbObserver();
  try {
    if (elList) elList.scrollTop = 0;
  } catch (_) {}

  const list = listRenderState.items;
  if (!list.length) {
    if (elList) elList.innerHTML = '';
    listRenderState.mode = 'full';
    listRenderState.spacerEl = null;
    listRenderState.contentEl = null;
    listRenderState.pool = [];
    return;
  }

  const useVirtual = list.length >= 800;
  listRenderState.mode = useVirtual ? 'virtual' : 'full';
  if (useVirtual) renderVirtualList(list);
  else renderFullList(list);
}

async function fetchLoginWelcome() {
  state.welcomeText = '';
  updateHeaderText();
}

async function requestQsbByUrl(url, { method, bodyBytes, expect } = {}) {
  const m = String(method || 'GET').toUpperCase();
  const path = urlToPath(url);
  if (!state.p2p) {
    const resp = await fetch(path, {
      method: m,
      credentials: 'same-origin',
      headers: bodyBytes != null ? { 'Content-Type': 'application/octet-stream' } : undefined,
      body: bodyBytes != null ? bodyBytes : undefined,
    });
    const ab = await resp.arrayBuffer().catch(() => null);
    const bytes = ab ? new Uint8Array(ab) : null;
    const decoded = expect === 'auth' ? (bytes ? qsbDecodeAuthRes(bytes) : null) : expect === 'list' ? (bytes ? qsbDecodeListRes(bytes) : null) : null;
    return { status: resp.status, decoded };
  }

  const hooks = state._p2pHooks;
  try {
    const res = await state.p2p.api.request({
      method: m,
      path,
      headers: bodyBytes != null ? { 'Content-Type': 'application/octet-stream' } : {},
      bodyBytes: bodyBytes != null ? bodyBytes : undefined,
      timeoutMs: 60000,
    });
    const bytes = res && res.bytes ? res.bytes : null;
    const decoded = expect === 'auth' ? (bytes ? qsbDecodeAuthRes(bytes) : null) : expect === 'list' ? (bytes ? qsbDecodeListRes(bytes) : null) : null;
    const st = res != null && res.status !== undefined && res.status !== null ? Number(res.status) : 0;
    return { status: Number.isFinite(st) ? st : 0, decoded };
  } catch (_) {
    if (hooks && typeof hooks.reconnectNow === 'function') await hooks.reconnectNow('api_transport_error');
    return { status: 0, decoded: null };
  }
}

async function fetchList() {
  if (!state.token) {
    setErrorI18n('noToken');
    return;
  }
  if (state.p2p) {
    cancelAllP2pFileFetches();
    stopP2pTinyObserver();
  }
  setErrorI18n('');

  const url = buildUrl('/api/quickShare/public/list', { qt: state.token, p: state.rel || '', qsat: state.qsat || '' });
  const resp = await requestQsbByUrl(url, { method: 'GET', expect: 'list' });
  const listHttpStatus = Number(resp.status);
  const listBodyCode =
    resp.decoded && resp.decoded.ok === false && resp.decoded.code != null ? Number(resp.decoded.code) : NaN;

  if (listHttpStatus === 998 || listBodyCode === 998) {
    clearQsatFromStorage();
    state.qsat = '';
    showPwdModal(true, t('pwdHint'));
    return;
  }

  if (listHttpStatus === 999 || listBodyCode === 999) {
    clearQsatFromStorage();
    state.qsat = '';
    showPwdModal(true, t('pwdWrong'));
    return;
  }

  if (listHttpStatus === 429 || listBodyCode === 429) {
    clearQsatFromStorage();
    state.qsat = '';
    showPwdModal(true, t('tooManyAttempts'));
    return;
  }

  if (listHttpStatus === 410 || listBodyCode === 410) {
    setErrorI18n('');
    showExpiredModal(true);
    return;
  }

  if (listHttpStatus === 404 || listBodyCode === 404) {
    setErrorI18n('shareNotFound');
    return;
  }

  if (listHttpStatus === 470 || listBodyCode === 470) {
    setErrorI18n('sharePathMissing');
    return;
  }

  const decoded = resp.decoded;
  if (!decoded || decoded.ok !== true) {
    const code = decoded && decoded.ok === false ? decoded.code : null;
    if (code === 404) setErrorI18n('shareNotFound');
    else if (code === 470) setErrorI18n('sharePathMissing');
    else if (code === 998) {
      clearQsatFromStorage();
      state.qsat = '';
      showPwdModal(true, t('pwdHint'));
    } else if (code === 999) {
      clearQsatFromStorage();
      state.qsat = '';
      showPwdModal(true, t('pwdWrong'));
    } else if (code === 429) {
      clearQsatFromStorage();
      state.qsat = '';
      showPwdModal(true, t('tooManyAttempts'));
    } else setErrorI18n('loadError');
    return;
  }

  const data = decoded.data || {};
  state.shareRemark = data.share && typeof data.share.remark === 'string' ? data.share.remark.trim() : '';
  state.endTime = data.share ? data.share.end_time : null;
  updateHeaderText();
  renderExpire();

  renderCrumbs(data.segments);
  const items = Array.isArray(data.items) ? data.items : [];
  state.items = items;
  renderList(items);
}

function initQsatFromStorage() {
  try {
    const key = `qs_qsat_${state.token}`;
    const saved = sessionStorage.getItem(key);
    if (saved) state.qsat = saved;
  } catch (_) {}
}

function saveQsatToStorage(qsat) {
  try {
    const key = `qs_qsat_${state.token}`;
    sessionStorage.setItem(key, String(qsat || ''));
  } catch (_) {}
}

function clearQsatFromStorage() {
  try {
    const key = `qs_qsat_${state.token}`;
    sessionStorage.removeItem(key);
  } catch (_) {}
}

async function authByPassword(pwd) {
  try {
    const pwdHash = await sha256Hex(pwd);
    const payload = pwdHash ? { qt: state.token, pwdHash } : { qt: state.token, pwd: String(pwd || '') };
    const bodyBytes = qsbEncodeAuthReq(payload);
    const url = buildUrl('/api/quickShare/public/auth');
    const resp = await requestQsbByUrl(url, { method: 'POST', bodyBytes, expect: 'auth' });

    if (resp.status === 998) {
      clearQsatFromStorage();
      state.qsat = '';
      showPwdModal(true, t('pwdHint'));
      return;
    }
    if (resp.status === 999) {
      clearQsatFromStorage();
      state.qsat = '';
      showPwdModal(true, t('pwdWrong'));
      return;
    }
    if (resp.status === 429) {
      clearQsatFromStorage();
      state.qsat = '';
      showPwdModal(true, t('tooManyAttempts'));
      return;
    }

    const decoded = resp.decoded;
    const qsat = decoded && decoded.ok === true && decoded.qsat ? String(decoded.qsat) : '';
    if (!qsat) {
      showPwdModal(true, t('pwdWrong'));
      return;
    }
    state.qsat = qsat;
    saveQsatToStorage(qsat);
    showPwdModal(false);
    fetchList();
  } catch (_) {
    showPwdModal(true, t('pwdWrong'));
  }
}

function wireEvents() {
  if (elDlToggle) {
    elDlToggle.addEventListener('click', e => {
      e.stopPropagation();
      showDownloadsModal(true);
    });
  }
  elThemeToggle.addEventListener('click', e => {
    e.stopPropagation();
    toggleMenu('theme');
  });
  elLangToggle.addEventListener('click', e => {
    e.stopPropagation();
    toggleMenu('lang');
  });
  if (elDlClear) {
    elDlClear.addEventListener('click', e => {
      e.stopPropagation();
      clearDoneDownloads();
    });
  }
  if (elDlClose) {
    elDlClose.addEventListener('click', e => {
      e.stopPropagation();
      showDownloadsModal(false);
    });
  }
  if (elDlModal) {
    elDlModal.addEventListener('click', e => {
      if (e.target === elDlModal) showDownloadsModal(false);
    });
  }
  if (elMemoryDownloadCancel) {
    elMemoryDownloadCancel.addEventListener('click', e => {
      e.stopPropagation();
      hideMemoryDownloadModal(false);
    });
  }
  if (elMemoryDownloadConfirm) {
    elMemoryDownloadConfirm.addEventListener('click', e => {
      e.stopPropagation();
      hideMemoryDownloadModal(true);
    });
  }
  if (elMemoryDownloadModal) {
    elMemoryDownloadModal.addEventListener('click', e => {
      if (e.target === elMemoryDownloadModal) hideMemoryDownloadModal(false);
    });
  }
  elPwdSubmit.addEventListener('click', () => {
    const pwd = (elPwdInput.value || '').trim();
    if (!pwd) return;
    authByPassword(pwd);
  });
  elPwdInput.addEventListener('keydown', e => {
    if (e.key === 'Enter') elPwdSubmit.click();
  });
  if (elExpiredModal && elExpiredClose) {
    elExpiredModal.addEventListener('click', e => {
      if (e.target === elExpiredModal) showExpiredModal(false);
    });
    elExpiredClose.addEventListener('click', () => showExpiredModal(false));
  }

  document.addEventListener('click', () => {
    closeMenus();
  });
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape') {
      closeMenus();
      showDownloadsModal(false);
      hideMemoryDownloadModal(false);
      showExpiredModal(false);
    }
  });

  showViewerDownloadFab(false);
  showViewerNav(false);
}

async function init() {
  const ua = navigator.userAgent.toLowerCase();
  const isWechat = ua.includes('micromessenger');
  if (isWechat) {
    const tip = document.createElement('div');
    tip.className = 'wechatTip';
    tip.innerHTML = `<span class="wechatTipText">${t('wechatTip')}</span><button class="wechatTipClose" type="button">${svgIcon('close')}</button>`;
    document.body.appendChild(tip);
    const closeBtn = tip.querySelector('.wechatTipClose');
    const closeTip = () => {
      tip.style.opacity = '0';
      tip.style.transform = 'translateY(-100%)';
      setTimeout(() => tip.remove(), 300);
    };
    if (closeBtn) closeBtn.addEventListener('click', closeTip);
    setTimeout(closeTip, 3000);
  }
  setTheme(getTheme());
  if (window.QSLocales && typeof window.QSLocales.init === 'function') {
    await window.QSLocales.init(initLang);
  }
  await setLang(window.QS_I18N ? window.QS_I18N.locale : state.lang);
  wireEvents();
  initQsatFromStorage();
  let reconnectTimer = null;
  let reconnectAttempt = 0;
  let connecting = false;
  let manualClose = false;
  let connectPromise = null;
  let autoUpgradeTimer = null;
  let upgrading = false;

  const stopAllDownloadsByDisconnect = () => {
    for (const it of downloadsState.list) {
      if (!it) continue;
      if (it.status !== 'queued' && it.status !== 'downloading') continue;
      it.cancelRequested = true;
      it.status = 'failed';
      try {
        if (it.stream && typeof it.stream.abort === 'function') it.stream.abort();
      } catch (_) {}
      try {
        if (it.writable && typeof it.writable.abort === 'function') it.writable.abort();
      } catch (_) {}
      try {
        if (it.writer && typeof it.writer.abort === 'function') it.writer.abort();
      } catch (_) {}
      it.stream = null;
      it.writable = null;
      it.writer = null;
    }
    downloadsState.queue = downloadsState.queue.filter(x => x && x.status === 'queued');
    scheduleDownloadsUiUpdate({ immediate: true });
  };

  // 尝试将 relay 连接升级为 IPv6/直连
  const scheduleDirectUpgrade = relayP2p => {
    if (autoUpgradeTimer) clearTimeout(autoUpgradeTimer);
    autoUpgradeTimer = setTimeout(async () => {
      autoUpgradeTimer = null;
      if (manualClose || !state.p2p || state.p2p !== relayP2p) return;
      upgrading = true;
      console.log('[QuickShare][P2P] auto-upgrade: trying direct...');
      let directP2p = null;
      try {
        directP2p = await connectP2pByEncPairCode(state.encPairCode, {
          directOnly: true,
          onDisconnected: reason => {
            if (manualClose || upgrading) return;
            if (state.p2p === directP2p) state.p2p = null;
            updateDownloadsButton();
            scheduleReconnect(reason);
          },
        });
        if (directP2p.transportKind === 'relay' || directP2p.transportKind === 'unknown') {
          throw new Error('direct_not_available');
        }
        // 直连成功，替换 relay 连接
        if (state.p2p === relayP2p) {
          try {
            relayP2p.close();
          } catch (_) {}
          state.p2p = directP2p;
          updateDownloadsButton();
          if (!document.hidden) fetchList().catch(() => {});
          console.log('[QuickShare][P2P] auto-upgrade: switched to direct');
        } else {
          try {
            directP2p.close();
          } catch (_) {}
        }
      } catch (_) {
        console.log('[QuickShare][P2P] auto-upgrade: direct failed, keeping relay');
        try {
          if (directP2p) directP2p.close();
        } catch (_) {}
      } finally {
        upgrading = false;
      }
    }, 1500);
  };

  const closeP2p = () => {
    manualClose = true;
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
    clearTimeout(autoUpgradeTimer);
    autoUpgradeTimer = null;
    reconnectAttempt = 0;
    connecting = false;
    connectPromise = null;
    try {
      if (state.p2p && typeof state.p2p.close === 'function') state.p2p.close();
    } catch (_) {}
    state.p2p = null;
    cancelAllP2pFileFetches();
    stopP2pTinyObserver();
    updateDownloadsButton();
    setP2pConnecting(false);
  };

  const scheduleReconnect = reason => {
    if (!state.encPairCode) return;
    if (manualClose) return;
    if (connecting || connectPromise) return;
    clearTimeout(reconnectTimer);
    const delay = Math.min(10000, 800 * Math.pow(2, Math.min(6, reconnectAttempt)));
    reconnectAttempt += 1;
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null;
      connectP2p().catch(() => {});
    }, delay);
    stopAllDownloadsByDisconnect();
    cancelAllP2pFileFetches();
    stopP2pTinyObserver();
    setError('');
    setP2pConnecting(true, 'p2pReconnecting');
    toast(t('p2pReconnecting'));
    if (reason) {
    }
  };

  const connectP2p = async () => {
    if (!state.encPairCode) return;
    if (connectPromise) return await connectPromise;
    connectPromise = (async () => {
      if (connecting) return;
      connecting = true;
      manualClose = false;
      setP2pConnecting(true, reconnectAttempt > 0 ? 'p2pReconnecting' : 'p2pConnecting');
      try {
        if (state.p2p && typeof state.p2p.close === 'function') state.p2p.close();
      } catch (_) {}
      state.p2p = null;
      updateDownloadsButton();
      try {
        const p2p = await connectP2pByEncPairCode(state.encPairCode, {
          onDisconnected: reason => {
            if (manualClose || upgrading) return;
            try {
              if (p2p && typeof p2p.close === 'function') p2p.close();
            } catch (_) {}
            if (state.p2p === p2p) state.p2p = null;
            clearTimeout(autoUpgradeTimer);
            autoUpgradeTimer = null;
            updateDownloadsButton();
            scheduleReconnect(reason);
          },
        });
        state.p2p = p2p;
        reconnectAttempt = 0;
        setP2pConnecting(false);
        updateDownloadsButton();
        if (!document.hidden) fetchList().catch(() => {});
        // 若走了 relay，自动尝试升级为直连（IPv6 优先）
        if (p2p.transportKind === 'relay') {
          scheduleDirectUpgrade(p2p);
        }
      } catch (err) {
        scheduleReconnect(err && err.message ? String(err.message) : 'connect_failed');
        throw err;
      } finally {
        connecting = false;
      }
    })().finally(() => {
      connectPromise = null;
    });
    return await connectPromise;
  };

  state._p2pHooks = {
    reconnectNow: async reason => {
      if (!state.encPairCode) return false;
      if (manualClose) return false;
      setP2pConnecting(true, 'p2pReconnecting');
      try {
        await connectP2p();
        return !!state.p2p;
      } catch (_) {
        scheduleReconnect(reason || 'reconnect_failed');
        return false;
      }
    },
  };

  window.addEventListener('beforeunload', () => closeP2p());

  Promise.resolve()
    .then(async () => {
      if (state.encPairCode) await connectP2p();
    })
    .then(() => {
      fetchLoginWelcome();
      fetchList();
    })
    .catch(() => {
      setError('P2P Error');
    });
}
init();

