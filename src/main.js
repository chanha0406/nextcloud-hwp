/**
 * SPDX-FileCopyrightText: 2026 HWP Documents contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Vue 2 Options API component for OCA.Viewer (no Vue import).
 * Embeds self-hosted @rhwp/editor (rhwp-studio iframe) with DAV save.
 */

const MIMES = [
	'application/x-hwp',
	'application/x-hwp-v5',
	'application/x-hwpx',
]

/** Bump with appinfo version so browsers do not reuse stale chunks. */
const ASSET_VERSION = '1.2.2'

/**
 * @param {string} url
 * @returns {string}
 */
function withCacheBust(url) {
	const sep = url.includes('?') ? '&' : '?'
	return `${url}${sep}v=${ASSET_VERSION}`
}

/**
 * @param {string} name
 * @returns {string}
 */
function appJsUrl(name) {
	let url
	if (typeof OC !== 'undefined' && typeof OC.filePath === 'function') {
		url = OC.filePath('hwpdocuments', 'js', name)
	} else {
		const base = (typeof OC !== 'undefined' && OC.appswebroots?.hwpdocuments)
			? OC.appswebroots.hwpdocuments
			: '/custom_apps/hwpdocuments'
		url = `${base}/js/${name}`
	}
	try {
		url = new URL(url, window.location.origin).href
	} catch (e) {
		// keep
	}
	return withCacheBust(url)
}

/**
 * Self-hosted studio (mirrored under custom_apps/hwpdocuments/studio).
 * @returns {string}
 */
function studioUrl() {
	const base = (typeof OC !== 'undefined' && OC.appswebroots?.hwpdocuments)
		? OC.appswebroots.hwpdocuments
		: '/custom_apps/hwpdocuments'
	try {
		return new URL(`${base}/studio/index.html`, window.location.origin).href
	} catch (e) {
		return `${base}/studio/index.html`
	}
}

let createEditorPromise = null

/**
 * @returns {Promise<(container: string|HTMLElement, options?: object) => Promise<object>>}
 */
function loadCreateEditor() {
	if (!createEditorPromise) {
		const url = appJsUrl('editor/index.js')
		console.info('[hwpdocuments] importing @rhwp/editor', url)
		createEditorPromise = import(/* @vite-ignore */ url)
			.then((mod) => mod.createEditor)
			.catch((e) => {
				createEditorPromise = null
				throw e
			})
	}
	return createEditorPromise
}

/**
 * @param {string} url
 * @param {AbortSignal} signal
 * @returns {Promise<ArrayBuffer>}
 */
async function downloadFile(url, signal) {
	console.info('[hwpdocuments] downloading', url)
	const response = await fetch(url, {
		credentials: 'same-origin',
		signal,
		headers: {
			requesttoken: window.oc_requesttoken || '',
		},
	})
	if (!response.ok) {
		throw new Error(`Download failed: HTTP ${response.status}`)
	}
	const buffer = await response.arrayBuffer()
	console.info('[hwpdocuments] downloaded bytes', buffer.byteLength)
	return buffer
}

/**
 * @param {string} url
 * @param {Uint8Array|ArrayBuffer} bytes
 * @param {string} mime
 */
async function uploadFile(url, bytes, mime) {
	const body = bytes instanceof Uint8Array
		? bytes
		: new Uint8Array(bytes)
	const response = await fetch(url, {
		method: 'PUT',
		credentials: 'same-origin',
		headers: {
			'Content-Type': mime || 'application/octet-stream',
			requesttoken: window.oc_requesttoken || '',
		},
		body,
	})
	if (!response.ok) {
		throw new Error(`Save failed: HTTP ${response.status}`)
	}
}

