# local view-model transform contract

implementation in progress. capability ui.transform has exact scopes profile, chatList and displayLinks. it is restricted to localPrivate packages. no native view, raw peer id or account object crosses the bridge. immutable input and validated patches are bounded to32KiB,depth8 and4096jsonnodes. failures use the unchanged native input.

api.transforms.register({id,slot,priority?}, handler) returns an async disposable. slots match the capability scopes. native methods ui.transform.register/unregister/result are allowlisted; registrations belong to one runtime generation. dispatchkind transform payload is {id,requestId,input}; trusted bootstrap awaits the handler, then submits ui.transform.result {requestId,value}. results are accepted only for that runtime's pending request and validated by production DGPluginViewTransform.apply. the handler never supplies installation identity.

profile input {panes:[{id:string,empty:boolean}]}, patch {hide:string[]}. only panes positively known to be empty can be hidden; unknown/nonempty panes and security/settings controls cannot be hidden. fallback preserves all panes.

chatList input {items:[{handle:string,title:string,unread:integer,pinned:boolean}]}, patch {order?:string[],hidden?:string[]}. handles are native-generated opaque values. only unpinned supplied rows may be reordered/filtered. pinned rows preserve their native relative order. absent order entries remain in original order. no server folders, read states or messages change.

displayLinks input {items:[{handle:string,title:string,url:string}]}, patch {labels:[{handle:string,text:string}]}. only visible labels change; the native original destination and link-confirmation policy stay unchanged. labels reject control and bidi-override characters. adapters identify a locally modified label as plugin content.

the native entry point DGPluginManager.transformedViewModel(slot:input:update:) returns a cached full validated model immediately or the native input. it schedules bounded asynchronous runtime work; layout never waits for javascript. transforms run in priority,installationid,registrationid order. cache keys include input content and execution registration generation; stop/revoke/update clears caches and invalidates pending results. bounded caches/in-flight requests prevent a high-frequency layout from flooding runtimes. update is delivered on main only when the final cached model differs from input and previous output.

feature readiness requires real adapters and tests, not only this contract. native ios layout/frame verification remains a separate pending check.
