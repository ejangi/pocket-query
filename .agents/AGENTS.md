# Pocket Query Project Guidelines

This file governs the design, development, and behavioral standards for the Pocket Query cross-platform mobile application. All future agent reasoning and code generation must align with these parameters.

---

## 1. Project Goal
Build **Pocket Query**, an iOS and Android app that allows users to authenticate with their Google Cloud accounts and query Google BigQuery datasets, tables, and schemas directly from their mobile devices.

---

## 2. Core Tech Stack
* **Framework**: Flutter (Dart) for a single cross-platform codebase.
* **Authentication**: Google Sign-in (`google_sign_in` package) with OAuth scopes:
  * `https://www.googleapis.com/auth/bigquery`
  * `https://www.googleapis.com/auth/cloud-platform`
* **API Client**: Official `googleapis` and `googleapis_auth` Dart packages to communicate directly with the BigQuery REST API.
* **State Management**: Clean architecture using a robust, clean state management solution (e.g., BLoC or Provider).

---

## 3. Design & UX Principles (Figma Alignment)
All interfaces must align closely with the Figma design file (`AVuLQ1mdnBXg6I36hMpNQU`), reflecting these key layouts:
1. **Splash Screen**: Must feature a prominent Google Sign-in flow.
2. **Schema Browser**: Users can drill down hierarchically: Datasets ➔ Tables ➔ Fields. Fields must have active triggers to inject them directly into the SQL editor.
3. **Minimizable Editor & Results Grid**: Provide seamless transition states between a maximised editor pane (with autocomplete suggestion overlays) and a clean results grid.
4. **Dry-Run / Cost Estimator**: Estimate the query size (bytes scanned) and query cost in the editor *before* execution to prevent accidental billing overhead.
5. **Quick Count**: Optimize frequent requests by offering a metadata-only/optimized count query.

---

## 4. Development Rules
* **Target & Execution Environment**: Always default to running and testing the app on the **Android Studio Emulator** (or connected Android device). Do NOT run in Linux desktop mode by default, as Google Login is unsupported on Linux desktop mode.
* **Code Styling**: Follow the official Flutter/Dart formatting guidelines (`flutter format`).
* **Clean Architecture**: Keep UI widgets separate from state management logic and network services.
* **Security**: Google access tokens should be stored securely on-device (e.g., using `flutter_secure_storage`) and must never be exposed or logged.
