# Pi Control – Store release preparation

The project is prepared for signed Android and iOS store builds without keeping credentials in Git.

## Android / Google Play

1. Choose the permanent application ID before the first Play Store upload. The current ID is `com.example.pi_control` so existing sideload installations keep receiving compatible APK updates.
2. Create an upload keystore and keep it outside this repository.
3. Create `android/key.properties` locally with `storeFile`, `storePassword`, `keyAlias`, and `keyPassword`.
4. Run `flutter build appbundle --release`. The result is `build/app/outputs/bundle/release/app-release.aab`.
5. Create the Play Console app and upload the AAB to an internal test track first.

If `android/key.properties` is absent, local release APKs continue to use the debug key for sideload testing. They are not suitable for Play Store publishing.

## iOS / TestFlight and App Store

1. Join the Apple Developer Program and choose the permanent bundle ID. The current ID is `com.example.piControl`.
2. Add the App Store Connect API key to Codemagic directly; never commit `.p8` keys or certificates.
3. Enable automatic iOS code signing in the existing Codemagic `pi-control` application.
4. Build a signed IPA and publish it to TestFlight for internal testing before App Store review.

The final store submissions require the owner's Google and Apple accounts, legal app information, screenshots, privacy details, and approval of the store submissions.
