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

Since standard Google OAuth plug-ins are targeted for Android, iOS, macOS, and Web, local Linux desktop testing runs in an adaptive **Mock Mode**.

### 1. Run as Native Linux Desktop App (Recommended)
This is the fastest compile option. It launches a native Linux window directly on your desktop:

```bash
flutter run -d linux
```

*Note: On Linux, the login flow is bypassed with a primary **"Get Started"** button that logs you in with a local `'Test User'` profile instantly. Local schema caching utilizes system keyring bindings.*

### 2. Run as Web Application
If you have authorized `http://localhost:5000` inside your Google Cloud Console Credentials (JavaScript Origins), you can run the app locally inside your browser:

```bash
flutter run -d web-server --web-port 5000 --web-hostname 0.0.0.0
```

### 3. Run on Emulators or Devices
List available device emulators or connected targets:

```bash
flutter emulators
flutter devices
```

Launch and deploy:

```bash
flutter emulators --launch <emulator_id>
flutter run -d <device_id>
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
