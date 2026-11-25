const _plugin = "donutgram";

export default definePlugin({
  async activate(api) {
    await api.messages.beforeSend({id: "testdonut"}, ({text}) => {
      if (text === ".testdonut") return {text: "donutgram plugin works"};
      return {};
    });
    await api.commands.register({
      id: "send-example",
      title: "send example text",
      placement: "composer",
      run: () => api.messages.send({text: "sent by message tools"})
    });
    await api.commands.register({
      id: "edit-selected",
      title: "replace selected message text",
      placement: "messageMenu",
      run: () => api.messages.edit({text: "edited by message tools"})
    });
    await api.commands.register({
      id: "delete-selected",
      title: "delete selected message for everyone",
      placement: "messageMenu",
      run: () => api.messages.delete()
    });
  }
});
