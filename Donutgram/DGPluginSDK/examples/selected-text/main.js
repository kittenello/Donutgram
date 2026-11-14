const _plugin = "donutgram";
export default definePlugin({
  async activate(api) {
    await api.commands.register({
      id: "text-statistics",
      title: "статистика текста",
      placement: "selection",
      async run() {
        const selected = await api.selection.get();
        if (!selected || typeof selected.text !== "string") return;
        const words = (selected.text.match(/\S+/gu) || []).length;
        const characters = Array.from(selected.text).length;
        await api.ui.toast("слов: " + words + ", символов: " + characters);
      }
    });
  }
});
