const _plugin = "donutgram";
export default definePlugin({
  async activate(api) {
    return api.transforms.register({id: "hide-empty-panes", slot: "profile"}, input => ({
      hide: input.panes.filter(pane => pane.empty).map(pane => pane.id)
    }));
  }
});
