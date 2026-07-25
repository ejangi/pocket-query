# Issue Spec: GitHub Actions CI/CD Build & Release Pipeline

## 1. Overview
This specification details the GitHub Actions workflow design for **Pocket Query**. The pipeline enforces strict test and quality gatekeeping on every code change and automates Android APK packaging and GitHub Release publication upon pushing version tags (`v*.*.*`).

---

## 2. Pipeline Triggers
* **Continuous Integration (CI)**: Runs on every `push` and `pull_request` targeting `main`.
* **Release Pipeline**: Triggers on `push` of tags matching `v*` (e.g., `v1.0.0`, `v1.2.3`), as well as manual trigger (`workflow_dispatch`).

---

## 3. Workflow Jobs & Stages

### Stage 1: Quality & Test Gatekeeping (`test`)
* **Runner**: `ubuntu-latest`
* **Steps**:
  1. Checkout repository code.
  2. Setup Java 17 (Zulu).
  3. Setup Flutter SDK (stable branch).
  4. Fetch dependencies (`flutter pub get`).
  5. Check formatting: `dart format --output=none --set-exit-if-changed .`
  6. Static analysis: `flutter analyze`
  7. Run test suite: `flutter test`
* **Rule**: If any step fails, the workflow immediately aborts before building binaries.

### Stage 2: Android APK Packaging (`build-android`)
* **Runner**: `ubuntu-latest`
* **Dependency**: Requires `test` job completion.
* **Execution Condition**: Tag push (`v*`) or `workflow_dispatch`.
* **Steps**:
  1. Setup Java 17 and Flutter SDK.
  2. Compile release APK: `flutter build apk --release`
  3. Rename APK to `pocket-query-<tag>.apk` (e.g. `pocket-query-v1.0.0.apk`).
  4. Upload APK as a workflow artifact.

### Stage 3: Future iOS Packaging (`build-ios` - Placeholder)
* **Runner**: `macos-latest` (when enabled)
* **Dependency**: Requires `test` job completion.
* **Status**: Positioned as a documented placeholder in `.github/workflows/release.yml`. When iOS development commences, this stage will compile the iOS bundle/IPA.

### Stage 4: GitHub Release Publication (`release`)
* **Runner**: `ubuntu-latest`
* **Dependency**: Requires `build-android` completion.
* **Execution Condition**: Tag push (`v*`).
* **Steps**:
  1. Download Android APK artifact.
  2. Generate GitHub Release Notes automatically (`generate_release_notes: true`) listing commit and PR changelogs since the prior tag.
  3. Append Markdown **Android Installation Instructions** to the release notes body.
  4. Attach the downloadable `pocket-query-<tag>.apk` to the release.

---

## 4. Release Notes & Installation Instructions Template

```markdown
## 📱 Android Installation Instructions

1. Download the `pocket-query-<tag>.apk` file attached below to your Android device.
2. If prompted by Android, allow installation from **Unknown Sources** / your browser for this package.
3. Open the downloaded `.apk` file and follow the on-screen prompts to complete installation.
4. Launch **Pocket Query** and authenticate with your Google Cloud account.
```
