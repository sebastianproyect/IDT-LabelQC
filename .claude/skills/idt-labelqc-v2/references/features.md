# Especificación de Funcionalidades — IDT LabelQC v2

## MODO PRODUCCIÓN

### Objetivo
Operario en planta: escanear rápido, resultado inmediato, continuar.

### Flujo
1. Abrir pantalla → cámara activa automáticamente
2. Apuntar al código → detección automática
3. Resultado inmediato:
   - **VERDE** (A, B, C): `✓ OK — APROBADO` + grado + motivo principal
   - **ROJO** (D, F): `✗ NO OK — RECHAZADO` + grado + motivo principal
4. Botón "Continuar" → listo para siguiente escaneo
5. Botón "Detalle" (ícono lupa) → navegar a resultado técnico
6. No guardar automáticamente en DB
7. Sin límite de tiempo en resultado

### Pantalla
- Fondo negro (cámara)
- Badge superior: `PRODUCCIÓN` (verde)
- Overlay de encuadre: guías de escaneo animadas
- Resultado: overlay de pantalla completa con animación entrada
- Botón linterna
- Botón volver

### UX Industrial
- Letras grandes (legible con guantes, distancia)
- Colores de alto contraste
- Vibración háptica: ligero para OK, fuerte para NOK
- Sin texto pequeño en resultado principal

---

## MODO TÉCNICO

### Objetivo
Técnico/calidad: análisis completo ISO con todos los parámetros.

### Pantalla de escaneo
- Igual que producción pero badge `TÉCNICO` (azul/cian)
- Indicador "Análisis ISO completo..." durante procesamiento

### Pantalla de resultado técnico
Mostrar:
- Imagen capturada (si disponible) o placeholder con ícono código
- Código decodificado + tipo simbología + norma aplicada
- Grado global (badge grande con color)
- Tabla de parámetros ISO:
  - Nombre parámetro
  - Medida + unidad
  - Grado individual (color)
  - Indicador `~est.` si `isEstimated: true`
- Recomendaciones (basadas en método de impresión configurado)
- Botones: Generar PDF, Guardar, Comparar Patrón, Nuevo escaneo

### Indicadores de estimación
- Valores estimados: mostrar `~` prefijo + tooltip explicativo
- Si >50% estimados: banner amarillo "Análisis parcial — acercar cámara al código"
- En PDF: nota al pie listando parámetros estimados

---

## MODO ORDEN DE FABRICACIÓN (OF)

**Este módulo reemplaza completamente la implementación anterior.**

### Creación de OF
Pantalla mínima, solo dos campos:
1. **Número OF:** entrada de texto manual + botón cámara (leer QR/barcode)
2. **Usuario:** desplegable con lista de operarios desde Gestión de Usuarios
3. Botón "Crear OF"

Sin campos adicionales en la creación (no cliente, no máquina, no producto al inicio).

### Pantalla permanente de escaneo OF

Una vez creada la OF:
- **Pantalla permanente** — el operario NO sale de aquí durante la producción
- Zona superior: cámara activa + guías de encuadre
- Zona inferior: lista scrollable de escáneres realizados
- Cada item de la lista muestra: timestamp + grado + código + estado (OK/NOK)
- **Sin límite de escaneos** — continúa hasta que el operario pulse "Finalizar"
- Cada escaneo: analizar → añadir al histórico → mostrar en lista → cámara lista para siguiente
- Actualización en tiempo real de KPIs de la OF en la barra superior:
  - Total escaneados
  - % OK
  - Peor grado
  - Tendencia (flecha arriba/abajo/estable)

### Cierre de OF
Al pulsar "Finalizar":
1. Resumen de la OF:
   - Total escaneados
   - Distribución de grados (A/B/C/D/F con barras)
   - Tendencia de calidad (gráfico simple)
   - Alertas SPC si se detectaron
2. Opción: Generar PDF → compartir/guardar
3. Botón: Cerrar OF

### Objetivo funcional
- Control de producción en tiempo real
- Detección temprana de degradación (cabezal, ribbon, temperatura)
- Trazabilidad completa de la producción
- Base de datos para SPC

---

## GOLDEN SAMPLE

### Qué es
Una referencia de calidad aceptada. Se guarda un escaneo de un código de alta calidad (A o B) como muestra patrón para comparar futuros escaneos.

### Guardar Golden Sample
- Solo se puede guardar si grado es A o B
- Asociado a: simbología + (opcionalmente) valor del código
- Se guardan: parámetros ISO, imagen, timestamp, usuario

### Comparar con Golden Sample
En modo Técnico, si existe golden sample para esa simbología:
- Sección adicional en resultado: "Comparación Golden Sample"
- Tabla: Parámetro | Golden | Actual | Diferencia | Estado
- Estado: Verde (dentro de tolerancia) / Amarillo (desviación leve) / Rojo (fuera de tolerancia)
- Acciones recomendadas según desviaciones

### Gestión de Golden Samples
- Pantalla de lista de golden samples guardados
- Filtro por simbología
- Activar/desactivar cada muestra
- Ver detalle completo
- Eliminar

---

## SPC (Control Estadístico de Proceso)

### Objetivo
Detectar tendencias y degradaciones antes de que el proceso produzca códigos inaceptables.

### Datos de entrada
- Histórico de escáneres de OF
- Parámetros ISO por escaneo
- Timestamps

### Gráficos de control
- X-bar chart: media de Symbol Contrast por OF
- R chart: rango (variabilidad)
- Individual (I) chart: por escaneo individual

