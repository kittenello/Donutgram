const _plugin = "donutgram";
export default definePlugin({
  async activate(api) {
    let image;
    const callbacks = {};
    async function update(key, value) {
      const settings = await api.settings.get();
      settings[key] = value;
      await api.settings.set(settings);
      await show();
    }
    for (const key of ["enabled", "label", "note", "level", "count", "mode", "accent"]) {
      callbacks[key] = api.ui.callback(value => update(key, value));
    }
    const notice = api.ui.callback(async () => { await api.ui.toast("значения сохранены в настройках плагина"); });
    async function show() {
      const settings = await api.settings.get();
      const available = await api.capabilities.list();
      if (available["theme.contribute"]) await api.theme.contribute({accent: settings.accent});
      if (!image) {
        try { image = await api.assets.image({path: "assets/sample.png"}); }
        catch (error) { if (error.code !== "feature_unavailable" && error.code !== "invalid_argument") throw error; }
      }
      const nodes = [
        {type: "markdown", id: "intro", text: "# нативные элементы\n**настройки** сохраняются локально. [документация](https://example.org) отображается без открытия ссылки."},
        {type: "section", id: "controls", title: "параметры", children: [
          {type: "toggle", id: "enabled", title: "включено", value: settings.enabled, callbackId: callbacks.enabled.id},
          {type: "input", id: "label", title: "подпись", value: settings.label, callbackId: callbacks.label.id},
          {type: "multiline", id: "note", title: "заметка", value: settings.note, callbackId: callbacks.note.id},
          {type: "slider", id: "level", title: "уровень", value: settings.level, minimum: 0, maximum: 1, step: 0.1, callbackId: callbacks.level.id},
          {type: "stepper", id: "count", title: "количество", value: settings.count, minimum: 0, maximum: 10, step: 1, callbackId: callbacks.count.id},
          {type: "select", id: "mode", title: "режим", value: settings.mode, options: [{title: "компактный", value: "compact"}, {title: "свободный", value: "comfortable"}], callbackId: callbacks.mode.id},
          {type: "select", id: "accent", title: "акцент своей страницы", value: settings.accent, options: [{title: "синий", value: "blue"}, {title: "зелёный", value: "green"}, {title: "фиолетовый", value: "purple"}, {title: "оранжевый", value: "orange"}], callbackId: callbacks.accent.id}
        ]},
        {type: "list", id: "summary", children: [{type: "text", id: "saved", text: "подпись: " + settings.label}]},
        {type: "button", id: "notice", title: "проверить сохранение", callbackId: notice.id}
      ];
      if (image) nodes.push({type: "image", id: "sample", title: "локальное изображение", asset: image});
      await api.ui.render({id: "controls", title: "нативные элементы", nodes});
    }
    await api.commands.register({id: "show-controls", title: "нативные элементы", placement: "settings", run: show});
  }
});
