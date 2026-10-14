# Network guard

Mamori is a self-use native macOS application, not a replacement VPN. This release supports a deliberately narrow GlobalProtect configuration. It contains a real PF helper implementation. Build 6 passed a local live start/status/restore cycle and normal Quit on 2026-10-14; see [Progress.md](Progress.md) for the precise scope. Automated tests and preview runs do not install the helper, change firewall rules, disconnect a VPN, or terminate work applications. Compilation and pure tests alone are not an end-to-end enforcement test.

## Activation prerequisites

- The app and embedded helper must be signed with valid Apple signing identities from the same Team ID. Apple Development is supported for local development; Developer ID Application and notarization are the public distribution path. The app identifier is `com.mamori.app`; the helper identifier and Mach service are `com.mamori.guard`. The build validator and runtime checks verify the embedded helper, not just its presence. See [Signing.md](Signing.md).
- An ad-hoc signature has no acceptable Team ID. The normal app therefore reports setup required and cannot install or activate protection. The separate preview bundle always simulates effects. Neither treats an observed VPN connection alone as evidence of real enforcement.
- The app is outside App Sandbox. The helper is embedded at `Contents/MacOS/MamoriGuard`, with its `SMAppService` daemon property list at `Contents/Library/LaunchDaemons/com.mamori.guard.plist`.
- The property list exposes only that Mach service, uses `BundleProgram`, and must not use unconditional `KeepAlive`. The service is demand-started; a successful explicit Stop exits normally after returning its acknowledgment. A failed restore keeps its recovery journal and remains available for retry.
- No Network Extension entitlement is used by this PF implementation. Hardened Runtime and proper signing remain necessary for a distributable build. Installation uses the normal `SMAppService` approval process; a password is never passed through Mamori.
- GlobalProtect must already be connected. After helper setup, read-only discovery checks the signed running Palo Alto `PanGPS`, a GlobalProtect-owned system network service, its matching active interface and assigned address, sampled external routes, and live IPv4 gateway transport endpoints. Every Start guarding performs a fresh helper discovery and starts with that result. Displayed tunnel and gateway values are read-only; optional manual discovery is only for inspection. A failed discovery cannot start protection, and a Quit or cancelled activation during discovery prevents a late start. Discovery does not install policy or reconnect the VPN. Two sampled routes do not prove full-tunnel coverage; a full tunnel remains an explicit deployment assumption, and the evidence must be validated against the installed GlobalProtect version.

The first release intentionally refuses to arm when PF is already enabled, existing PF states exist, interface skipping is configured, the stock Apple filter anchor is missing, or other active filter rules are present. It does not flush another component's connection states to make setup work.

## Packet policy

The helper uses only the owned child anchor `com.apple/000.mamori`, reached through the pre-existing stock `com.apple/*` filter anchor. It does not edit `/etc/pf.conf`, reload the main ruleset, or create a root-anchor reference. Reusing the stock wildcard is a specific self-use compatibility assumption, not a claim that the Apple namespace is a public extension API.

The policy blocks IPv4 and IPv6 on all unapproved interfaces, including interfaces added after activation. It allows:

1. Loopback traffic.
2. The selected, verified tunnel while it remains verified.
3. TCP 443 and UDP 4501 to or from the exact configured gateway IPv4 addresses.
4. Minimal IPv4 DHCP broadcast/request and server-response traffic.

Rules do not create PF state; TCP passes explicitly use `flags any` so already-established flows can use approved paths. The helper compiles and journals the intended policy, loads default-deny while PF is disabled, verifies the complete ordered canonical readback, and only then obtains its own PF enable reference. Existing untracked connections are subject to the policy when PF is enabled. No DNS, entire browser, local subnet, or arbitrary HTTPS exception is installed.

Gateway exceptions are IP/port exceptions, not process-specific exceptions: other applications could communicate with those exact approved endpoints. This is a disclosed limitation of this small PF implementation. IPv6 VPN transport, proxies, split-tunnel configurations, SSO-specific exceptions, and automatic VPN reconnection are outside this release. Sampled route checks may not detect every split-tunnel configuration. DNS/SSO needed for a later manual VPN connection can remain blocked. Mamori must not silently remove its block to make authentication work.

## State and failures

