# iOS notes

## Push notifications (APNs / OneSignal)

`Runner/Runner.entitlements` sets `aps-environment` to `development`, which
works for debug builds installed from Xcode. **App Store / TestFlight builds
need `production`**: change the value before archiving (or let Xcode's
automatic signing apply the distribution provisioning profile, which carries
`production`). The App ID must have the Push Notifications capability, and
the OneSignal app needs the matching APNs key/certificate.

`Info.plist` already declares `UIBackgroundModes` → `remote-notification`
(and `NSFaceIDUsageDescription` for the biometric lock).
