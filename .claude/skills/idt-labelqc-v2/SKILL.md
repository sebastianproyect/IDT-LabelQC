---
name: idt-labelqc-v2
description: Master skill for IDT LabelQC — professional industrial barcode quality verification platform. ALWAYS invoke this skill for ANY work on IDT LabelQC: new features, bug fixes, architecture decisions, ISO analysis, work orders, golden sample, SPC, database design, UI/UX, configuration, or any code change. This skill enforces SUPERPROMPT V2 rules — Clean Architecture, MVVM, SOLID, multidisciplinary team analysis before coding, and the critical ISO analyzer redesign (geometric data, NEVER YUV image bytes). If the user mentions labels, barcodes, ISO grades, EAN-13, QR, work orders, production control, print quality, or anything related to the LabelQC app, use this skill.
license: MIT
metadata:
  author: sebastianproyect
  version: "2.0.0"
---

# IDT LabelQC — Master Skill v2

This is the authoritative reference for all development on IDT LabelQC. Read this fully before writing any code.

## Team Mindset (OBLIGATORIO antes de cualquier código)

Before writing a single line of code, you must reason as a multidisciplinary team:

| Rol | Responsabilidad |
|-----|----------------|
| Arquitecto Senior | Evalúa impacto arquitectural, consistencia entre capas |
| Ingeniero Mobile Senior | Rendimiento Flutter, ciclo de vida, platform issues |
| Especialista ISO | Valida que los cálculos cumplen norma real |
| Especialista Impresión Industrial | Interpreta causas físicas de defectos |
| Especialista GS1 | Valida estructura de datos, simbología, aplicaciones |
| Especialista SPC | Diseña control estadístico, reglas Nelson/Western Electric |
| Ingeniero de Calidad | Define criterios aceptación, trazabilidad |
| Diseñador UX Industrial | Pantallas para entorno de planta, luz, guantes, ruido |
| Arquitecto Clean Architecture | Enforza capas, dependencias, contratos |

**Proceso obligatorio antes de implementar:**
1. Analizar requisitos completos
2. Detectar inconsistencias o mejoras superiores
3. Proponer arquitectura y esperar consistencia
4. Solo entonces: implementar

---

## Fases de Desarrollo (nunca en otro orden)

```
Fase 1 → Analizar requisitos + detectar mejoras + inconsistencias
Fase 2 → Arquitectura: Clean Arch + MVVM + SOLID + Repository + DI + Offline First
Fase 3 → Modelos + Casos de uso + BD + Servicios + Interfaces
Fase 4 → UX: pantallas + estados + errores + wireframes
Fase 5 → Implementación de código
```

---

## Bug Crítico: Analizador ISO — NUNCA usar capture.image para cálculos

**El problema:**
```
mobile_scanner devuelve imagen en YUV420
img.decodeImage(capture.image) → null
→ _fallbackParameters() activado
→ todos los grados = F (siempre)
returnImage=false → capture.image = null → mismo resultado
```

**La solución obligatoria:** → ver `references/iso-engine.md`

**Regla absoluta:**
- `capture.image` / `returnImage=true` → SOLO para visualización, informes, debugging
- Análisis ISO principal → datos geométricos del código (corners, boundingBox, rawValue, format, size)
- Parámetros no calculables geométricamente → ESTIMAR + MARCAR como estimado + JUSTIFICAR

---

## Arquitectura del Proyecto

→ Detalles completos en `references/architecture.md`

**Stack obligatorio:**
- Flutter (Android + iOS)
- Clean Architecture (domain / data / presentation)
- MVVM (ViewModels por pantalla)
- SOLID en cada capa
- Repository Pattern (abstracciones en domain, implementaciones en data)
- Dependency Injection (get_it)
- Offline First (SQLite, future cloud sync)
- API Ready (interfaces preparadas para REST/ERP/MES)

**Estructura de capas:**
```
lib/
  domain/          ← entities, use_cases, repositories (interfaces), value_objects
  data/            ← repositories (impl), datasources, models, mappers
  presentation/    ← screens, viewmodels, widgets
  services/        ← iso_engine, spc_engine, golden_sample, pdf, export
  core/            ← di, router, theme, constants, errors
```

---

## Motor ISO — Fuentes de datos por parámetro

→ Detalles completos en `references/iso-engine.md`

| Parámetro | Fuente | Fiabilidad |
|-----------|--------|-----------|
| Decodability | rawValue != null | EXACTO |
| Quiet Zones | corners + boundingBox | EXACTO |
| Symbol Contrast | imagen RGB (si disponible) | ESTIMADO si imagen mala |
| Modulation | imagen RGB | ESTIMADO |
| Defects | imagen RGB | ESTIMADO |
| Edge Contrast | imagen RGB | ESTIMADO |
| Min Reflectance | imagen RGB | ESTIMADO |
| Fixed Pattern Damage | corners geometry | ESTIMADO |
| Grid Nonuniformity | corners geometry | ESTIMADO |
| Axial Nonuniformity | corners geometry | ESTIMADO |
| Print Growth | imagen RGB | ESTIMADO |
| Unused Error Correction | rawValue + symbology | APROXIMADO |

