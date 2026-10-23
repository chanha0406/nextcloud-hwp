const u = [
  "application/x-hwp",
  "application/x-hwp-v5",
  "application/x-hwpx"
], w = "1.2.5";
function p(t) {
  const e = t.includes("?") ? "&" : "?";
  return `${t}${e}v=${w}`;
}
function f(t) {
  let e;
  typeof OC < "u" && typeof OC.filePath == "function" ? e = OC.filePath("hwpdocuments", "js", t) : e = `${typeof OC < "u" && OC.appswebroots?.hwpdocuments ? OC.appswebroots.hwpdocuments : "/custom_apps/hwpdocuments"}/js/${t}`;
  try {
    e = new URL(e, window.location.origin).href;
  } catch {
  }
  return p(e);
}
function m() {
  const t = typeof OC < "u" && OC.appswebroots?.hwpdocuments ? OC.appswebroots.hwpdocuments : "/custom_apps/hwpdocuments";
  try {
    return new URL(`${t}/studio/index.html`, window.location.origin).href;
  } catch {
    return `${t}/studio/index.html`;
  }
}
let l = null;
function g() {
  if (!l) {
    const t = f("editor/index.js");
    console.info("[hwpdocuments] importing @rhwp/editor", t), l = import(
      /* @vite-ignore */
      t
    ).then((e) => e.createEditor).catch((e) => {
      throw l = null, e;
    });
  }
  return l;
}
async function v(t, e) {
  console.info("[hwpdocuments] downloading", t);
  const s = await fetch(t, {
    credentials: "same-origin",
    signal: e,
    headers: {
      requesttoken: window.oc_requesttoken || ""
    }
  });
  if (!s.ok)
    throw new Error(`Download failed: HTTP ${s.status}`);
  const i = await s.arrayBuffer();
  return console.info("[hwpdocuments] downloaded bytes", i.byteLength), { buffer: i, etag: s.headers.get("etag") };
}
function y(t, e) {
  const s = t instanceof Uint8Array ? t : new Uint8Array(t || []);
  if (!(s.byteLength >= 4 && (e ? s[0] === 80 && s[1] === 75 : s[0] === 208 && s[1] === 207 && s[2] === 17 && s[3] === 224)))
    throw new Error(e ? "Refusing to save a file that is not HWPX" : "Refusing to save a file that is not HWP");
  return s;
}
async function b(t, e, s, i) {
  const o = {
    "Content-Type": s,
    requesttoken: window.oc_requesttoken || ""
  };
  i && (o["If-Match"] = i);
  const n = await fetch(t, {
    method: "PUT",
    credentials: "same-origin",
    headers: o,
    body: e
  });
  if (!n.ok)
    throw new Error(`Save failed: HTTP ${n.status}`);
  return n.headers.get("etag");
}
const E = {
  name: "HwpDocuments",
  data() {
    return {
      loading: !0,
      saving: !1,
      status: "",
      error: null,
      saveError: null,
      saveMessage: "",
      fileEtag: null,
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
      return String(this.fileName).toLowerCase().endsWith(".hwpx");
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
    t(t, e) {
      return typeof window.t == "function" ? window.t(t, e) : e;
    },
    setStatus(t) {
      this.status = t;
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
        console.info("[hwpdocuments] slide inactive — pause"), this.loadToken++, this.abortCtrl && (this.abortCtrl.abort(), this.abortCtrl = null), this.destroyEditor(), this.loading = !0, this.error = null, this.loadingUrl = null, this.setStatus("");
        return;
      }
      const t = this.fileUrl;
      if (!t) {
        this.setStatus(this.t("hwpdocuments", "Waiting for file URL…"));
        return;
      }
      t === this.loadingUrl && this.editor && !this.loading || t === this.loadingUrl && this.loading || this.loadDocument(t);
    },
    destroyEditor() {
      if (this.editor) {
        try {
          this.editor.destroy();
        } catch {
        }
        this.editor = null;
      }
      const t = this.$refs.editorEl;
      t && (t.innerHTML = "");
    },
    notifyDone() {
      typeof this.doneLoading == "function" && this.doneLoading();
    },
    isStale(t) {
      return t !== this.loadToken || !this.isActiveSlide;
    },
    async loadDocument(t) {
      const e = ++this.loadToken;
      this.abortCtrl && this.abortCtrl.abort();
      const s = new AbortController();
      this.abortCtrl = s, this.destroyEditor(), this.loading = !0, this.error = null, this.saveError = null, this.saveMessage = "", this.fileEtag = null, this.loadingUrl = t, this.setStatus(this.t("hwpdocuments", "Starting…")), console.info("[hwpdocuments] load start", { token: e, url: t, active: this.active });
      try {
        this.setStatus(this.t("hwpdocuments", "Loading editor and file…"));
        const i = await g(), o = await v(t, s.signal), n = o.buffer;
        if (this.fileEtag = o.etag, this.isStale(e)) {
          console.warn("[hwpdocuments] load cancelled after download", { token: e, current: this.loadToken });
          return;
        }
        this.loading = !1, await this.$nextTick();
        const r = this.$refs.editorEl;
        if (!r)
          throw new Error("Editor mount point missing");
        this.setStatus(this.t("hwpdocuments", "Starting studio…"));
        const a = await i(r, {
          studioUrl: m(),
          width: "100%",
          height: "100%",
          renderer: "canvas2d"
        });
        if (this.isStale(e)) {
          a.destroy();
          return;
        }
        this.editor = a, this.setStatus(this.t("hwpdocuments", "Opening document…"));
        const c = await a.loadFile(n, this.fileName, {
          skipUnsavedGuard: !0,
          suppressDialogs: !0
        });
        console.info("[hwpdocuments] editor ready", c), this.setStatus(""), this.notifyDone();
      } catch (i) {
        if (this.isStale(e) || s.signal.aborted) {
          console.warn("[hwpdocuments] load aborted", i?.message || i);
          return;
        }
        console.error("[hwpdocuments] editor error:", i), this.destroyEditor(), this.error = `${this.t("hwpdocuments", "Failed to open editor.")} (${i?.message || i})`, this.loading = !1, this.loadingUrl = null, this.notifyDone();
      }
    },
    async saveDocument() {
      if (!(!this.editor || this.saving || !this.fileUrl)) {
        this.saving = !0, this.saveMessage = this.t("hwpdocuments", "Saving…"), this.saveError = null;
        try {
          const t = this.isHwpx, e = this.mime === "application/x-hwpx", s = this.mime === "application/x-hwp" || this.mime === "application/x-hwp-v5";
          if (e && !t || s && t)
            throw new Error("File extension and type do not match");
          const i = t ? await this.editor.exportHwpx() : await this.editor.exportHwp(), o = y(i, t), n = t ? "application/x-hwpx" : "application/x-hwp", r = await b(this.fileUrl, o, n, this.fileEtag);
          r && (this.fileEtag = r);
          try {
            await this.editor.notifySaved(this.fileName);
          } catch (a) {
            console.warn("[hwpdocuments] notifySaved skipped", a);
          }
          this.saveMessage = this.t("hwpdocuments", "Saved"), setTimeout(() => {
            this.saveMessage === this.t("hwpdocuments", "Saved") && (this.saveMessage = "");
          }, 2500);
        } catch (t) {
          console.error("[hwpdocuments] save error:", t), this.saveMessage = "", this.saveError = `${this.t("hwpdocuments", "Failed to save.")} (${t?.message || t})`;
        } finally {
          this.saving = !1;
        }
      }
    }
  },
  render(t) {
    const e = [];
    return e.push(t("div", { class: "hwp-documents__toolbar" }, [
      t("button", {
        attrs: {
          type: "button",
          disabled: this.saving || this.loading || !this.editor || !!this.error
        },
        on: { click: () => this.saveDocument() }
      }, this.t("hwpdocuments", "Save")),
      this.saveMessage ? t("span", { class: "hwp-documents__save-msg" }, this.saveMessage) : null,
      this.saveError ? t("span", { class: "hwp-documents__save-msg" }, this.saveError) : null
    ])), this.error ? e.push(t("div", { class: "hwp-documents__error" }, [t("p", this.error)])) : this.loading && e.push(t("div", { class: "hwp-documents__status" }, [
      t("p", this.status || this.t("hwpdocuments", "Loading document…"))
    ])), e.push(t("div", {
      ref: "editorEl",
      class: "hwp-documents__editor",
      style: {
        display: this.loading || this.error ? "none" : "block"
      }
    })), t("div", { class: "hwp-documents hwp-documents--editor" }, e);
  }
};
function S(t) {
  const e = window._oca_viewer_handlers;
  if (e instanceof Map) {
    e.has(t.id) || e.set(t.id, t);
    return;
  }
  if (Array.isArray(e)) {
    e.some((s) => s?.id === t.id) || e.push(t);
    return;
  }
  window._oca_viewer_handlers = /* @__PURE__ */ new Map([[t.id, t]]);
}
function h(t) {
  return window.OCA?.Viewer?.registerHandler ? (window.OCA.Viewer.availableHandlers?.some((e) => e.id === t.id) || window.OCA.Viewer.registerHandler(t), !0) : !1;
}
const d = {
  id: "hwpdocuments",
  group: null,
  mimes: u,
  component: E
};
S(d);
h(d) || document.addEventListener("DOMContentLoaded", () => h(d));
setTimeout(() => h(d), 0);
setTimeout(() => h(d), 500);
//# sourceMappingURL=hwpdocuments-main.mjs.map
