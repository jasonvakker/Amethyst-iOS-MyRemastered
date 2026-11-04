# Controlify on Air 5.1.0 / Minecraft 1.21.1

Base: `d1a50521bf537763deadb45f11cfc674ca1e25fe`, from
`feature/neoforge-lwjgl-5.1.0`. Implementation branch:
`feature/controlify-1.21.1-passthrough`.

## Setting and recovery

Open the game profile's settings → **Advanced Settings → Controller Mode**:

- **Air Native Controls** (default): existing Air button/key mappings, stick-to-WASD and mouse translation.
- **Controller Mod Passthrough (Controlify)**: standard analog gamepad input delivered to the mod through GLFW; Air's controller translation is detached.

The floating game-menu button → **Controller Mode** changes the same profile setting
while the game is running. Touch controls, keyboard access and the floating menu stay
available. Select Air Native Controls there to recover immediately. The setting is
stored as `controllerMode: native|controlify` in the existing profile; absent/unknown
values behave as native. The selector saves only this field; inherited renderer,
JVM and memory values are not materialized or rewritten. There is no data migration
or modpack editing.

Only Minecraft **1.21.1**, NeoForge **21.1.238**, and Controlify **2.5.2 / 3.0.1 LTS**
are the intended and inspected combination. The installed Controlify version on the
physical iPad was not available for inspection. Confirm its version in the game log;
other releases, particularly SDL-only releases for 26.3+, are not covered.
Controlify 2.4.4 was also inspected: it has the GLFW fallback but **does not implement
this SDL-path override**. Automatic backend selection for that older release is not
established; its existing environment may still select GLFW naturally. The loader
probe rejects it explicitly. Do not treat a successful toggle alone as proof that
an unsupported mod version received input.

## Root cause and pipeline audit

At the base commit, `JavaApp/src/lwjgl/org/lwjgl/glfw/GLFW.java` unconditionally
reported joystick 0 present and mapped, returned `Unknown` as its gamepad name and
`aio0` as its GUID, supplied empty heap buffers, and always failed gamepad-state
reads. This reproduces a phantom even in a fresh process with no controller and
explains why quitting/relaunching Air did not remove it. No persisted registration
or accelerometer is needed to produce this result. Physical-device log evidence is
still needed to establish every backend previously selected on the user's iPad.

The independent native path was:

1. `SurfaceViewController` observes GameController connect/disconnect and attaches
   `ControllerInput` blocks to the extended gamepad. It also enables Air's virtual
   mouse and optionally hides touch controls on connect.
2. Native button blocks select the active game/menu key map from the profile's
   `defaultGamepadCtrl`; left-stick blocks inject discrete WASD through
   `CallbackBridge_nativeSendKey`; right/menu sticks update shared mouse state.
3. A display-link tick calls `ControllerInput.tick`, which injects mouse movement
   through `SurfaceViewController.sendTouchPoint`. `input_bridge_v3.m` queues the
   keyboard/mouse events for the Java GLFW callback/event pump.
4. None of these mappings populated GLFW's joystick state. Disabling them alone
   could not supply analog input to Controlify.

Inspected hypotheses:

| Hypothesis | Finding |
| --- | --- |
| Fake GLFW joystick | Confirmed deterministic source defect; removed. |
| SDL accelerometer joystick | Real SDL/iOS concern, but not necessary to explain GLFW's hardcoded `Unknown`. Hint now set before JVM/mod SDL initialization. No sensor is exposed by the new bridge. |
| Stale device registration | No physical registry existed in the GLFW stub. New registry clears on disconnect, mode change and surface cleanup; generation counters handle slot reuse. |
| Incorrect SDL initialization | Independent risk: 1.21.1 Controlify uses its own JNA SDL loader, not MC 26.3's SDL3Bridge. Avoided by selecting its existing GLFW fallback before SDL initialization. |

## Implemented analog path and backend selection

`GCController.extendedGamepad` → main-thread `NativeGamepadBridge.refresh` → locked,
64-byte-per-device snapshots → JNI `GamepadBridge.nativeSnapshot` → GLFW joystick /
gamepad APIs → Controlify's `GLFWControllerManager` / `GLFWGamepadDriver`.

The snapshot preserves four stick floats and both trigger floats. Apple Y axes are
inverted to GLFW's down-positive convention; trigger values are converted from
0..1 to GLFW's -1..1 (rest=-1). Fifteen semantic buttons and a D-pad hat follow GLFW's
standard order. No analog axis becomes a key. DualSense's Apple profile class
supplies a model name and synthesized SDL-format Sony 054c/0ce6 GUID; this is model
identification, not a USB/HID serial or a VID/PID read from Bluetooth. Generic
controllers use a stable model-name GUID without fabricated VID/PID values.

