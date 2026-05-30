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

- Open one or both xLights XML files (the app auto-detects each by its root element).
- Browse a detailed layout report and a condensed controller-wiring report.
- Print or export either report to PDF.
- Runs entirely in the browser — your files are parsed locally and never uploaded.

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

Built with Flutter using `xml` for parsing, `file_picker` for file selection, and
`printing`/`pdf` for report export.
