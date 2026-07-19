# Pocket Query

Pocket Query is a cross-platform mobile application built with Flutter that allows users to authenticate with their Google Cloud accounts and query Google BigQuery datasets, tables, and schemas directly from their devices.

---

## Technical Stack

* **Framework**: Flutter (Dart)
* **Authentication**: Google Sign-in with OAuth scopes for BigQuery and Cloud Platform.
* **Database client**: Official `googleapis` and `googleapis_auth` Dart packages.
* **Storage caching**: On-device caching using `flutter_secure_storage`.
* **State Management**: `Provider` architecture with dynamic `ChangeNotifierProxyProvider` state loops.

---

## Local Development & Testing

### 1. Run on Android Studio Emulator (Default & Recommended)
To test full authentication with Google Sign-in, run the app on an Android emulator or connected physical Android device.

List available device emulators or connected targets:
```bash
flutter emulators
flutter devices
```

Launch emulator and deploy:
```bash
flutter emulators --launch Pixel_9  # Or launch via Android Studio
flutter run
```

### 2. Run as Native Linux Desktop App (Mock Mode)
Standard Google OAuth plug-ins run in an adaptive **Mock Mode** on Linux desktop. This bypasses real Google Sign-in with a mock `'Test User'`.

```bash
flutter run -d linux
```

### 3. Run as Web Application
If you have authorized `http://localhost:5000` inside your Google Cloud Console Credentials (JavaScript Origins), you can run the app locally inside your browser:

```bash
flutter run -d web-server --web-port 5000 --web-hostname 0.0.0.0
```

---

## Running Automated Tests

Run the full automated test suite (including widget, SQL highlighting parser, and BigQuery service mock unit tests):

```bash
flutter test
```

### E2E Integration Tests
Run integration flow simulations:

```bash
flutter test integration_test/app_test.dart
```

---

## Updating BigQuery SQL Syntax Rules

The editor uses a custom syntax parser compiled from actual Google Cloud specifications. To download, parse, and update standard SQL functions, data types, and keywords from GCP reference docs:

```bash
python3 scratch/update_bigquery_syntax.py
```

This compiles lexical tables into `assets/metadata/bigquery_syntax.json`, which is bundled directly with the application package.
