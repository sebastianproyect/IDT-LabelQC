# Base de Datos — IDT LabelQC v2

## Principios
- SQLite como fuente de verdad (Offline First)
- Esquema preparado para Cloud Sync (columnas `synced`, `server_id`)
- Preparado para ERP/MES (campos de trazabilidad)
- Migraciones controladas con versión de BD

---

## Tablas

### `users`
```sql
CREATE TABLE users (
  id          TEXT PRIMARY KEY,       -- UUID
  name        TEXT NOT NULL UNIQUE,   -- nombre del operario
  active      INTEGER NOT NULL DEFAULT 1,
  created_at  INTEGER NOT NULL,       -- Unix timestamp ms
  updated_at  INTEGER NOT NULL,
  synced      INTEGER NOT NULL DEFAULT 0,
  server_id   TEXT
);
```

### `work_orders`
```sql
CREATE TABLE work_orders (
  id              TEXT PRIMARY KEY,
  order_number    TEXT NOT NULL,
  user_id         TEXT NOT NULL REFERENCES users(id),
  user_name       TEXT NOT NULL,       -- desnormalizado para trazabilidad
  status          TEXT NOT NULL,       -- 'active' | 'closed'
  start_date      INTEGER NOT NULL,
  end_date        INTEGER,
  total_scans     INTEGER NOT NULL DEFAULT 0,
  ok_scans        INTEGER NOT NULL DEFAULT 0,
  nok_scans       INTEGER NOT NULL DEFAULT 0,
  notes           TEXT,
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  synced          INTEGER NOT NULL DEFAULT 0,
  server_id       TEXT
);
```

### `scans`
```sql
CREATE TABLE scans (
  id                    TEXT PRIMARY KEY,
  work_order_id         TEXT REFERENCES work_orders(id),  -- nullable (modo libre)
  user_id               TEXT REFERENCES users(id),
  user_name             TEXT,
  timestamp             INTEGER NOT NULL,
  symbology             TEXT NOT NULL,    -- 'ean13' | 'qrCode' | 'code128' | ...
  decoded_value         TEXT NOT NULL,
  standard              TEXT NOT NULL,    -- 'ISO 15416' | 'ISO 15415'
  overall_grade         TEXT NOT NULL,    -- 'A' | 'B' | 'C' | 'D' | 'F'
  overall_numeric       REAL NOT NULL,    -- 4.0 | 3.0 | 2.0 | 1.0 | 0.0
  is_acceptable         INTEGER NOT NULL, -- 1 si grade >= min_acceptable
  capture_mode          TEXT NOT NULL,    -- 'production' | 'technical' | 'work_order'
  image_path            TEXT,             -- ruta local al archivo de imagen (opcional)
  -- Parámetros ISO (todos nullable, con flag de estimación)
  sc_value              REAL,
  sc_grade              TEXT,
  sc_estimated          INTEGER DEFAULT 0,
  mr_value              REAL,
  mr_grade              TEXT,
  mr_estimated          INTEGER DEFAULT 0,
  ec_value              REAL,
  ec_grade              TEXT,
  ec_estimated          INTEGER DEFAULT 0,
  mod_value             REAL,
  mod_grade             TEXT,
  mod_estimated         INTEGER DEFAULT 0,
  def_value             REAL,
  def_grade             TEXT,
  def_estimated         INTEGER DEFAULT 0,
  dec_value             REAL,
  dec_grade             TEXT,
  dec_estimated         INTEGER DEFAULT 0,
  qz_value              REAL,
  qz_grade              TEXT,
  qz_estimated          INTEGER DEFAULT 0,
  fpd_value             REAL,
  fpd_grade             TEXT,
  fpd_estimated         INTEGER DEFAULT 0,
  gnu_value             REAL,
  gnu_grade             TEXT,
  gnu_estimated         INTEGER DEFAULT 0,
  anu_value             REAL,
  anu_grade             TEXT,
  anu_estimated         INTEGER DEFAULT 0,
  pg_value              REAL,
  pg_grade              TEXT,
  pg_estimated          INTEGER DEFAULT 0,
  uec_value             REAL,
  uec_grade             TEXT,
  uec_estimated         INTEGER DEFAULT 0,
  -- Geometría guardada para análisis posterior
  corners_json          TEXT,            -- JSON de List<Offset>
  bounding_box_json     TEXT,            -- JSON de Rect
  capture_width         REAL,
  capture_height        REAL,
  -- Recomendaciones
  recommendations_json  TEXT,            -- JSON de List<Recommendation>
  created_at            INTEGER NOT NULL,
  synced                INTEGER NOT NULL DEFAULT 0,
  server_id             TEXT
);
```

