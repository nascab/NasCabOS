import './view.js'
import { createTOCView } from './ui/tree.js'
import { Overlayer } from './overlayer.js'
import { createT, resolveLocale } from './i18n.js'

const getCSS = ({ spacing, justify, hyphenate, fontSize, theme }) => `
    @namespace "http://www.w3.org/1999/xhtml";
    @namespace epub "http://www.idpf.org/2007/ops";
    html {
        color-scheme: ${theme === 'dark' ? 'dark' : 'light'};
        font-size: ${fontSize}px;
        background: ${theme === 'dark' ? '#0f1115' : '#ffffff'};
        color: ${theme === 'dark' ? '#e7e7e7' : '#111111'};
    }
    body {
        background: ${theme === 'dark' ? '#0f1115' : '#ffffff'} !important;
        color: ${theme === 'dark' ? '#e7e7e7' : '#111111'} !important;
    }
    span, font {
        color: inherit !important;
    }
    div,
    h1, h2, h3, h4, h5, h6 {
        color: inherit !important;
    }
    a:link { color: ${theme === 'dark' ? '#8ab4f8' : '#1a73e8'}; }
    a:visited { color: ${theme === 'dark' ? '#c58af9' : '#681da8'}; }
    p, li, blockquote, dd {
        color: inherit !important;
        line-height: ${spacing};
        text-align: ${justify ? 'justify' : 'start'};
        -webkit-hyphens: ${hyphenate ? 'auto' : 'manual'};
        hyphens: ${hyphenate ? 'auto' : 'manual'};
        -webkit-hyphenate-limit-before: 3;
        -webkit-hyphenate-limit-after: 2;
        -webkit-hyphenate-limit-lines: 2;
        hanging-punctuation: allow-end last;
        widows: 2;
    }
    /* prevent the above from overriding the align attribute */
    [align="left"] { text-align: left; }
    [align="right"] { text-align: right; }
    [align="center"] { text-align: center; }
    [align="justify"] { text-align: justify; }

    pre {
        white-space: pre-wrap !important;
    }
    .fs,
    .fs > div {
        width: auto !important;
        height: auto !important;
        overflow: visible !important;
    }
    img.singlePage {
        position: static !important;
        width: auto !important;
        height: auto !important;
        max-width: 100% !important;
        display: block !important;
        margin: 0 auto !important;
    }
    aside[epub|type~="endnote"],
    aside[epub|type~="footnote"],
    aside[epub|type~="note"],
    aside[epub|type~="rearnote"] {
        display: none;
    }
`

const $ = document.querySelector.bind(document)

const params = new URLSearchParams(location.search)
const fileHash = String(params.get('file_hash') || params.get('fileHash') || '').trim()
const accessToken = String(params.get('accessToken') || '').trim()
const apiBaseParam = String(params.get('apiBase') || params.get('api_base') || '').trim()

const resolveApiUrl = input => {
    const raw = String(input ?? '').trim()
    if (!raw) return raw
    if (!apiBaseParam) return raw
    try {
        return new URL(raw, apiBaseParam).toString()
    } catch (_) {
        return raw
    }
}

const normalizeP2pUrl = raw => {
    const s = String(raw ?? '').trim()
    if (!s) return s
    try {
        const u = new URL(s, location.href)
        if (u.hostname !== 'p2p.local') return s
        return `/__p2p__${u.pathname}${u.search}${u.hash}`
    } catch (_) {
        return s
    }
}

const requestJson = async (url, { method = 'GET', body } = {}) => {
    const headers = {}
    if (accessToken) headers.Authorization = `Bearer ${accessToken}`
    if (body !== undefined) headers['Content-Type'] = 'application/json'

    const res = await fetch(normalizeP2pUrl(resolveApiUrl(url)), {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
    })

    try {
        return await res.json()
    } catch (_) {
        return null
    }
}

const normalizeLanguageTag = lang => {
    const raw = (lang ?? '').toString().trim()
    if (!raw) return ''
    const normalized = raw.replace(/_/g, '-')
    const parts = normalized.split('-').filter(Boolean)
    if (parts.length >= 2) return `${parts[0].toLowerCase()}-${parts[1].toUpperCase()}`
    return parts[0].toLowerCase()
}

const uiLang = normalizeLanguageTag(params.get('lang') || params.get('locale'))
const navLang = normalizeLanguageTag(navigator.language)
const locale = resolveLocale(uiLang || navLang || 'en')

