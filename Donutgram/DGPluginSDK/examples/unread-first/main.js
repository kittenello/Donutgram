const _plugin = "donutgram";
export default definePlugin({
  async activate(api) {
    return api.transforms.register({id: "unread-first", slot: "chatList"}, async input => {
      const settings = await api.settings.get();
      const movable = input.items.filter(item => !item.pinned);
      const ordered = [...movable].sort((left, right) => {
        const unread = Number(right.unread > 0) - Number(left.unread > 0);
        if (unread) return unread;
        return left.title < right.title ? -1 : (left.title > right.title ? 1 : 0);
      });
      return {
        order: ordered.map(item => item.handle),
        hidden: settings.hideRead ? movable.filter(item => item.unread === 0).map(item => item.handle) : []
      };
    });
  }
});
