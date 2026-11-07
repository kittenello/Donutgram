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
export interface UINode { type: "section" | "text" | "list" | "button" | "toggle" | "input" | "select"; id: string; title?: string; text?: string; value?: Scalar; callbackId?: string; children?: UINode[]; options?: {title: string; value: Scalar}[]; }
export interface UIPage { id: string; title: string; nodes: UINode[]; }
export interface API {
  commands: {register(command: Command, handler?: (input?: JSONValue) => void | Promise<void>): Promise<Disposable>};
  events: {on(name: "plugin.activated" | "plugin.deactivating" | "app.foreground" | "app.background" | "theme.changed" | "locale.changed" | "powerSaving.changed", handler: (payload: JSONValue) => void | Promise<void>): Promise<Disposable>};
  storage: {get(key: string): Promise<JSONValue>; set(key: string, value: JSONValue): Promise<void>; remove(key: string): Promise<void>; keys(): Promise<string[]>};
  settings: {get(): Promise<{[key: string]: JSONValue}>; set(values: {[key: string]: JSONValue}): Promise<void>};
  capabilities: {has(capability: string): Promise<boolean>; list(): Promise<JSONValue>};
  environment: {get(): Promise<JSONValue>};
  composer: {getActiveDraft(): Promise<Draft | null>; replaceSelection(value: {composer: string; expectedRevision: string; range?: TextRange; text: string}): Promise<void>};
  selection: {get(): Promise<Selection | null>};
  theme: {get(): Promise<{appearance: "light" | "dark"}>};
  network: {request(value: {url: string; method?: "GET" | "POST"; headers?: {[key: string]: string}; body?: string}): Promise<JSONValue>};
  ui: {callback(handler: (value: JSONValue) => void | Promise<void>): {id: string; dispose(): void}; toast(text: string): Promise<void>; render(value: UIPage): Promise<JSONValue>; dispose(value: {id: string}): Promise<void>};
}
export interface Plugin { activate(api: API): void | Promise<unknown>; deactivate?(): void | Promise<unknown>; }
declare global {
  const dg: API;
  function definePlugin(manifest: Manifest, plugin: Plugin): Plugin;
  function definePlugin(plugin: Plugin): Plugin;
}