**Regla:** Nunca inventar resultados. Si no se puede calcular con fiabilidad, marcar `isEstimated: true` en `GradeValue`.

---

## Modos de Operación

→ Detalles completos en `references/features.md`

### PRODUCCIÓN
- Operario → escanear → resultado inmediato (verde/rojo)
- Verde: A, B, C | Rojo: D, F
- Mostrar motivo principal
- No guardar automáticamente
- Continuar escaneando

### TÉCNICO
- Imagen + código + tipo + norma + parámetros + notas + resultado + recomendaciones

### ORDEN DE FABRICACIÓN (OF)
- Entrada: solo Número OF + Usuario (desplegable desde configuración)
- Pantalla permanente de escaneo
- Cada lectura → analizar + añadir al histórico → mostrar lista inferior
- Sin límite de escaneos (operario decide cuándo finalizar)
- Al finalizar: PDF opcional
- Objetivo: control producción + detección desviaciones + degradación + medidas correctivas

### GOLDEN SAMPLE
- Guardar solo A y B
- Comparar automáticamente: Golden vs Actual vs Diferencia vs Estado
- Acciones recomendadas

### SPC
- Registrar tendencias
- Detectar degradaciones
- Avisar: cabezal, ribbon, temperatura, suciedad, alineación, mantenimiento
- Reglas SPC industriales (Nelson/Western Electric)

---

## Configuración

→ Detalles en `references/features.md`

**ELIMINAR:** empresa, usuarios y seguridad actuales
**MANTENER:** interfaz
**CORREGIR:** bug calidad mínima aceptable (debe poder modificarse y persistirse)
**AÑADIR:**
- Método de impresión: TTR, Sato, Zebra, Digital, Konica, OKI, Inkjet, CLS, Zhilian, Analógico, Offset, Serigrafía
- Este parámetro personaliza las recomendaciones ISO (p.ej. bajo contraste en TTR → subir energía)

**Gestión de Usuarios (nuevo sistema):**
- Simple: solo nombre del operario
- Alta / Edición / Baja
- Persistencia SQLite
- OF usa desplegable con estos usuarios

---

## Base de Datos

→ Detalles en `references/db-schema.md`

Tablas obligatorias:
- `users` (nombre, activo, timestamps)
- `work_orders` (OF, usuario, estado, timestamps)
- `scans` (OF_id?, user_id, barcode_data, iso_params, grades, image_path?)
- `golden_samples` (scan_id, symbology, parámetros, activo)
- `spc_data` (scan_id, work_order_id, control_chart_data)
- `config` (key/value, persistente)
- `print_method` (relacionado con config)

Preparada para: Cloud sync, ERP, MES, multiempresa, multidioma

---

## Informes y Exportaciones

- PDF: nunca automático, siempre opcional
- Contenido PDF: imagen + código + ISO + resultado + golden sample + recomendaciones + estado + firmas
- Exportar: PDF, CSV, Excel
- Compartir / guardar / imprimir

---

## Dashboard

- KPIs: número controles, media, peor, mejor
- Tendencias + SPC

---

## Reglas de Implementación

1. **Nunca simplificar funcionalidades críticas**
2. Si existe solución técnicamente superior, explicarla y adoptarla
3. Justificar todas las decisiones técnicas
4. Marcar estimaciones como `isEstimated: true`, nunca como valores exactos falsos
5. Arquitectura preparada para nuevas normas ISO sin rediseño
6. Escalabilidad: OCR, IA, ERP, MES, REST API, Cloud, GS1 avanzado, predicción, mantenimiento predictivo, multiempresa, multidioma

---

## Entregables Obligatorios (en este orden)

1. Arquitectura + casos de uso + modelo de dominio + BD
2. Wireframes + UX + UI + árbol del proyecto
3. Motor ISO + Motor Golden Sample + Motor SPC
4. Gestión OF + Gestión usuarios + Configuración
5. PDF + Dashboard + Roadmap + Plan de desarrollo
6. Código base + pruebas + validación + despliegue

---

## Referencias

- `references/iso-engine.md` — Diseño completo del motor ISO geométrico
- `references/architecture.md` — Clean Architecture + MVVM + estructura de carpetas
- `references/features.md` — Especificación detallada de todas las pantallas y modos
- `references/db-schema.md` — Esquema de base de datos completo
