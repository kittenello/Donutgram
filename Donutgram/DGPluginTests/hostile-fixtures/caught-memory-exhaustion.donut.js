const _plugin = "donutgram";
const manifest = {"kind":"donutgram.plugin","schemaVersion":1,"id":"dev.donutgram.fixture-memory","name":"memory exhaustion fixture","version":"1.0.0","description":"memory exhaustion must latch stop despite catch","apiVersion":"^1.0.0","permissions":[]};
export default definePlugin(manifest, {activate() { try { const values = []; while (true) values.push("x".repeat(100000)); } catch (error) {} }});
