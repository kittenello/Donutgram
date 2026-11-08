export type JSONValue = null | boolean | number | string | JSONValue[] | {[key: string]: JSONValue};
export type Placement = "settings" | "composer" | "selection" | "messageMenu" | "chatToolbar";
export interface PluginError extends Error { code: string; }
export interface Permission { capability: string; scope: string; reason: string; origins?: string[]; }
export interface SettingField { type: "boolean" | "string" | "number" | "integer"; title: string; description?: string; default?: JSONValue; minimum?: number; maximum?: number; maxLength?: number; enum?: JSONValue[]; }
export interface Manifest {
  kind: "donutgram.plugin";
  schemaVersion: 1;
  id: string;
  name: string;
  version: string;
  description: string;
  author?: {name: string; username?: string};
  apiVersion: "^1.0.0" | "1.0.0";
  minClientVersion?: string;
  entry?: string;
  icon?: string;
  permissions: Permission[];
  optionalPermissions?: Permission[];
  settingsSchema?: {type: "object"; properties: {[key: string]: SettingField}};
  profile?: "localPrivate" | "publicNetwork";
  changelog?: string;
}
export interface Disposable { dispose(): Promise<void>; }
export interface Command { id: string; title: string; placement: Placement; run?: (input?: JSONValue) => void | Promise<void>; }
export interface TextRange { start: number; end: number; }
export interface Draft { handle: string; revision: string; text: string; selection: TextRange; entities: JSONValue[]; entitiesComplete: false; plainTextComplete: false; }
export interface Selection { text: string; source: "composer" | "message"; entities: JSONValue[]; entitiesComplete: false; }
export type Scalar = null | boolean | number | string;
export type AssetHandle = string;
export interface UIBase { id: string; title?: string; text?: string; }
export type UINode =
  | (UIBase & {type: "section" | "list"; children?: UINode[]})
  | (UIBase & {type: "text" | "markdown"})
  | (UIBase & {type: "button"; callbackId: string})
  | (UIBase & {type: "toggle"; value: boolean; callbackId: string})
  | (UIBase & {type: "input" | "multiline"; value: string; callbackId: string})
  | (UIBase & {type: "select"; value?: Scalar; callbackId: string; options: {title: string; value: Scalar}[]})
  | (UIBase & {type: "slider" | "stepper"; value: number; minimum: number; maximum: number; step: number; callbackId: string})
  | (UIBase & {type: "image"; asset: AssetHandle});
export interface UIPage { id: string; title: string; nodes: UINode[]; }
export interface PluginEvent { readonly id: string; readonly timestamp: number; readonly version: 1; readonly data: JSONValue; }
export type PluginEventName = "plugin.activated" | "account.contextChanged" | "app.foreground" | "theme.changed" | "locale.changed" | "chat.opened" | "chat.closed" | "composer.changed" | "message.observed";
export interface Environment { readonly clientVersion: string; readonly locale: string; readonly appearance: "light" | "dark"; readonly lowPowerMode: boolean; }
export interface SelectedMessage { readonly handle: string; readonly text: string; readonly timestamp: number; readonly entities: JSONValue[]; readonly entitiesComplete: false; readonly mediaComplete: false; }
export interface TransformInputs {
  profile: {panes: readonly {id: string; empty: boolean}[]};
  chatList: {items: readonly {handle: string; title: string; unread: number; pinned: boolean}[]};
  displayLinks: {items: readonly {handle: string; title: string; url: string}[]};
}
export interface TransformPatches {
  profile: {hide: string[]};
  chatList: {order?: string[]; hidden?: string[]};
  displayLinks: {labels: {handle: string; text: string}[]};
}
export type TransformSlot = keyof TransformInputs;
export type PluginPageAccent = "blue" | "green" | "purple" | "orange";
export interface API {
  commands: {register(command: Command, handler?: (input?: JSONValue) => void | Promise<void>): Promise<Disposable>};
  events: {on(name: PluginEventName, handler: (event: PluginEvent) => void | Promise<void>): Promise<Disposable>};
  storage: {get(key: string): Promise<JSONValue>; set(key: string, value: JSONValue): Promise<void>; remove(key: string): Promise<void>; keys(): Promise<string[]>};
  settings: {get(): Promise<{[key: string]: JSONValue}>; set(values: {[key: string]: JSONValue}): Promise<void>};
  capabilities: {has(capability: string): Promise<boolean>; list(): Promise<{[method: string]: boolean}>};
  environment: {get(): Promise<Environment>};
  composer: {getActiveDraft(): Promise<Draft | null>; replaceSelection(value: {composer: string; expectedRevision: string; range?: TextRange; text: string}): Promise<void>};
  selection: {get(): Promise<Selection | null>};
  theme: {get(): Promise<{appearance: "light" | "dark"}>; contribute(params: {accent: PluginPageAccent}): Promise<{accent: PluginPageAccent}>; clear(): Promise<void>};
  network: {request(value: {url: string; method?: "GET" | "HEAD"}): Promise<{url: string; status: number; headers: {[key: string]: string}; body: string}>};
  messages: {read(params?: Record<string, never>): Promise<SelectedMessage[]>};
  chats: {metadata(params?: Record<string, never>): Promise<{handle: string; title: string; scope: "currentNativeChat"}>};
  peers: {read(params?: Record<string, never>): Promise<{handle: string; title: string}[]>};
  navigation: {open(params: {screen: "plugins"}): Promise<void>};
  notifications: {local(params: {text: string}): Promise<void>};
  files: {pick(): Promise<{handle: string; name: string; size: number}>; read(params: {handle: string}): Promise<{text: string; encoding: "utf8"}>};
  translation: {request(params: {targetLanguage: string; text?: string}): Promise<{text: string; service: "telegram"; targetLanguage: string}>};
  assets: {image(params: {path: string}): Promise<AssetHandle>};
  transforms: {register<S extends TransformSlot>(descriptor: {id: string; slot: S; priority?: number}, handler: (input: Readonly<TransformInputs[S]>) => TransformPatches[S] | Promise<TransformPatches[S]>): Promise<Disposable>};
  actions: {messages: {
    prepare(params: {text: string}): Promise<{handle: string; recipient: string; text: string; expiresIn: number}>;
    sendInteractive(params: {handle: string}): Promise<{status: "queued"}>;
    compose(params: {text: string}): Promise<{status: "draftPrepared"}>;
  }};
  ui: {callback(handler: (value: JSONValue) => void | Promise<void>): {id: string; dispose(): void}; toast(text: string): Promise<void>; render(value: UIPage): Promise<JSONValue>; dispose(value: {id: string}): Promise<void>};
}
export interface Plugin { activate(api: API): void | Promise<unknown>; deactivate?(): void | Promise<unknown>; }
declare global {
  const dg: API;
  function definePlugin(manifest: Manifest, plugin: Plugin): Plugin;
  function definePlugin(plugin: Plugin): Plugin;
}
