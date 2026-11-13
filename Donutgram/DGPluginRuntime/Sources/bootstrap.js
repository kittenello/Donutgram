(() => {
  'use strict';
  const native = globalThis.__dgNative;
  delete globalThis.__dgNative;
  const commands = new Map();
  const listeners = new Map();
  const callbacks = new Map();
  const transforms = new Map();
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
        const registration = {handler: run};
        commands.set(value.id, registration);
        try { await request('ui.command.register', value); }
        catch (failure) { if (commands.get(value.id) === registration) commands.delete(value.id); throw failure; }
        let disposed = false;
        let disposing = null;
        return Object.freeze({dispose: () => {
          if (disposed) return Promise.resolve();
          if (disposing) return disposing;
          disposing = request('ui.command.unregister', {id: value.id}).then(() => {
            disposed = true;
            if (commands.get(value.id) === registration) commands.delete(value.id);
          }).finally(() => { disposing = null; });
          return disposing;
        }});
      }
    }),
    events: Object.freeze({
      async on(name, handler) {
        if (typeof name !== 'string' || typeof handler !== 'function') throw error('invalid_event');
        let group = listeners.get(name);
        while (group && group.closing) {
          try { await group.closing; } catch (_) {}
          group = listeners.get(name);
        }
        if (!group) {
          if (listeners.size >= 64) throw error('invalid_event');
          group = {handlers: new Set(), ready: null, closing: null};
          listeners.set(name, group);
          group.ready = request('events.subscribe', {name}).catch(failure => {
            if (listeners.get(name) === group) listeners.delete(name);
            throw failure;
          });
        }
        if (group.handlers.size >= 16) throw error('event_limit');
        const registration = {handler};
        group.handlers.add(registration);
        try { await group.ready; }
        catch (failure) { group.handlers.delete(registration); throw failure; }
        let disposed = false;
        let disposing = null;
        return Object.freeze({dispose: () => {
          if (disposed) return Promise.resolve();
          if (disposing) return disposing;
          if (group.handlers.size > 1) {
            disposed = true;
            group.handlers.delete(registration);
            return Promise.resolve();
          }
          disposing = request('events.unsubscribe', {name}).then(() => {
            disposed = true;
            group.handlers.delete(registration);
            if (listeners.get(name) === group) listeners.delete(name);
          }).finally(() => { group.closing = null; disposing = null; });
          group.closing = disposing;
          return disposing;
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
    environment: Object.freeze({get: () => request('environment.get')}),
    composer: Object.freeze({getActiveDraft: () => request('composer.getActiveDraft'), replaceSelection: method('composer.replaceSelection')}),
    selection: Object.freeze({get: () => request('selection.get')}),
    theme: Object.freeze({get: () => request('theme.get'), contribute: method('theme.contribute'), clear: () => request('theme.clear')}),
    network: Object.freeze({request: method('network.request')}),
    messages: Object.freeze({read: method('messages.read'), send: method('messages.send'), edit: method('messages.edit'), delete: method('messages.delete'), beforeSend: (descriptor, handler) => api.transforms.register({...descriptor, slot: 'outgoing'}, handler)}),
    chats: Object.freeze({metadata: method('chats.metadata')}),
    peers: Object.freeze({read: method('peers.read')}),
    navigation: Object.freeze({open: method('navigation.open')}),
    notifications: Object.freeze({local: method('notifications.local')}),
    files: Object.freeze({pick: () => request('files.pick'), read: method('files.read')}),
    assets: Object.freeze({image: method('assets.image')}),
    translation: Object.freeze({request: method('translation.request')}),
    actions: Object.freeze({messages: Object.freeze({
      prepare: method('messages.prepare'),
      sendInteractive: method('messages.sendInteractive'),
      compose: method('messages.compose')
    })}),
    transforms: Object.freeze({
      async register(descriptor, handler) {
        if (!descriptor || typeof descriptor.id !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$/.test(descriptor.id) || !['profile', 'chatList', 'displayLinks', 'outgoing'].includes(descriptor.slot) || typeof handler !== 'function') throw error('invalid_transform');
        const priority = descriptor.priority === undefined ? 0 : descriptor.priority;
        if (!Number.isInteger(priority) || priority < -100 || priority > 100) throw error('invalid_transform');
        if (transforms.size >= 8 || transforms.has(descriptor.id)) throw error('transform_limit');
        const value = {id: descriptor.id, slot: descriptor.slot, priority};
        const family = descriptor.slot === 'outgoing' ? 'messages.interceptor' : 'ui.transform';
        const registration = {handler, family};
        transforms.set(value.id, registration);
        try { await request(family + '.register', value); }
        catch (failure) { if (transforms.get(value.id) === registration) transforms.delete(value.id); throw failure; }
        let disposed = false;
        let disposing = null;
        return Object.freeze({dispose: () => {
          if (disposed) return Promise.resolve();
          if (disposing) return disposing;
          disposing = request(family + '.unregister', {id: value.id}).then(() => {
            disposed = true;
            if (transforms.get(value.id) === registration) transforms.delete(value.id);
          }).finally(() => { disposing = null; });
          return disposing;
        }});
      }
    }),
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
      const registration = commands.get(payload.id);
      if (!registration) throw error('command_not_found');
      await registration.handler(payload.input);
    } else if (kind === 'ui') {
      const handler = callbacks.get(payload.id);
      if (!handler) throw error('callback_not_found');
      await handler(payload.value);
    } else if (kind === 'transform') {
      const registration = transforms.get(payload.id);
      if (!registration) throw error('transform_not_found');
      const value = await registration.handler(payload.input);
      await request(registration.family + '.result', {requestId: payload.requestId, value});
    } else if (kind === 'event') {
      const group = listeners.get(payload.name);
      if (group) for (const registration of Array.from(group.handlers)) {
        if (group.handlers.has(registration)) await registration.handler(payload.payload);
      }
    } else throw error('invalid_event');
  });
})();
