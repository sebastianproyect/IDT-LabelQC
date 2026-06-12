---
name: flutter-apk-deploy
description: Build and deploy the IDT LabelQC Flutter Android APK via GitHub Actions. Use this skill when the user wants to build a new APK, push changes to trigger a build, monitor a GitHub Actions build, or share a download link for the APK. Also covers diagnosing and fixing Gradle, Kotlin, Flutter version compatibility errors.
license: MIT
metadata:
  author: sebastianproyect
  version: "1.0.0"
---

# Flutter APK Deploy — IDT LabelQC

Automates the full cycle: code change → git push → GitHub Actions build → public APK release link.

## When to Apply

- User wants to build a new APK after making code changes
- User asks "¿cómo descargo el APK?" / "¿está lista la build?"
- A GitHub Actions build is failing (red ✗)
- User wants to share the APK with someone else
- Gradle/Kotlin/AGP version errors appear in the CI log

---

## Project Setup

| Item | Value |
|------|-------|
| Repo | `https://github.com/sebastianproyect/IDT-LabelQC` |
| APK download | `https://github.com/sebastianproyect/IDT-LabelQC/releases/latest` |
| Flutter subdir | `labelqc_pro/` |
| CI config | `.github/workflows/build-apk.yml` |
| Trigger | Push to `master` or `main`, or manual `workflow_dispatch` |

---

## Step 1 — Make Changes and Push

```bash
# Stage specific changed files (never git add -A blindly)
git add <files>
git commit -m "fix: description of what changed"
git push origin master
```

After the push, GitHub Actions starts automatically. The build takes **~5 minutes**.

---

## Step 2 — Monitor the Build

Check status at: `https://github.com/sebastianproyect/IDT-LabelQC/actions`

The workflow steps are:
1. `checkout` — clone repo
2. `setup-java` — Java 17 (temurin)
3. `flutter-action` — Flutter stable channel
4. `flutter pub get` — install Dart dependencies
5. `flutter build apk --release` — compile APK
6. `softprops/action-gh-release` — publish APK as GitHub Release

---

## Step 3 — Download the APK

Once the build shows a green ✓:

```
https://github.com/sebastianproyect/IDT-LabelQC/releases/latest
```

Download `IDT-LabelQC.apk` and send it via WhatsApp, email, or any file sharing app.

**Android install:** Settings → Install unknown apps → allow the file manager → tap the APK.

---

## Common Build Failures and Fixes

### Gradle version too old
```
Minimum supported Gradle version is X.Y
```
**Fix:** Edit `labelqc_pro/android/gradle/wrapper/gradle-wrapper.properties`:
```
distributionUrl=https\://services.gradle.org/distributions/gradle-8.11.1-bin.zip
```

### Kotlin metadata version incompatible
```
compiled with Kotlin stdlib X.Y.Z but KGP can only read metadata up to A.B.C
```
**Fix:** In `labelqc_pro/android/settings.gradle`, update:
```groovy
id "org.jetbrains.kotlin.android" version "2.2.20" apply false
```

### Old Gradle plugin format (apply from:)
```
The old Gradle plugin API is no longer supported
```
**Fix:** `settings.gradle` must use declarative `pluginManagement {}` + `plugins {}` blocks — see current file.

### Package conflict (web ^0.5.0 vs ^1.0.0)
**Fix:** In `pubspec.yaml`, use `share_plus: ^13.1.0` (not `^9.0.0`).

### BarcodeType name conflict
```
'BarcodeType' is defined in both mobile_scanner and entities.dart
```
**Fix:**
```dart
import 'package:mobile_scanner/mobile_scanner.dart' hide BarcodeType;
```

### CupertinoPageTransitionsBuilder removed
**Fix:** Remove the `TargetPlatform.iOS` entry from `pageTransitionsTheme` in `app_theme.dart`.

### const Map with double keys
```
Constant expressions can't use 'double' keys
```
**Fix:** Change `const` to `final` for the map.

### slope type mismatch (num vs double)
**Fix:** Use `slope.toDouble()` in `DegradationForecast` constructor.

---

## Current Gradle/Kotlin/AGP Versions (working)

| Tool | Version |
|------|---------|
| Gradle | 8.11.1 |
| AGP (Android Gradle Plugin) | 8.7.3 |
| Kotlin Gradle Plugin | 2.2.20 |
| Java | 17 (temurin) |
| Flutter | stable channel |
| minSdk | 23 (Android 6.0+) |
