(() => {
  'use strict';
  const native = globalThis.__dgNative;
  delete globalThis.__dgNative;
  const commands = new Map();
  const listeners = new Map();
  const callbacks = new Map();
  const pending = new Map();
  let nextId = 1;
  let nextCallbackId = 1;
  let definition = null;
  let environment = Object.freeze({});
  let activated = false;
  const error = (code) => Object.assign(new Error(code), {code});
  function request(method, params = {}) {
    if (pending.size >= 64) return Promise.reject(error('request_limit'));
    if (nextId >= Number.MAX_SAFE_INTEGER) return Promise.reject(error('request_limit'));
    const id = nextId++;
    return new Promise((resolve, reject) => {
      pending.set(id, {resolve, reject});
      try { native(JSON.stringify({id, method, params})); }
      catch (value) { pending.delete(id); reject(value); }
    });
  }
  const method = (name) => (params = {}) => request(name, params);
  const api = Object.freeze({
    commands: Object.freeze({
      async register(descriptor, handler) {
        if (!descriptor || typeof descriptor.id !== 'string' || commands.size >= 64 || commands.has(descriptor.id)) throw error('invalid_command');
        const run = handler || descriptor.run;
        if (typeof run !== 'function') throw error('invalid_command');
        const value = {id: descriptor.id, title: descriptor.title, placement: descriptor.placement};
        await request('ui.command.register', value);
        commands.set(value.id, run);
        let disposed = false;
        return Object.freeze({dispose: async () => {
          if (disposed) return;
          disposed = true;
          commands.delete(value.id);
          await request('ui.command.unregister', {id: value.id});
        }});
      }
    }),
    events: Object.freeze({
      async on(name, handler) {
        if (typeof name !== 'string' || typeof handler !== 'function' || listeners.size >= 64) throw error('invalid_event');
        await request('events.subscribe', {name});
        if (!listeners.has(name)) listeners.set(name, new Set());
        const handlers = listeners.get(name);
        if (handlers.size >= 16) throw error('event_limit');
        handlers.add(handler);
        return Object.freeze({dispose: async () => {
          handlers.delete(handler);
          if (!handlers.size) { listeners.delete(name); await request('events.unsubscribe', {name}); }
        }});
      }
    }),
    storage: Object.freeze({
      get: (key) => request('storage.get', {key}),
      set: (key, value) => request('storage.set', {key, value}),
      remove: (key) => request('storage.remove', {key}),
      keys: () => request('storage.keys')
    }),
    settings: Object.freeze({get: () => request('settings.get'), set: (values) => request('settings.set', {values})}),
    capabilities: Object.freeze({has: (capability) => request('capabilities.has', {capability}), list: () => request('capabilities.list')}),
    environment: Object.freeze({get: () => Promise.resolve(environment)}),
    composer: Object.freeze({getActiveDraft: () => request('composer.getActiveDraft'), replaceSelection: method('composer.replaceSelection')}),
    selection: Object.freeze({get: () => request('selection.get')}),
    theme: Object.freeze({get: () => request('theme.get')}),
    network: Object.freeze({request: method('network.request')}),
    ui: Object.freeze({
      callback(handler) {
        if (typeof handler !== 'function' || callbacks.size >= 128 || nextCallbackId >= Number.MAX_SAFE_INTEGER) throw error('callback_limit');
        const id = 'callback.' + nextCallbackId++;
        callbacks.set(id, handler);
        return Object.freeze({id, dispose: () => { callbacks.delete(id); }});
      },
      toast: (text) => request('ui.toast', {text}), render: method('ui.render'), dispose: method('ui.dispose')
    })
  });
  function expose(name, value) {
    Object.defineProperty(globalThis, name, {value, writable: false, configurable: false});
  }
  expose('definePlugin', (manifest, implementation) => {
    if (definition) throw error('duplicate_definition');
    definition = implementation || manifest;
    if (!definition || typeof definition.activate !== 'function') throw error('invalid_definition');
    return definition;
  });
  expose('dg', api);
  expose('__dgConfigure', (value) => { environment = Object.freeze(value); });
  expose('__dgActivate', async () => {
    if (!definition || activated) throw error('invalid_lifecycle');
    activated = true;
    await definition.activate(api);
  });
  expose('__dgReply', (id, response) => {
    const operation = pending.get(id);
    if (!operation) return;
    pending.delete(id);
    if (response && response.error) operation.reject(Object.assign(new Error(String(response.error.message || response.error.code)), {code: response.error.code}));
    else operation.resolve(response ? response.result : null);
  });
  expose('__dgDispatch', async (kind, payload) => {
    if (!activated) throw error('not_active');
    if (kind === 'command') {
      const run = commands.get(payload.id);
      if (!run) throw error('command_not_found');
      await run(payload.input);
    } else if (kind === 'ui') {
      const handler = callbacks.get(payload.id);
      if (!handler) throw error('callback_not_found');
      await handler(payload.value);
    } else if (kind === 'event') {
      const handlers = listeners.get(payload.name);
      if (handlers) for (const handler of handlers) await handler(payload.payload);
    } else throw error('invalid_event');
  });
})();
