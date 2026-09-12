# MBNime

Flutter video client for Android and Windows with a Persian RTL interface.

- Internal player with subtitles, Android PiP and desktop keyboard controls.
- Responsive episode grid; internal/external player and downloader choices.
- Background downloads, pause/resume, cover notifications and organized folders.
- DLNA/Chromecast and system Wireless Display/Miracast connection.
- Verified GitHub updates; C++ Windows updater with rollback and relaunch.

## Development

Flutter 3.44.6 / Dart 3.12.2. Windows requires Visual Studio C++ tools.
Android uses Java 17+, SDK 37, minSdk 24 and the Gradle wrapper.

```sh
flutter pub get
flutter analyze --no-pub lib test
flutter test --no-pub
flutter run --dart-define=MBN_API_KEY=<your-service-client-key>
```

On the maintainer's Windows checkout, run `./Run-MBNime-Debug.ps1` to pass
the ignored `.signing/api-config.json` automatically (no secret in shell history).
Use `-Device <device-id>` for Android. After changing build-time configuration,
stop the previous run and start again; hot reload does not update Dart defines.

The service client key is supplied at build time. No user passwords, sessions,
login-code generator or signing keys are included. Account access and content
availability depend on the upstream service. Only access content you are
authorized to view/download.

See [Persian release guide](docs/RELEASES_FA.md) and [release notes](changelogs/1.2.0.fa.md).
Official packages: [GitHub Releases](https://github.com/MBNpro-ir/MBNime-App/releases).

`tools/Test-WindowsUpdater.ps1` tests replacement, rollback, relaunch and rejection
of incomplete bundles using isolated test executables, without touching the app.

Vendored dependencies retain their original licenses and document local patches.
