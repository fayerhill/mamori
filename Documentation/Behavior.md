# Mamori lifecycle contract

`SessionReducer` is a synchronous, deterministic reducer. It performs no network, power, process, or file operations. A serialized platform adapter executes its effects and returns completion events. Initial state is idle with keep-awake and automatic app quitting off, and no selected apps. Preferences may populate selections; they must never silently resume a guard session.

## Guard state and restoration

Starting protection enters `arming`. Only a verified backend completion may show `protected`; a verified gate with a disconnected or unverified VPN shows `blocked`. Inconclusive VPN evidence is not a confirmed loss and does not trigger app termination. The adapter must report `connected` only for the selected, currently verified VPN, never merely because some utun interface exists. A failure to verify the network gate itself is `backendFailed`, producing `fault`, rather than an assertion that blocking works.

Activation and restoration effects carry increasing operation numbers. Return the exact number with each completion; stale and duplicate acknowledgments cannot update a newer operation. VPN events must come from the current observer, on the same serialized adapter; discard observations from an obsolete observer generation before reducing them.

Stopping protection cancels pending automatic app actions and requests restoration. It leaves independent keep-awake unchanged. Starting another session is unavailable until restoration succeeds. A restore failure remains visible as `fault`; `retryRestoration` keeps the recovery path available.

Normal Quit cancels automatic app actions and keep-awake, then waits for a successful restore acknowledgment before emitting `exitApplication`. It also requests an acknowledgment when apparently idle, so the backend can check for owned residual resources. An activation already in flight cannot be canceled by discarding its callback: the reducer waits for it to finish and requests a fresh restoration, even if an earlier restoration succeeded. The newest restoration must acknowledge that owned resources are absent before exit. The backend must serialize its mutations and must not report restoration success before cleanup is verified. Missing callbacks leave a visible restoring state; the adapter can report restoration failure and offer retry, but must not manufacture success to exit.

A crash or forced termination is not a normal Quit event. This reducer does not translate an XPC disconnect into permission to remove protection. Network protection and helper recovery policy belong to the guard backend.

If startup discovers that the helper is still enforcing a previous session, `existingGuardNeedsRestoration` shows a recovery fault and enables restoration retry. It does not silently resume the session, report it inactive, or mutate the backend.

## Automatic app quitting

The feature has an independent switch and starts off. Only a confirmed connected-to-disconnected transition, after it was armed while connected, can produce a quit batch. Repeated disconnected observations do not repeat it. Enabling the feature or adding an app while already blocked waits for the next confirmed connection and loss. A verified connection cancels outstanding quit actions; no event or effect reopens an app.

The application adapter supplies stable identities for selected GUI apps belonging to the current user. The picker includes installed apps, including stopped apps; only a fresh running instance can receive a quit request. Mamori, recognized VPN clients, and critical system components are excluded. The adapter rechecks the current user, process ID, launch time, bundle identifier, and canonical path before acting. A string identifier is not authorization to quit an arbitrary process. The feature never selects generic node, Python, or background system processes implicitly. A browser or terminal can be selected explicitly, and this covers the whole application and its windows or sessions.

Every batch has a ticket. Immediately before both normal termination and any user-enabled delayed force termination, the adapter calls `canPerformAutoQuit(id:ticket:)`. Disabling the feature, ending protection, normal Quit, reconnection, or a backend fault invalidates pending actions. Deselecting an app cancels that app without canceling other selected apps. Readding it does not add it to the already-dispatched batch. Once an app is confirmed terminated, send `applicationDidQuit`; this never releases keep-awake. Canceling work cannot reopen an app that has already quit or recover its unsaved changes.

## Independent keep-awake

Keep-awake choices are off, while Mamori runs, or a positive duration in seconds. The duration starts after acquisition succeeds. The platform uses a power assertion rather than changing global power preferences. It permits display sleep and screen locking; it does not promise to defeat lid closure, explicit sleep, shutdown, restart, or low-battery sleep. It does not ensure that a remote AI job continues.

An acquisition failure returns the control to off and exposes an error. Changes and timeouts carry lease tickets; a stale acquisition success must release that specific lease, never a newer one. The adapter must make release idempotent and must honor the ticket. Duplicate completions for the current completed acquisition do nothing. Stopping the network guard or quitting selected apps leaves keep-awake active; normal Quit releases it and cancels its timer even when network restoration needs retry.

## Verification boundary

The unit tests run this reducer with synthetic completions, including reordered activation/restoration results, obsolete callbacks and timers, uncertain VPN evidence, selection changes, restore failures, and wake failures. They never alter PF, power settings, running apps, services, or connectivity. These tests prove orchestration behavior, not that a real VPN or packet filter enforces protection; physical network and lifecycle acceptance checks remain separate integration work.
