# DataMart S.A.S. — Pipeline ETL con Apache Airflow

[English](README.md) | **Español**

## Primera plataforma de datos: de CSV operacionales a un Data Warehouse en PostgreSQL

Pipeline de extremo a extremo orquestado con **Apache Airflow 3.1.5** dentro de Docker: lee dos fuentes CSV de Kaggle con formatos distintos, las limpia y unifica, separa ventas de devoluciones, registra cada rechazo con su motivo y carga un **modelo estrella** en un PostgreSQL analítico, listo para responder las preguntas de negocio.

**Autor:** Vanessa Fontalvo Reniz · Ingeniera de Sistemas y Computación
**Módulo:** Ingeniería de Datos — Prueba de desempeño (Airflow + Data Warehouse)

> Todos los documentos de `docs/` están en inglés (principal, `*.md`) y en español (`*.es.md`): [decisiones técnicas](docs/technical_decisions.es.md), [exploración de datos](docs/data_exploration.es.md), [modelo de datos](docs/data_model.es.md) y [respuestas de negocio](docs/business_answers.es.md).

---

## Dónde está cada entregable

| Entregable (enunciado, sección 8) | Dónde |
|---|---|
| `docker-compose.yml` con todos los servicios | [`docker-compose.yml`](docker-compose.yml) |
| `.env.example` (el `.env` real está en `.gitignore`) | [`.env.example`](.env.example) |
| DAG y su código | [`dags/datamart_etl_dag.py`](dags/datamart_etl_dag.py) + [`include/datamart/`](include/datamart) |
| Scripts DDL | [`sql/ddl/`](sql/ddl) |
| Datos y seeds para correr desde cero | [`data/raw/`](data/raw) + [`seeds/`](seeds) |
| README: de clonar a datos verificados en menos de 10 minutos | Secciones [1](#1-inicio-rápido-menos-de-10-minutos) y [2](#2-verificación-paso-a-paso) |
| Decisiones técnicas (modelo, casos ambiguos, idempotencia) | [`docs/technical_decisions.es.md`](docs/technical_decisions.es.md) |
| Diagrama del modelo de datos | [`docs/data_model.png`](docs/data_model.png) (imagen), [`docs/data_model.es.md`](docs/data_model.es.md), [`docs/data_model.dbml`](docs/data_model.dbml) (dbdiagram.io) |
| Consultas SQL de validación, una por pregunta | [`sql/queries/`](sql/queries), con sus resultados en [`docs/business_answers.es.md`](docs/business_answers.es.md) |

---

## 1. Inicio rápido (menos de 10 minutos)

**Requisitos:** Docker Desktop (o Docker Engine + Compose v2) con al menos **4 GB de RAM**, Git y los puertos **8080** y **5433** libres. No hace falta instalar Python ni descargar nada de Kaggle: los datos vienen en el repositorio.

```bash
# 1. Clonar
git clone https://github.com/vanefRiwi/datamart-test.git
cd datamart-test

# 2. Crear el .env a partir del ejemplo (en Linux, además, tu UID)
cp .env.example .env
echo "AIRFLOW_UID=$(id -u)" >> .env     # solo Linux; omitir en Windows/macOS

# 3. Levantar todo (equivale a `docker-compose up -d` con Compose v1)
docker compose up -d
```

Ese único comando deja todo listo **sin pasos manuales**: crea el usuario admin, las Connections, las Variables y las tablas del repositorio analítico, y el DAG se ejecuta solo.

| Servicio | Qué hace | Acceso |
|---|---|---|
| `airflow-apiserver` | UI y API de Airflow | http://localhost:8080 (usuario y clave de `.env`, por defecto `admin` / `change_this_admin_password`) |
| `airflow-scheduler` | Detecta y ejecuta el DAG | — |
| `airflow-dag-processor` | Parsea los DAGs | — |
| `airflow-triggerer` | Tareas diferidas | — |
| `postgres-airflow` | Metadatos de Airflow (no es el repositorio analítico) | interno |
| `postgres-dwh` | Repositorio analítico con las tablas creadas al iniciar | `localhost:5433` |
| `airflow-init` | Migra metadatos, crea el admin, las **Connections** y las **Variables**, y termina | — |

**Tiempos esperados** (medidos desde un clon nuevo):

| Paso | Tiempo |
|---|---|
| Descarga de imágenes (solo la primera vez, unos 1,5 GB) | 2 a 5 min, según la conexión |
| `docker compose up -d` hasta que todos los servicios estén healthy | cerca de 1 min |
| Primera ejecución del DAG (arranca sola, el DAG nace activo) | cerca de 2 a 3 min |
| Verificaciones de la sección 2 | cerca de 2 min |

Para empezar de cero (borra las dos bases de datos): `docker compose down -v`.

---

## 2. Verificación paso a paso

Ejecuta estos comandos desde la carpeta del repositorio cuando `docker compose up -d` termine.

### 2.1 Todos los servicios están arriba

```bash
docker compose ps -a
```

Esperado: `airflow-apiserver`, `airflow-scheduler`, `airflow-dag-processor`, `airflow-triggerer`, `postgres-airflow` y `postgres-dwh` en `Up ... (healthy)`; `airflow-init` en `Exited (0)`. Si alguno dice `(health: starting)`, espera 30 segundos y repite.

El log del init muestra lo que creó:

```bash
docker compose logs airflow-init | tail -15
```

Esperado: `Connections: ['dwh_postgres', 'fs_datamart']`, las 5 Variables e `Init done.`

### 2.2 Las Connections están configuradas y funcionan

```bash
docker compose exec airflow-scheduler airflow connections get dwh_postgres -o yaml
docker compose exec airflow-scheduler airflow connections get fs_datamart -o yaml
```

Esperado: `dwh_postgres` con `conn_type: postgres`, `host: postgres-dwh`, `port: '5432'`, `schema: datamart_dwh` y el usuario de `.env`; `fs_datamart` con `conn_type: fs` y `path: /opt/airflow/data` dentro de `extra_dejson`.

Para comprobar que `dwh_postgres` de verdad llega al repositorio analítico, ejecuta la tarea del DAG que la usa (`airflow tasks test` corre una tarea sin registrar una ejecución del DAG):

```bash
docker compose exec airflow-scheduler airflow tasks test datamart_daily_etl create_dwh_tables
```

Esperado: el log muestra `Running 01_schemas.sql` ... `Running 04_staging_audit.sql` y termina con `new_state=success`.

Desde la UI: **Admin → Connections → `dwh_postgres` → Edit → Test** muestra `Connection successfully tested` (la prueba de conexiones está habilitada en `docker-compose.yml`).

| Connection | Tipo | Uso |
|---|---|---|
| `dwh_postgres` | postgres | Repositorio analítico (host `postgres-dwh`, credenciales tomadas de `.env`) |
| `fs_datamart` | fs | Carpeta `/opt/airflow/data` que vigilan los `FileSensor` |

### 2.3 Las Variables están inicializadas

```bash
docker compose exec airflow-scheduler bash -c 'for v in datamart_sales_file datamart_history_file datamart_source_timezone datamart_max_reject_ratio datamart_currency; do printf "%-26s %s\n" "$v" "$(airflow variables get $v)"; done'
```

Esperado:

```
datamart_sales_file        raw/data.csv
datamart_history_file      raw/online_retail.csv
datamart_source_timezone   Europe/London
datamart_max_reject_ratio  0.10
datamart_currency          GBP
```

También se ven en la UI en **Admin → Variables**.

| Variable | Valor inicial | Para qué |
|---|---|---|
| `datamart_sales_file` | `raw/data.csv` | Archivo diario de órdenes |
| `datamart_history_file` | `raw/online_retail.csv` | Historial extendido |
| `datamart_source_timezone` | `Europe/London` | Zona horaria de la fuente para convertir a UTC |
| `datamart_max_reject_ratio` | `0.10` | Umbral de calidad: si se rechaza más del 10 %, el DAG falla antes de cargar |
| `datamart_currency` | `GBP` | Moneda de los montos |

Se definen en [`airflow/init/variables.json`](airflow/init/variables.json) y las crea [`airflow/init/init_airflow.sh`](airflow/init/init_airflow.sh) en cada arranque.

### 2.4 Las tablas del repositorio analítico existen desde el arranque

```bash
docker compose exec postgres-dwh psql -U dwh_user -d datamart_dwh -c '\dt dwh.*' -c '\dt audit.*'
```

Esperado: 7 tablas en `dwh` (`dates_dim`, `products_dim`, `customers_dim`, `countries_dim`, `sales_fact`, `returns_fact`, `daily_product_revenue_agg`) y 2 en `audit` (`rejected_records`, `pipeline_runs`). Si en `.env` usas otro usuario distinto de `dwh_user`, cambia `-U` en cada comando `psql`.

### 2.5 El DAG terminó bien

```bash
docker compose exec airflow-scheduler airflow dags list-runs datamart_daily_etl
```

Esperado: una ejecución `scheduled__...` en estado `success` (mientras corre dice `running`; espera y repite). En la UI: **Dags → `datamart_daily_etl`**, todas las tareas en verde. Para correrlo otra vez a mano: ▶ en la UI o `docker compose exec airflow-scheduler airflow dags trigger datamart_daily_etl`.

### 2.6 Los datos llegaron al repositorio analítico

```bash
docker compose exec postgres-dwh psql -U dwh_user -d datamart_dwh -c "
SELECT 'sales_fact' AS tabla, COUNT(*) FROM dwh.sales_fact
UNION ALL SELECT 'returns_fact', COUNT(*) FROM dwh.returns_fact
UNION ALL SELECT 'daily_product_revenue_agg', COUNT(*) FROM dwh.daily_product_revenue_agg
UNION ALL SELECT 'products_dim', COUNT(*) FROM dwh.products_dim
UNION ALL SELECT 'customers_dim', COUNT(*) FROM dwh.customers_dim
UNION ALL SELECT 'rejected_records', COUNT(*) FROM audit.rejected_records;"

docker compose exec postgres-dwh psql -U dwh_user -d datamart_dwh -c "SELECT run_id, rows_sales_fact, rows_returns_fact, rows_rejected, status FROM audit.pipeline_runs;"
```

Esperado: **522.535** ventas, **10.004** devoluciones, **277.958** filas producto-día, **3.927** productos, **4.363** clientes (incluido ANONYMOUS) y **18.740** rechazos; una fila en `audit.pipeline_runs` por ejecución con estado `success`. Correr el DAG otra vez deja exactamente los mismos conteos (idempotencia).

### 2.7 Las consultas de negocio responden cada pregunta

```bash
for f in sql/queries/*.sql; do echo "== $f"; docker compose exec -T postgres-dwh psql -U dwh_user -d datamart_dwh < "$f"; done
```

La salida coincide con las tablas de [`docs/business_answers.es.md`](docs/business_answers.es.md). En Windows PowerShell, un archivo a la vez: `Get-Content sql/queries/q1_monthly_net_sales.sql | docker compose exec -T postgres-dwh psql -U dwh_user -d datamart_dwh`.

Desde DBeaver o Power BI: host `localhost`, puerto `5433`, base `datamart_dwh` y el usuario/clave de `.env`.

---

## 3. Fuentes de datos

| Fuente | Archivo | Filas | Problemas principales |
|---|---|---:|---|
| Ventas diarias (Kaggle `carrie1/ecommerce-data`) | `data/raw/data.csv` | 541.909 | Encoding ISO-8859-1, cantidades negativas, precios ≤ 0, 24,9 % sin cliente, códigos de servicio (POST, DOT...), duplicados |
| Historial (Kaggle `thedevastator/online-retail-transaction-dataset`) | `data/raw/online_retail.csv` | 541.909 | Columna `index` extra, CustomerID decimal (`17850.0`) y **mismo periodo y líneas** que la fuente diaria |

Los CSV están en `data/raw/` tal como vienen de Kaggle (45 y 50 MB). La exploración completa está en [`docs/data_exploration.es.md`](docs/data_exploration.es.md).

---

## 4. Diagrama del pipeline

```
                ┌───────────────────────── DAG datamart_daily_etl (@daily) ──────────────────────────┐
                │                                                                                    │
 data/raw/      │  prepare_tmp_dir (setup)                     create_dwh_tables                     │
 data.csv ──────┼─► wait_for_sales_file ───► extract_daily_sales ───┐                                │
 online_retail ─┼─► wait_for_history_file ─► extract_history ───────┼─► transform_and_merge          │
 seeds/*.csv ───┼──────────────────────────► extract_category_rules ┘            │                   │
                │                                                         check_quality              │
                │                                            ┌───────────────────┴──────────┐        │
                │                                       load_staging                load_rejections  │
                │                                            │                              │        │
                │                                     load_dimensions                       │        │
                │                              ┌─────────────┴─────────────┐                │        │
                │                       load_sales_fact            load_returns_fact        │        │
                │                              └─────────────┬─────────────┘                │        │
                │                                   build_daily_revenue                     │        │
                │                                            └──────────► validate_load ◄───┘        │
                │                                                               │                    │
                │                                                     cleanup_tmp (teardown)         │
                └────────────────────────────────────────────────────────────────────────────────────┘
                                                      │
                                                      ▼
                         PostgreSQL DWH: staging.* → dwh.* (estrella) + audit.*
```

| Tarea | Qué hace |
|---|---|
| `wait_for_*_file` | `FileSensor` (Connection `fs_datamart`) espera el CSV hasta 10 minutos, en modo `reschedule` |
| `extract_*` | Lee el CSV (detecta el encoding), lleva las columnas a un esquema común y guarda Parquet en `data/tmp/<run_id>/` |
| `extract_category_rules` | Lee la semilla de categorías (estrategia en lugar de la API opcional) |
| `transform_and_merge` | Normaliza códigos, clientes y países, pasa fechas a UTC, marca rechazos, deduplica entre fuentes y arma la dimensión producto |
| `check_quality` | Separa ventas y devoluciones y valida el contrato de datos y el umbral de rechazos |
| `load_staging` / `load_rejections` | `COPY` masivo a `staging.*` y al log `audit.rejected_records` |
| `load_dimensions` | Upsert de fechas, productos, clientes y países |
| `load_*_fact` | Delete-insert de `sales_fact` y `returns_fact` en una transacción |
| `build_daily_revenue` | Reconstruye bruto, devoluciones y neto por producto y día |
| `validate_load` | Chequeos SQL post-carga y registro en `audit.pipeline_runs` |
| `cleanup_tmp` | Borra los Parquet del run aunque algo falle |

Todas las tareas tienen `retries=2` con espera exponencial; el DAG tiene `max_active_runs=1` y `catchup=False`.

---

## 5. Proceso ETL

### Extract
Cada fuente se lee como texto (`dtype=str`) para no inferir tipos a ciegas. Si UTF-8 falla se reintenta con ISO-8859-1. Las columnas se renombran a un esquema común (`InvoiceNo`/`Invoice` → `invoice_no`, `UnitPrice`/`Price` → `unit_price`, `CustomerID`/`Customer ID` → `customer_id`) y se guarda el número de fila original para trazabilidad.

### Transform
1. Códigos en mayúsculas y sin espacios; descripciones sin espacios repetidos.
2. CustomerID como texto entero (`17850.0` → `17850`); vacío = cliente ANONYMOUS.
3. Fechas con formato explícito por fuente → `Europe/London` → **UTC**.
4. Países normalizados con `seeds/country_mapping.csv`.
5. Cada fila recibe un motivo de rechazo o queda válida (ver tabla en [decisiones técnicas](docs/technical_decisions.es.md#motivos-de-rechazo-se-evalúan-en-orden-gana-el-primero)).
6. `row_hash` = MD5 de la clave natural; duplicados dentro de cada fuente y entre fuentes (gana `data.csv`).
7. Nombre canónico (descripción más frecuente) y categoría por palabra clave.

### Validaciones
Contrato de datos antes de cargar (columnas, llaves únicas, nulos, precio y cantidad, cuadre de filas, umbral de rechazos) y chequeos SQL después de cargar.

### Load
`COPY` a tablas `staging` → upsert de dimensiones → delete-insert de hechos con JOIN a las dimensiones → agregado diario. Todo dentro de transacciones.

---

## 6. Modelo de datos

**Constelación de hechos** (dos estrellas): **dos hechos separados** (ventas y devoluciones) que comparten cuatro dimensiones, más un agregado diario de revenue neto.

```
               dates_dim          products_dim
                    │  ╲          ╱    │
                    │   sales_fact     │
 customers_dim ─────┼──╱          ╲────┼───── countries_dim
                    │   returns_fact   │
                    │  ╱          ╲    │
          daily_product_revenue_agg (id_date, id_product)
```

![Modelo de datos](docs/data_model.png)

- Diagrama completo: [`docs/data_model.png`](docs/data_model.png) (imagen de arriba), [`docs/data_model.es.md`](docs/data_model.es.md) (Mermaid, se dibuja en GitHub) y [`docs/data_model.dbml`](docs/data_model.dbml) (pégalo en [dbdiagram.io](https://dbdiagram.io/d) → Import para un diagrama interactivo).
- DDL: [`sql/ddl/`](sql/ddl). Corre al crear el contenedor (`docker-entrypoint-initdb.d`) y otra vez en la tarea `create_dwh_tables` (todo es `IF NOT EXISTS`).
- Por qué este diseño: [`docs/technical_decisions.es.md`](docs/technical_decisions.es.md#2-modelo-del-repositorio-analítico).

---

## 7. Decisiones técnicas y casos ambiguos

Resumen; la justificación completa, con cifras y alternativas descartadas, está en **[`docs/technical_decisions.es.md`](docs/technical_decisions.es.md)**.

| Caso | Decisión |
|---|---|
| Transacciones sin CustomerID (24,9 %) | Se incluyen con el cliente genérico `ANONYMOUS` (`id_customer = -1`): excluirlas borraría el 14,7 % del revenue |
| Descripciones distintas para un código | Nombre canónico = la más frecuente en mayúsculas; empate → la más reciente. Se guarda el número de variantes |
| Fuentes que se solapan | Clave natural compuesta normalizada; si la línea está en ambas, gana `data.csv` |
| Códigos POST, DOT, M, D, BANK CHARGES... | Rechazo `not_a_product_code` |
| Venta con precio ≤ 0 | Rechazo `non_positive_price` en `audit.rejected_records` |
| Categoría sin API | Semilla de reglas por palabra clave con prioridad (`seeds/category_rules.csv`) |
| Idempotencia | Transformación determinística + upsert de dimensiones + delete-insert de hechos + `row_hash` como PK. Probado: dos ejecuciones dan exactamente las mismas filas |

---

## 8. Preguntas de negocio

Una consulta por pregunta en [`sql/queries/`](sql/queries); respuestas con el resultado exacto de cada consulta en **[`docs/business_answers.es.md`](docs/business_answers.es.md)**.

| # | Pregunta | Consulta | Respuesta corta |
|---|---|---|---|
| 1 | Evolución mensual de ventas netas | `q1_monthly_net_sales.sql` | Pico en noviembre 2011 (neto 1.426.587,54); sep-nov = 34,97 % del bruto |
| 2 | Categorías por revenue y devoluciones | `q2_category_revenue_returns.sql` | Home = 59,79 % del bruto; Stationery la de mayor proporción de devolución (16,16 %) |
| 3 | Top 10 neto y top 10 tasa de devolución | `q3_top_products.sql` | #1 por neto: 22423 REGENCY CAKESTAND 3 TIER (164.459,49); #1 por tasa de devolución: 23843 (100,00 %) |
| 4 | Países y ticket promedio | `q4_country_avg_ticket.sql` | Reino Unido = 90,53 % de facturas; ticket más alto: Países Bajos (3.052,57) |
| 5 | Identificados vs. sin CustomerID | `q5_identified_vs_anonymous.sql` | Sin CustomerID: ticket 1.101,38 vs 474,77, 95,8 productos por factura |
| 6 | Descripciones inconsistentes y códigos únicos | `q6_inconsistent_descriptions.sql` | 3.927 códigos; 637 (16,22 %) inconsistentes |
| 7 | Recomendación al equipo de producto | `q7_product_recommendation.sql` | Dos pedidos cancelados = 51,68 % de todas las devoluciones → tope de cantidad por línea |

---

## 9. Desarrollo local con uv

El código del ETL se puede probar sin Docker. El entorno virtual se maneja con [uv](https://docs.astral.sh/uv/) y usa **las mismas versiones** que trae la imagen de Airflow 3.1.5 (pandas 2.1.4, SQLAlchemy 1.4.54, pyarrow 18.1.0).

```bash
uv sync                                        # crea .venv con dependencias y herramientas de desarrollo
uv run pytest                                  # pruebas de reglas de negocio (el test del DAG se omite sin Airflow)
uv run ruff check . && uv run ruff format --check .
uv run python scripts/explore_sources.py      # perfil de las dos fuentes
```

Airflow no se instala en el entorno local a propósito: es pesado y ya corre en Docker. Por eso la lógica vive en `include/datamart/` (pandas + SQL puros) y el DAG solo orquesta.

---

## 10. Estructura del repositorio

```
datamart-test/
├── docker-compose.yml          # Airflow 3.1.5 + Postgres de metadatos + Postgres DWH
├── .env.example                # Variables de entorno necesarias (el .env real está en .gitignore)
├── pyproject.toml / uv.lock    # Entorno local con uv
├── airflow/init/
│   ├── init_airflow.sh         # Connections + Variables al arrancar
│   └── variables.json          # Valores iniciales de las Airflow Variables
├── dags/
│   └── datamart_etl_dag.py     # Orquestación (solo define tareas y dependencias)
├── include/datamart/           # Lógica del ETL
│   ├── config.py               # Rutas, ids de Airflow, reglas y motivos de rechazo
│   ├── extract.py              # Lectura de CSV y semillas
│   ├── transform.py            # Limpieza, UTC, deduplicación, nombre canónico, categoría
│   ├── quality.py              # Ventas vs devoluciones y contrato de datos
│   ├── load.py                 # COPY, upserts, delete-insert, agregado y validación
│   └── log_utils.py            # Helpers de log
├── sql/
│   ├── ddl/                    # Esquemas y tablas (se ejecutan al iniciar el DWH)
│   └── queries/                # Una consulta por pregunta de negocio
├── seeds/                      # Reglas de categoría y mapeo de países
├── data/raw/                   # Fuentes CSV de Kaggle
├── docs/                       # Decisiones, exploración, modelo y respuestas (EN + ES)
├── scripts/explore_sources.py  # Exploración de datos
├── tests/                      # Pruebas con pytest
├── config/ logs/ plugins/      # Carpetas que monta Airflow
└── README.md / README.es.md   # Documentación en inglés y en español
```

---

## 11. Solución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| `airflow-init` falla con `Permission denied` en `logs/` (Linux) | UID distinto al de la imagen | `echo "AIRFLOW_UID=$(id -u)" >> .env` y `docker compose up -d` |
| `Define DWH_PASSWORD in .env` al levantar | No existe `.env` | `cp .env.example .env` |
| Las tablas del DWH no se crean | El volumen ya existía de una ejecución anterior | `docker compose down -v` y levantar de nuevo (igual la tarea `create_dwh_tables` las crea) |
| La tarea `transform_and_merge` se queda sin memoria | Docker con poca RAM | Asignar al menos 4 GB a Docker |
| `airflow-init` falla con `set: pipefail: invalid option name` o `$'\r': command not found` (Windows) | El repositorio se clonó con finales de línea CRLF | Con `.gitattributes` ya no pasa en un clon nuevo. En una copia existente: `git rm -r --cached . -q` y `git reset --hard` (descarta cambios locales sin commit) y luego `docker compose up -d` |
| El DAG falla después de actualizar el repositorio (nombres de Variables, tablas o valores cambiaron) | La base de metadatos y el DWH conservan datos de la versión anterior | `docker compose down -v` y `docker compose up -d` para empezar de cero |
| El puerto 5433 u 8080 está ocupado | Otro servicio local | Cambiar `DWH_HOST_PORT` en `.env` o el puerto del api-server en el compose |