### Reglas de detección (Nelson / Western Electric)
1. Un punto fuera de 3σ → **ALARMA CRÍTICA**
2. 9 puntos consecutivos del mismo lado de la media → tendencia
3. 6 puntos consecutivos crecientes o decrecientes → degradación
4. 2 de 3 puntos entre 2σ y 3σ → warning
5. 4 de 5 puntos entre 1σ y 2σ → alerta temprana

### Alertas y recomendaciones
Las alertas SPC se mapean a causas físicas según el método de impresión configurado:

| Alerta | TTR | Digital | Inkjet | Offset |
|--------|-----|---------|--------|--------|
| Contraste bajando | Energía baja, ribbon agotado | Tóner bajo | Cabezales obstruidos | Tinta insuficiente |
| Variabilidad alta | Temperatura inestable | Fusor defectuoso | Presión variable | Viscosidad tinta |
| Tendencia descendente | Revisar cabezal | Mantenimiento | Limpiar cabezales | Revisar rodillos |
| Spike aislado | Suciedad en cabezal | Papel atascado | Burbuja de aire | Contaminación |

### Integración
- SPC se calcula automáticamente al cerrar una OF con ≥10 escáneres
- Dashboard muestra últimas alertas SPC activas
- En modo OF: indicador de tendencia en tiempo real

---

## CONFIGURACIÓN (Rediseñada)

### ELIMINAR
- ~~Datos de empresa~~ (eliminado)
- ~~Sistema de usuarios con roles complejo~~ (reemplazado)

### MANTENER
- Tema de interfaz (oscuro por defecto)
- Idioma (preparado, español por defecto)

### CORREGIR
- **Bug calidad mínima aceptable:** el valor del umbral (actualmente hardcoded) debe:
  - Ser modificable desde configuración
  - Persistir en SQLite (`config` table, key: `min_acceptable_grade`)
  - Default: Grade C (2.0)
  - Rango: F (0.0) — A (4.0)
  - Afectar a: producción (verde/rojo), OF (OK/NOK), SPC (línea de control)

### AÑADIR: Método de Impresión
Selector de método de impresión activo:
- TTR (Transferencia Térmica)
- Sato (impresora específica)
- Zebra (impresora específica)
- Digital (tóner/láser)
- Konica
- OKI
- Inkjet (chorro de tinta)
- CLS
- Zhilian
- Analógico
- Offset
- Serigrafía

Este parámetro personaliza:
- Recomendaciones en resultado técnico
- Texto de alertas SPC
- Acciones sugeridas en Golden Sample

### AÑADIR: Gestión de Usuarios (nuevo sistema simple)
Ver sección siguiente.

---

## GESTIÓN DE USUARIOS (Sistema Nuevo)

**Reemplaza completamente el sistema anterior.**

### Concepto
Sistema simple. Solo nombres de operarios. Sin roles, sin contraseñas, sin empresa.
El objetivo es identificar quién hizo cada escaneo/OF para trazabilidad.

### Campos del usuario
- `id` (UUID, generado automáticamente)
- `name` (nombre del operario, obligatorio, único)
- `active` (boolean, default true)
- `created_at` (timestamp)

### Pantalla de gestión
- Lista de usuarios activos
- Botón añadir usuario: solo pedir nombre
- Swipe para desactivar/eliminar
- Editar nombre (tap)
- Sin contraseñas, sin roles

### Uso en la app
- Desplegable en creación de OF
- Mostrado en resultados y PDF para trazabilidad
- Filtro en dashboard y exportaciones

---

## DASHBOARD

### KPIs principales
- Total controles (hoy / semana / mes)
- % OK (controles aceptables / total)
- Grado medio (numérico)
- Peor grado registrado
- Mejor grado registrado

### Gráficos
- Tendencia de calidad (línea temporal)
- Distribución de grados (barras A/B/C/D/F)
- Top simbologías escaneadas
- Alertas SPC activas

### Filtros
- Por fecha
- Por usuario
- Por simbología
- Por OF

---

## INFORMES Y EXPORTACIÓN

### PDF (nunca automático)
Contenido:
1. Encabezado: fecha, usuario, OF (si aplica)
2. Imagen del código (si disponible)
3. Código decodificado + simbología + norma
4. Resultado global (grade + color)
5. Tabla de parámetros ISO (con indicador estimación)
6. Comparación Golden Sample (si aplica)
7. Recomendaciones
8. Histórico de OF (si es informe de OF)
9. Tendencia SPC (si aplica)
10. Estado final: APROBADO / RECHAZADO
11. Espacio para firmas

### CSV / Excel
- Exportar histórico de escaneos
- Columnas: timestamp, usuario, OF, simbología, grado_global, SC, MOD, DEF, ...
- Filtros aplicables

### Compartir
- `share_plus` → WhatsApp, email, Google Drive, etc.
- Imprimir directo desde app

---

## ROADMAP FUTURO (documentado en arquitectura, no implementar ahora)

1. **v1.0:** Motor geométrico ISO + OF mejorada + Golden Sample básico + Config nueva
2. **v1.1:** SPC completo + Dashboard mejorado + PDF completo
3. **v2.0:** Cloud sync + API REST + multiusuario avanzado
4. **v3.0:** Motor ISO con imagen RGB + ML/IA + integración ERP/MES
5. **v4.0:** Motor ISO hardware externo + OCR + GS1 avanzado + predicción
