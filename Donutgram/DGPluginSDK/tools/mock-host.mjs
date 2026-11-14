import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const snapshot = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const fixture = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
const root = path.dirname(fileURLToPath(import.meta.url));
const bootstrap = fs.readFileSync(path.resolve(root, '../../DGPluginRuntime/Sources/bootstrap.js'), 'utf8');
const grants = snapshot.manifest.permissions;
const registered = new Map();
const storage = new Map();
const toasts = [];
const pages = new Map();
const networkCalls = [];
const assets = new Map();
const nativeCalls = [];
const transformRegistrations = new Map();
const transformReplies = new Map();
const eventNames = new Set(['plugin.activated', 'account.contextChanged', 'app.foreground', 'theme.changed', 'locale.changed', 'chat.opened', 'chat.closed', 'composer.changed', 'message.observed']);
let themeTokens = null;
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
  'theme.get': ['theme.read', 'currentTheme'],
  'theme.contribute': ['theme.contribute', 'localTokens'],
  'theme.clear': ['theme.contribute', 'localTokens'],
  'ui.render': ['ui.contribute', 'settings'],
  'ui.dispose': ['ui.contribute', 'settings'],
  'assets.image': ['ui.contribute', 'settings'],
  'network.request': ['network.public', 'declaredOrigins'],
  'messages.read': ['messages.read', 'selectedChats', true],
  'chats.metadata': ['chats.metadata.read', 'selectedChats', true],
  'peers.read': ['peers.read', 'selectedPeers', true],
  'navigation.open': ['navigation.open', 'safeScreens', true],
  'notifications.local': ['notifications.local', 'pluginAccount', true],
  'files.pick': ['files.userSelected', 'selectedFile', true],
  'files.read': ['files.userSelected', 'selectedFile'],
  'translation.request': ['translation.request', 'selectedText', true],
  'messages.prepare': ['messages.sendInteractive', 'chosenRecipient', true],
  'messages.sendInteractive': ['messages.sendInteractive', 'chosenRecipient', true],
  'messages.compose': ['messages.compose', 'chosenRecipient', true],
  'messages.send': ['messages.send', 'chosenRecipient'],
  'messages.edit': ['messages.edit', 'selectedMessages'],
  'messages.delete': ['messages.delete', 'selectedMessages'],
  'messages.interceptor.register': ['messages.intercept', 'activeComposer'],
  'messages.interceptor.unregister': ['messages.intercept', 'activeComposer'],
  'messages.interceptor.result': ['messages.intercept', 'activeComposer']
};
function requireHost(condition, code) { if (!condition) throw Object.assign(new Error(code), {code}); }
function validatePage(page) {
  const validated = spawnSync(process.env.PYTHON || 'python', [path.join(root, 'dgplugin.py'), 'validate-ui', '-'], {input: JSON.stringify(page), encoding: 'utf8', timeout: 1000, maxBuffer: 65536});
  requireHost(validated.status === 0, 'invalid_argument');
}
function host(method, params) {
  const rule = rules[method];
  if (rule) {
    requireHost(grants.some((grant) => grant.capability === rule[0] && grant.scope === rule[1]), 'permission_denied');
    if (rule[2]) requireHost(gesture, 'permission_denied');
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
  if (method === 'ui.render') {
    validatePage(params);
    for (const node of walkNodes(params.nodes)) if (node.type === 'image') requireHost(assets.has(node.asset), 'stale_handle');
    pages.set(params.id, structuredClone(params));
    return params.id;
  }
  if (method === 'ui.dispose') { pages.delete(params.id); return null; }
  if (method === 'theme.contribute') {
    requireHost(Object.keys(params).length === 1 && ['blue', 'green', 'purple', 'orange'].includes(params.accent), 'invalid_argument');
    themeTokens = {accent: params.accent};
    return themeTokens;
  }
  if (method === 'theme.clear') { requireHost(Object.keys(params).length === 0, 'invalid_argument'); themeTokens = null; return null; }
  if (method === 'assets.image') {
    requireHost(typeof params.path === 'string' && params.path.startsWith('assets/') && snapshot.resources?.[params.path] === true, 'invalid_argument');
    const handle = 'asset.' + assets.size;
    assets.set(handle, params.path);
    return handle;
  }
  if (method === 'ui.transform.register' || method === 'messages.interceptor.register') {
    requireHost(params.slot !== 'displayLinks', 'feature_unavailable');
    const outgoing = method === 'messages.interceptor.register';
    requireHost(outgoing ? params.slot === 'outgoing' : grants.some((grant) => grant.capability === 'ui.transform' && grant.scope === params.slot), 'scope_denied');
    requireHost((snapshot.manifest.profile || 'localPrivate') === 'localPrivate' && !transformRegistrations.has(params.id), 'permission_denied');
    transformRegistrations.set(params.id, params);
    return params.id;
  }
  if (method === 'ui.transform.unregister' || method === 'messages.interceptor.unregister') { transformRegistrations.delete(params.id); return null; }
  if (method === 'ui.transform.result' || method === 'messages.interceptor.result') { transformReplies.set(params.requestId, params.value); return null; }
  if (method === 'network.request') {
    requireHost(snapshot.manifest.profile === 'publicNetwork', 'permission_denied');
    requireHost(Object.keys(params).every((key) => ['url', 'method'].includes(key)) && ['GET', 'HEAD'].includes(params.method || 'GET'), 'invalid_argument');
    const url = new URL(params.url);
    requireHost(url.protocol === 'https:' && !url.username && !url.password && !url.hash && !url.port && grants.some((grant) => grant.capability === 'network.public' && grant.origins?.includes(url.origin)), 'scope_denied');
    requireHost(Object.hasOwn(fixture.responses || {}, params.url), 'mock_response_missing');
    networkCalls.push({url: params.url, method: params.method || 'GET'});
    return structuredClone(fixture.responses[params.url]);
  }
  if (['messages.read', 'messages.send', 'messages.edit', 'messages.delete', 'chats.metadata', 'peers.read', 'navigation.open', 'notifications.local', 'files.pick', 'files.read', 'translation.request', 'messages.prepare', 'messages.sendInteractive', 'messages.compose'].includes(method)) {
    requireHost(Object.hasOwn(fixture.nativeResults || {}, method), 'feature_unavailable');
    nativeCalls.push({method, params});
    return structuredClone(fixture.nativeResults[method]);
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
  if (method === 'capabilities.has') return grants.some((grant) => grant.capability === params.capability && (grant.capability !== 'ui.transform' || ['profile', 'chatList'].includes(grant.scope)));
  if (method === 'capabilities.list') return Object.fromEntries(Object.keys(rules).map((name) => [name, !(fixture.unavailable || []).includes(name)]));
  if (method === 'theme.get') return {appearance: 'light'};
  if (method === 'events.subscribe') { requireHost(eventNames.has(params.name), 'feature_unavailable'); return null; }
  if (method === 'events.unsubscribe') return null;
  throw Object.assign(new Error('feature_unavailable'), {code: 'feature_unavailable'});
}
function* walkNodes(nodes) { for (const node of nodes) { yield node; if (node.children) yield* walkNodes(node.children); } }
context.__dgNative = (json) => {
  const envelope = JSON.parse(json);
  let response;
  try { response = {result: host(envelope.method, envelope.params)}; }
  catch (error) { response = {error: {code: error.code || 'mock_host_error', message: error.message}}; }
  const responseJSON = JSON.stringify(response);
  vm.runInContext(`__dgReply(${JSON.stringify(envelope.id)}, JSON.parse(${JSON.stringify(responseJSON)}))`, context, {timeout: 250});
};
vm.runInContext(bootstrap, context, {timeout: 250});
vm.runInContext('__dgConfigure({clientVersion:"13.2",locale:"en",appearance:"light",lowPowerMode:false})', context, {timeout: 250});
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
for (const event of fixture.uiEvents || []) {
  const page = pages.get(event.page);
  const node = page && [...walkNodes(page.nodes)].find((item) => item.id === event.node);
  assert(node?.callbackId, 'callback_not_registered');
  gesture = true;
  try { await vm.runInContext(`__dgDispatch("ui", ${JSON.stringify({id: node.callbackId, value: event.value})})`, context, {timeout: 250}); }
  finally { gesture = false; }
}
for (const [index, transform] of (fixture.transforms || []).entries()) {
  assert(transformRegistrations.has(transform.id), 'transform_not_registered');
  const requestId = 'mock-transform-' + index;
  await vm.runInContext(`__dgDispatch("transform", ${JSON.stringify({id: transform.id, input: transform.input, requestId})})`, context, {timeout: 250});
  assert.deepEqual(transformReplies.get(requestId), transform.expectedPatch);
}
if ('expectedText' in fixture) assert.equal(draft?.text, fixture.expectedText);
if ('expectedToasts' in fixture) assert.deepEqual(toasts, fixture.expectedToasts);
if ('expectedNetworkCalls' in fixture) assert.deepEqual(networkCalls, fixture.expectedNetworkCalls);
if ('expectedNativeCalls' in fixture) assert.deepEqual(nativeCalls, fixture.expectedNativeCalls);
if ('expectedSettings' in fixture) assert.deepEqual(settings, fixture.expectedSettings);
if ('expectedPages' in fixture) assert.deepEqual([...pages.keys()], fixture.expectedPages);
if ('expectedTheme' in fixture) assert.deepEqual(themeTokens, fixture.expectedTheme);
if ('expectedPageNodes' in fixture) for (const [id, text] of Object.entries(fixture.expectedPageNodes)) assert.equal([...pages.values()].flatMap((page) => [...walkNodes(page.nodes)]).find((node) => node.id === id)?.text, text);
process.stdout.write(JSON.stringify({passed: true, commands: [...registered.keys()], transforms: [...transformRegistrations.keys()], draft, toasts, pages: [...pages.values()], networkCalls, nativeCalls}));
