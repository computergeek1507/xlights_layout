# xLights Layout Viewer

A Flutter app that reads your [xLights](https://xlights.org/) show files and turns
them into a clean, printable layout and controller-wiring report.

Load your `xlights_rgbeffects.xml` (and optionally `xlights_networks.xml`) and the
app renders two views you can browse on screen or export to PDF:

- **Layout** — a detailed view of every prop/model in the show.
- **Controller Wiring** — a condensed view of how props are wired to controllers.

## Live demo

Once Pages is enabled, the web build is published at:

**https://computergeek1507.github.io/xlights_layout/**

## Features

- Open one or both xLights XML files (the app auto-detects each by its root element)
  from this device, a GitHub repository (public or private), or Google Drive.
- Browse a detailed layout report and a condensed controller-wiring report.
- Print or export either report to PDF.
- Runs entirely in the browser — your files are parsed locally and never uploaded.
  Remote files are downloaded straight from GitHub/Google to the app; there is no server in between.

## Loading from GitHub

Choose **Load files → From GitHub** and enter the repository as `owner/repo`,
`owner/repo/path/to/show`, or paste a github.com link (repo, folder or file). The app
scans the repo for `xlights_rgbeffects.xml` and lets you pick if there are several
(e.g. backup folders); `xlights_networks.xml` in the same folder is loaded too.

Private repositories need a token. Create a
[fine-grained personal access token](https://github.com/settings/personal-access-tokens/new)
limited to the show repo with **Repository permissions → Contents: Read-only**. The token is
only sent to `api.github.com`, and is stored on the device only if you tick
*Remember token on this device* (browser localStorage on web).

## Loading from Google Drive

Choose **Load files → From Google Drive**, sign in, and pick a show folder from the
search results — or paste a Drive link to the show folder or one of its XML files. My Drive,
"Shared with me" and shared drives are searched. Supported on web, Android, iOS and macOS
(Google has no sign-in plugin for Windows/Linux desktop builds).

Drive needs an OAuth client you own:

1. In [Google Cloud Console](https://console.cloud.google.com/) create a project, enable the
   **Google Drive API**, and configure the OAuth consent screen with the scope
   `https://www.googleapis.com/auth/drive.readonly`. Add yourself (and anyone else) as test
   users. `drive.readonly` is a *restricted* scope, so opening the app to all Google users
   requires Google's verification.
2. Create OAuth client IDs:
   - **Web application** — add `https://computergeek1507.github.io` (and
     `http://localhost:<port>` for `flutter run -d chrome --web-port <port>`) as an
     authorized JavaScript origin.
   - **Android** — package `com.scoot.xlights_layout` and your signing SHA-1.
   - **iOS** (also used for macOS) — your bundle ID. Add its reversed client ID as a URL scheme in
     `ios/Runner/Info.plist` / `macos/Runner/Info.plist` per the
     [google_sign_in docs](https://pub.dev/packages/google_sign_in).
3. Pass the IDs at build time (they are not secrets, but are kept out of the repo):

   ```bash
   flutter run -d chrome --web-port 5000 --dart-define=GOOGLE_CLIENT_ID=<web-client-id>
   flutter build ios --dart-define=GOOGLE_APPLE_CLIENT_ID=<ios-client-id>
   ```

   For the GitHub Pages build, set a repository **variable** (Settings → Secrets and variables →
   Actions → Variables) named `GOOGLE_CLIENT_ID`. Without it the Drive option shows as not set up.

## Getting started

Prerequisites: [Flutter](https://docs.flutter.dev/get-started/install) (stable channel, Dart SDK 3.12+).

```bash
flutter pub get
flutter run            # run on your default device
flutter run -d chrome  # run as a web app
```

Run the tests:

```bash
flutter test
```

## Building for the web

```bash
flutter build web --release --base-href /xlights_layout/
```

The output is written to `build/web/`. The `--base-href` flag must match the path
the app is served from (here, the GitHub Pages project subpath).

## Deployment

Pushes to `main` are built and published to GitHub Pages automatically by the
[`Deploy to GitHub Pages`](.github/workflows/deploy.yml) workflow.

To enable it once: in the repository **Settings → Pages**, set **Source** to
**GitHub Actions**. The workflow can also be run manually from the **Actions** tab.

## Tech

Built with Flutter using `xml` for parsing, `file_picker` for file selection,
`printing`/`pdf` for report export, `http` for the GitHub and Drive REST APIs, and
`google_sign_in` for Drive authorization.
