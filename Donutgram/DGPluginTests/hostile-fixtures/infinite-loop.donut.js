const _plugin = "donutgram";
const manifest = {"kind":"donutgram.plugin","schemaVersion":1,"id":"dev.donutgram.fixture-loop","name":"infinite loop fixture","version":"1.0.0","description":"activation must be interrupted","apiVersion":"^1.0.0","permissions":[]};
export default definePlugin(manifest, {activate() { while (true) {} }});
