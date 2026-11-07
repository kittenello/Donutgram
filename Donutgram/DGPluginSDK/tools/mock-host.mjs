import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

const snapshot = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const fixture = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
const root = path.dirname(fileURLToPath(import.meta.url));
const bootstrap = fs.readFileSync(path.resolve(root, '../../DGPluginRuntime/Sources/bootstrap.js'), 'utf8');
const grants = snapshot.manifest.permissions;
const registered = new Map();
const storage = new Map();
const toasts = [];
let gesture = false;
let draft = structuredClone(fixture.draft || null);
let revision = 0;
let settings = structuredClone(fixture.settings || Object.fromEntries(Object.entries(snapshot.manifest.settingsSchema?.properties || {}).filter(([, value]) => 'default' in value).map(([key, value]) => [key, value.default])));
const context = vm.createContext(Object.create(null), {codeGeneration: {strings: false, wasm: false}});
const rules = {
  'composer.getActiveDraft': ['composer.read', 'activeComposer', true],
  'composer.replaceSelection': ['composer.transform', 'activeComposer', true],
  'selection.get': ['messages.selection.read', 'activeSelection', true],
  'storage.get': ['storage.local', 'pluginAccount'],
  'storage.set': ['storage.local', 'pluginAccount'],
  'storage.keys': ['storage.local', 'pluginAccount'],
  'storage.remove': ['storage.local', 'pluginAccount'],
  'theme.get': ['theme.read', 'currentTheme']
};
function host(method, params) {
  const rule = rules[method];
  if (rule) {
    assert(grants.some((grant) => grant.capability === rule[0] && grant.scope === rule[1]), 'permission_denied');
    if (rule[2]) assert(gesture, 'gesture_required');
  }
  if (method === 'ui.command.register') {
    assert(grants.some((grant) => grant.capability === 'ui.contribute' && grant.scope === params.placement), 'scope_denied');
    assert(!registered.has(params.id), 'duplicate command');
    registered.set(params.id, params);
    return params.id;
  }
  if (method === 'ui.command.unregister') { registered.delete(params.id); return null; }
  if (method === 'ui.toast') {
    assert(grants.some((grant) => grant.capability === 'ui.contribute'), 'permission_denied');
    toasts.push(params.text); return null;
  }
  if (method === 'composer.getActiveDraft') return draft;
  if (method === 'composer.replaceSelection') {
    if (params.composer && params.handle) assert.equal(params.composer, params.handle, 'conflicting_handle');
    assert(draft && (params.composer || params.handle) === draft.handle && params.expectedRevision === draft.revision, 'stale_revision');
    params.range ||= draft.selection;
    assert(params.range.start >= 0 && params.range.end >= params.range.start && params.range.end <= draft.text.length, 'invalid_range');
    draft.text = draft.text.slice(0, params.range.start) + params.text + draft.text.slice(params.range.end);
    draft.revision = 'mock-revision-' + ++revision;
    draft.selection = {start: params.range.start + params.text.length, end: params.range.start + params.text.length};
    return null;
  }
  if (method === 'selection.get') return fixture.selection || null;
  if (method === 'settings.get') return settings;
  if (method === 'settings.set') { settings = params.values; return null; }
  if (method === 'storage.get') return storage.get(params.key) ?? null;
  if (method === 'storage.set') { storage.set(params.key, params.value); return null; }
  if (method === 'storage.remove') { storage.delete(params.key); return null; }
  if (method === 'storage.keys') return [...storage.keys()];
  if (method === 'capabilities.has') return grants.some((grant) => grant.capability === params.capability);
  if (method === 'capabilities.list') return Object.keys(rules);
  if (method === 'theme.get') return {appearance: 'light'};
  if (method === 'events.subscribe' || method === 'events.unsubscribe') return null;
  throw Object.assign(new Error('feature_unavailable'), {code: 'feature_unavailable'});
}
context.__dgNative = (json) => {
  const envelope = JSON.parse(json);
  let response;
  try { response = {result: host(envelope.method, envelope.params)}; }
  catch (error) { response = {error: {code: error.code || 'mock_host_error', message: error.message}}; }
  const responseJSON = JSON.stringify(response);
  vm.runInContext(`__dgReply(${JSON.stringify(envelope.id)}, JSON.parse(${JSON.stringify(responseJSON)}))`, context, {timeout: 250});
};
vm.runInContext(bootstrap, context, {timeout: 250});
vm.runInContext('__dgConfigure({apiVersion:"1.0.0",appearance:"light"})', context, {timeout: 250});
const modules = new Map();
async function load(name) {
  assert(typeof name === 'string' && !name.startsWith('/') && !name.split('/').includes('..') && Object.hasOwn(snapshot.files, name), 'module_not_found');
  if (modules.has(name)) return modules.get(name);
  const module = new vm.SourceTextModule(snapshot.files[name], {context, identifier: name});
  modules.set(name, module);
  await module.link((specifier, referencing) => {
    assert(specifier.startsWith('./'), 'module_not_found');
    const resolved = path.posix.join(path.posix.dirname(referencing.identifier), specifier);
    return load(resolved);
  });
  return module;
}
const entry = await load(snapshot.manifest.entry || 'main.js');
await entry.evaluate({timeout: 250});
await vm.runInContext('__dgActivate()', context, {timeout: 250});
for (const command of fixture.commands || []) {
  assert(registered.has(command), 'command_not_registered');
  gesture = true;
  try { await vm.runInContext(`__dgDispatch("command", ${JSON.stringify({id: command})})`, context, {timeout: 250}); }
  finally { gesture = false; }
}
if ('expectedText' in fixture) assert.equal(draft?.text, fixture.expectedText);
if ('expectedToasts' in fixture) assert.deepEqual(toasts, fixture.expectedToasts);
process.stdout.write(JSON.stringify({passed: true, commands: [...registered.keys()], draft, toasts}));
