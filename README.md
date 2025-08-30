# Esquema completo de base de datos (PostgreSQL)

Este repositorio contiene el “schema full” (esquema completo) de una base de datos PostgreSQL, incluyendo:
- Preámbulo y configuraciones recomendadas
- Esquema `public`
- Tipos ENUM
- Funciones y trigger functions
- Tablas
- Secuencias/DEFAULTs
- Constraints (PK/UK)
- Índices
- Triggers
- Claves foráneas (FK)
- Vistas
- Grants/ACL

La versión de PostgreSQL usada para el dump fue 17.5. El script está ordenado por dependencias para garantizar que se pueda ejecutar de principio a fin sin errores.

Nota: el script invoca `uuid_generate_v4()`. Asegúrate de tener la extensión:
```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

## ¿Qué es “schema full”?
“Schema full” significa que el archivo SQL incluye absolutamente toda la definición del esquema de la base de datos: tipos, funciones, tablas, restricciones, índices, triggers, claves foráneas, vistas y permisos. Es auto-contenido y reproducible.

## Contenido principal del modelo
- Usuarios, roles y permisos administrativos:
  - `users`, `user_roles`, `role_permissions`
- Suscripciones y claves:
  - `subscription_plans`, `subscription_keys`, `user_subscriptions`, `plan_command_access`
- Créditos y transacciones:
  - `user_credits`, `credit_transactions`
- Comandos, ejecuciones y estadísticas:
  - `commands`, `command_categories`, `command_configs`, `command_executions` (+ tablas mensuales heredadas 2025_01, 2025_02, 2025_03), `command_statistics`
- Moderación:
  - `user_bans`, `user_warnings`, `user_reports`, `user_history`
- Grupos:
  - `groups`
- Auditoría y registros del sistema:
  - `audit_log`, `service_health_logs`, `system_errors`, `webhook_logs`, `search_log`, `daily_statistics`, `global_statistics`
- BIN/Cards (bines, marcas, niveles, bancos, países) y scraping:
  - `bins`, `cards`, `card_brands`, `card_levels`, `banks`, `countries`, `scraping_log`, `app_cards`, `card_logs`
- Scamalytics (cache/análisis/consultas):
  - `scamalytics_cache`, `scamalytics_analysis`, `scamalytics_query_log`
- Proxy validations:
  - `proxy_validations`
- Vistas útiles:
  - `v_approved_cards`, `v_charged_cards`, `v_unprocessed_cards`

## Requisitos
- PostgreSQL 17.x (o compatible)
- Extensión `uuid-ossp` para `uuid_generate_v4()`:
  ```sql
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
  ```

## Cómo aplicar el esquema
1) Con psql:
```bash
psql "postgresql://usuario:password@host:puerto/base" -f db/schema_full.sql
```

2) Con Docker (ejemplo):
```bash
docker exec -i <contenedor-postgres> psql -U <usuario> -d <base> -f - < db/schema_full.sql
```

## Organización del archivo
El archivo `db/schema_full.sql` está estructurado por dependencias:
- Primero: schema, tipos, funciones
- Luego: tablas y secuencias/defaults
- Después: constraints, índices, triggers, claves foráneas y vistas
- Finalmente: grants/ACL

Esto asegura que el script se ejecute de forma idempotente y sin errores por dependencia.

## Notas
- Hay tipos ENUM “duplicados” (por ejemplo `admin_role` y `adminrole`) para compatibilidad. Se mantienen tal como están en el dump original.
- Existen tablas heredadas por mes para `command_executions` (p.ej. `command_executions_2025_01`, `command_executions_2025_02`, `command_executions_2025_03`) para particionar por tiempo.
- Se incluyen triggers de auditoría genéricos para múltiples tablas.

## Licencia
Este esquema se provee tal cual. Adapta a tus necesidades y valida en tu entorno.