const defaultTheme = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
const defaultSettings = {
    fontSize: 16,
    spacing: 1.4,
    flow: 'paginated',
    theme: defaultTheme,
    showProgressBar: true,
}
const settingsStorageKey = 'nascab.reader.settings.v1'

const t = createT(locale)

let percentFormat
let listFormat
try {
    percentFormat = new Intl.NumberFormat(locale, { style: 'percent' })
    listFormat = new Intl.ListFormat(locale, { style: 'short', type: 'conjunction' })
} catch (_) {
    percentFormat = new Intl.NumberFormat('en', { style: 'percent' })
    listFormat = new Intl.ListFormat('en', { style: 'short', type: 'conjunction' })
}

const applyStaticI18n = () => {
    const dropTitleEl = $('#drop-target h1')
    if (dropTitleEl) dropTitleEl.innerText = t('dropTitle')

    const fileButton = $('#file-button')
    if (fileButton) fileButton.innerText = t('chooseFile')

    const dropP = $('#drop-target p')
    if (dropP && fileButton) {
        dropP.replaceChildren(
            document.createTextNode(`${t('dropPrefix')} `),
            fileButton,
            document.createTextNode(` ${t('dropSuffix')}`),
        )
    }

    const sideBarButton = $('#side-bar-button')
    if (sideBarButton) sideBarButton.setAttribute('aria-label', t('showSidebar'))

    const settingsButton = $('#settings-button')
    if (settingsButton) settingsButton.setAttribute('aria-label', t('showSettings'))

    const leftButton = $('#left-button')
    if (leftButton) leftButton.setAttribute('aria-label', t('goLeft'))

    const rightButton = $('#right-button')
    if (rightButton) rightButton.setAttribute('aria-label', t('goRight'))

    document.title = t('appTitle')

    const settingsTitle = $('#settings-title')
    if (settingsTitle) settingsTitle.innerText = t('settingsTitle')

    const settingsClose = $('#settings-close')
    if (settingsClose) settingsClose.innerText = t('close')

    const fontSizeLabel = $('#setting-font-size-label')
    if (fontSizeLabel) fontSizeLabel.innerText = t('fontSize')

    const spacingLabel = $('#setting-line-spacing-label')
    if (spacingLabel) spacingLabel.innerText = t('lineSpacing')

    const turningLabel = $('#setting-turning-label')
    if (turningLabel) turningLabel.innerText = t('turning')

    const themeLabel = $('#setting-theme-label')
    if (themeLabel) themeLabel.innerText = t('theme')

    const progressBarLabel = $('#setting-progress-bar-label')
    if (progressBarLabel) progressBarLabel.innerText = t('progressBar')

    const turningSelect = $('#setting-turning')
    if (turningSelect) {
        const options = turningSelect.querySelectorAll('option')
        if (options[0]) options[0].textContent = t('turningPaginated')
        if (options[1]) options[1].textContent = t('turningScrolled')
    }

    const themeSelect = $('#setting-theme')
    if (themeSelect) {
        const options = themeSelect.querySelectorAll('option')
        if (options[0]) options[0].textContent = t('themeLight')
        if (options[1]) options[1].textContent = t('themeDark')
    }

    const progressBarSelect = $('#setting-progress-bar')
    if (progressBarSelect) {
        const options = progressBarSelect.querySelectorAll('option')
        if (options[0]) options[0].textContent = t('progressBarShow')
        if (options[1]) options[1].textContent = t('progressBarHide')
    }
}

const clampNumber = (value, min, max) => Math.max(min, Math.min(max, value))

const loadSettings = () => {
    try {
        const raw = localStorage.getItem(settingsStorageKey)
        if (!raw) return { ...defaultSettings }
        const parsed = JSON.parse(raw) || {}
        const fontSize = clampNumber(parseInt(parsed.fontSize, 10) || defaultSettings.fontSize, 12, 28)
        const spacing = clampNumber(parseFloat(parsed.spacing) || defaultSettings.spacing, 1.0, 2.4)
        const flow = parsed.flow === 'scrolled' ? 'scrolled' : 'paginated'
        const theme = parsed.theme === 'dark' ? 'dark' : 'light'
        const showProgressBar = parsed.showProgressBar === undefined ? defaultSettings.showProgressBar : !!parsed.showProgressBar
        return { fontSize, spacing, flow, theme, showProgressBar }
    } catch (_) {
        return { ...defaultSettings }
    }
}