const HwpDocuments = {
	name: 'HwpDocuments',

	data() {
		return {
			loading: true,
			saving: false,
			status: '',
			error: null,
			saveMessage: '',
			editor: null,
			loadToken: 0,
			loadTimer: null,
			abortCtrl: null,
			loadingUrl: null,
		}
	},

	computed: {
		fileUrl() {
			return this.src || this.source || this.davPath || null
		},
		fileName() {
			return this.name || this.basename || this.filename || 'document.hwp'
		},
		isHwpx() {
			const n = String(this.fileName).toLowerCase()
			return n.endsWith('.hwpx') || this.mime === 'application/x-hwpx'
		},
		isActiveSlide() {
			return this.active !== false
		},
	},

	watch: {
		active() {
			this.scheduleLoad()
		},
		fileUrl() {
			this.scheduleLoad()
		},
	},

	mounted() {
		this.scheduleLoad()
	},

	beforeDestroy() {
		this.cancelScheduledLoad()
		this.loadToken++
		if (this.abortCtrl) {
			this.abortCtrl.abort()
			this.abortCtrl = null
		}
		this.destroyEditor()
	},

	methods: {
		t(app, text) {
			if (typeof window.t === 'function') {
				return window.t(app, text)
			}
			return text
		},

		setStatus(text) {
			this.status = text
		},

		cancelScheduledLoad() {
			if (this.loadTimer) {
				clearTimeout(this.loadTimer)
				this.loadTimer = null
			}
		},

		scheduleLoad() {
			this.cancelScheduledLoad()
			this.loadTimer = setTimeout(() => {
				this.loadTimer = null
				this.syncLoad()
			}, 75)
		},

		syncLoad() {
			if (!this.isActiveSlide) {
				console.info('[hwpdocuments] slide inactive — pause')
				this.loadToken++
				if (this.abortCtrl) {
					this.abortCtrl.abort()
					this.abortCtrl = null
				}
				this.destroyEditor()
				this.loading = true
				this.error = null
				this.loadingUrl = null
				this.setStatus('')
				return
			}

			const url = this.fileUrl
			if (!url) {
				this.setStatus(this.t('hwpdocuments', 'Waiting for file URL…'))
				return
			}

			if (url === this.loadingUrl && this.editor && !this.loading) {
				return
			}
			if (url === this.loadingUrl && this.loading) {
				return
			}

			this.loadDocument(url)
		},

		destroyEditor() {
			if (this.editor) {
				try {
					this.editor.destroy()
				} catch (e) {
					// ignore
				}
				this.editor = null
			}
			const el = this.$refs.editorEl
			if (el) {
				el.innerHTML = ''
			}
		},

		notifyDone() {
			if (typeof this.doneLoading === 'function') {
				this.doneLoading()
			}
		},

		isStale(token) {
			return token !== this.loadToken || !this.isActiveSlide
		},

		async loadDocument(url) {
			const token = ++this.loadToken
			if (this.abortCtrl) {
				this.abortCtrl.abort()
			}
			const abort = new AbortController()
			this.abortCtrl = abort

			this.destroyEditor()
			this.loading = true
			this.error = null
			this.saveMessage = ''
			this.loadingUrl = url
			this.setStatus(this.t('hwpdocuments', 'Starting…'))
			console.info('[hwpdocuments] load start', { token, url, active: this.active })

			try {
				this.setStatus(this.t('hwpdocuments', 'Loading editor and file…'))
				const createEditor = await loadCreateEditor()
				const buffer = await downloadFile(url, abort.signal)

				if (this.isStale(token)) {
					console.warn('[hwpdocuments] load cancelled after download', { token, current: this.loadToken })
					return
				}

				// Ensure mount point exists (may still be on loading screen).
				this.loading = false
				await this.$nextTick()
				const mount = this.$refs.editorEl
				if (!mount) {
					throw new Error('Editor mount point missing')
				}

				this.setStatus(this.t('hwpdocuments', 'Starting studio…'))
				const editor = await createEditor(mount, {
					studioUrl: studioUrl(),
					width: '100%',
					height: '100%',
					renderer: 'canvas2d',
				})

				if (this.isStale(token)) {
					editor.destroy()
					return
				}

				this.editor = editor
				this.setStatus(this.t('hwpdocuments', 'Opening document…'))
				const result = await editor.loadFile(buffer, this.fileName, {
					skipUnsavedGuard: true,
					suppressDialogs: true,
				})
				console.info('[hwpdocuments] editor ready', result)
				this.setStatus('')
				this.notifyDone()
			} catch (e) {
				if (this.isStale(token) || abort.signal.aborted) {
					console.warn('[hwpdocuments] load aborted', e?.message || e)
					return
				}
				console.error('[hwpdocuments] editor error:', e)
				this.destroyEditor()
				this.error = `${this.t('hwpdocuments', 'Failed to open editor.')} (${e?.message || e})`
				this.loading = false
				this.loadingUrl = null
				this.notifyDone()
			}
		},

		async saveDocument() {
			if (!this.editor || this.saving || !this.fileUrl) {
				return
			}
			this.saving = true
			this.saveMessage = this.t('hwpdocuments', 'Saving…')
			this.error = null
			try {
				const bytes = this.isHwpx
					? await this.editor.exportHwpx()
					: await this.editor.exportHwp()
				const mime = this.isHwpx ? 'application/x-hwpx' : 'application/x-hwp'
				await uploadFile(this.fileUrl, bytes, mime)
				try {
					await this.editor.notifySaved(this.fileName)
				} catch (e) {
					console.warn('[hwpdocuments] notifySaved skipped', e)
				}
				this.saveMessage = this.t('hwpdocuments', 'Saved')
				setTimeout(() => {
					if (this.saveMessage === this.t('hwpdocuments', 'Saved')) {
						this.saveMessage = ''
					}
				}, 2500)
			} catch (e) {
				console.error('[hwpdocuments] save error:', e)
				this.saveMessage = ''
				this.error = `${this.t('hwpdocuments', 'Failed to save.')} (${e?.message || e})`
			} finally {
				this.saving = false
			}
		},
	},

	render(h) {
		const children = []

		children.push(h('div', { class: 'hwp-documents__toolbar' }, [
			h('button', {
				attrs: {
					type: 'button',
					disabled: this.saving || this.loading || !this.editor || !!this.error,
				},
				on: { click: () => this.saveDocument() },
			}, this.t('hwpdocuments', 'Save')),
			this.saveMessage
				? h('span', { class: 'hwp-documents__save-msg' }, this.saveMessage)
				: null,
		]))

		if (this.error) {
			children.push(h('div', { class: 'hwp-documents__error' }, [h('p', this.error)]))
		} else if (this.loading) {
			children.push(h('div', { class: 'hwp-documents__status' }, [
				h('p', this.status || this.t('hwpdocuments', 'Loading document…')),
			]))
		}

		children.push(h('div', {
			ref: 'editorEl',
			class: 'hwp-documents__editor',
			style: {
				display: this.loading || this.error ? 'none' : 'block',
			},
		}))

		return h('div', { class: 'hwp-documents hwp-documents--editor' }, children)
	},
}

function queueHandler(handler) {
	const existing = window._oca_viewer_handlers
	if (existing instanceof Map) {
		if (!existing.has(handler.id)) {
			existing.set(handler.id, handler)
		}
		return
	}
	if (Array.isArray(existing)) {
		if (!existing.some((x) => x?.id === handler.id)) {
			existing.push(handler)
		}
		return
	}
	window._oca_viewer_handlers = new Map([[handler.id, handler]])
}

function registerNow(handler) {
	if (!window.OCA?.Viewer?.registerHandler) {
		return false
	}
	if (window.OCA.Viewer.availableHandlers?.some((x) => x.id === handler.id)) {
		return true
	}
	window.OCA.Viewer.registerHandler(handler)
	return true
}

const handler = {
	id: 'hwpdocuments',
	group: null,
	mimes: MIMES,
	component: HwpDocuments,
}

queueHandler(handler)
if (!registerNow(handler)) {
	document.addEventListener('DOMContentLoaded', () => registerNow(handler))
}
setTimeout(() => registerNow(handler), 0)
setTimeout(() => registerNow(handler), 500)
