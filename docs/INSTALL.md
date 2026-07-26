# Install StayPane from source

StayPane v1 is distributed as source code under the MIT License. It is an unsigned source distribution: the project does not provide a Developer ID-signed or notarized public binary, a Mac App Store package, or a Chrome Web Store listing. Building and using it locally requires no paid Apple or Google developer account.

## Supported environment

- An Apple silicon Mac running macOS 26 or newer.
- Xcode 26 Command Line Tools, or full Xcode 26 or newer with its macOS SDK.
- Git, Make, and the `codesign` command supplied by Xcode.
- Node.js 20 or newer with npm.
- Google Chrome 120 or newer only when Browser Window Targets or Tab Targets are needed.

Confirm the active tools before building:

```sh
xcode-select -p
swift --version
node --version
npm --version
git --version
```

If multiple full Xcode versions are installed, select Xcode 26 before continuing. Full Xcode is optional for the documented Make workflow; the Xcode 26 Command Line Tools are sufficient. StayPane's supported release environment is Apple silicon on macOS 26 or newer even if some package targets happen to compile elsewhere.

## Fresh-clone verification and installation

Copy the repository's HTTPS or SSH URL from GitHub, then run:

```sh
git clone <repository-url> StayPane
cd StayPane
make verify
make install
```

`make verify` installs the locked extension development dependencies, runs the Swift, Native Bridge, extension, privacy, release-contract, and hermetic installer checks, builds the release products, packages `.build/StayPane.app`, and audits that package. Its console output is intentionally summarized and redacted; detailed temporary logs are printed in redacted form only when a step fails.

`make install` refuses to continue while any StayPane copy is running, builds and verifies the complete bundle, stages it beside the destination, safely replaces an earlier installation, registers the installed Native Bridge, and opens `~/Applications/StayPane.app`. A failed replacement restores the previous installed copy. Preferences, Session History, and Recovery data live outside the bundle and are not removed during updates.

The installed app appears in the user Applications folder, Launchpad, Spotlight, Command-Tab, and the Dock. It keeps its menu-bar item at the same time. Closing the Status Panel does not quit StayPane; click the Dock icon or menu-bar item to reveal it again. Use Command-Q, the application menu, or the Dock's Quit command for the existing controlled Session exit.

The bundle is ad-hoc signed. Ad-hoc signing lets macOS load a locally built bundle; it is not Apple Developer ID signing or notarization. Depending on local security policy, macOS may require an explicit **Open** action or approval under **System Settings → Privacy & Security**. Do not disable Gatekeeper globally.

To inspect or compile the Swift package in Xcode, open `Package.swift` with Xcode 26 and build the `StayPane` scheme. Contributors can use `make run` for the temporary development app at `.build/StayPane.app`. Use `make app` for the complete development bundle because it also packages `StayPaneBridge`, the built Chrome companion, application icon, `Info.plist`, and the local ad-hoc signature.

## Accessibility and First-Run Onboarding

Open StayPane from Applications and follow First-Run Onboarding. StayPane explains why Accessibility is required and opens **System Settings → Privacy & Security → Accessibility**. Enable `~/Applications/StayPane.app`, return to StayPane, and run the Harmless Window-Control Verification. StayPane does not need or request Screen Recording.

If Accessibility previously contained the development copy from `.build`, remove that obsolete entry and add the installed app. macOS does not let StayPane grant or migrate this permission itself. Because source updates remain ad-hoc signed, macOS may occasionally require authorization again after a rebuild.

Accessibility lets StayPane discover, minimize, restore, and refocus windows. The permission is powerful, but StayPane remains an honest self-control tool rather than a tamper-proof security boundary. Force Quit, source modification, uninstalling, administrator actions, revoking Accessibility, or disabling the Chrome companion remain deliberate bypasses. When complete enforcement becomes unreliable, StayPane uses Fail Open and restores what it can.

Session state, minimal Session History, redacted Diagnostics, Native Bridge messages, and Chrome observations are local-only. StayPane has no account, cloud service, remote policy, analytics, telemetry, automatic crash upload, background update check, or automatic diagnostic submission.

