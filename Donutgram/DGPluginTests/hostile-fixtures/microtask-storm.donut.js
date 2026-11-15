const _plugin = "donutgram";
const manifest = {"kind":"donutgram.plugin","schemaVersion":1,"id":"dev.donutgram.fixture-microtasks","name":"microtask storm fixture","version":"1.0.0","description":"activation must exceed the bounded job budget","apiVersion":"^1.0.0","permissions":[]};
export default definePlugin(manifest, {async activate() { while (true) await Promise.resolve(); }});
