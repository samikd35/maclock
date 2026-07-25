# StayPane competitor analysis

**Research date:** 25 July 2026

**Scope:** macOS focus enforcement, app and website blockers, exact-workspace tools, browser focus tools, platform substitutes, and human-accountability substitutes

**Evidence standard:** first-party product pages, support documentation, privacy policies, app-store listings, source repositories, and StayPane's own repository documentation

> **Reading note:** “Observed” means documented by the product owner or visible in this repository. Vendor claims such as user counts are not independently verified. “Inference” is the analyst's interpretation. When a capability is described as absent, the precise meaning is “not documented in the first-party material reviewed,” unless the vendor explicitly says otherwise.

## Executive summary

StayPane is not yet another generic app or website blocker. Its potentially defensible idea is **commitment to an exact desktop workspace**: the user chooses particular macOS windows and Chrome windows or tabs, optionally constrains an allowed tab to its current website or exact page, and then cannot change that selection after enforcement begins. A fixed end time, a 30-second early-reset sequence, local-only operation, safe restoration of minimized windows, and explicit fail-open behavior make the intended contract unusually legible. Those characteristics are documented in the [PRD](./PRD.md), [product policy](../../docs/contexts/product/CONTEXT.md), [macOS context](../../docs/contexts/macos/CONTEXT.md), [Chrome context](../../docs/contexts/chrome/CONTEXT.md), and [native-bridge context](../../docs/contexts/native-bridge/CONTEXT.md).

The present maturity must be stated conservatively. StayPane is a **source-only v1 candidate awaiting human acceptance**, not a launched or proven product. Tickets 01–13 are marked complete, but Ticket 14 remains `ready-for-human`; its full manual acceptance matrix and short real-session check are still unchecked in the [implementation queue](../../tickets.md). The public workflow still requires building the Swift app from source and loading the Chrome extension unpacked, as described in the [README](../../README.md) and [installation guide](../../docs/INSTALL.md).

The competitive conclusion is mixed:

