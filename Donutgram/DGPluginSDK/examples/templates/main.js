const _plugin = "donutgram";
export default definePlugin({
  async activate(api) {
    await api.commands.register({
      id: "insert-template",
      title: "вставить шаблон",
      placement: "composer",
      async run() {
        const settings = await api.settings.get();
        const draft = await api.composer.getActiveDraft();
        if (!draft || typeof settings.template !== "string") return;
        await api.composer.replaceSelection({composer: draft.handle, expectedRevision: draft.revision, range: draft.selection, text: settings.template});
      }
    });
  }
});