Slots stay stable while connected. Only extended gamepads are enumerated, only
in passthrough mode. Absent devices return false/null, never a fabricated controller.
Connect/disconnect callbacks run on the Java GLFW event-pump thread, without calling
Java from UIKit or synchronously dispatching JNI work onto the main thread.
Snapshots and metadata are copied together under a lock. Held native keys/buttons,
stick direction, sticky shift and accumulated mouse state are released/reset before
mode transitions. Only Air-owned GameController callbacks are detached.

The shipped NeoForge Controlify 2.5.2 and 3.0.1 LTS JARs both use
`controlify.debug.sdl_natives_override`, try the indicated native through libsdl4j/JNA,
and choose GLFW when the load fails. Air supplies the intentionally impossible
path `/dev/null/air-glfw-controller-backend`. This deliberately triggers their
existing fallback before they can load the renderer SDL or a macOS-native library.
The expected one-time SDL load error mentioning that exact path is normal for this
mode. There is no patched mod JAR, agent, native download or custom SDL ABI.

This override is selected for identifiable 1.21.1 launches even in native mode so
the in-game switch can work in either direction. Native mode exposes no gamepads to
Controlify, leaving Air's keyboard/mouse controls in charge. Other profiles opt in
by selecting passthrough; their compatibility is not established. Standard input
is covered; GLFW does not supply DualSense gyro, adaptive triggers or haptics.
Controlify's USB/HID scan can be unavailable for an iPad Bluetooth device; its
version-specific fallback uses the GLFW driver name when HID type is unknown.
PlayStation glyph auto-identification is not established by this bridge.

## Upstream examined and reused

