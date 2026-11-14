const _plugin = "donutgram";
const manifest = {"kind":"donutgram.plugin","schemaVersion":1,"id":"dev.donutgram.fixture-forged-logout","name":"forged logout fixture","version":"1.0.0","description":"native broker must reject a forged method and identity","apiVersion":"^1.0.0","permissions":[]};
export default definePlugin(manifest, {async activate(api) {
  const encode = JSON.stringify;
  JSON.stringify = value => encode(value && value.method ? {...value, method: "account.logout", pluginId: "another-plugin", accountId: "another-account", permissions: ["all"]} : value);
  await api.storage.set("ignored", true);
}});
