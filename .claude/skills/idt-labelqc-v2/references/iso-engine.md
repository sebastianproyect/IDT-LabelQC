# Motor ISO — Diseño del Analizador Geométrico

## El problema con capture.image (YUV420)

```
mobile_scanner (Android) → captura en formato YUV420/NV21
capture.image → bytes en formato YUV420, NO JPEG estándar
img.decodeImage(bytes) → null (image package no soporta YUV420)
→ ISO15416Analyzer / ISO15415Analyzer reciben imagen null
→ _fallbackParameters() activado automáticamente
→ todos los parámetros = Grade F
→ SIEMPRE aparece "NO OK — RECHAZADO" aunque el código sea perfecto
```

**Adicionalmente:**
- `returnImage=false` (default) → `capture.image = null` → mismo resultado
- `returnImage=true` → puede devolver JPEG en algunas versiones/dispositivos, pero NO es fiable cross-device

## La solución: Motor ISO Geométrico

El motor ISO debe rediseñarse completamente. La fuente **principal** de análisis son los datos geométricos que mobile_scanner SÍ proporciona de forma fiable:

```
BarcodeCapture:
  ├── barcodes[0].rawValue       → contenido decodificado (String)
  ├── barcodes[0].format         → BarcodeFormat (ean13, qrCode, etc.)
  ├── barcodes[0].corners        → List<Offset> en coordenadas imagen
  ├── barcodes[0].boundingBox    → Rect en coordenadas imagen
  └── capture.size               → Size de la imagen procesada

Derivables:
  ├── tamaño del código (píxeles)
  ├── orientación (ángulo de las corners)
  ├── relación de aspecto
  ├── densidad de módulos estimada
  └── quiet zones (distancia borde código → borde imagen)
```

---

## Principio Fundamental

> Si mobile_scanner **pudo decodificar** el código (rawValue != null), significa que:
> - El contraste es suficiente para ML Kit → estimar Grade B mínimo para SC
> - La estructura es legible → Fixed Pattern Damage es aceptable
> - El decodificador funcionó → Decodability = Grade A

Esto es más honesto que inventar medidas de píxeles sobre una imagen JPEG comprimida.

---

## Parámetros ISO 15416 (Códigos 1D: EAN-13, Code128, etc.)

### Decodability
- **Fuente:** `rawValue != null`
- **Cálculo:** Si decoded → Grade A (4.0). Si no decoded → Grade F (0.0)
- **Fiabilidad:** EXACTA — ML Kit lo determinó
- `isEstimated: false`

### Quiet Zones
- **Fuente:** `corners` + `boundingBox` + `capture.size`
- **Cálculo:**
  ```
  leftQZ = barcode.boundingBox.left pixels
  rightQZ = (capture.size.width - barcode.boundingBox.right) pixels
  moduleWidth = barcode.boundingBox.width / expectedModules(symbology)
  qzInModules = min(leftQZ, rightQZ) / moduleWidth
  ```
- **Fiabilidad:** BUENA (depende de encuadre del operario)
- `isEstimated: false`

### Symbol Contrast (SC)
- **Fuente ideal:** imagen RGB bien capturada
- **Fuente alternativa:** si decoded → estimar SC ≥ 40% (Grade C mínimo garantizado por el hecho de que ML Kit lo leyó)
- **Cálculo imagen:** `(Rmax - Rmin) / Rmax * 100`
- `isEstimated: true` cuando no hay imagen RGB fiable

### Minimum Reflectance (MR)
- **Fuente:** imagen RGB
- **Cálculo:** `Rmin ≤ 0.5 * Rmax`
- **Fallback:** si decoded → estimar Grade B (ML Kit leyó, por tanto hay reflectancia diferenciada)
- `isEstimated: true` sin imagen

### Edge Contrast (EC)
- **Fuente:** imagen RGB (perfil de reflectancia)
- **Fallback:** estimar desde número de transiciones detectadas en corners
- `isEstimated: true` sin imagen

### Modulation (MOD)
- **Fuente:** imagen RGB
- **Fallback:** estimar Grade B si decoded
- `isEstimated: true` sin imagen