## Install Chrome Integration

Chrome setup is optional for native Application Targets and Window Targets. `make install` registers the installed Native Bridge automatically. Run this command only if the app reports that the registration needs repair:

```sh
make setup-chrome
```

The command requires an installed copy and rewrites the user-level Native Host Registration to `~/Applications/StayPane.app/Contents/MacOS/StayPaneBridge` for the fixed unpacked extension identity. It requires no paid Apple or Google developer account. Contributors testing `.build` explicitly use `make setup-chrome-dev`.

Then load the companion:

1. Open `chrome://extensions` in each Chrome Profile that will provide browser Targets.
2. Enable **Developer mode**.
3. Choose **Load unpacked** and select `~/Applications/StayPane.app/Contents/Resources/ChromeExtension`.
4. Open **StayPane Chrome Companion → Details** and enable **Allow in Incognito**. Incognito tabs remain unselectable; this capability lets StayPane minimize Incognito windows during precise browser enforcement.
5. Keep StayPane running. Repeat the preceding steps for every Chrome Profile represented in a Session Allowlist.

### Verify the Bridge Connection

Open **Setup & Help** in StayPane and choose **Test Connection**. Each configured Chrome Profile moves from Synchronizing to Ready after its first current Tab Snapshot. A missing companion, unsupported Incognito capability, identity mismatch, or failed Native Bridge remains visible and prevents affected Browser Window Targets or Tab Targets from passing preflight.

The registered manifest is stored at:

```text
~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.staypane.native_bridge.json
```

It permits only extension ID `hoofhoedlagpoclhkgnkmejaihaapoke` and points to the packaged `StayPaneBridge` executable.

If the manifest points to an earlier `.build/StayPane.app`, StayPane reports that the Native Host Registration needs repair and offers **Repair Native Host**. Users migrating from the development bundle must also remove the old unpacked extension once and load it from the installed path. Future source updates keep that path stable and require only Chrome's **Reload** action.

### Remove Chrome Integration

1. Open `chrome://extensions` in every configured Chrome Profile and choose **Remove** for StayPane Chrome Companion.
2. Remove the user-level Native Host Registration:

   ```sh
   rm "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.staypane.native_bridge.json"
   ```

3. Quit StayPane, open `~/Applications` in Finder, and move StayPane to the Trash. Removing the application does not remove local Session History automatically.

Native Application Target and Window Target Sessions remain usable without Chrome Integration.

### Optional local-data removal

Local data is deliberately preserved when StayPane is reinstalled or removed. Only after StayPane is fully quit, no Session or Restoration is active, and you have backed up anything you want to keep, you may remove it manually:

```sh
rm -rf "$HOME/Library/Application Support/StayPane"
defaults delete org.staypane.app
```

This is irreversible: it deletes local Recovery data, Session History, settings, onboarding progress, and floating-timer preferences. It is not required for ordinary uninstalling or updating.

## Update StayPane

StayPane never downloads or installs updates automatically. Review the upstream changes, then update explicitly:

```sh
git pull --ff-only
make verify
make install
```

Quit StayPane before `make install`; installation never force-quits an active Session. Open `chrome://extensions` and choose **Reload** for StayPane Chrome Companion in every configured Chrome Profile. Reloading is required because Chrome keeps the previously loaded extension files until told to refresh them.

## Short release smoke Session

After the build and Accessibility setup, complete the short real Session described in [`manual-testing/v1-release-matrix.md`](manual-testing/v1-release-matrix.md). It verifies that the public instructions alone are enough to configure one Target, complete enforcement, restore the workspace, and observe notification-independent completion feedback.

## Unsupported Environments

StayPane v1 does not officially support Intel Macs; macOS versions earlier than 26; Safari, Firefox, Edge, Brave, Arc, or other browsers; Incognito Tab Targets; signed or notarized binary distribution; the Mac App Store; the Chrome Web Store; automatic Focus control; cloud sync; enterprise policy; parental control; or tamper-proof enforcement. Contributions that reduce needless compatibility restrictions are welcome, but they must not be presented as supported v1 behavior without the corresponding acceptance work.
