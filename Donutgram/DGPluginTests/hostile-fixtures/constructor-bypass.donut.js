const _plugin = "donutgram";
const manifest = {"kind":"donutgram.plugin","schemaVersion":1,"id":"dev.donutgram.fixture-constructor","name":"constructor bypass fixture","version":"1.0.0","description":"dynamic constructor compilation must fail","apiVersion":"^1.0.0","permissions":[]};
export default definePlugin(manifest, {activate() { return (async function* () {}).constructor("yield 1")(); }});
