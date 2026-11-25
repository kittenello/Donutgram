const _plugin = "donutgram";
import {cleanTrackingURL} from "./modules/clean-url.js";
export default definePlugin({
  async activate(api) {
    await api.commands.register({
      id: "clean-selected-link",
      title: "очистить ссылку",
      placement: "composer",
      async run() {
        const draft = await api.composer.getActiveDraft();
        if (!draft) return;
        const range = draft.selection;
        const original = draft.text.slice(range.start, range.end);
        const text = cleanTrackingURL(original);
        if (text === null) { await api.ui.toast("выделите ссылку http или https"); return; }
        if (text === original) return;
        await api.composer.replaceSelection({composer: draft.handle, expectedRevision: draft.revision, range, text});
      }
    });
  }
});