The privileged service owns the authoritative network state. The menu bar app owns application selection and termination, and the UI reads the helper's result. `Protected` requires verified helper enforcement; `Blocked` means the retained packet policy is verified and the VPN is disconnected or unconfirmed. These are separate VPN evidence states: an unreadable observation is not a confirmed loss and cannot trigger automatic app quitting. `Fault` means protection itself cannot be confirmed. The UI follows helper evidence while guarding, rather than promoting read-only client observation into proof of enforcement.

Every three seconds, and on status requests, the helper checks rule integrity, root-anchor shape, competing active rules, PF state/skip settings, and VPN evidence. This polling is for detection, status and policy narrowing; the pre-installed non-tunnel block is the primary protection against direct traffic during that interval. UI process loss or manual VPN disconnection does not remove the default-deny policy. The helper does not reconnect GlobalProtect or silently loosen exceptions for recovery.

An administrator or another root component can alter PF between checks. A PF implementation does not provide a tamper-proof or universally zero-leak guarantee. The helper reports a fault when its invariants fail and retains the existing owned rules. It does not overwrite other software's new policy.

A private journal records desired state, owner UID, complete canonical owned rules, pending policy updates, the PF enable reference, and the boot-session UUID. A policy update is journaled before loading and reconciled against full ordered readback after interruption. Boot identity prevents release of an old PF reference against a later boot. An interrupted explicit Stop is resumed as restoration, not as automatic activation. The tiny interval between acquiring a PF reference and saving its token cannot be made transactional using `pfctl`; a recorded pending acquisition without a token causes a recovery fault instead of a false restoration acknowledgment. The helper never compensates with a global PF disable.

## Quit and uninstall

The owned anchor may not exist before the first activation or after its rules are flushed. Mamori verifies its existence through stable parent-anchor listings before reading its rules. Confirmed absence counts as an empty ruleset; a failed listing, changing hierarchy, or error reading an existing anchor remains a fault. Inspection errors include the PF command, exit status, and bounded diagnostics to make further failures actionable.

Normal Quit must wait for an `inactive` helper acknowledgment. The service records stop intent, removes only its anchor rules, verifies their absence, releases only its own enable token, and removes its recovery journal. A same-boot retry verifies whether that exact reference is already absent before completing interrupted cleanup; unreadable reference state preserves the journal. It never runs a global `pfctl -d`, global rules/state flush, or old-file overwrite. A failure returns `fault` and preserves recovery information.

The private service footprint is `/Library/Application Support/Mamori/guard-session.json` and its root-owned directory. Removal uses fixed paths, removes the directory only when empty, and verifies removal even when an interrupted cleanup has already deleted the journal. The client requests restoration before unregistering its own `SMAppService` daemon and login item. Settings → Complete Uninstall then permanently removes the validated running production app and the current user's exact Mamori data paths; it does not use Trash, remove other copies, or expose arbitrary root deletion. Preview simulates uninstall. Failures retain a visible recovery path; see [Installation.md](Installation.md). No attempt is made to erase system authorization history, unified logs, unrelated shell history, or backups. API calls and direct process arguments do not create interactive shell history.

Stopping protection does not restore terminated application data or reconnect old sockets. Intentional Quit and crashes have different semantics: only an authenticated explicit Stop permits cleanup.

## Validation boundary

Automated tests render and inspect policies and exercise state/journal decisions using fixtures. They never invoke the helper, PF, service registration, VPN control, or real application termination. The helper and client can be compiled without activation.

Before treating a signed installation as verified, a separately authorized test must cover existing connections, IPv4/IPv6, UDP/QUIC, DNS, the real gateway/SSO behavior, tunnel replacement, physical network changes, helper/UI failure, and explicit restore. The local build 6 cycle validated activation, periodic rule verification, and restoration. Build 7 additionally passed two cycles using fresh automatic discovery on each start, without disconnecting the VPN or terminating a work application. The broader disruptive matrix above remains unvalidated; the local cycle is not a demonstrated universal leak-proof guarantee.

## Primary references

- [Apple: Packet Filter is not API](https://developer.apple.com/documentation/technotes/tn3165-packet-filter-is-not-api)
- [Apple: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple: SMAppService registration](https://developer.apple.com/documentation/servicemanagement/smappservice/register())
- [Palo Alto Networks: GlobalProtect ports](https://docs.paloaltonetworks.com/ngfw/administration/firewall-administration/reference-port-number-usage/ports-used-for-globalprotect)
- Local macOS `pfctl(8)` and `pf.conf(5)` manual pages for anchors, states, interface skipping, and reference-counted enablement.
