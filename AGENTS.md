# Pi Control release rules

- After every Android app version update, build the release APK and publish it to the Raspberry Pi with `tools/publish_apk_to_pi.ps1`.
- The existing APK release directory on the Pi is exactly `/mnt/pishare/App/.apk` (uppercase `App`, hidden `.apk`). Never create `/mnt/pishare/app/apk` or another substitute directory.
- Keep versioned APK filenames in the form `Pi-Control-<version>.apk` and preserve older releases unless the user explicitly asks to remove them.
- Never store Raspberry Pi passwords, SSH tokens, or other credentials in this repository or in release scripts.