const saveSettings = settings => {
    try {
        localStorage.setItem(settingsStorageKey, JSON.stringify(settings))
    } catch (_) {}
}

const applyThemeToShell = theme => {
    document.documentElement.dataset.theme = theme === 'dark' ? 'dark' : 'light'
}

const formatFontSizeValue = v => `${v}px`
const formatSpacingValue = v => `${v.toFixed(1)}x`

const formatLanguageMap = x => {
    if (!x) return ''
    if (typeof x === 'string') return x
    const keys = Object.keys(x)
    return x[keys[0]]
}

const formatOneContributor = contributor => typeof contributor === 'string'
    ? contributor : formatLanguageMap(contributor?.name)

const formatContributor = contributor => Array.isArray(contributor)
    ? listFormat.format(contributor.map(formatOneContributor))
    : formatOneContributor(contributor)

const isEditableTarget = target => {
    const el = target instanceof Element ? target : target?.parentElement
    if (!el) return false
    if (el.closest('#settings-modal')) return true
    if (el instanceof HTMLInputElement) {
        const type = (el.type || '').toLowerCase()
        return type !== 'button' && type !== 'checkbox' && type !== 'radio' && type !== 'range'
    }
    return !!el.closest('textarea, select, [contenteditable], [role="textbox"]')
        || !!el.isContentEditable
}

