# IDT LabelQC — Guía de Instalación Completa

## ¿Qué hay en este paquete?

El archivo ZIP contiene el **código fuente completo** de la app IDT LabelQC en Flutter.
Para obtener la APK instalable necesitas compilarlo en una máquina con Flutter instalado.

---

## OPCIÓN A — Compilar tú mismo (recomendado)

### Paso 1 — Instalar Flutter (una sola vez)

**Windows:**
```
winget install Google.Flutter
```
O descarga de: https://docs.flutter.dev/get-started/install/windows

**Mac:**
```
brew install flutter
```

**Linux:**
```
sudo snap install flutter --classic
```

### Paso 2 — Instalar Android Studio (una sola vez)

Descarga de: https://developer.android.com/studio
Durante la instalación, acepta instalar el Android SDK.

### Paso 3 — Configurar Flutter

```bash
flutter doctor
```
Asegúrate de que Android SDK esté aceptado:
```bash
flutter doctor --android-licenses
```

### Paso 4 — Compilar IDT LabelQC

```bash
# Descomprime el ZIP
unzip IDT_LabelQC_source.zip

# Entra a la carpeta
cd labelqc_pro

# Descarga dependencias
flutter pub get

# Compila la APK
flutter build apk --release
```

**La APK estará en:**
```
labelqc_pro/build/app/outputs/flutter-apk/app-release.apk
```

### Paso 5 — Instalar en el móvil

**Opción 1 - Por USB (con USB Debugging activado):**
```bash
flutter install
```

**Opción 2 - Copia manual:**
1. Copia `app-release.apk` al móvil
2. En el móvil: Ajustes → Seguridad → Instalar aplicaciones desconocidas → Activar
3. Abre el archivo APK desde el gestor de archivos

---

## OPCIÓN B — Usando el script automático

Una vez que tengas Flutter instalado:

```bash
unzip IDT_LabelQC_source.zip
bash labelqc_pro/build_apk.sh
```

---

## OPCIÓN C — Servicio de compilación en la nube (sin instalar nada)

Puedes usar **Codemagic** (gratis hasta 500 min/mes):
1. Sube el código a GitHub
2. Conecta con codemagic.io
3. Selecciona "Flutter App"
4. Descarga la APK generada

O **GitHub Actions** (también gratis) con el workflow Flutter.

---

## Primeros pasos en la app

Al abrir la app por primera vez:
- **Usuario:** `admin`
- **Contraseña:** `admin123`

Cambia la contraseña en Configuración → Usuarios.

---

## Características incluidas

✅ Modo Producción (escaneo rápido verde/rojo)
✅ Modo Técnico (análisis ISO 15415/15416 completo)
✅ Gestión de Órdenes de Fabricación
✅ Patrones Maestros (Golden Sample)
✅ Base de datos SQLite local
✅ Generación de informes PDF
✅ Dashboard con KPIs y gráficos
✅ Motor de recomendaciones
✅ Control Estadístico de Procesos (SPC)
✅ Tema oscuro industrial
✅ Compatible Android 6.0+ (API 23)

---

## Soporte técnico

Para dudas sobre la compilación o la app, consulta:
- Flutter docs: https://docs.flutter.dev
- Dart packages: https://pub.dev