- **The generic proposition is already commoditized.** Raycast Focus now offers free app and website block/allow modes on macOS and Windows inside a widely distributed launcher, while products such as 1Focus, FocusMe, Focus Bear, and Cold Turkey Micromanager cover app allowlisting in more mature packages. Raycast is the most important distribution threat because it can make “allow only my work apps and sites” feel like a free feature rather than a standalone product category. See [Raycast Focus](https://www.raycast.com/core-features/focus), the [Raycast Focus manual](https://manual.raycast.com/focus), and [Raycast pricing](https://www.raycast.com/pricing).
- **The exact-workspace proposition remains differentiated in the reviewed material.** No reviewed competitor documents StayPane's combination of stable macOS window identity, exact Chrome window/tab identity, per-tab Current Website or Exact Page scope, immutable mid-session selection, and local restoration semantics. Some competitors match window titles or choose apps; OneTabFocus locks selected Chrome tabs; none documents the full combination.
- **StayPane is deliberately weaker at tamper resistance.** Cold Turkey, 1Focus, FocusMe, and Focus emphasize locked modes that resist quitting, uninstalling, time changes, task managers, or settings changes. StayPane explicitly acknowledges Force Quit, extension removal, permission revocation, and administrator intervention as bypasses. The honest positioning is therefore **deliberate friction with safety guarantees**, not “impossible to bypass.”
- **Distribution and onboarding are the largest practical weaknesses.** Competitors offer signed downloads, app-store installation, cross-platform clients, browser-family coverage, schedules, presets, mobile coverage, and/or cloud sync. High-traction adjacent products such as Opal can extend an established iPhone subscription onto Mac. StayPane currently requires macOS 26 on Apple silicon, Accessibility approval, a source build, and an unpacked Chrome extension. That dramatically narrows the reachable market before product value can be tested.
- **Privacy is a meaningful advantage, but not a unique category.** StayPane stores no target titles, URLs, or domains in history; has no account, telemetry, server, remote data, or background update; and keeps its Chrome bridge local. SelfControl, Abstand, Focus, 1Focus, and Cold Turkey also make strong local/privacy claims, so “local-first” should support the exact-workspace position rather than stand alone.
- **The most promising initial audience is people whose distraction lives inside necessary apps.** Developers, researchers, writers, analysts, and designers often need Chrome, a terminal, an editor, or a document app open, so an app-level allowlist is too broad. “Stay with the exact windows and tabs you chose” is a sharper wedge than “block distracting apps.”

The highest-leverage next moves are: finish human acceptance; reduce installation friction with a signed/notarized build; prove exact-window and exact-tab behavior in a short visual demo; add pre-session reusable workspace presets without making active sessions mutable; expand to Safari; and instrument privacy-preserving activation and interruption metrics before pursuing schedules, mobile apps, or a broad habit platform.

## StayPane baseline

### Product and job to be done

**Observed.** StayPane is a macOS menu-bar application with a Chrome Manifest V3 companion. A session is a non-repeating focus interval with an immutable duration and allowlist once enforcement starts. The user can allow an entire application, one exact application window, an entire Chrome window, or one exact Chrome tab. A Chrome tab may additionally be limited to its Current Website or Exact Page. Disallowed native windows are minimized; attempts to activate them redirect focus to the last allowed target. StayPane does not quit user processes. These rules are specified in the [PRD](./PRD.md), [product context](../../docs/contexts/product/CONTEXT.md), [macOS context](../../docs/contexts/macos/CONTEXT.md), and [Chrome context](../../docs/contexts/chrome/CONTEXT.md).

**Inference.** The core job is not simply “remove distractions.” It is:

> When I must work inside apps that also contain distractions, let me commit to the exact windows, tabs, and web scope needed for one interval, while keeping the intervention understandable, reversible, and private.

That job is narrower than the dominant blocker category and more precise than OS window organization. It is most valuable when the distracting and productive activity share the same application—for example, one research tab versus the rest of Chrome, one project window versus other editor windows, or one document versus unrelated documents.

### Commitment and safety contract

**Observed.** The planned session ends at a fixed wall-clock time, including through sleep, crash, or restart. The normal Quit path is routed through the same 30-second reset sequence and final confirmation as ending early. StayPane does not claim to stop Force Quit, extension removal, permission revocation, or administrator intervention. If required Accessibility or Chrome-profile enforcement becomes unavailable, it fails open and marks the session Interrupted instead of trapping the user. Minimized windows are restored only when StayPane can do so safely. Exact-window selection requires a stable Accessibility identifier; if one is unavailable, the product refuses exact-window mode and suggests the broader app target. See the [PRD](./PRD.md), [macOS policy](../../docs/contexts/macos/CONTEXT.md), and [Chrome policy](../../docs/contexts/chrome/CONTEXT.md).

**Inference.** This is an internally coherent “safe commitment” model:

1. The user cannot casually renegotiate an active session.
2. The software creates friction around an early exit.
3. The software does not pretend to be an adversarial security boundary.
4. When its authority becomes uncertain, it releases rather than escalating.

That contract is strategically useful, but it must be explained. Users looking for maximum anti-bypass strength may reasonably prefer Cold Turkey or 1Focus. Users who fear getting locked out, losing windows, or surrendering browsing data may prefer StayPane.

### Privacy and architecture

**Observed.** StayPane has no account, analytics, telemetry, server, remote data, or background updater. Its history is capped at 100 entries and records timestamps, duration, and outcome—not target names, window titles, URLs, or domains. Diagnostics are capped, redacted, and local. The native app and Chrome extension communicate through a local, user-only Unix socket with a fixed extension identity and versioned schema. Screen Recording is not required. These constraints are documented in the [PRD](./PRD.md), [native-bridge context](../../docs/contexts/native-bridge/CONTEXT.md), and [local bridge ADR](../../docs/adr/0001-use-a-local-versioned-native-bridge.md).

**Inference.** The privacy design is stronger than merely saying “we do not sell data.” It minimizes what is collected in the first place, including locally. That matters because an exact-workspace tool can otherwise reconstruct sensitive client names, research topics, browsing patterns, or internal documents.

### Current scope and maturity

**Observed.** The current target is Apple silicon on macOS 26 or later, with Chrome v1 support. Safari, other Chromium browsers, and Firefox are roadmap items. The v1 scope excludes schedules, recurring sessions, templates, mobile/cross-device enforcement, and deep internal-content targeting in non-browser apps. Distribution is source-only: users build the native app and load the extension unpacked. See the [README](../../README.md), [installation guide](../../docs/INSTALL.md), [roadmap](../../ROADMAP.md), and [PRD](./PRD.md).

**Observed.** Tickets 01–13 are complete, while Ticket 14 is `ready-for-human` and its acceptance matrix plus a short real focus session remain unchecked. See [tickets.md](../../tickets.md).

**Inference.** Competitive analysis should therefore guide validation and packaging, not imply product-market fit. There is not yet repository evidence of completed end-to-end human acceptance, public distribution, adoption, retention, or willingness to pay.

## Customer jobs and market map

The category is easier to understand as overlapping jobs rather than a single list of “focus apps.”

| Customer job | Typical solution | Representative products | Where StayPane fits |
|---|---|---|---|
| Block known distracting apps or sites | Blocklists, schedules, locked mode | [Cold Turkey Blocker](https://getcoldturkey.com/features/), [1Focus](https://onefocusapp.com/), [Focus](https://heyfocus.com/), [Freedom](https://freedom.to/features) | Can exclude broad targets, but this is not the distinctive wedge |
| Allow only a work environment | App/site allowlists or whitelists | [Raycast Focus](https://www.raycast.com/core-features/focus), [Cold Turkey Micromanager](https://getcoldturkey.com/micromanager/features/), [FocusMe](https://docs.focusme.com/concepts/blocking-applications), [Focus Bear](https://support.focusbear.io/portal/en/kb/articles/customizing-your-block-list-in-focus-bear), [Nudge](https://nudgefocus.app/) | Direct category, with finer window/tab precision |
| Stay inside exact content within necessary apps | Tab locking, window grouping, URL scope | [OneTabFocus](https://chromewebstore.google.com/detail/onetabfocus-%E2%80%94-focus-mode/bjokjemhbfjjfkfojmdbabmoepooooif?hl=en-US), [Apple Stage Manager](https://support.apple.com/en-mide/guide/mac-help/mchl534ba392/mac) | Strongest differentiation: exact identities plus enforcement |
| Make a promise difficult to reverse | Anti-bypass locks, passwords, accountability | [Cold Turkey Blocker](https://getcoldturkey.com/features/), [1Focus](https://onefocusapp.com/prevent-bypassing/), [FocusMe](https://docs.focusme.com/concepts/accountability-partner), [Focus](https://heyfocus.com/docs/v1/features/hardcore-mode/) | Moderate commitment; explicitly not tamper-resistant |
| Reduce phone and cross-device leakage | Synced or companion blocking across desktop and mobile | [Freedom](https://freedom.to/features), [Focus Bear](https://www.focusbear.io/features), [Opal](https://www.opal.so/fr/blog/opal-now-for-your-mac), [Apple Screen Time](https://support.apple.com/guide/mac-help/what-is-screen-time-mchlfb0b5864/mac) | Not addressed in v1 |
| Lower distraction without hard blocking | Notification filters, pauses, friction prompts | [Apple Focus](https://support.apple.com/en-euro/guide/mac-help/mchl613dc43f/mac), [one sec](https://apps.apple.com/rw/app/one-sec-screen-time-focus/id1532875441?platform=mac), [ScreenZen](https://apps.apple.com/us/app/1541027222?platform=mac), [Jomo](https://apps.apple.com/gb/app/jomo-screen-time-blocker/id1609960918?platform=mac) | Adjacent, generally lighter-weight |
| Follow through through social presence | Virtual coworking/body doubling | [Focusmate](https://www.focusmate.com/) | Substitute for enforcement; possible complementary future workflow |

### Direct competitors

The closest direct products are Raycast Focus, Cold Turkey Micromanager, 1Focus, FocusMe, Focus Bear, and Nudge because they let users define an allowed work lane rather than only enumerate forbidden distractions. OneTabFocus is direct for Chrome tabs but not for the desktop as a whole.

### Adjacent competitors

Cold Turkey Blocker, Focus, Freedom, SelfControl, and Abstand mostly begin from blocklists, schedules, or broad “block the computer” rules. They compete for the same focus budget and search intent even when the interaction model differs.

### Substitutes

Apple Screen Time, Apple Focus, Stage Manager, Spaces, tab groups, full-screen mode, and virtual coworking can address part of the underlying job without installing a dedicated exact-workspace product. They matter because a user may judge “good enough” workflow organization or social accountability to be easier than enforcement.

## Comparison matrix

Prices and plans are those documented on 25 July 2026 and may vary by region, tax, promotion, or later changes.

| Product | Platform and status | Control granularity | Commitment / early exit | Privacy and account | Price / vendor traction |
|---|---|---|---|---|---|
| **StayPane** | Source-only v1 candidate; Apple silicon, macOS 26+; Chrome companion | App, exact native window, Chrome window, exact tab, Current Website, Exact Page | Immutable active selection; fixed end; 30-second reset; acknowledged system-level bypasses; fail-open on lost authority | No account, network service, telemetry, target-content history, or remote data | MIT source; no launch or traction claim; human acceptance still pending ([PRD](./PRD.md), [tickets](../../tickets.md)) |
| **Raycast Focus** | macOS and Windows; bundled Raycast feature | Block Apps & Websites or Allow Apps & Websites; reusable categories | Pause, resume, edit, complete, and short snooze are documented; sleep pauses the session | Raycast describes a local-first architecture, but accounts, cloud sync, and AI features have separate data flows | Free; feature inherits Raycast distribution; no focus-specific adoption figure found ([feature](https://www.raycast.com/core-features/focus), [manual](https://manual.raycast.com/focus), [privacy](https://www.raycast.com/privacy), [pricing](https://www.raycast.com/pricing)) |
| **Cold Turkey Micromanager** | macOS and Windows | App whitelist; nonallowed apps minimized or force-closed | Timer or until restart; vendor claims resistance to force quit, uninstall, time change, and task-manager workarounds | Settings described as local/private; no account needed for core use | Free: one allowed app and 1–24 hours; Pro adds unlimited apps/duration and breaks; numeric Pro price was not exposed in the reviewed accessible page ([features](https://getcoldturkey.com/micromanager/features/), [pricing](https://getcoldturkey.com/micromanager/pricing/), [privacy](https://getcoldturkey.com/privacy/)) |
| **1Focus** | Mac App Store; macOS | App/site/internet blocklists; Pro app and website allowlists | Active blocks cannot be cancelled; can protect against deleting the app and can block system escape routes when configured | No signup; vendor says no user-data collection, upload, or tracking | Free basic tier; Pro $1.99/month or $9.99/year with 14-day trial; vendor claims 100,000+ users and 6,000+ reviews ([product](https://onefocusapp.com/), [anti-bypass](https://onefocusapp.com/prevent-bypassing/), [privacy](https://onefocusapp.com/privacy/), [App Store](https://apps.apple.com/us/app/1focus-app-website-blocker/id969210610?mt=12)) |
| **FocusMe** | Windows, macOS, Linux, Android; browser extensions | App/site allow and block plans, whole-computer rules, process/path/window-title matching | None, password, random characters, enforced mode; accountability partner can approve changes | Optional sync/account features; current policy documents collection that can include settings, usage, analytics, and service providers | $9.95/month headline; annual and lifetime options; 14-day trial and 60-day guarantee; vendor claims 100,000+ downloads and 10,000+ users ([features](https://focusme.com/features/), [pricing](https://focusme.com/pricing/), [privacy](https://focusme.com/privacy/), [about](https://focusme.com/about-us/)) |
| **Freedom** | Mac, Windows, iOS, Android, Chromebook, Linux; unlimited devices | App/site/internet blocklists; desktop website exceptions | Locked mode; support docs currently allow one locked-session early end per seven days; uninstall protection is device-specific | Account and cloud sync for lists, sessions, and schedules; blocking is described as local and browsing history is not logged | $39.99/year ($3.33/month billed annually), 7-day trial; vendor claims 3.5 million users ([features](https://freedom.to/features), [plans](https://support.freedom.to/en/articles/13764747-what-s-included-in-free-and-premium-plans), [locked mode](https://support.freedom.to/en/articles/1802927-locked-mode), [privacy](https://freedom.to/privacy)) |
| **Focus** | Native macOS menu-bar product | App/site/internet blocklists, profiles, schedules, Pomodoro, scripts | Hardcore mode claims survival across restart and forced termination; password mode also available | Vendor says focus data remains local | Focus 2 is $49 one-time; lifetime bundle $129; 7-day trial ([product](https://heyfocus.com/), [hardcore](https://heyfocus.com/docs/v1/features/hardcore-mode/), [privacy](https://heyfocus.com/docs/help/focus-is-private/), [checkout](https://heyfocus.com/checkout/)) |
| **Focus Bear** | Mac, Windows, iOS, Android | Allow/block selected apps and sites; routines, modes, meeting detection, breaks | Strict “Grizzly” and lighter “Cuddly” modes; emergency “break glass” flow | Account and cross-device sync; policy documents cloud/service-provider processing while denying keystroke or screenshot collection | Limited free tier; Pro $9.99/month, 7-day trial; vendor claims 20,000+ users ([features](https://www.focusbear.io/features), [pricing](https://www.focusbear.io/pricing), [FAQ](https://www.focusbear.io/faqs), [privacy](https://www.focusbear.io/privacy-policy)) |
| **Opal** | iPhone and Mac; Mac app supports app and website blocking across several browsers | App/site sessions, schedules, allowlists, app groups, screen-time reports, Focus Score | Deep Focus is marketed as the stricter mode; current Mac resistance is less clear than iPhone | Account/subscription ecosystem; cross-device product, although first-party forum staff said Mac/iPhone session-data sync was not yet implemented in Dec. 2025 | Pro subscription extends from iPhone to Mac; vendor claimed 4M+ members and 60M+ hours saved at the Mac launch ([Mac launch](https://www.opal.so/fr/blog/opal-now-for-your-mac), [features](https://www.opal.so/blog/opal-supports-lady-gagas-born-this-way-foundation), [sync request](https://community.opal.so/t/sync-sessions-data-between-phone-and-mac-app/9828)) |
| **Nudge** | Announced Mac product; homepage still presents a waitlist / “almost ready” state | Allowed apps plus blocked websites; presets, history, analytics | Privacy page documents pause, resume, and early stop; Accessibility redirects focus | Local-first core, optional Mixpanel analytics, Paddle for subscriptions | Homepage says free for 2 hours/day and Plus $1.49/month billed annually; privacy text says 3 hours/day and five focus days/week, a first-party inconsistency ([product](https://nudgefocus.app/), [privacy](https://nudgefocus.app/privacy)) |
| **OneTabFocus** | Chrome extension released June 2026 | Locks one or more selected tabs into a focus group; hides other tabs and restores groups/order | User can end early; extension can be disabled like a normal browser add-on | Vendor listing says local Chrome storage, no URL/history/content reading, and no telemetry | Free with Pro at $24/year or $39 lifetime; Chrome Web Store showed 3 users and no ratings when reviewed ([Chrome Web Store](https://chromewebstore.google.com/detail/onetabfocus-%E2%80%94-focus-mode/bjokjemhbfjjfkfojmdbabmoepooooif?hl=en-US)) |
| **Cold Turkey Blocker** | macOS and Windows; mature blocker | Sites, apps, internet/device, exceptions, schedules, allowances, Pomodoro | Multiple locks; vendor documents resistance to uninstalling, disabling extensions, system-time changes, task-manager routes, and other bypasses | Statistics/settings described as local; no cloud account required for core use | Free web blocker, 7-day Pro trial, one-time Pro license; numeric price was not exposed in the reviewed accessible page; vendor claims millions of downloads ([features](https://getcoldturkey.com/features/), [pricing](https://getcoldturkey.com/pricing/), [compare](https://getcoldturkey.com/compare/), [privacy](https://getcoldturkey.com/privacy/)) |
| **SelfControl** | Free, open-source macOS app | Website, mail-server, and internet blocklists | Timer continues after restart or deleting the app | Open source; newer release notes disclose automatic error reporting | Free GPL project; long-lived project, but no first-party current user count found ([site](https://selfcontrolapp.com/), [source](https://github.com/SelfControlApp/selfcontrol/), [release notes](https://selfcontrolapp.com/releasenotes.html)) |
| **Abstand** | Early open-source macOS app; Windows/Linux planned | App, website, and whole-Mac blocks; scheduled strictness levels | Casual, balanced, and strict modes | Local SQLite/JSON; AGPLv3 source | Free/open source; v0.1.18 repository showed 8 stars and 1 fork when reviewed ([site](https://www.abstand.app/), [source](https://github.com/builder-group/abstand)) |
| **Apple Screen Time** | Built into Apple platforms | App categories, individual apps, websites, downtime, Always Allowed | Passcode/family controls; an authorized user or administrator can change or disable it | Apple Account can sync settings and usage across devices | Included with the OS; no separate traction figure needed ([overview](https://support.apple.com/guide/mac-help/what-is-screen-time-mchlfb0b5864/mac), [app limits](https://support.apple.com/en-ca/guide/mac-help/mchld1c137dd/mac), [Always Allowed](https://support.apple.com/en-ie/guide/mac-help/mchl4949e9f4/mac), [passcode](https://support.apple.com/en-ie/guide/mac-help/mchl336af525/mac)) |
| **Focusmate** | Web-based virtual coworking | Human session matching rather than device control | Partner presence, stated goals, check-in, timeliness/no-show rules | Account, video provider, and normal cloud analytics; sessions are not recorded | Free 3 sessions/week; Plus $8/month annually or $12 monthly; vendor claims 9M+ sessions and 400M+ focus minutes ([product](https://www.focusmate.com/), [getting started](https://support.focusmate.com/en/articles/9110188-getting-started), [pricing](https://www.focusmate.com/pricing/), [privacy](https://www.focusmate.com/privacy/)) |

### Capability heatmap

This table is an analyst synthesis of first-party documentation, not a hands-on bypass test. “Not found” means the capability was not documented in the reviewed materials.

| Product | App allowlist | Exact macOS window identity | Exact browser tab identity | Per-tab website/page scope | Cross-device | Strong anti-bypass claim | Local/open posture |
|---|---:|---:|---:|---:|---:|---:|---:|
| StayPane | Yes | **Yes** | **Yes** | **Yes** | No | No—deliberately bounded | **Local + MIT** |
| Raycast Focus | Yes | Not found | Not found | Not found | Desktop only | No; snooze/edit/pause documented | Local-first; broader Raycast services optional |
| Cold Turkey Micromanager | Yes | Not found | No | No | Desktop only | **Yes** | Local/private |
| 1Focus | Yes (Pro) | Not found | Not found | Site allowlist, not documented per-tab | Mac only | **Yes** | Local/no account |
| FocusMe | Yes | Window-title matching, not identity | Not found | Web rules, not documented per-tab | Desktop + Android | **Yes** | Optional cloud/account; not open |
| Focus Bear | Yes | Not found | Not found | Web rules, not documented per-tab | **Yes** | Configurable strictness | Account/cloud sync |
| Opal | Yes | Not found | Not found | Site/app rules, not documented per-tab | iPhone + Mac product; session sync gap reported by staff in Dec. 2025 | Stronger iPhone Deep Focus; Mac status less clear | Account/subscription ecosystem |
| Nudge | Yes | Not found | Not found | Domain blocking, not documented per-tab | Mac only | No; pause/stop documented | Local-first; optional analytics |
| OneTabFocus | No desktop control | No | **Yes** | Not found | Chrome only | No | Local extension storage |
| Cold Turkey Blocker | No app allowlist; separate Micromanager product | Window-title blocking documented on Windows, not macOS | Not found | URL exceptions, not documented per-tab | Desktop only | **Yes** | Local/private |
| Apple Stage Manager | App/window grouping | Groups windows, but does not enforce identity | No | No | Mac only | No | Built into macOS |

The heatmap exposes StayPane's opportunity and its risk. It leads on precision but trails on distribution, platform coverage, and lock strength. If users do not value exact identity enough to tolerate setup friction, the advantage will remain technically interesting but commercially weak.

## Most relevant competitor profiles

### 1. Raycast Focus — the distribution and commoditization threat

**Observed.** Raycast Focus lets users name a goal and duration, then either block or allow selected apps and websites. Focus Categories make configurations reusable. The feature integrates with Raycast's floating Focus Bar, menu/taskbar UI, Apple Focus Filters, Shortcuts, deep links, and an AI Focus extension. Raycast documents support for Safari, Chrome, Firefox, and related browser families without requiring a separate extension. The feature is free on macOS and Windows. Raycast also documents pause, resume, edit, complete, and a short snooze; sleep pauses the session and the timer is reconciled afterward. See [Raycast Focus](https://www.raycast.com/core-features/focus), the [Focus manual](https://manual.raycast.com/focus), [shortcut documentation](https://manual.raycast.com/focus/how-to-create-a-shortcut), [pricing](https://www.raycast.com/pricing), and [privacy](https://www.raycast.com/privacy).

**Strengths.**

- Free, broad distribution inside an existing launcher.
- Very low configuration cost through categories and command-based workflows.
- App and website allowlisting is already part of the product, so the generic StayPane story can be copied or dismissed as redundant.
- Multiple browsers without a companion extension.
- Strong native integration and an extensibility ecosystem.

**Weaknesses / gaps relative to StayPane.**

- The reviewed material does not document exact native-window identity, Chrome-window identity, exact tab identity, or per-tab Current Website/Exact Page enforcement.
- Editing, snoozing, pausing, and completing are convenience-oriented rather than an immutable commitment contract.
- Raycast's broader accounts, sync, Pro, and AI services create a more complex privacy surface than StayPane's no-network architecture, even though Raycast describes the core as local-first.

**Inference.** Raycast is the most important strategic competitor even if it is not the closest technical match. It can absorb the broad category at a zero marginal price. StayPane should never lead with “block distracting apps and websites” or “allow only work apps.” The lead must be the behavior Raycast does not document: **choose the exact windows and tabs that constitute this session, then make that choice immutable until a clearly defined end.**

### 2. Cold Turkey Micromanager — the closest mature app-allowlist benchmark

**Observed.** Micromanager allows only whitelisted apps during a timer. The free tier allows one app for one to 24 hours; Pro adds unlimited apps and duration, breaks and allowances, and import/export. Nonallowed apps can be minimized or force-closed. Sessions can run for a timer or until restart. The vendor claims that active blocks resist uninstalling, time changes, task-manager-style routes, and force quitting; release notes describe auto-restart behavior after forced termination. The product supports macOS and Windows and says settings remain private/local. See the [product page](https://getcoldturkey.com/micromanager/), [features](https://getcoldturkey.com/micromanager/features/), [pricing](https://getcoldturkey.com/micromanager/pricing/), [support](https://getcoldturkey.com/micromanager/support/), [news](https://getcoldturkey.com/micromanager/news/), and [privacy policy](https://getcoldturkey.com/privacy/).

**Strengths.**

- Simple and legible app-whitelist model.
- Stronger anti-bypass posture than StayPane.
- Mature paid packaging, cross-desktop support, and a one-time license.
- User choice between minimizing and force-closing.

**Weaknesses / gaps relative to StayPane.**

- App-level only; its own comparison material separates Micromanager's app whitelist from Cold Turkey Blocker's website features.
- The reviewed material does not document exact windows, browser tabs, or navigation scope.
- Force-closing processes is more disruptive than StayPane's minimize-and-restore approach.
- Support documentation acknowledges macOS app-listing and external-monitor limitations, and the company describes support as a small/one-person operation.

**Inference.** Micromanager validates demand for “allow only work apps,” but also demonstrates why that position is insufficient. StayPane can win when one allowed application contains both the work and the distraction. Its language should directly illustrate that case: “Chrome is necessary. Most of Chrome is not.”

### 3. 1Focus — the affordable native Mac incumbent

**Observed.** 1Focus is a Mac App Store app that blocks websites, apps, or internet access. Its Pro tier provides “block all apps except these” and website allowlist behavior. It supports Safari, Chrome, Brave, Edge, Opera, and Arc. The vendor says active blocks cannot be cancelled, the app can prevent being moved to Trash during a block, and users can configure rules against unsupported/new apps, Activity Monitor, or System Settings. It requires no signup and claims no user-data collection, upload, or tracking. Basic use is free; Pro is $1.99/month or $9.99/year with a 14-day trial. The site claims more than 100,000 users and more than 6,000 reviews. See [1Focus](https://onefocusapp.com/), [Mac blocking behavior](https://onefocusapp.com/block-mac-with-1focus/), [anti-bypass documentation](https://onefocusapp.com/prevent-bypassing/), [privacy](https://onefocusapp.com/privacy/), and the [App Store listing](https://apps.apple.com/us/app/1focus-app-website-blocker/id969210610?mt=12).

**Strengths.**

- Low price, App Store trust, and long operating history.
- Strong local/no-account privacy story.
- Broad browser coverage and both app/site allowlists.
- High commitment strength for users who explicitly want a hard lock.

**Weaknesses / gaps relative to StayPane.**

- The reviewed material does not document exact window or tab identity or a different navigation scope per allowed tab.
- The product is centered on rules for apps, sites, schedules, and internet access rather than preserving a selected workspace.
- The strict lock is a benefit for some users and a safety concern for others.

**Inference.** 1Focus is likely the hardest value comparison on macOS because it is inexpensive, native, private, and established. StayPane cannot beat it on breadth or lock strength today. It must beat it on **precision and safety semantics**.

### 4. Nudge — the emerging conceptual near-neighbor

**Observed.** Nudge presents a Mac menu-bar product in which users choose allowed apps and blocked websites. Its site describes local-first operation, focus presets, history, analytics, Accessibility-based redirection to allowed apps, and browser automation that reads the active URL in supported browsers and redirects blocked domains. It explicitly says the blocker is not network-level and will not cover every browser. The homepage still says the product is “almost ready” and asks visitors to join a waitlist. Pricing text says the free tier permits two focus hours per day and Plus costs $1.49/month billed annually, while its privacy text describes three free hours per day and five focus days per week. The privacy page also names pause, resume, stop-early events, optional Mixpanel analytics, and Paddle subscription processing. See [Nudge](https://nudgefocus.app/) and [Nudge privacy](https://nudgefocus.app/privacy).

**Strengths.**

- Very close “allowed work lane” language with an approachable menu-bar form.
- Presets and analytics reduce repeated setup and support retention.
- Low proposed price and local-first story.
- Broader current browser list than StayPane's Chrome-only v1 claim.

**Weaknesses / gaps relative to StayPane.**

- Pre-release/waitlist status and negligible public proof in the reviewed material.
- Conflicting first-party statements about free limits undermine clarity.
- The reviewed material describes app-level and domain-level rules, not exact window/tab identity or per-tab navigation scope.
- Pause and stop-early behavior imply a lighter commitment contract.

**Inference.** Nudge is evidence that another builder independently sees the allowed-app focus lane. It is not yet evidence of market traction. StayPane can establish a clearer trust position by publishing a precise behavioral contract, avoiding quota inconsistency, and demonstrating exact-target behavior. It should also assume that presets and low-friction onboarding will quickly become table stakes.

### 5. FocusMe — the breadth and accountability benchmark

**Observed.** FocusMe supports Windows, macOS, Linux, and Android. Plans can block or allow apps, sites, and the entire computer, with schedules, Pomodoro, time and launch limits, screen breaks, browser extensions, CLI/automation, and settings sync. Application matching can use process, path, or window title; macOS title matching requires Accessibility. Blocking actions include minimize, close, kill, or hide. Protection modes include no protection, password, random characters, and enforced mode. An accountability partner can approve stop, pause, or edit requests. Optional AI coaching and task features expand the product beyond blocking. The headline price is $9.95/month, with annual and lifetime options, a 14-day no-card trial, and a 60-day guarantee. FocusMe claims 100,000+ downloads, 10,000+ users, and more than ten years of operation. Its current privacy policy documents optional stored settings and usage, desktop/browser analytics, and third-party infrastructure. See [documentation](https://docs.focusme.com/introduction), [application blocking](https://docs.focusme.com/concepts/blocking-applications), [quick start](https://docs.focusme.com/quick-start), [accountability partner](https://docs.focusme.com/concepts/accountability-partner), [features](https://focusme.com/features/), [pricing](https://focusme.com/pricing/), [privacy](https://focusme.com/privacy/), and [about](https://focusme.com/about-us/).

**Strengths.**

- Exceptional breadth and platform coverage.
- Multiple levels of strictness for different motivations.
- Human accountability is stronger than software-only friction for some users.
- Automation and configuration depth suit power users and managed workflows.

**Weaknesses / gaps relative to StayPane.**

- High cognitive load compared with choosing one exact workspace.
- Window-title matching is pattern-based and may change with content; it is not the same documented contract as stable window identity.
- The cloud/account/analytics surface is materially larger.
- The wide feature set weakens the simplicity of its story.

**Inference.** FocusMe is a useful “do everything” contrast. StayPane should resist becoming a smaller FocusMe. The accountability-partner mechanism is worth studying later, but only after the exact-workspace loop is validated.

### 6. Cold Turkey Blocker — the anti-bypass benchmark

**Observed.** Cold Turkey Blocker supports website, application, internet/device blocks, exceptions, schedules, Pomodoro, allowances, rewards, and several locking mechanisms including a timer, time range, random text, delay, schedule, restart, or password. It documents protections against uninstalling, disabling required extensions, changing system time, using system monitors, and changing certain screen-time settings while locked. Statistics are described as local. The free tier is a website blocker; Pro is a one-time license with a seven-day trial. The vendor claims millions of downloads. Its comparison page clarifies that the app-whitelist function belongs to Micromanager. See [features](https://getcoldturkey.com/features/), [pricing](https://getcoldturkey.com/pricing/), [comparison](https://getcoldturkey.com/compare/), [user guide](https://getcoldturkey.com/support/user-guide/), [news](https://getcoldturkey.com/news/), and [privacy](https://getcoldturkey.com/privacy/).

**Strengths.**

- Category-leading commitment language and many lock types.
- Mature scheduling and rule system.
- Strong local/privacy positioning and one-time purchase.
- Clear separation between blocking and app-whitelist products.

**Weaknesses / gaps relative to StayPane.**

- Oriented around enumerating forbidden resources rather than selecting a preserved workspace.
- Exact browser-tab identity and per-tab navigation scope were not documented in the reviewed material.
- The strictness creates a different risk/benefit profile and may be more invasive.

**Inference.** Cold Turkey owns “hard to bypass.” StayPane should not challenge that claim without changing architecture and risk posture. It should instead make “safe, exact, and honest” a deliberate alternative.

### 7. Freedom — the cross-device benchmark

**Observed.** Freedom provides app, website, and internet blocking across Mac, Windows, iOS, Android, Chromebook, and Linux, with unlimited devices, recurring or advance schedules, ambient audio, and locked mode. The free plan offers limited start-now sessions; premium unlocks schedules and locked mode. Current pricing is $39.99/year, equivalent to $3.33/month when billed annually, with a seven-day trial. Support documentation says a locked session may currently be ended once per seven-day period and gives device-specific uninstallation-protection instructions. Freedom describes blocking as local and says it does not log browsing history, while its account/cloud system syncs authentication, blocklists, sessions, and schedules. The vendor claims 3.5 million users. See [features](https://freedom.to/features), [premium](https://freedom.to/premium?source=perks), [plan comparison](https://support.freedom.to/en/articles/13764747-what-s-included-in-free-and-premium-plans), [locked mode](https://support.freedom.to/en/articles/1802927-locked-mode), [ending a session](https://support.freedom.to/en/articles/1776713-ending-a-block-session), [uninstallation protection](https://support.freedom.to/en/articles/6116638-how-to-prevent-uninstallation-of-the-freedom-app), and [privacy](https://freedom.to/privacy).

**Strengths.**

- Cross-device reach addresses the common escape from laptop to phone.
- Mature scheduling and sync.
- Large vendor-claimed user base and clear subscription packaging.

**Weaknesses / gaps relative to StayPane.**

- Broad app/site lists rather than exact native windows or browser tabs.
- Account and cloud synchronization expand the privacy surface.
- Locked-mode behavior is more policy-heavy and less deterministic than StayPane's documented 30-second early-reset path.

**Inference.** Freedom shows why desktop-only enforcement can leak value: a user can pick up a phone. StayPane should initially target workflows where desktop precision is worth more than device coverage, then use Apple Focus/Shortcuts integration or a lightweight companion before assuming it needs a full cross-platform cloud service.

### 8. Focus Bear — the audience and behavior-design benchmark

**Observed.** Focus Bear combines app/site allow and block modes with routines, micro-breaks, meeting detection, mobile clients, and cross-device behavior. Its strict “Grizzly” and lighter “Cuddly” modes give users different levels of resistance, and an emergency “break glass” flow offers an escape path. The product explicitly positions itself for ADHD and AuDHD users. The free tier has session and list limits; Pro costs $9.99/month with a seven-day trial. The company claims more than 20,000 users. Account and cloud synchronization are part of the product, while the FAQ and privacy materials deny collection of keystrokes or screenshots. See the [product](https://www.focusbear.io/), [features](https://www.focusbear.io/features), [pricing](https://www.focusbear.io/pricing), [block-list support](https://support.focusbear.io/portal/en/kb/articles/customizing-your-block-list-in-focus-bear), [mode support](https://support.focusbear.io/portal/en/kb/articles/focus-bear-mode-options), [FAQ](https://www.focusbear.io/faqs), and [privacy](https://www.focusbear.io/privacy-policy).

**Strengths.**

- Clear audience, empathetic tone, and broader behavior-change journey.
- Cross-device blocking plus routines and recovery breaks.
- User-selectable strictness lowers the one-size-fits-all problem.

**Weaknesses / gaps relative to StayPane.**

- Much broader product with more onboarding and account state.
- Exact window identity, exact tab identity, and per-tab navigation scope were not documented in reviewed materials.
- Subscription and cloud sync are a different privacy/economic proposition.

**Inference.** The segmentation lesson is more valuable than the feature list. StayPane should test whether neurodivergent knowledge workers experience “necessary app, wrong window/tab” as an acute problem, but it should not make health or efficacy claims without research and evidence.

### 9. Opal — the high-traction consumer and gamification benchmark

**Observed.** Opal began as a mobile screen-time product and added a Mac app that blocks apps and websites. Its Mac launch announcement says an existing Pro subscription extends to Mac and claims a community of more than four million members with more than 60 million hours saved. Opal's materials describe sessions, schedules, app groups/allowlists, Deep Focus, Focus Reports, Focus Score, and historical insights. Official community staff have documented browser support in the Mac app for Chrome, Safari, Arc, Opera, Edge, and Brave, while also acknowledging that the newer Mac app has not yet reached mobile feature parity. A December 2025 staff response treated syncing session data between phone and Mac as a feature request rather than current behavior. See the [Mac launch](https://www.opal.so/fr/blog/opal-now-for-your-mac), [Focus features](https://www.opal.so/blog/opal-supports-lady-gagas-born-this-way-foundation), [Mac browser-support thread](https://community.opal.so/t/mac-app-browser-support-firefox-dia/264?page=2), [feature-parity help](https://www.opal.so/help/how-do-i-use-opals-assist-feature), and [sync request](https://community.opal.so/t/sync-sessions-data-between-phone-and-mac-app/9828).

**Strengths.**

- Very high vendor-claimed consumer reach and an established mobile brand.
- Polished behavior-change layer: Focus Score, reports, comparisons, app groups, schedules, and stricter sessions.
- iPhone-to-Mac subscription extension lowers purchase friction for existing users.
- Much broader documented Mac browser coverage than StayPane v1.

**Weaknesses / gaps relative to StayPane.**

- The reviewed material does not document exact native-window identity, exact browser-tab identity, or a Current Website/Exact Page promise per tab.
- Feature parity and session/data sync between Mac and iPhone were still incomplete in first-party support material.
- Gamification and behavioral history are a broader, more data-rich proposition than StayPane's minimal local history.
- Opal's own community contains repeated user reports that Mac sessions could be bypassed with Force Quit, logout, or Activity Monitor. These are **user-reported observations on an Opal-hosted forum, not a verified current product behavior or independent test**. Opal staff acknowledged in the same thread that the Mac app was not yet as robust as the phone version. See the [Mac improvement thread](https://community.opal.so/t/mac-app-suggestions-for-improvement/3563?page=2).

**Inference.** Opal shows the reach available when focus is packaged as an ongoing consumer habit system rather than a desktop utility. It also reinforces the value of StayPane's explicit boundary: if macOS always retains system-level escape hatches, a product should state that honestly instead of allowing “Deep Focus” language to imply more than the implementation can guarantee. StayPane should learn from Opal's reporting and onboarding, but it should not copy gamification until users show that scores improve retention without compromising its minimal-data philosophy.

### 10. OneTabFocus — the closest browser-specific idea

**Observed.** OneTabFocus is a Chrome extension released in June 2026. It lets users lock one or more selected tabs into a native Chrome tab group, collapses other tabs into a hidden group, returns the user when they switch away, offers a Pomodoro timer, and restores tab groups and ordering after the session. The listing says it stores data locally in Chrome, does not read URL/history/page content, and has no telemetry. The user can end early. The Chrome Web Store displayed three users and no ratings at review time. Pro is listed at $24/year or $39 lifetime. See the [Chrome Web Store listing](https://chromewebstore.google.com/detail/onetabfocus-%E2%80%94-focus-mode/bjokjemhbfjjfkfojmdbabmoepooooif?hl=en-US).

**Strengths.**

- Extremely low installation and comprehension cost.
- Native tab groups preserve user context.
- Strong privacy claim and no desktop permissions.

**Weaknesses / gaps relative to StayPane.**

- Browser-only and easily disabled like an ordinary extension.
- No native app/window enforcement, fixed-end recovery, or desktop restoration.
- The reviewed listing does not document Current Website or Exact Page navigation constraints.
- Traction is effectively unproven.

**Inference.** OneTabFocus validates the intuitive appeal of “these tabs, not Chrome as a whole.” StayPane should demonstrate why the native companion matters: it can coordinate exact tab choice with the rest of the desktop and can distinguish different URL-scope promises.

### 11. Focusmate — the accountability substitute

**Observed.** Focusmate matches users for 25-, 50-, or 75-minute virtual coworking sessions. Partners join by video, state goals, work mostly quietly, and check in at the end. Lateness and no-shows affect timeliness, and accounts can be frozen for repeated problems. Focusmate says sessions are not recorded and uses a video provider. The free tier permits three sessions per week; Plus costs $8/month billed annually or $12 monthly. The company claims more than nine million sessions, more than 400 million focus minutes, and users in more than 150 countries. See [Focusmate](https://www.focusmate.com/), [getting started](https://support.focusmate.com/en/articles/9110188-getting-started), [FAQ](https://www.focusmate.com/faq/), [pricing](https://www.focusmate.com/pricing/), [business](https://www.focusmate.com/business/), and [privacy](https://www.focusmate.com/privacy/).

**Strengths.**

- Solves motivation and follow-through without invasive device control.
- Social presence is difficult for a software lock to imitate.
- Simple session ritual and substantial vendor-claimed usage.

**Weaknesses / gaps relative to StayPane.**

- Does not stop device switching or wrong-window/tab behavior.
- Requires scheduling, camera presence, another person, and an account.
- Privacy and social comfort differ fundamentally from a local tool.

**Inference.** Focusmate is a substitute and a possible complement. A future “Start StayPane when my Focusmate session begins” workflow could combine exact environment control with human accountability, but partnership work is premature before the standalone loop is validated.

## Secondary competitors and substitutes

### Focus

Focus is a polished Mac menu-bar blocker with apps, websites, internet rules, profiles, timers, Pomodoro, schedules, breaks, statistics, scripts, and hotkeys. Apps may be hidden or quit, and the vendor's Hardcore mode claims resistance to restart and forced termination. Pricing is a one-time $49 for Focus 2 or $129 for a lifetime bundle; the vendor says focus data remains local. Exact window/tab identity was not documented in reviewed material. Its strongest lesson is the value of native workflow integration and a one-time local-software business model. See [Focus](https://heyfocus.com/), [application blocking](https://heyfocus.com/docs/v1/getting-started/blocking-applications/), [Hardcore mode](https://heyfocus.com/docs/v1/features/hardcore-mode/), [scripting](https://heyfocus.com/docs/features/scripting/), [checkout](https://heyfocus.com/checkout/), and [privacy](https://heyfocus.com/docs/help/focus-is-private/).

### SelfControl

SelfControl is a free, GPL-licensed Mac tool that blocks websites, mail servers, or the internet for a timer that continues after restart or app deletion. It is a durable benchmark for strict, narrow, open-source utility, but it does not address apps, windows, or tab identity. Recent release notes disclose automatic error reporting, so even open-source privacy claims require precise version-specific language. See [SelfControl](https://selfcontrolapp.com/), its [source repository](https://github.com/SelfControlApp/selfcontrol/), and [release notes](https://selfcontrolapp.com/releasenotes.html).

### Abstand

Abstand is an early AGPLv3 Mac blocker with app, website, whole-Mac, schedule, and strictness options; Windows and Linux are planned. Its site and source emphasize local data through SQLite/JSON, and the repository was at v0.1.18 with eight stars and one fork when reviewed. It shows that local/open blocking is accessible to new entrants, but it does not document StayPane's exact identity and restoration model. See [Abstand](https://www.abstand.app/) and [GitHub](https://github.com/builder-group/abstand).

### Apple Screen Time, Focus, and Stage Manager

Screen Time provides usage reporting, App Limits, Downtime, website controls, Always Allowed, cross-device Apple Account settings, and passcode/family controls. An authorized user can change or disable the configuration. Apple Focus silences or allows notifications and can apply app-specific filters; it does not document restricting which windows, apps, or web pages may be used. Stage Manager keeps the current app or app group centered and arranges recent apps at the side, but users can freely switch groups. These are “good enough” substitutes for users who need awareness, quieter notifications, or workspace organization rather than commitment enforcement. See Apple's [Screen Time overview](https://support.apple.com/guide/mac-help/what-is-screen-time-mchlfb0b5864/mac), [App Limits](https://support.apple.com/en-ca/guide/mac-help/mchld1c137dd/mac), [Always Allowed](https://support.apple.com/en-ie/guide/mac-help/mchl4949e9f4/mac), [passcode controls](https://support.apple.com/en-ie/guide/mac-help/mchl336af525/mac), [turn-off instructions](https://support.apple.com/en-ca/guide/mac-help/mchl7a0a2743/mac), [Apple Focus](https://support.apple.com/en-euro/guide/mac-help/mchl613dc43f/mac), and [Stage Manager](https://support.apple.com/en-mide/guide/mac-help/mchl534ba392/mac).

### Mobile-first friction tools

one sec, ScreenZen, and Jomo compete for the broad “use distracting apps less” job through pauses, limits, interventions, or schedules, with mobile usage central to their value. They are less direct for exact desktop workspaces, but they raise the expectation that focus support should cover the phone and be behaviorally gentle rather than purely punitive. See the official App Store listings for [one sec](https://apps.apple.com/rw/app/one-sec-screen-time-focus/id1532875441?platform=mac), [ScreenZen](https://apps.apple.com/us/app/1541027222?platform=mac), and [Jomo](https://apps.apple.com/gb/app/jomo-screen-time-blocker/id1609960918?platform=mac).

## Positioning gaps and opportunities

### 1. Own “exact workspace,” not “app blocker”

**Observed gap.** Direct competitors document application or website allowlists, and OneTabFocus documents selected tabs. None of the reviewed material documents StayPane's full combination of exact native windows, exact browser-window/tab identities, Current Website/Exact Page scope, immutable active selection, and coordinated desktop restoration.

**Recommended position.**

> **Stay with the exact windows and tabs you chose.**
>
> StayPane turns the workspace you selected into a commitment for one focus interval—locally, without reading or uploading your work.

Supporting proof should use scenarios, not adjectives:

- Allow one project window in an editor, not every project open in the same app.
- Allow the selected Chrome tab, not every Chrome tab.
- Let a research tab move within its current website while another tab remains pinned to one exact page.
- If permissions disappear, end safely as Interrupted rather than pretending enforcement still works.

### 2. Name the category problem: “necessary apps contain distractions”

Traditional blocker copy starts with known bad destinations. StayPane is strongest when the user cannot block the whole app:

- Chrome contains the research and the distraction.
- A code editor contains the current client project and unrelated projects.
- A document application contains the deliverable and personal notes.
- A terminal contains the active task and everything else the machine can do.

This problem statement differentiates the product before the feature list begins.

### 3. Make bounded enforcement a trust feature

StayPane should publish an explicit three-level promise:

1. **Casual redirection:** disallowed windows are minimized and focus returns to the allowed workspace.
2. **Commitment friction:** active targets cannot be edited; early reset requires a wait and confirmation.
3. **Not a security boundary:** Force Quit, extension removal, revoked permissions, and administrator actions can bypass it.

That is weaker than Cold Turkey's strictness but more credible than an absolute “unbreakable” claim. The phrase “hard to bypass” should be avoided unless later hands-on adversarial tests support it.

### 4. Privacy should be concrete and content-minimizing

“Local-first” is common. StayPane's sharper proof is:

- No account or service.
- No telemetry.
- No stored window titles, URLs, domains, or target names in history.
- No Screen Recording.
- Local user-only native bridge.
- Open source.

The product should explain that it processes enough current target identity to enforce a session but deliberately avoids turning that into a behavioral archive.

### 5. Installation is currently inconsistent with the trust promise

A user who values exact, safe behavior is asked to build a Swift app, approve Accessibility, and load an unpacked browser extension. That is a high-trust request wrapped in a high-friction and unfamiliar installation flow. Competitors provide App Store or signed installers.

The first packaging goal should be a reproducible, signed, notarized build with clear permission explanations and a visible diagnostic check. Source availability should remain the audit path, not the only installation path.

### 6. Presets can preserve immutability

Raycast Categories, Nudge presets, Focus profiles, FocusMe plans, and Cold Turkey blocks all reduce repeat configuration. StayPane's v1 excludes templates, but repeated target selection may damage retention.

A compatible design is **pre-session workspace presets**:

- A preset only pre-fills targets and duration.
- The user reviews current identities before starting.
- Once the session begins, the resolved target set remains immutable.
- If an exact saved identity no longer exists, setup shows it as unresolved instead of silently broadening.

This keeps the commitment contract intact while reducing recurring setup cost.

## SWOT and risk analysis

### Strengths

- Exact macOS window and Chrome tab identity, not just app/process/title patterns.
- Per-tab Current Website and Exact Page scope.
- Coherent immutable-session and fixed-end model.
- Safe fail-open behavior and explicit Interrupted outcome.
- Minimize/refocus/restoration model rather than process termination.
- Strong content-minimizing, local, open-source architecture.
- Honest limits around Force Quit and permission loss.

### Weaknesses

- Source-only v1 candidate awaiting human acceptance; no launch, adoption, retention, or payment evidence.
- Apple silicon macOS 26+ and Chrome-only v1 sharply constrain reach.
- Accessibility and unpacked-extension onboarding add trust and support burdens.
- Weak tamper resistance compared with strict blockers.
- No schedules, presets, repeat flows, mobile coverage, cloud sync, partner accountability, or team administration.
- Exact-window support depends on stable Accessibility identifiers that some apps may not expose.
- Required Chrome bridge/profile state can fail, and fail-open safety means a session can be Interrupted.

### Opportunities

- Establish “exact workspace commitment” as a distinct subcategory before broader incumbents add window/tab identity.
- Serve developers, researchers, writers, analysts, and privacy-sensitive professionals whose productive and distracting contexts coexist inside one app.
- Use a short technical demo to make an otherwise abstract precision advantage obvious.
- Offer a signed/notarized convenience build while keeping source and local operation available.
- Expand first to Safari to match a core Mac audience, then selected Chromium browsers.
- Pair with Apple Focus or Shortcuts so desktop workspace commitment also quiets notifications.
- Later test an optional accountability key or partner approval without making accounts mandatory.

### Threats

- Raycast can extend its free feature toward finer target selection and distribute instantly.
- Nudge and OneTabFocus show low-barrier entry into allowed-workspace and selected-tab messaging.
- Established blockers have years of trust, support content, app-store reviews, and anti-bypass engineering.
- Apple can improve Stage Manager, Screen Time, Focus, or browser APIs and make part of the workflow native.
- macOS Accessibility or Chrome extension changes can break identity/enforcement assumptions.
- Users may value cross-device coverage, schedules, or simplicity more than exactness.
- Local/open source is not unique because SelfControl, Abstand, and other entrants can make similar claims.
- A safety bug that leaves windows minimized or blocks the wrong target would damage trust disproportionately.

### Risk register

| Risk | Why it matters | Early evidence to collect | Mitigation |
|---|---|---|---|
| Exactness is technically impressive but not valuable enough | Users may choose a simpler free allowlist | Interviews and usability tests using “necessary app, wrong context” scenarios; compare against Raycast | Narrow positioning; show live before/after behavior |
| Setup cost overwhelms value | Source build, permissions, and target selection create abandonment | Permission-to-first-session completion; time to first valid session; setup failure reasons | Signed build, guided checks, presets, clearer target preview |
| Users expect tamper resistance | “Lock” language may imply security guarantees | Comprehension test after reading onboarding; support questions | Use “commitment” and publish bypass boundaries prominently |
| Exact-window identity is inconsistent across apps | Accessibility identifiers may be absent or unstable | Compatibility matrix by app/version; unresolved-target frequency | Refuse unsafe precision, document broad fallback, prioritize high-value compatible apps |
| Chrome-only scope misses the Mac market | Safari is a default and privacy-aligned browser | Browser mix among target interviewees | Make Safari the first browser expansion after v1 acceptance |
| Fail-open interruptions feel unreliable | Safety behavior may be interpreted as product failure | Interrupted rate and reason, restore success, bridge recovery outcomes | Proactive diagnostics, precise explanations, recovery tests |
| Privacy promise is weakened by future analytics | Product learning can pressure collection | Decide metrics before adding telemetry | Keep metrics opt-in, aggregate, and target-content-free; publish schema |
| Feature creep erases the wedge | Schedules, habits, AI, teams, and mobile can dilute product | Roadmap review against core JTBD | Require every feature to strengthen exact-workspace activation, completion, or trust |

## Recommendations

### Priority 0 — finish the current release claim

1. **Complete Ticket 14 human acceptance before public launch language.** Run the full manual matrix and one short real session from the public instructions. Record failures and repeat after fixes. Until then, use “source-only v1 candidate,” not “released,” “production-ready,” or “proven.” The current status is visible in [tickets.md](../../tickets.md).
2. **Test the trust boundaries, not only the happy path.** Include sleep, crash/restart, Chrome disconnect, extension removal, Accessibility loss, exact-window close/reopen, multiple displays/Spaces, early reset, Quit, and restoration.
3. **Create a compatibility ledger.** List tested apps, whether they expose stable exact-window identifiers, and whether broad app targeting is the only safe option.

### Priority 1 — make the wedge understandable and installable

1. **Rewrite public positioning around exact workspace commitment.** The first comparison should be against an app allowlist: “Raycast/1Focus can allow Chrome; StayPane can allow this Chrome tab and keep it on this site/page.”
2. **Publish a 45–60 second visual proof.** Demonstrate:
   - two windows in the same app;
   - two tabs in the same Chrome window;
   - a Current Website tab versus an Exact Page tab;
   - early-reset countdown;
   - safe Interrupted behavior when authority disappears.
3. **Ship a signed and notarized build.** Keep source builds documented, but remove compilation as the default first-run experience.
4. **Make permission onboarding diagnostic.** Explain why Accessibility is needed, why Screen Recording is not, what the Chrome bridge does, and how the product behaves when permission is lost.
5. **Add pre-session presets or Recent Workspaces.** Resolve and confirm identities at start; never silently broaden; remain immutable in-session.

### Priority 2 — broaden within the Mac exact-workspace thesis

1. **Add Safari next.** This aligns with the Mac-native and privacy-sensitive audience and closes a prominent browser gap.
2. **Then support selected Chromium browsers.** Use evidence from interview browser mix rather than attempting every browser family at once.
3. **Integrate Apple Focus and Shortcuts.** Raycast demonstrates the value of native workflow entry points. A StayPane session could optionally activate an Apple Focus mode and expose start/status/reset actions without creating cloud state.
4. **Offer configurable commitment tiers only if research asks for them.** For example:
   - Standard: current 30-second reset.
   - Strong: longer reset plus typed confirmation.
   - Partner key: optional approval held by another person.

Any stronger tier must retain an emergency safety path and clearly state what system-level bypasses remain.

### Priority 3 — decide packaging and business model after activation proof

The current source-only local architecture fits a one-time utility better than an immediate subscription. A plausible model is:

- Free MIT source and self-build path.
- Paid signed/notarized convenience download with updates and support.
- Optional supporter/lifetime tier.
- Subscription only if recurring services such as cross-device sync, team administration, or hosted accountability are later validated.

This is an inference, not a pricing study. Competitor anchors range from free Raycast/SelfControl/Abstand, to 1Focus at $9.99/year, to Focus at $49 one-time, to Freedom at $39.99/year, to FocusMe/Focus Bear near $10/month. StayPane should not price until users demonstrate that exactness changes behavior enough to justify installation.

### Product metrics that preserve the privacy model

Before adding any analytics, decide what can be learned without target content. Useful measures include:

- Installation-to-permission-check completion.
- Permission-check-to-first-session conversion.
- Time to configure and start the first session.
- Sessions completed, reset early, or Interrupted.
- Early-reset countdowns started versus cancelled.
- Interruption class: Accessibility, native bridge, Chrome profile, extension, recovery, or unknown.
- Restoration success/failure.
- Preset resolution success/failure.
- Return for a second session within a chosen local interval.

Do not collect target names, titles, URLs, domains, page content, keystrokes, or screenshots. A local-only dashboard can answer early usability questions; if opt-in telemetry is later introduced, publish its exact event schema and retention policy.

### Research program before major expansion

Conduct 12–20 problem interviews across developers, writers, researchers, analysts, designers, students, and self-identified ADHD/AuDHD knowledge workers. Recruit people who already use a blocker or manual window/tab ritual. Ask for concrete recent episodes:

- Which necessary app contained the distraction?
- Was the problem another app, another window, another tab, or navigation inside the same tab?
- What did they try?
- Why did it fail?
- How much setup would they tolerate for a 25-, 50-, or 90-minute session?
- Do they want a safe escape, a hard lock, or another person to hold the key?
- Is phone leakage more common than wrong-desktop-context leakage?

Then run concept tests with three messages:

1. Generic app/site allowlist.
2. Exact-window and exact-tab commitment.
3. Private/local safe commitment with transparent bypass limits.

The second or third must materially outperform the generic version for the product to have a defendable wedge.

## Recommended competitive narrative

### One-sentence position

**StayPane is a private Mac focus tool that commits you to the exact windows and browser tabs you chose—not merely the apps that contain them.**

### What to compare

| Instead of saying | Say |
|---|---|
| “A distraction blocker for Mac” | “A commitment layer for the exact workspace you selected” |
| “Allow apps and websites” | “Allow this editor window and these Chrome tabs” |
| “Unbreakable focus” | “Immutable in-session choices with a transparent early-reset path” |
| “Privacy-first” | “No account, telemetry, Screen Recording, target titles, or URL history” |
| “Blocks Chrome” | “Chrome remains available, but only the selected tabs and navigation scope do” |
| “Better than every blocker” | “Designed for the case app-level blockers cannot solve: the work and distraction are in the same app” |

### Who should not choose it

Clear disqualification builds trust:

- Someone who needs a tamper-resistant or administrator-enforced security control.
- Someone whose main distraction is their phone.
- Someone who needs Windows, Linux, Android, or iOS coverage.
- Someone who wants recurring schedules and automatic daily routines.
- Someone whose required apps do not expose stable Accessibility window identifiers.
- Someone unwilling to grant Accessibility or install the browser companion.

## Limitations

- This is desk research as of 25 July 2026, based only on first-party materials. Vendor feature, privacy, adoption, rating, and bypass claims were not independently verified.
- No competitor was installed or subjected to hands-on bypass, recovery, performance, accessibility, or restoration testing. “Stronger anti-bypass” refers to documented vendor posture.
- Absence of a capability from reviewed documentation is not proof that no implementation exists. The report uses “not documented” language accordingly.
- Prices may be regional, tax-exclusive, promotional, or dynamically rendered. The accessible Cold Turkey pages did not expose a reliable numeric Pro price, so no number is invented.
- Nudge's homepage and privacy text conflict on free limits, and its site still presents a pre-release waitlist state. OneTabFocus and Abstand are very early products with minimal public traction.
- StayPane repository documents are in active development. The full manual acceptance gate and short real-session check are still pending, so the product is treated as a source-only v1 candidate awaiting human acceptance.
- The analysis does not establish market size, revenue, search volume, retention, customer satisfaction, or willingness to pay. Those require customer interviews, product telemetry consistent with the privacy model, commercial datasets, or independent review research outside this first-party-only scope.
- Medical or productivity efficacy is not evaluated. Audience positioning around ADHD/AuDHD is a segmentation observation, not evidence of treatment or health benefit.

## Bottom line

StayPane has a real but narrow strategic opening. The opening is **not** “focus software for Mac,” “app and website blocking,” “allow only work apps,” or even “private focus.” Those are crowded and, in Raycast's case, increasingly free.

The opening is the precise commitment object:

> **this window, this tab, this website or page, for this interval**

If users with necessary-but-distracting apps immediately recognize that problem, StayPane can occupy a distinct exact-workspace category with unusually clear safety and privacy semantics. If they do not, breadth competitors will win on easier installation, more platforms, more schedules, stronger locks, or lower effective price. The next phase should therefore prove the problem and remove distribution friction—not accumulate generic blocker features.