### Defects (DEF)
- **Fuente:** imagen RGB
- **Fallback:** estimar Grade B si decoded
- `isEstimated: true` sin imagen

### Scan Reflectance Profile
- **Fuente:** imagen RGB, perfil de escaneo
- **Fallback:** no disponible sin imagen → omitir o marcar N/A
- `isEstimated: true`

---

## Parámetros ISO 15415 (Códigos 2D: QR, DataMatrix, etc.)

### Decodability
- **Fuente:** `rawValue != null` → Grade A
- `isEstimated: false`

### Quiet Zones / Fixed Pattern Damage
- **Fuente:** `corners` — las 4 esquinas definen el área del símbolo
- **Cálculo geométrico:**
  - QR: finder patterns en esquinas → si corners son ortogonales y simétricas → Grade A
  - DataMatrix: L-pattern y timing → detectable desde aspect ratio de corners
- **Fiabilidad:** ESTIMADA (no podemos ver los píxeles de los finder patterns)
- `isEstimated: true`

### Grid Nonuniformity / Axial Nonuniformity
- **Fuente:** `corners` → calcular distorsión ortogonal
- **Cálculo:**
  ```
  lado_superior = dist(corners[0], corners[1])
  lado_inferior = dist(corners[3], corners[2])
  lado_izquierdo = dist(corners[0], corners[3])
  lado_derecho = dist(corners[1], corners[2])
  gnu = |lado_superior - lado_inferior| / avg(lados)
  anu = |lado_horiz - lado_vert| / avg(lados)
  ```
- **Fiabilidad:** BUENA — corners son precisas en ML Kit
- `isEstimated: false` (cálculo real)

### Symbol Contrast / Modulation / Print Growth
- **Fuente:** imagen RGB si disponible
- **Fallback:** estimar desde decoded status
- `isEstimated: true` sin imagen

### Unused Error Correction
- **Fuente:** `rawValue` + `symbology` → estimar basándose en longitud del mensaje vs capacidad
- **Cálculo:** `(capacidad_ECC - datos_reales) / capacidad_ECC * 100`
- `isEstimated: true` (cálculo aproximado sin acceso al decodificador interno)

---

## Interfaz del Motor ISO (dominio)

```dart
abstract class ISOAnalyzer {
  ISOParameters analyze(BarcodeAnalysisInput input);
}

class BarcodeAnalysisInput {
  final String? rawValue;
  final BarcodeSymbology symbology;
  final List<Offset>? corners;
  final Rect? boundingBox;
  final Size captureSize;
  final Uint8List? imageBytes;  // opcional, solo para mejora de precisión
}

class GradeValue {
  final double rawMeasurement;
  final String unit;
  final ISOGrade grade;
  final double numericGrade;
  final bool isEstimated;        // NUEVO: obligatorio
  final String? estimationBasis; // NUEVO: justificación
}
```

---

## Jerarquía de fuentes (prioridad descendente)

```
1. Dato geométrico exacto (corners, boundingBox, rawValue)
   → isEstimated: false

2. Imagen RGB bien decodificada por img.decodeImage()
   → isEstimated: false (si imagen válida)

3. Inferencia desde decoded status
   → isEstimated: true, basis: "Inferido desde decodificación exitosa"

4. Valor por defecto conservador
   → isEstimated: true, basis: "Estimación conservadora: parámetro no calculable"
```

---

## Reglas para el motor ISO en UI

- Mostrar indicador `~` o `est.` junto a valores estimados
- En modo Técnico: mostrar tooltip explicando la base de la estimación
- En informes PDF: nota al pie indicando qué parámetros son estimados
- NUNCA mostrar una medida falsa sin marcarla
- Si >50% de parámetros son estimados → mostrar banner "Análisis parcial — acercar cámara"

---

## Futuros motores intercambiables

La interfaz `ISOAnalyzer` permite:
- Motor v1: geométrico (actual)
- Motor v2: geométrico + RGB image
- Motor v3: ML/IA con modelo entrenado
- Motor v4: integración con verificador externo (Bluetooth/USB)

Sin cambiar las pantallas ni los casos de uso.