- [Taylen27 release 1.2.0](https://github.com/Taylen27/Amethyst-iOS/releases/tag/1.2.0)
  explicitly limits its Controlify fix to 26.3+.
- At [6542ff2](https://github.com/Taylen27/Amethyst-iOS/commit/6542ff2),
  `Natives/input/ControllerInput.m` guards key mapping, both stick handlers and mouse
  tick with `AMControllerPassthrough`. That separation is backported here, with
  explicit state release and callback cleanup.
- Its `Natives/sdl3_hook.m` calls SDL_SetMainReady on a private Controlify SDL copy,
  loads `Frameworks/lwjgl34/libSDL3_controlify.dylib`, and sets the accelerometer hint.
  The hint is reused before JVM startup; its 26.3 SDL initialization/JNI path is not
  copied into 1.21.1.
- Its Java SDL3Bridge discovers `amethyst.controlify` during SDL event polling.
  Minecraft 1.21.1 never executes that runtime path, so this implementation uses the
  native profile setting and the existing GLFW overlay instead.
- The source tree at 6542ff2 lacks the private dylib, **but the actual release IPA
  includes it**. Downloaded IPA SHA-256:
  `c9f413f24266d010a81c3a51df44464944aeba4268581ee40592c920371e9d33`.
  Inspection found both SDL dylibs; the private one is Mach-O arm64, platform IOS,
  min OS 14.0, SDK 16.0, with SDL_SetMainReady/SDL_Init/SDL_GetGamepads exports.
  Its extracted signature has no TeamIdentifier and requires normal app re-signing.
  No SDL dylib is added by this change; GameController is already linked by Air.
- [Controlify LTS source](https://github.com/isXander/Controlify/tree/lts/src/main/java/dev/isxander/controlify)
  and the actual shipped JAR bytecode establish the version-specific SDL loader,
  GLFW fallback, gamepad layout and connect/disconnect callback requirements.
- [Controlify controller architecture](https://moddedmc.wiki/en/project/controlify/latest/docs/architecture/controllers),
  [GLFW gamepad input](https://www.glfw.org/docs/3.3/input_guide.html#gamepad), and
  [SDL's iOS integration guide](https://wiki.libsdl.org/SDL3/README-ios) informed the
  choice to avoid a second UIKit/SDL lifecycle for this GLFW-based game.

## Reproduce host checks

```sh
# Java 8 for the actual launcher build; Java 21 for Controlify loader probes.
BOOTJDK=/path/to/jdk8/bin tests/controller/run.sh
make -C JavaApp -j4 BOOTJDK=/path/to/jdk8/bin
python3 tests/controller/verify_controlify.py /path/to/controlify.jar /path/to/jna-5.13.0.jar
# Optional actual assembled GLFW API test on an Apple Silicon Mac:
BOOTJDK=/path/to/jdk8/bin tests/controller/glfw_api_probe.sh /path/to/lwjgl-3.3.3-natives-macos-arm64.jar
plutil -lint Natives/resources/en.lproj/Localizable.strings Natives/resources/zh-Hans.lproj/Localizable.strings
git diff --check
# Inspect a produced IPA and compare the existing base's signing/framework inventory:
python3 tests/controller/verify_ipa.py /path/to/Air.ipa /tmp/air-ipa-check --baseline-ipa /path/to/base-Air.ipa
```

The tests exercise production ControllerInput method bodies with host adapters for
UIKit/key injection, production bridge code, Apple's real synthetic extended-gamepad
implementation, and a host-only JNI fixture. They test analog precision, axis signs,
trigger rest/range, all available buttons, D-pad directions/diagonals, no-device cold
start, mode gating, disconnect, slot reuse, exactly-once callbacks, buffer sizes,
user-pointer cleanup and actual native-to-Java delivery. No iPad execution is implied.
The optional loader probe executes the shipped Controlify SDL loader, DebugProperties,
libsdl4j and JNA; only Minecraft logging/platform dependencies are stubbed.

Inspected JAR SHA-256:

- Controlify 2.5.2+1.21.1-neoforge:
  `495c419d942e58bfdfb5bf65c1a9258b41de3156d7c3cf09408661ae8e61eb93`
- Controlify 3.0.1+lts+1.21.1-neoforge:
  `0c8b8d6e57599b516a16f2df2a7314ee96228c94f145f5d7bea2e2ec7b2f90e7`

## Actual validation results

- PASS: full JavaApp build with the existing Makefile and Zulu JDK 8.
- PASS: Java snapshot tests, Apple synthetic-gamepad tests, production JNI round trip,
  actual assembled GLFW API/GLFWGamepadState probe, production ControllerInput
  release/callback/mode-transition tests, and a production-method check that profile
  mode saves preserve all unrelated JSON fields (including missing inherited keys).
- PASS: eight actual NeoForge 21.1.238 BootstrapLauncher/JPMS probes with the rebuilt
  bundles (both LWJGL variants). The patched 46-module graph remains valid with no
  duplicate package owners; the historical ignored-LWJGL and empty-property failure
  cases remain reproduced. These probes stop at unavailable desktop/iOS native
  initialization, not at a successful game launch.
- PASS: actual Controlify 2.5.2 and 3.0.1 LTS loader probes reject the intentional
  override before SDL initialization and retain the GLFW fallback.
- PASS: both assembled LWJGL bundles contain the bridge classes as Java 8 bytecode;
  Mojang split-package exclusions remain intact; localization syntax validates.
- Local full native build unavailable: Makefile reports missing CMake; independently,
  xcrun confirms the iPhoneOS SDK is absent. Full iOS compilation/package validation
  is delegated to the existing Xcode 15.4 CI workflow, with bridge tests added.
- PASS: final [Xcode 15.4 CI build](https://github.com/jasonvakker/Amethyst-iOS-MyRemastered/actions/runs/41895635407)
  for app source `bcc6dd5dbeb9995df02129dc9d8866270dfe090b`. Both IPA and TIPA
  packaged successfully; all five expanded host test groups passed in CI. The build
  log contains no compiler errors (existing dependency warnings remain).
- PASS: actual final IPA inspection found the exported
  `_Java_org_lwjgl_glfw_GamepadBridge_nativeSnapshot` in the iOS arm64 executable,
  all three bridge classes in both LWJGL bundles as Java 8 bytecode, and no JPMS
  split packages. Bundle ID, signing entitlements and Frameworks inventory match
  the previously validated d1a5052 base IPA.
- PASS: actual GLFW API/GLFWGamepadState probe and all eight NeoForge bootstrap
  probes repeated with JARs extracted from the final IPA. These remain host tests.
- Physical iPad / DualSense / Oritech launch and performance: **unverified**.

DEBUG logs use `[ControllerBridge]` for profile mode, requested and actually registered
GLFW backend, JNI symbol resolution, physical connect/disconnect, names/model GUIDs,
connection generation delivery and rate-limited analog samples. Controlify's own
DEBUG logging is enabled in Debug builds. No account tokens or API keys are logged
by this feature.

## Final artifacts and evidence

App source built: `bcc6dd5dbeb9995df02129dc9d8866270dfe090b`. Later commits contain
only the artifact-inspection test and this report; application source is identical.

- [IPA artifact](https://github.com/jasonvakker/Amethyst-iOS-MyRemastered/actions/runs/41895635407/artifacts/13356042774)
- [TIPA artifact](https://github.com/jasonvakker/Amethyst-iOS-MyRemastered/actions/runs/41895635407/artifacts/13356927179)
- Artifact retention: 2 February 2027.
- Final IPA SHA-256: `4ca1d1291e583473d40bdac91cb907a244a9749a70409d5f594fe209e942b519`.
- Historical Makefile filename: `com.air-devs.air-1.0-ios.ipa`; actual bundle version
  remains **5.1.0**, ID **com.air-devs.air**.

Local evidence is under `../controller-validation/`: `controller-tests.log`,
`controlify-2.5.2-loader.log`, `controlify-3.0.1-loader.log`, `final-ci-evidence.log`,
`final-ipa-verification.json`, `final-ipa-glfw-api.log`, `final-ipa-bootstrap-probes.log`,
and the individual bootstrap logs. The IPA is in `final-artifacts/IPA/`.
The package was inspected, not installed. No physical-device test result is claimed.

## iPad acceptance checklist — all remain unverified

Use the existing Air application/container, Minecraft 1.21.1, NeoForge 21.1.238 and
Oritech profile. Keep the same renderer, Java runtime, JIT and memory settings.
If installing a test IPA, update the existing app using the same bundle identity /
signing arrangement; do not delete/reinstall Air or create a different app container.
No installation is performed by this implementation workflow.

1. Set the profile to Controller Mod Passthrough, disconnect DualSense in iPadOS,
   fully quit Air, relaunch and enable JIT through StikDebug. Open Controlify:
   **zero connected controllers**. A historical saved configuration entry alone is
   not a connected controller; do not delete configuration to hide a failed test.
2. Pair/connect DualSense: **one Sony DualSense**, one connect log, no phantom.
   Confirm `[ControllerBridge] Controlify backend=GLFW` in the Debug log.
3. Move each stick slowly through intermediate positions and full travel. Verify
   proportional walking/turning and correct directions. Test L2/R2 from rest through
   partial and full travel, face buttons, shoulders, thumb clicks, Options/Create,
   and every D-pad direction/diagonal. Inventory cursor, slot selection, item actions
   and menu navigation must work through Controlify's bindings.
4. Keep a stick/trigger/button held; disconnect. The device disappears, movement
   stops, and no key remains held. Reconnect several times: exactly one controller.
5. Switch to Air Native Controls through the touch-accessible floating menu. The
   mod's connected gamepad disappears; Air's normal mappings and virtual mouse work.
   Hold W-equivalent / mouse-button / sticky shift, then switch back to passthrough:
   all native outputs release and analog Controlify input resumes without double input.
6. While in passthrough, reconnect, open/close launcher settings, change resolution,
   rotate the iPad and reopen inventory. Air must not re-enable its virtual mouse,
   emit stick-to-WASD or fight Controlify's cursor. Touch/menu access remains usable.
7. Relaunch the existing NeoForge + Oritech profile in each mode with StikDebug JIT.
   Load an existing world and compare normal render/performance/memory behavior.
   Record launch success, FPS and any new crash; host tests do not establish this.

## Changed files

- `JavaApp/src/lwjgl/org/lwjgl/glfw/GLFW.java` — real joystick/gamepad APIs and event delivery.
- `JavaApp/src/lwjgl/org/lwjgl/glfw/GamepadBridge.java` — snapshot decoder and lifecycle.
- `Natives/input/NativeGamepadBridge.h`, `.m` — GameController producer and JNI.
- `Natives/input/ControllerInput.h`, `.m` — mode gate, callback ownership and held-input cleanup.
- `Natives/SurfaceViewController.h`, `.m` — startup/runtime mode, cursor/touch recovery and cleanup.
- `Natives/SurfaceViewController+Navigation.m` — touch-accessible runtime selector.
- `Natives/PLProfiles.m` — native default.
- `Natives/ProfileSettingsViewController.m` — per-profile setting.
- `Natives/JavaLauncher.m` — version-specific GLFW selection and pre-init sensor hint.
- `Natives/CMakeLists.txt` — compile the bridge into the existing executable.
- `Natives/resources/en.lproj/Localizable.strings`, `zh-Hans.lproj/Localizable.strings` — labels/help.
- `tests/controller/GamepadBridgeTests.java`, `NativeGamepadBridgeTests.m`,
  `NativeGamepadJNI.m`, `NativeGamepadProbe.java`, `ControllerInputTests.m`,
  `GLFWApiProbe.java`, `ProfileModeTests.m`, `run.sh`, `glfw_api_probe.sh`, `verify_controlify.py`, `verify_ipa.py` — reproducible checks.
- `.github/workflows/neoforge-ipa.yml` — test/build the isolated branch with the existing toolchain.
- `CONTROLLER_PASSTHROUGH.md` — this audit and acceptance record.
