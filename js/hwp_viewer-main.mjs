const w = [
  "application/x-hwp",
  "application/x-hwp-v5",
  "application/x-hwpx"
], c = "1.1.0";
function u(e) {
  const t = e.includes("?") ? "&" : "?";
  return `${e}${t}v=${c}`;
}
function p(e) {
  let t;
  typeof OC < "u" && typeof OC.filePath == "function" ? t = OC.filePath("hwp_viewer", "js", e) : t = `${typeof OC < "u" && OC.appswebroots?.hwp_viewer ? OC.appswebroots.hwp_viewer : "/custom_apps/hwp_viewer"}/js/${e}`;
  try {
    t = new URL(t, window.location.origin).href;
  } catch {
  }
  return u(t);
}
function f() {
  const e = typeof OC < "u" && OC.appswebroots?.hwp_viewer ? OC.appswebroots.hwp_viewer : "/custom_apps/hwp_viewer";
  try {
    return new URL(`${e}/studio/index.html`, window.location.origin).href;
  } catch {
    return `${e}/studio/index.html`;
  }
}
let n = null;
function v() {
  if (!n) {
    const e = p("editor/index.js");
    console.info("[hwp_viewer] importing @rhwp/editor", e), n = import(
      /* @vite-ignore */
      e
    ).then((t) => t.createEditor).catch((t) => {
      throw n = null, t;
    });
  }
  return n;
}
async function g(e, t) {
  console.info("[hwp_viewer] downloading", e);
  const i = await fetch(e, {
    credentials: "same-origin",
    signal: t,
    headers: {
      requesttoken: window.oc_requesttoken || ""
    }
  });
  if (!i.ok)
    throw new Error(`Download failed: HTTP ${i.status}`);
  const s = await i.arrayBuffer();
  return console.info("[hwp_viewer] downloaded bytes", s.byteLength), s;
}
async function m(e, t, i) {
  const s = t instanceof Uint8Array ? t : new Uint8Array(t), o = await fetch(e, {
    method: "PUT",
    credentials: "same-origin",
    headers: {
      "Content-Type": i,
      requesttoken: window.oc_requesttoken || ""
    },
    body: s
  });
  if (!o.ok)
    throw new Error(`Save failed: HTTP ${o.status}`);
}
const _ = {
  name: "HwpViewer",
  data() {
    return {
      loading: !0,
      saving: !1,
      status: "",
      error: null,
      saveMessage: "",
      editor: null,
      loadToken: 0,
      loadTimer: null,
      abortCtrl: null,
      loadingUrl: null
    };
  },
  computed: {
    fileUrl() {
      return this.src || this.source || this.davPath || null;
    },
    fileName() {
      return this.name || this.basename || this.filename || "document.hwp";
    },
    isHwpx() {
      return String(this.fileName).toLowerCase().endsWith(".hwpx") || this.mime === "application/x-hwpx";
    },
    isActiveSlide() {
      return this.active !== !1;
    }
  },
  watch: {
    active() {
      this.scheduleLoad();
    },
    fileUrl() {
      this.scheduleLoad();
    }
  },
  mounted() {
    this.scheduleLoad();
  },
  beforeDestroy() {
    this.cancelScheduledLoad(), this.loadToken++, this.abortCtrl && (this.abortCtrl.abort(), this.abortCtrl = null), this.destroyEditor();
  },
  methods: {
    t(e, t) {
      return typeof window.t == "function" ? window.t(e, t) : t;
    },
    setStatus(e) {
      this.status = e;
    },
    cancelScheduledLoad() {
      this.loadTimer && (clearTimeout(this.loadTimer), this.loadTimer = null);
    },
    scheduleLoad() {
      this.cancelScheduledLoad(), this.loadTimer = setTimeout(() => {
        this.loadTimer = null, this.syncLoad();
      }, 75);
    },
    syncLoad() {
      if (!this.isActiveSlide) {
        console.info("[hwp_viewer] slide inactive — pause"), this.loadToken++, this.abortCtrl && (this.abortCtrl.abort(), this.abortCtrl = null), this.destroyEditor(), this.loading = !0, this.error = null, this.loadingUrl = null, this.setStatus("");
        return;
      }
      const e = this.fileUrl;
      if (!e) {
        this.setStatus(this.t("hwp_viewer", "Waiting for file URL…"));
        return;
      }
      e === this.loadingUrl && this.editor && !this.loading || e === this.loadingUrl && this.loading || this.loadDocument(e);
    },
    destroyEditor() {
      if (this.editor) {
        try {
          this.editor.destroy();
        } catch {
        }
        this.editor = null;
      }
      const e = this.$refs.editorEl;
      e && (e.innerHTML = "");
    },
    notifyDone() {
      typeof this.doneLoading == "function" && this.doneLoading();
    },
    isStale(e) {
      return e !== this.loadToken || !this.isActiveSlide;
    },
    async loadDocument(e) {
      const t = ++this.loadToken;
      this.abortCtrl && this.abortCtrl.abort();
      const i = new AbortController();
      this.abortCtrl = i, this.destroyEditor(), this.loading = !0, this.error = null, this.saveMessage = "", this.loadingUrl = e, this.setStatus(this.t("hwp_viewer", "Starting…")), console.info("[hwp_viewer] load start", { token: t, url: e, active: this.active });
      try {
        this.setStatus(this.t("hwp_viewer", "Loading editor and file…"));
        const s = await v(), o = await g(e, i.signal);
        if (this.isStale(t)) {
          console.warn("[hwp_viewer] load cancelled after download", { token: t, current: this.loadToken });
          return;
        }
        this.loading = !1, await this.$nextTick();
        const l = this.$refs.editorEl;
        if (!l)
          throw new Error("Editor mount point missing");
        this.setStatus(this.t("hwp_viewer", "Starting studio…"));
        const h = await s(l, {
          studioUrl: f(),
          width: "100%",
          height: "100%",
          renderer: "canvas2d"
        });
        if (this.isStale(t)) {
          h.destroy();
          return;
        }
        this.editor = h, this.setStatus(this.t("hwp_viewer", "Opening document…"));
        const d = await h.loadFile(o, this.fileName, {
          skipUnsavedGuard: !0,
          suppressDialogs: !0
        });
        console.info("[hwp_viewer] editor ready", d), this.setStatus(""), this.notifyDone();
      } catch (s) {
        if (this.isStale(t) || i.signal.aborted) {
          console.warn("[hwp_viewer] load aborted", s?.message || s);
          return;
        }
        console.error("[hwp_viewer] editor error:", s), this.destroyEditor(), this.error = `${this.t("hwp_viewer", "Failed to open editor.")} (${s?.message || s})`, this.loading = !1, this.loadingUrl = null, this.notifyDone();
      }
    },
    async saveDocument() {
      if (!(!this.editor || this.saving || !this.fileUrl)) {
        this.saving = !0, this.saveMessage = this.t("hwp_viewer", "Saving…"), this.error = null;
        try {
          const e = this.isHwpx ? await this.editor.exportHwpx() : await this.editor.exportHwp(), t = this.isHwpx ? "application/x-hwpx" : "application/x-hwp";
          await m(this.fileUrl, e, t);
          try {
            await this.editor.notifySaved(this.fileName);
          } catch (i) {
            console.warn("[hwp_viewer] notifySaved skipped", i);
          }
          this.saveMessage = this.t("hwp_viewer", "Saved"), setTimeout(() => {
            this.saveMessage === this.t("hwp_viewer", "Saved") && (this.saveMessage = "");
          }, 2500);
        } catch (e) {
          console.error("[hwp_viewer] save error:", e), this.saveMessage = "", this.error = `${this.t("hwp_viewer", "Failed to save.")} (${e?.message || e})`;
        } finally {
          this.saving = !1;
        }
      }
    }
  },
  render(e) {
    const t = [];
    return t.push(e("div", { class: "hwp-viewer__toolbar" }, [
      e("button", {
        attrs: {
          type: "button",
          disabled: this.saving || this.loading || !this.editor || !!this.error
        },
        on: { click: () => this.saveDocument() }
      }, this.t("hwp_viewer", "Save")),
      this.saveMessage ? e("span", { class: "hwp-viewer__save-msg" }, this.saveMessage) : null
    ])), this.error ? t.push(e("div", { class: "hwp-viewer__error" }, [e("p", this.error)])) : this.loading && t.push(e("div", { class: "hwp-viewer__status" }, [
      e("p", this.status || this.t("hwp_viewer", "Loading document…"))
    ])), t.push(e("div", {
      ref: "editorEl",
      class: "hwp-viewer__editor",
      style: {
        display: this.loading || this.error ? "none" : "block"
      }
    })), e("div", { class: "hwp-viewer hwp-viewer--editor" }, t);
  }
};
function y(e) {
  const t = window._oca_viewer_handlers;
  if (t instanceof Map) {
    t.has(e.id) || t.set(e.id, e);
    return;
  }
  if (Array.isArray(t)) {
    t.some((i) => i?.id === e.id) || t.push(e);
    return;
  }
  window._oca_viewer_handlers = /* @__PURE__ */ new Map([[e.id, e]]);
}
function a(e) {
  return window.OCA?.Viewer?.registerHandler ? (window.OCA.Viewer.availableHandlers?.some((t) => t.id === e.id) || window.OCA.Viewer.registerHandler(e), !0) : !1;
}
const r = {
  id: "hwp_viewer",
  group: null,
  mimes: w,
  component: _
};
y(r);
a(r) || document.addEventListener("DOMContentLoaded", () => a(r));
setTimeout(() => a(r), 0);
setTimeout(() => a(r), 500);
//# sourceMappingURL=hwp_viewer-main.mjs.map
