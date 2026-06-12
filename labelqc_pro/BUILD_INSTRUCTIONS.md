# IDT LabelQC — Instrucciones de Compilación

## Requisitos previos (instalar en tu máquina)

1. **Flutter SDK** (3.24+): https://flutter.dev/docs/get-started/install
2. **Android Studio** con Android SDK (API 34)
3. **Java JDK 17+**

## Pasos para compilar la APK

```bash
# 1. Ir a la carpeta del proyecto
cd idtlabelqc

# 2. Obtener dependencias
flutter pub get

# 3. Generar código Drift (base de datos)
dart run build_runner build --delete-conflicting-outputs

# 4. Compilar APK release
flutter build apk --release --no-shrink

# La APK estará en:
# build/app/outputs/flutter-apk/app-release.apk
```

## Compilar APK debug (más rápido, para pruebas)

```bash
flutter build apk --debug
# APK en: build/app/outputs/flutter-apk/app-debug.apk
```

## Instalar directamente en dispositivo conectado por USB

```bash
flutter run --release
```

## Para iOS (requiere Mac + Xcode)

```bash
flutter build ios --release
```

## Notas importantes

- El proyecto usa **Drift** para la base de datos SQLite.
  Tras hacer `flutter pub get`, ejecuta el build_runner una vez.
  
- La primera vez que se abre la app, se crea automáticamente
  el usuario administrador: **usuario: admin / contraseña: admin123**
  
- La cámara necesita permiso en el dispositivo al primer uso.

