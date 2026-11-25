const _plugin = "donutgram";
export default definePlugin({
  async activate(api) {
    await api.commands.register({
      id: "repository-summary",
      title: "публичный репозиторий",
      placement: "settings",
      async run() {
        const available = await api.capabilities.list();
        if (!available["network.request"]) {
          await api.ui.toast("публичная сеть недоступна в этой сборке");
          return;
        }
        const response = await api.network.request({url: "https://api.github.com/repos/madler/zlib", method: "GET"});
        if (response.status !== 200) {
          await api.ui.toast("сервис вернул статус " + response.status);
          return;
        }
        const repository = JSON.parse(response.body);
        const name = typeof repository.full_name === "string" ? repository.full_name.slice(0, 200) : "репозиторий";
        const description = typeof repository.description === "string" ? repository.description.slice(0, 1000) : "без описания";
        const stars = Number.isSafeInteger(repository.stargazers_count) ? repository.stargazers_count : 0;
        await api.ui.render({id: "repository", title: "публичный репозиторий", nodes: [
          {type: "text", id: "name", text: name},
          {type: "text", id: "description", text: description},
          {type: "text", id: "stars", text: "звёзд на github: " + stars}
        ]});
      }
    });
  }
});
