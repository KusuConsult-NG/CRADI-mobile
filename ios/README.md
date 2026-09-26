# iOS notes

## Minimum iOS version — 15.0

`onesignal_flutter` 5.7.0 requires iOS 15, so the whole project is on **15.0**:

* `Podfile` → `platform :ios, '15.0'`, and the `post_install` block pins every
  pod to the same `IPHONEOS_DEPLOYMENT_TARGET`.
* `Runner.xcodeproj/project.pbxproj` → `IPHONEOS_DEPLOYMENT_TARGET = 15.0` in
  **all three** build configurations (Debug, Release, Profile).

Both must move together; if Xcode and CocoaPods disagree, `pod install` fails
or the archive is rejected. (`Flutter/AppFrameworkInfo.plist` still says
`MinimumOSVersion 13.0` — that is the Flutter template's floor for the engine
framework and is below ours, so it is left as Flutter ships it.)

## Push notifications (APNs / OneSignal)

Entitlements are split per build configuration, so nothing has to be edited by
hand before an archive:

| Configuration | `CODE_SIGN_ENTITLEMENTS` | `aps-environment` |
| --- | --- | --- |
| Debug | `Runner/Runner.entitlements` | `development` |
| Profile | `Runner/Runner.entitlements` | `development` |
| Release | `Runner/RunnerRelease.entitlements` | `production` |

TestFlight and App Store builds use Release, so they now carry `production`.
An APNs token issued against the sandbox is rejected by the production
gateway, which is why a `development` entitlement makes push **fail silently**
once the build leaves Xcode. Keep both files in sync when adding a capability.

The App ID must have the Push Notifications capability, and the OneSignal app
needs the matching APNs key/certificate. `Info.plist` declares
`UIBackgroundModes` → `remote-notification` (only that — there is no
background fetch).

## Deep links

`Info.plist` declares the `cradi://` URL type; Universal Links for
`https://cradi.ng` additionally need the *Associated Domains* entitlement
(`applinks:cradi.ng`) added in Xcode and an `apple-app-site-association` file
hosted at that domain.

Delivery to the router is done in Dart by
`lib/core/services/deep_link_service.dart` (an `app_links` listener), **not**
by Flutter's framework deep linking — see the class comment for why. Do not
add `FlutterDeepLinkingEnabled` to `Info.plist`: it would also push Supabase
auth callbacks (password recovery, email confirmation) into `go_router`.

## Localization

`Runner/<lang>.lproj/InfoPlist.strings` translate the permission prompts for
en, ha, yo, ig and pcm; `CFBundleLocalizations` in `Info.plist` lists the same
set. The files are wired into the project as a single `InfoPlist.strings`
variant group in the Runner target's *Copy Bundle Resources* phase — they show
up in Xcode under *Runner* with a language disclosure triangle.

## Export compliance

`ITSAppUsesNonExemptEncryption` is deliberately **not** set — see the comment
in `Info.plist` and `docs/DEPLOYMENT.md`. Until it is decided, App Store
Connect asks the encryption question on every upload.
