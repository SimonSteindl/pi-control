# F-Droid submission preparation — Pi Control

Status: preparation only; this is **not** an official F-Droid submission.

## App details verified from the source tree

- Name: Pi Control
- Application ID: `io.github.simonsteindl.picontrol`
- Upstream source: https://github.com/SimonSteindl/pi-control
- License: Apache-2.0 (root `LICENSE`)
- Flutter project directory: `app/`
- Current upstream version in `app/pubspec.yaml`: `2.4.0+15`
- Release tag for that version: `2.4.0`
- Release tag commit: `31ee2b48567ad2d3401fe638c375da220fccf75b`
- Fastlane descriptions exist for `en-US` and `de-DE`.

## Official submission route

The official F-Droid repository uses its separate `fdroiddata` GitLab repository. A metadata file must be added there and submitted as a merge request. This file in the upstream GitHub repository is preparation documentation only; it does not publish the app.

Official guide: https://f-droid.org/docs/Submitting_to_F-Droid_Quickstart/

## Checks to complete before submitting

- [ ] Confirm that all Flutter/Dart dependencies and Android plugin dependencies meet F-Droid's free-software policy.
- [ ] Make a reproducible F-Droid build recipe for the Flutter app in `app/`, pinning a Flutter SDK release compatible with the Dart constraint in `app/pubspec.yaml`.
- [ ] Run an F-Droid-style source build and fix build/metadata errors.
- [ ] Check whether the app requires any anti-features disclosures or privacy-policy details.
- [ ] Check the release/version tag and changelog metadata.
- [ ] Submit `io.github.simonsteindl.picontrol.yml` to the official `fdroiddata/metadata/` directory in a merge request.
- [ ] Wait for F-Droid maintainer review; acceptance and publication are not guaranteed.

## Important compatibility note

The current GitHub Actions workflow uses the Flutter stable channel, which is not pinned to a specific SDK release. F-Droid builds need a pinned, compatible toolchain so the build can be repeated. Do not treat the GitHub Actions APK as the F-Droid build.