### `golden_samples`
```sql
CREATE TABLE golden_samples (
  id              TEXT PRIMARY KEY,
  scan_id         TEXT NOT NULL REFERENCES scans(id),
  symbology       TEXT NOT NULL,
  decoded_value   TEXT,              -- null = aplica a toda la simbología
  label           TEXT,              -- nombre descriptivo ej: "EAN-13 Producto A"
  overall_grade   TEXT NOT NULL,
  overall_numeric REAL NOT NULL,
  -- Parámetros de referencia (copiados del scan para independencia)
  parameters_json TEXT NOT NULL,     -- ISOParameters serializado
  image_path      TEXT,
  active          INTEGER NOT NULL DEFAULT 1,
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  synced          INTEGER NOT NULL DEFAULT 0,
  server_id       TEXT
);
```

### `spc_records`
```sql
CREATE TABLE spc_records (
  id                TEXT PRIMARY KEY,
  work_order_id     TEXT REFERENCES work_orders(id),
  calculated_at     INTEGER NOT NULL,
  sample_count      INTEGER NOT NULL,
  -- X-bar chart
  xbar_mean         REAL,
  xbar_ucl          REAL,            -- Upper Control Limit (3σ)
  xbar_lcl          REAL,            -- Lower Control Limit
  xbar_sigma        REAL,
  -- R chart
  r_mean            REAL,
  r_ucl             REAL,
  -- Violations (JSON array of rule violations)
  violations_json   TEXT,
  -- Trend data (JSON array of {scan_id, value, timestamp})
  trend_data_json   TEXT,
  parameter         TEXT NOT NULL,   -- qué parámetro se analizó ('sc', 'mod', 'overall')
  synced            INTEGER NOT NULL DEFAULT 0
);
```

### `config`
```sql
CREATE TABLE config (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL,
  updated_at  INTEGER NOT NULL
);
-- Valores predeterminados:
-- ('min_acceptable_grade', '2.0', ...)   ← Grade C
-- ('print_method', 'ttr', ...)
-- ('theme', 'dark', ...)
-- ('language', 'es', ...)
-- ('db_version', '2', ...)
```

---

## Índices para rendimiento

```sql
CREATE INDEX idx_scans_work_order ON scans(work_order_id);
CREATE INDEX idx_scans_timestamp ON scans(timestamp);
CREATE INDEX idx_scans_symbology ON scans(symbology);
CREATE INDEX idx_scans_grade ON scans(overall_grade);
CREATE INDEX idx_work_orders_status ON work_orders(status);
CREATE INDEX idx_work_orders_user ON work_orders(user_id);
CREATE INDEX idx_golden_samples_symbology ON golden_samples(symbology, active);
```

---

## Migraciones

```dart
// En AppDatabase.dart
static const int dbVersion = 2;

Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    // Migración v1 → v2: añadir columnas estimated, users, golden_samples, spc
    await db.execute('ALTER TABLE scans ADD COLUMN sc_estimated INTEGER DEFAULT 0');
    // ...
    await db.execute(createUsersTable);
    await db.execute(createGoldenSamplesTable);
    await db.execute(createSpcRecordsTable);
  }
}
```

---

## Preparación para Cloud Sync

Columnas `synced` (0 = pendiente, 1 = sincronizado) y `server_id` en todas las tablas.

Patrón de sync:
```dart
abstract class ISyncRepository {
  Future<List<Map<String, dynamic>>> getPendingSync();
  Future<void> markSynced(String id, String serverId);
  Future<void> pullUpdates(DateTime since);
}
```

Implementaciones futuras:
- `FirestoreSyncRepository`
- `RestAPISyncRepository`

---

## Preparación para ERP/MES

La tabla `scans` incluye `work_order_id` que puede mapearse a órdenes ERP.
Las columnas `server_id` permiten referenciar IDs externos.

```dart
abstract class IERPExporter {
  Future<void> exportScan(Scan scan);
  Future<void> exportWorkOrder(WorkOrder workOrder);
}
```

---

## Inicialización de datos

```dart
// Al crear la BD por primera vez:
Future<void> _seedInitialData(Database db) async {
  // Config por defecto
  await db.insert('config', {'key': 'min_acceptable_grade', 'value': '2.0', 'updated_at': now});
  await db.insert('config', {'key': 'print_method', 'value': 'ttr', 'updated_at': now});
  await db.insert('config', {'key': 'theme', 'value': 'dark', 'updated_at': now});
  await db.insert('config', {'key': 'language', 'value': 'es', 'updated_at': now});

  // Usuario admin por defecto (simple, sin contraseña)
  await db.insert('users', {
    'id': const Uuid().v4(),
    'name': 'Administrador',
    'active': 1,
    'created_at': now,
    'updated_at': now,
  });
}
```
