#!/bin/bash
set -e

echo "╔══════════════════════════════════════════════╗"
echo "║     IDT LabelQC — Build Script v1.0          ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# Check Flutter
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter no encontrado."
    echo "   Instala Flutter: https://flutter.dev/docs/get-started/install"
    exit 1
fi

flutter --version | head -1
echo ""

# Enter project directory
cd "$(dirname "$0")/labelqc_pro"

echo "📦 Descargando dependencias..."
flutter pub get

echo ""
echo "🔨 Compilando APK (modo release)..."
flutter build apk --release

echo ""
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
if [ -f "$APK_PATH" ]; then
    SIZE=$(du -sh "$APK_PATH" | cut -f1)
    echo "✅ APK generada correctamente!"
    echo "   Tamaño: $SIZE"
    echo "   Ruta: $(pwd)/$APK_PATH"
    echo ""
    echo "📱 Para instalar en dispositivo conectado por USB:"
    echo "   flutter install"
    echo ""
    echo "📲 O copia la APK al móvil e instala desde el gestor de archivos"
    echo "   (asegúrate de habilitar 'Fuentes desconocidas' en Android)"
else
    echo "❌ La APK no se generó. Revisa los errores anteriores."
    exit 1
fi