class Reader {
    #tocView
    #wheelAccum = 0
    #wheelLockUntil = 0
    #wheelLastAt = 0
    #preferenceSaveTimer = 0
    #progressSaveTimer = 0
    #pendingProgress = null
    #touchGesture = null
    #suppressClickUntil = 0
    #tapZonePointer = null
    #boundHandleKeydown = this.#handleKeydown.bind(this)
    #boundHandleWheel = this.#handleWheel.bind(this)
    #boundFocusReadingSurface = () => this.#focusReadingSurface()
    #boundHandleTouchStart = this.#handleTouchStart.bind(this)
    #boundHandleTouchEnd = this.#handleTouchEnd.bind(this)
    #boundHandleTouchCancel = this.#handleTouchCancel.bind(this)
    #boundHandleTapZonePointerDown = this.#handleTapZonePointerDown.bind(this)
    #boundHandleTapZonePointerMove = this.#handleTapZonePointerMove.bind(this)
    #boundHandleTapZonePointerUp = this.#handleTapZonePointerUp.bind(this)
    #boundHandleTapZonePointerCancel = this.#handleTapZonePointerCancel.bind(this)
    settings = loadSettings()
    style = { justify: true, hyphenate: true }
    annotations = new Map()
    annotationsByValue = new Map()
    closeSideBar() {
        $('#dimming-overlay').classList.remove('show')
        $('#side-bar').classList.remove('show')
    }
    applySettings() {
        applyThemeToShell(this.settings.theme)

        const slider = $('#progress-slider')
        if (slider) {
            const show = !!this.settings.showProgressBar
            slider.style.display = show ? '' : 'none'
            slider.style.visibility = show ? 'visible' : 'hidden'
        }

        const tapZonesVisible = !!this.view && this.settings.flow === 'paginated'
        $('#left-tap-zone')?.classList.toggle('show', tapZonesVisible)
        $('#right-tap-zone')?.classList.toggle('show', tapZonesVisible)

        if (!this.view) return
        if (this.view.book?.format === 'pdf') return
        this.view.renderer.setStyles?.(getCSS({
            spacing: this.settings.spacing,
            justify: this.style.justify,
            hyphenate: this.style.hyphenate,
            fontSize: this.settings.fontSize,
            theme: this.settings.theme,
        }))
        this.view.renderer.setAttribute('flow', this.settings.flow)
    }
    constructor() {
        $('#side-bar-button').addEventListener('click', () => {
            $('#dimming-overlay').classList.add('show')
            $('#side-bar').classList.add('show')
        })
        $('#dimming-overlay').addEventListener('click', () => this.closeSideBar())

        const overlay = $('#settings-modal-overlay')
        const modal = $('#settings-modal')
        const btn = $('#settings-button')
        const closeBtn = $('#settings-close')

        const isOpen = () => modal.classList.contains('show')

        const close = () => {
            overlay.classList.remove('show')
            modal.classList.remove('show')
        }

        const open = () => {
            this.syncSettingsToUi()
            overlay.classList.add('show')
            modal.classList.add('show')
            closeBtn.focus()
        }

        btn.addEventListener('click', () => {
            if (isOpen()) close()
            else open()
        })
        closeBtn.addEventListener('click', close)
        overlay.addEventListener('click', close)

        document.addEventListener('keydown', e => {
            if (e.key !== 'Escape') return
            if (!isOpen()) return
            e.preventDefault()
            close()
        })

        this.bindSettingsUi()
        this.bindTapZones()
        this.applySettings()
    }
    bindTapZones() {
        const leftZone = $('#left-tap-zone')
        const rightZone = $('#right-tap-zone')
        const bindZone = (zone, direction) => {
            zone.dataset.direction = direction
            zone.addEventListener('pointerdown', this.#boundHandleTapZonePointerDown)
            zone.addEventListener('pointermove', this.#boundHandleTapZonePointerMove)
            zone.addEventListener('pointerup', this.#boundHandleTapZonePointerUp)
            zone.addEventListener('pointercancel', this.#boundHandleTapZonePointerCancel)
        }
        if (leftZone) bindZone(leftZone, 'left')
        if (rightZone) bindZone(rightZone, 'right')
    }
    async loadPreferenceFromServer() {
        if (!fileHash) return
        const resp = await requestJson(`/api/book/preference?file_hash=${encodeURIComponent(fileHash)}`).catch(() => null)
        const data = resp && resp.success ? resp.data : null
        if (!data) return

        if (data.font_size !== undefined && data.font_size !== null) {
            this.settings.fontSize = clampNumber(parseInt(data.font_size, 10) || defaultSettings.fontSize, 12, 28)
        }
        if (data.spacing !== undefined && data.spacing !== null) {
            this.settings.spacing = clampNumber(parseFloat(data.spacing) || defaultSettings.spacing, 1.0, 2.4)
        }
        if (data.flow !== undefined && data.flow !== null) {
            this.settings.flow = String(data.flow).trim() === 'scrolled' ? 'scrolled' : 'paginated'
        }
        if (data.theme !== undefined && data.theme !== null) {
            this.settings.theme = String(data.theme).trim() === 'dark' ? 'dark' : 'light'
        }

        saveSettings(this.settings)
        this.applySettings()
    }
    queueSavePreferenceToServer() {
        if (!fileHash) return
        if (this.#preferenceSaveTimer) window.clearTimeout(this.#preferenceSaveTimer)
        this.#preferenceSaveTimer = window.setTimeout(() => {
            this.#preferenceSaveTimer = 0
            requestJson('/api/book/preference', {
                method: 'POST',
                body: {
                    file_hash: fileHash,
                    font_size: this.settings.fontSize,
                    spacing: this.settings.spacing,
                    flow: this.settings.flow,
                    theme: this.settings.theme,
                },
            }).catch(() => null)
        }, 350)
    }
    queueSaveProgressToServer(detail) {
        if (!fileHash) return
        const fraction = typeof detail?.fraction === 'number' ? detail.fraction : Number(detail?.fraction)
        const location = detail && detail.location ? detail.location : null
        const pageItem = detail && detail.pageItem ? detail.pageItem : null

        let currentPage = 0
        if (pageItem && pageItem.label !== undefined && pageItem.label !== null) {
            const n = parseInt(String(pageItem.label), 10)
            if (!Number.isNaN(n)) currentPage = n
        } else if (location && location.current !== undefined && location.current !== null) {
            const n = Number(location.current) || 0
            currentPage = Math.max(0, Math.floor(n))
        }

        let totalPage = null
        if (location && location.total !== undefined && location.total !== null) {
            const n = Number(location.total) || 0
            totalPage = n > 0 ? Math.floor(n) : null
        }

        this.#pendingProgress = { currentPage, totalPage }

        if (this.#progressSaveTimer) window.clearTimeout(this.#progressSaveTimer)
        this.#progressSaveTimer = window.setTimeout(() => {
            this.#progressSaveTimer = 0
            const pending = this.#pendingProgress
            if (!pending) return
            const body = {
                file_hash: fileHash,
                current_page: pending.currentPage,
                fraction: Number.isFinite(fraction) ? fraction : 0,
            }
            if (pending.totalPage) body.total_page = pending.totalPage
            requestJson('/api/book/history', { method: 'POST', body }).catch(() => null)
        }, 3000)
    }
    bindSettingsUi() {
        const fontSizeInput = $('#setting-font-size')
        const fontSizeValue = $('#setting-font-size-value')
        const spacingInput = $('#setting-line-spacing')
        const spacingValue = $('#setting-line-spacing-value')
        const turningSelect = $('#setting-turning')
        const themeSelect = $('#setting-theme')
        const progressBarSelect = $('#setting-progress-bar')

        const commit = () => {
            saveSettings(this.settings)
            this.applySettings()
            this.queueSavePreferenceToServer()
        }

        fontSizeInput.addEventListener('input', () => {
            this.settings.fontSize = clampNumber(parseInt(fontSizeInput.value, 10) || defaultSettings.fontSize, 12, 28)
            fontSizeValue.innerText = formatFontSizeValue(this.settings.fontSize)
            commit()
        })

        spacingInput.addEventListener('input', () => {
            this.settings.spacing = clampNumber(parseFloat(spacingInput.value) || defaultSettings.spacing, 1.0, 2.4)
            spacingValue.innerText = formatSpacingValue(this.settings.spacing)
            commit()
        })

        turningSelect.addEventListener('change', () => {
            this.settings.flow = turningSelect.value === 'scrolled' ? 'scrolled' : 'paginated'
            commit()
        })

        themeSelect.addEventListener('change', () => {
            this.settings.theme = themeSelect.value === 'dark' ? 'dark' : 'light'
            commit()
        })

        progressBarSelect.addEventListener('change', () => {
            this.settings.showProgressBar = progressBarSelect.value !== 'hide'
            commit()
        })
    }
    syncSettingsToUi() {
        const fontSizeInput = $('#setting-font-size')
        const fontSizeValue = $('#setting-font-size-value')
        const spacingInput = $('#setting-line-spacing')
        const spacingValue = $('#setting-line-spacing-value')
        const turningSelect = $('#setting-turning')
        const themeSelect = $('#setting-theme')
        const progressBarSelect = $('#setting-progress-bar')

        fontSizeInput.value = `${this.settings.fontSize}`
        fontSizeValue.innerText = formatFontSizeValue(this.settings.fontSize)
        spacingInput.value = `${this.settings.spacing}`
        spacingValue.innerText = formatSpacingValue(this.settings.spacing)
        turningSelect.value = this.settings.flow
        themeSelect.value = this.settings.theme
        progressBarSelect.value = this.settings.showProgressBar ? 'show' : 'hide'
    }
    async open(file) {
        this.view = document.createElement('foliate-view')
        this.view.tabIndex = 0
        document.body.append(this.view)
        await this.view.open(file)
        await this.loadPreferenceFromServer().catch(() => {})
        this.view.addEventListener('load', this.#onLoad.bind(this))
        this.view.addEventListener('relocate', this.#onRelocate.bind(this))
        this.view.addEventListener('wheel', this.#boundHandleWheel, { passive: false })
        this.view.addEventListener('pointerdown', this.#boundFocusReadingSurface)
        this.#attachPagingInteractions(this.view)

        const { book } = this.view
        book.transformTarget?.addEventListener('data', ({ detail }) => {
            detail.data = Promise.resolve(detail.data).catch(e => {
                console.error(new Error(`Failed to load ${detail.name}`, { cause: e }))
                return ''
            })
        })
        this.applySettings()
        const jumped = await this.jumpToLastProgress().catch(() => false)
        if (!jumped) await this.view.goToFraction(0)

        $('#header-bar').style.visibility = 'visible'
        $('#nav-bar').style.visibility = 'visible'
        $('#left-button').addEventListener('click', () => this.view.goLeft())
        $('#right-button').addEventListener('click', () => this.view.goRight())

        const slider = $('#progress-slider')
        slider.dir = book.dir
        slider.addEventListener('input', e =>
            this.view.goToFraction(parseFloat(e.target.value)))
        for (const fraction of this.view.getSectionFractions()) {
            const option = document.createElement('option')
            option.value = fraction
            $('#tick-marks').append(option)
        }

        document.body.tabIndex = -1
        window.addEventListener('keydown', this.#boundHandleKeydown, true)
        requestAnimationFrame(() => this.#focusReadingSurface())

        const title = formatLanguageMap(book.metadata?.title) || t('untitledBook')
        document.title = title
        $('#side-bar-title').innerText = title
        $('#side-bar-author').innerText = formatContributor(book.metadata?.author)
        Promise.resolve(book.getCover?.())?.then(blob =>
            blob ? $('#side-bar-cover').src = URL.createObjectURL(blob) : null)

        const toc = book.toc
        if (toc) {
            this.#tocView = createTOCView(toc, href => {
                this.view.goTo(href).catch(e => console.error(e))
                this.closeSideBar()
            })
            $('#toc-view').append(this.#tocView.element)
        }

        // load and show highlights embedded in the file by Calibre
        const bookmarks = await book.getCalibreBookmarks?.()
        if (bookmarks) {
            const { fromCalibreHighlight } = await import('./epubcfi.js')
            for (const obj of bookmarks) {
                if (obj.type === 'highlight') {
                    const value = fromCalibreHighlight(obj)
                    const color = obj.style.which
                    const note = obj.notes
                    const annotation = { value, color, note }
                    const list = this.annotations.get(obj.spine_index)
                    if (list) list.push(annotation)
                    else this.annotations.set(obj.spine_index, [annotation])
                    this.annotationsByValue.set(value, annotation)
                }
            }
            this.view.addEventListener('create-overlay', e => {
                const { index } = e.detail
                const list = this.annotations.get(index)
                if (list) for (const annotation of list)
                    this.view.addAnnotation(annotation)
            })
            this.view.addEventListener('draw-annotation', e => {
                const { draw, annotation } = e.detail
                const { color } = annotation
                draw(Overlayer.highlight, { color })
            })
            this.view.addEventListener('show-annotation', e => {
                const annotation = this.annotationsByValue.get(e.detail.value)
                if (annotation.note) alert(annotation.note)
            })
        }
    }
    async jumpToLastProgress() {
        if (!fileHash) return
        const resp = await requestJson(`/api/book/history?file_hash=${encodeURIComponent(fileHash)}`).catch(() => null)
        const data = resp && resp.success ? resp.data : null
        if (!data) return false
        const fracRaw = Number(data.fraction)
        const frac = Number.isFinite(fracRaw) ? Math.max(0, Math.min(1, fracRaw)) : 0
        if (!frac) return false
        await this.view.goToFraction(frac)
        return true
    }
    #focusReadingSurface(doc = document) {
        if ($('#settings-modal')?.classList.contains('show')) return
        try {
            doc?.defaultView?.focus?.()
        } catch (_) {}
        try {
            this.view?.focus?.({ preventScroll: true })
        } catch (_) {
            this.view?.focus?.()
        }
    }
    #isPagingInteractionEnabled() {
        if (!this.view) return false
        if (this.settings.flow !== 'paginated') return false
        if ($('#settings-modal')?.classList.contains('show')) return false
        if ($('#side-bar')?.classList.contains('show')) return false
        return true
    }
    #getInteractionBounds(currentTarget) {
        if (currentTarget instanceof Document) {
            const width = currentTarget.defaultView?.innerWidth
                || currentTarget.documentElement?.clientWidth
                || 0
            return { left: 0, width }
        }
        if (currentTarget instanceof Element) {
            const rect = currentTarget.getBoundingClientRect()
            return { left: rect.left, width: rect.width }
        }
        return { left: 0, width: window.innerWidth || document.documentElement.clientWidth || 0 }
    }
    #attachPagingInteractions(target) {
        target.addEventListener('touchstart', this.#boundHandleTouchStart, { passive: true })
        target.addEventListener('touchend', this.#boundHandleTouchEnd, { passive: false })
        target.addEventListener('touchcancel', this.#boundHandleTouchCancel, { passive: true })
    }
    #handleTapZonePointerDown(event) {
        if (!this.#isPagingInteractionEnabled()) {
            this.#tapZonePointer = null
            return
        }
        if (!event.isPrimary) {
            this.#tapZonePointer = null
            return
        }
        if (event.pointerType === 'mouse' && event.button !== 0) {
            this.#tapZonePointer = null
            return
        }
        this.#tapZonePointer = {
            pointerId: event.pointerId,
            pointerType: event.pointerType,
            direction: event.currentTarget?.dataset?.direction ?? '',
            startX: event.clientX,
            startY: event.clientY,
            startedAt: Date.now(),
            swipeTriggered: false,
        }
        event.currentTarget?.setPointerCapture?.(event.pointerId)
    }
    #handleTapZonePointerMove(event) {
        const gesture = this.#tapZonePointer
        if (!gesture) return
        if (gesture.pointerId !== event.pointerId) return
        if (!this.#isPagingInteractionEnabled()) return
        if (gesture.swipeTriggered) return

        const absX = Math.abs(event.clientX - gesture.startX)
        const absY = Math.abs(event.clientY - gesture.startY)
        const width = Math.max(window.innerWidth || 0, document.documentElement?.clientWidth || 0)
        const swipeThreshold = clampNumber(Math.round(width * 0.05), 16, 36)
        const fastFlickThreshold = clampNumber(Math.round(width * 0.03), 12, 24)
        const duration = Date.now() - gesture.startedAt
        const isHorizontalSwipe = absX >= swipeThreshold && absX > absY * 0.9
        const isFastFlick = duration <= 260
            && absX >= fastFlickThreshold
            && absX > absY * 0.75
        if (!isHorizontalSwipe && !isFastFlick) return

        gesture.swipeTriggered = true
        this.#suppressClickUntil = Date.now() + 450
        event.preventDefault()
        if (event.clientX < gesture.startX) this.view.goRight()
        else this.view.goLeft()
    }
    #handleTapZonePointerUp(event) {
        const gesture = this.#tapZonePointer
        this.#tapZonePointer = null
        if (!gesture) return
        event.currentTarget?.releasePointerCapture?.(event.pointerId)
        if (gesture.pointerId !== event.pointerId) return
        if (!this.#isPagingInteractionEnabled()) return
        if (!event.isPrimary) return
        if (Date.now() < this.#suppressClickUntil) return
        if (gesture.pointerType === 'mouse' && event.button !== 0) return
        if (gesture.swipeTriggered) return

        const absX = Math.abs(event.clientX - gesture.startX)
        const absY = Math.abs(event.clientY - gesture.startY)
        const duration = Date.now() - gesture.startedAt
        const maxOffset = gesture.pointerType === 'mouse' ? 12 : 20
        const maxDuration = gesture.pointerType === 'mouse' ? 400 : 500
        if (duration > maxDuration || absX > maxOffset || absY > maxOffset) return
        this.#suppressClickUntil = Date.now() + 250
        event.preventDefault()
        if (gesture.direction === 'left') this.view.goLeft()
        else if (gesture.direction === 'right') this.view.goRight()
    }
    #handleTapZonePointerCancel(event) {
        event?.currentTarget?.releasePointerCapture?.(event.pointerId)
        this.#tapZonePointer = null
    }
    #handleTouchStart(event) {
        if (!this.#isPagingInteractionEnabled()) {
            this.#touchGesture = null
            return
        }
        if (event.touches.length !== 1) {
            this.#touchGesture = null
            return
        }
        const touch = event.touches[0]
        this.#touchGesture = {
            startX: touch.clientX,
            startY: touch.clientY,
            startedAt: Date.now(),
        }
    }
    #handleTouchEnd(event) {
        const gesture = this.#touchGesture
        this.#touchGesture = null
        if (!gesture) return
        if (!this.#isPagingInteractionEnabled()) return
        if (Date.now() < this.#suppressClickUntil) return
        if (event.changedTouches.length !== 1) return

        const touch = event.changedTouches[0]
        const deltaX = touch.clientX - gesture.startX
        const deltaY = touch.clientY - gesture.startY
        const absX = Math.abs(deltaX)
        const absY = Math.abs(deltaY)
        const duration = Date.now() - gesture.startedAt
        const { width } = this.#getInteractionBounds(event.currentTarget)
        if (width <= 0) return
        const swipeThreshold = clampNumber(Math.round(width * 0.05), 16, 36)
        const fastFlickThreshold = clampNumber(Math.round(width * 0.03), 12, 24)
        const isHorizontalSwipe = absX >= swipeThreshold && absX > absY * 0.9
        const isFastFlick = duration <= 260
            && absX >= fastFlickThreshold
            && absX > absY * 0.75

        if (isHorizontalSwipe || isFastFlick) {
            this.#suppressClickUntil = Date.now() + 450
            event.preventDefault()
            if (deltaX < 0) this.view.goRight()
            else this.view.goLeft()
            return
        }

        if (duration > 400 || absX > 20 || absY > 20) return
    }
    #handleTouchCancel() {
        this.#touchGesture = null
    }
    #handleKeydown(event) {
        if (!this.view) return
        if (event.defaultPrevented) return
        if (event.altKey || event.ctrlKey || event.metaKey) return
        if (isEditableTarget(event.target)) return

        const k = event.key
        const settingsOpen = $('#settings-modal')?.classList.contains('show')
        if (settingsOpen) return
        if (k === 'ArrowLeft' || k === 'h') {
            event.preventDefault()
            this.view.goLeft()
        } else if (k === 'ArrowRight' || k === 'l') {
            event.preventDefault()
            this.view.goRight()
        }
    }
    #handleWheel(event) {
        if (this.settings.flow !== 'paginated') return
        if (!this.view) return
        if (event.ctrlKey || event.metaKey) return
        if ($('#settings-modal')?.classList.contains('show')) return

        event.preventDefault()

        const now = Date.now()
        if (now < this.#wheelLockUntil) return
        if (now - this.#wheelLastAt > 200) this.#wheelAccum = 0
        this.#wheelLastAt = now

        const rawDelta = Math.abs(event.deltaY) >= Math.abs(event.deltaX) ? event.deltaY : event.deltaX
        if (!rawDelta) return

        if (event.deltaMode === 1 || event.deltaMode === 2) {
            this.#wheelLockUntil = now + 250
            if (rawDelta < 0) this.view.goRight()
            else this.view.goLeft()
            return
        }

        if (Math.abs(rawDelta) >= 50) {
            this.#wheelLockUntil = now + 250
            if (rawDelta > 0) this.view.goRight()
            else this.view.goLeft()
            return
        }

        this.#wheelAccum += rawDelta

        const threshold = 1
        if (Math.abs(this.#wheelAccum) < threshold) return

        const direction = this.#wheelAccum > 0 ? 1 : -1
        this.#wheelAccum = 0
        this.#wheelLockUntil = now + 250

        if (direction > 0) this.view.goRight()
        else this.view.goLeft()
    }
    #onLoad({ detail: { doc } }) {
        doc.addEventListener('keydown', this.#boundHandleKeydown)
        doc.addEventListener('wheel', this.#boundHandleWheel, { passive: false })
        doc.addEventListener('pointerdown', () => this.#focusReadingSurface(doc))
        this.#attachPagingInteractions(doc)
    }
    #onRelocate({ detail }) {
        const fractionRaw = detail?.fraction
        const fraction = typeof fractionRaw === 'number' ? fractionRaw : Number(fractionRaw)
        const location = detail?.location ?? null
        const tocItem = detail?.tocItem ?? null
        const pageItem = detail?.pageItem ?? null

        const percent = Number.isFinite(fraction) ? percentFormat.format(fraction) : ''
        const loc = pageItem && pageItem.label !== undefined && pageItem.label !== null
            ? `${t('page')} ${pageItem.label}`
            : (location && location.current !== undefined && location.current !== null
                  ? `${t('location')} ${location.current}`
                  : '')
        const slider = $('#progress-slider')
        if (slider && this.settings.showProgressBar) {
            slider.style.visibility = 'visible'
            if (Number.isFinite(fraction)) slider.value = fraction
            const title = percent && loc ? `${percent} · ${loc}` : (percent || loc)
            if (title) slider.title = title
        }
        if (tocItem?.href) this.#tocView?.setCurrentHref?.(tocItem.href)
        this.queueSaveProgressToServer(detail)
    }
}

const open = async file => {
    document.body.removeChild($('#drop-target'))
    const reader = new Reader()
    globalThis.reader = reader
    await reader.open(file)
}

const dragOverHandler = e => e.preventDefault()
const dropHandler = e => {
    e.preventDefault()
    const item = Array.from(e.dataTransfer.items)
        .find(item => item.kind === 'file')
    if (item) {
        const entry = item.webkitGetAsEntry()
        open(entry.isFile ? item.getAsFile() : entry).catch(e => console.error(e))
    }
}
const dropTarget = $('#drop-target')
dropTarget.addEventListener('drop', dropHandler)
dropTarget.addEventListener('dragover', dragOverHandler)

$('#file-input').addEventListener('change', e =>
    open(e.target.files[0]).catch(e => console.error(e)))
$('#file-button').addEventListener('click', () => $('#file-input').click())

applyStaticI18n()
const url = normalizeP2pUrl(params.get('url'))
if (url) open(url).catch(e => console.error(e))
else dropTarget.style.visibility = 'visible'
