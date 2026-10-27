# Technical decisions

**English** | [Español](technical_decisions.es.md)

This document explains **how the analytical warehouse was designed and why**, how each ambiguous case in the brief was resolved and how the DAG stays idempotent. The numbers are the real ones obtained by running the pipeline on the Kaggle files included in `data/raw/`.

**Map to the assignment (section 8, technical decisions document):**

| The assignment asks for | Section |
|---|---|
| How the analytical model was designed and why | [2. Analytical warehouse model](#2-analytical-warehouse-model) (diagram: [`data_model.png`](data_model.png)) |
| How the business rules of section 5 were applied | [3. Business rules](#3-business-rules-how-each-one-was-implemented) |
| Ambiguous case: transactions without customer ID | [4.1](#41-transactions-without-customerid) |
| Ambiguous case: different descriptions for one code | [4.2](#42-different-descriptions-for-the-same-code) |
| Ambiguous case: overlap and duplicates between sources | [4.3](#43-overlap-and-duplicates-between-the-two-sources) |
| How the DAG stays idempotent | [5. DAG idempotency](#5-dag-idempotency) |
| What was left pending and how it would be solved | [7. Pending work](#7-pending-work-and-how-i-would-do-it) |

---

## 1. Overall architecture

```
data/raw/*.csv ──► FileSensor ──► extraction (Parquet per run in data/tmp/<run_id>/)
                                       │
seeds/*.csv ──────────────────────────►│ transformation + merge + quality
                                       ▼
                     PostgreSQL DWH (postgres-dwh container)
                     ├── staging.*  landing tables (bulk COPY)
                     ├── dwh.*      star schema queried by the business
                     └── audit.*    rejections and run log
```

| Decision | Discarded alternative | Why |
|---|---|---|
| Airflow **3.1.5** with LocalExecutor | CeleryExecutor | A single node doesn't need Redis or workers; fewer containers and a faster start. |
| Two separate PostgreSQL instances (`postgres-airflow` and `postgres-dwh`) | One Postgres with two databases | The brief asks for it, and it isolates Airflow's metadata from the analytical load. |
| Official `apache/airflow:3.1.5` image without a `Dockerfile` | Extending the image | pandas 2.1.4, pyarrow, SQLAlchemy and the Postgres provider already ship with the image; nothing to install. |
| ETL package in `include/datamart` + `PYTHONPATH` | Code inside `dags/` | In Airflow 3 the `dags/` folder is not on the `sys.path` of every component; this way the DAG only orchestrates and the logic is tested without Airflow. |
| Tasks pass **Parquet paths** through XCom | Passing DataFrames through XCom | XCom stores JSON in the metadata database; it is not made for a million rows. |
| Load with `COPY` into `staging`, then `INSERT ... SELECT` | pandas `to_sql` | `COPY` loads 522 thousand rows in seconds, and Postgres resolves the joins with the dimensions. |
| Credentials only in `.env` → Connection `dwh_postgres` | Credentials in the code | Required by the brief; the DAG only knows the `conn_id`. |

---

## 2. Analytical warehouse model

**Star schema with two separate facts (sales and returns) that share dimensions, plus a daily aggregate.** The diagram is in [`data_model.md`](data_model.md) (Mermaid) and [`data_model.dbml`](data_model.dbml) (to import into dbdiagram.io).

| Table | Grain | Purpose |
|---|---|---|
| `dwh.dates_dim` | One day | Group by year, month, quarter, weekday. Key `id_date` = `YYYYMMDD`. |
| `dwh.products_dim` | One `stock_code` | Canonical name, category and number of description variants. |
| `dwh.customers_dim` | One customer | `id_customer = -1` is the generic **ANONYMOUS** customer. |
| `dwh.countries_dim` | One normalized country | EIRE → Ireland, RSA → South Africa, Unspecified → Unknown. |
| `dwh.sales_fact` | One invoice line with quantity > 0 | Gross revenue (`gross_revenue = quantity × unit_price`). |
| `dwh.returns_fact` | One line with quantity ≤ 0 | Returns and adjustments as positive numbers (`quantity_returned`, `return_amount`) and their type. |
| `dwh.daily_product_revenue_agg` | Product × day | Gross, returns and **net** per code and day (business rule). |
| `audit.rejected_records` | One rejected row | Source, original row, reason and raw record as JSONB. |
| `audit.pipeline_runs` | One DAG run | Rows read, valid, rejected, duplicated and status. |

### Why two fact tables instead of one with a sign?

- The business rule says returns **are not sales** and must be **kept apart**: with two tables nobody can add a return as a sale by mistake.
- Each fact has its own `CHECK` constraints (`quantity > 0` and `unit_price > 0` on sales; values ≥ 0 on returns).
- Since they share dimensions, net revenue is computed by subtracting per product, day, country or customer.

### Why a materialized daily aggregate?

The business rule defines net revenue as *"gross revenue after applying the return adjustments of the same product code in the same daily period"*. That is exactly the grain of `daily_product_revenue_agg`, which also has a `CHECK (net_revenue = gross_revenue - returns_amount)`. The monthly questions add up this table (277,958 rows) instead of scanning more than half a million lines.

> **Known limitation.** Many returns happen on a different day than the sale, so a product's daily net can be negative. That is why the business answers are read at monthly or total level, where the sale and its return fall in the same period.

### Other model decisions

- **`row_hash` as the primary key of the facts**: MD5 of the natural key (invoice, code, quantity, price, UTC date to the minute, customer). It doesn't depend on a sequence, so two runs leave identical rows, and the database rejects any duplicate.
- **Dates**: `invoice_ts_utc` (`TIMESTAMPTZ`) in the facts and `id_date` computed on the UTC date.
- **Money**: `NUMERIC(12,3)` for the price (some prices have 3 decimals) and `NUMERIC(14,2)` for amounts. Currency in a `currency` column (Variable `datamart_currency` = `GBP`).
- **Named constraints**: `fk_fact_*`, `uq_*`, `ck_*_positive`, so a load error says which rule was broken.

---

## 3. Business rules: how each one was implemented

| Rule | Implementation | Where |
|---|---|---|
| Quantity ≤ 0 is a return or adjustment | Goes to `returns_fact` as an absolute value. `return_type = cancellation` if the invoice starts with `C` (8,668), `adjustment` otherwise (1,336: damage, stock). | `quality.split_sales_returns` |
| Price ≤ 0 is not a valid sale | Rejected with reason `non_positive_price` in `audit.rejected_records` (1,161 per source). A return with price 0 is accepted (stock adjustment with no value). | `transform.normalize_source` |
| Dates in UTC | Explicit format per source, localized to `Europe/London` (Variable) and converted to UTC. At the October clock change standard time is assumed; in March the non-existent hour is shifted forward. | `transform.to_utc` |
| Codes in uppercase without spaces | `upper()` + removing every space before any join (`85123a ` → `85123A`). | `transform.normalize_code` |
| Gross and net revenue | Gross per line in `sales_fact`; net per code and day in `daily_product_revenue_agg`. | `load.build_daily_revenue` |

### Rejection reasons (evaluated in order, the first one wins)

| Order | Reason | Rule | Rows per source |
|---|---|---|---|
| 1 | `required_field_null` | Missing invoice, code, quantity or price | 0 |
| 2 | `invalid_date` | No date format can parse it | 0 |
| 3 | `not_a_product_code` | The code doesn't follow the catalog pattern (5 digits + suffix, or `DCGS…`) | 2,950 |
| 4 | `non_positive_price` | Sale with price ≤ 0 | 1,161 |
| 5 | `negative_price_on_return` | Return with a negative price | 0 |
| 6 | `duplicate_in_source` | Same natural key repeated inside the same file | 5,259 |

Total rejected: **18,740 rows out of 1,083,818 read (1.73 %)**. If the share goes above the Variable `datamart_max_reject_ratio` (10 %), the `check_quality` task fails and nothing is loaded.

### Where to change each decision

Every rule lives in one place, so changing it is a one-line edit:

| To change | Edit |
|---|---|
| Which codes count as products | `PRODUCT_CODE_PATTERN` in `include/datamart/config.py` |
| The anonymous customer id or code | `ANONYMOUS_CUSTOMER_ID` / `ANONYMOUS_CUSTOMER_CODE` in `config.py` (and the seed row in `sql/ddl/02_dimensions.sql`) |
| The rejection threshold, source timezone, currency or file names | Airflow Variables (`airflow/init/variables.json` or Admin → Variables), no code change |
| Product categories | `seeds/category_rules.csv` (keyword, category, priority) |
| Country aliases | `seeds/country_mapping.csv` |
| The period used for net revenue | `SQL_DAILY_AGG` in `include/datamart/load.py` (grain `id_date`, `id_product`) |

---

## 4. Ambiguous cases and how they were resolved

### 4.1 Transactions without CustomerID

- **Finding:** 135,080 rows (24.93 %) of `data.csv` have no customer.
- **Decision:** they are **included** and assigned to the generic customer `id_customer = -1` (`ANONYMOUS`, `is_identified = false`).
- **Why:** dropping them would remove **14.74 % of gross revenue** (1,509,991.68 GBP). Including them with an explicit customer keeps the real sale and allows comparing identified against anonymous buyers (question 5).
- **Impact:** any per-customer analysis must filter `id_customer <> -1`; the unique-customer queries already do.

### 4.2 Different descriptions for the same code

- **Finding:** 645 codes arrive with more than one way of writing the description (`Candle Holder White`, `CANDLE HOLDER WHITE`, or texts such as `damaged`, `check`, `?` on adjustments). 637 of them are product codes that reach the warehouse (question 6).
- **Decision:** canonical name = **the most frequent description** of the code, uppercased and with normalized spaces. On a tie the **most recent** wins, then alphabetical order.
- **Why:** it is a deterministic rule (same result on every run) and the most used description is the catalog one, not the manual adjustment note.
- **Traceability:** `products_dim.description_variants` stores how many different spellings arrived (also counting rejected rows), which answers question 6.

### 4.3 Overlap and duplicates between the two sources

- **Finding:** the history file provided (`online_retail.csv`) covers the **same period** as `data.csv` (2010-12-01 to 2011-12-09) and contains **the same lines** in another format: an extra `index` column and `CustomerID` as a decimal (`17850.0`). The 536,480 unique invoice-code-quantity-date combinations are in both.
- **Decision:** the real duplicate is detected with a normalized **composite key** (invoice, code, quantity, price, UTC date to the minute, customer) and **`data.csv` takes priority**: the history only adds the lines that are not in the daily dump.
- **Why:** the daily dump is the current operational system. The description is not part of the key because it is precisely the field that changes format.
- **Impact:** the 532,539 valid history lines are recognized as duplicates and not loaded twice (they are logged in `audit.pipeline_runs.duplicates_cross_source`, not in the rejection log, because they are not bad data). If the `online_retail_II.csv` with 2009-2010 arrives tomorrow, those lines would be loaded with `source_system = history`: the extraction already recognizes its column names (`Invoice`, `Price`, `Customer ID`) and its ISO dates.

### 4.4 Codes that are not products

`POST`, `DOT`, `C2` (shipping), `M` (manual), `D` (discount), `S` (samples), `BANK CHARGES`, `AMAZONFEE`, `CRUK`, `PADS`, `B` and the `GIFT_0001_*` vouchers are not merchandise: they are rejected as `not_a_product_code` so they don't distort the product rankings. `DCGS…` codes are kept because they are gift sets sold as products.

### 4.5 Product category without the API

The optional API was not built. The strategy is a **rules seed** (`seeds/category_rules.csv`) with keyword, category and priority: the rule with the lowest priority that matches as a whole word in the canonical name wins (`T-LIGHT` with priority 0 wins over `LIGHT`, so a candle holder doesn't end up as Electronics). Anything that doesn't match stays `Uncategorized`. The rule lives in a versioned file that is easy to extend; if the API is built, only the `extract_category_rules` task changes.

### 4.6 Currency and countries

The whole dataset is in pounds (`GBP`); there is no data from Colombia, Mexico or Peru, so no conversion is done, but the currency is kept in a column for when others arrive. Country names are normalized with `seeds/country_mapping.csv`.

---

## 5. DAG idempotency

**Test performed:** the DAG was run twice in a row with the same files and an MD5 hash of every row of each table was compared. The result was **identical** (522,535 sales, 10,004 returns, 277,958 aggregate rows, same keys in the dimensions).

| Mechanism | How it works |
|---|---|
| Deterministic transform | Same inputs → same rows, same canonical name and same `row_hash`. No `now()` or random values in keys. |
| Dimensions with upsert | `UPDATE` of what changed and `INSERT ... WHERE NOT EXISTS` of what is new: surrogate keys don't change and sequences don't skip values. |
| Facts with delete-insert | In a single transaction the rows of the processed sources are deleted and inserted again from staging. If the inserted count doesn't match staging, it rolls back. |
| `row_hash` as PK | Second safety net: the database rejects any repeated line. |
| Aggregate and rejections | Rebuilt completely on every run. |
| `max_active_runs=1` | Two runs never write at the same time. |

> **About filtering by date.** The data is from 2010-2011 and the DAG runs with today's date, so filtering by `data_interval_start` would leave every run empty. Each run processes the full files in `data/raw` (the "daily dump"). In production the next step would be to process only the file of the day and delete-insert only that date range.

`audit.pipeline_runs` is the only table that changes between runs on purpose: it is a log (one row per `run_id`).

---

## 6. DAG robustness

- `retries=2` with exponential backoff (2 to 10 minutes) on every task.
- `FileSensor` in `reschedule` mode waits up to 10 minutes for the CSVs without holding an executor slot.
- `prepare_tmp_dir` is a **setup** task and `cleanup_tmp` a **teardown**: the run's Parquet files are always deleted, even if something fails, and that cleanup doesn't change the final state of the DAG.
- Data contract before loading (`quality.check_contract`): exact columns, unique keys, required fields, price and quantity rules, and the row balance `read = valid + rejected + cross-source duplicates`.
- Validation after loading (`load.validate_load`): DWH counts = staging, the aggregate matches the facts and there are no sales with price ≤ 0.

---

## 7. Pending work and how I would do it

| Pending | How I would do it |
|---|---|
| Products API (optional extra) | A FastAPI service in the compose file serving the same rules as `category_rules.csv`, an HTTP Connection `product_api` and a Variable `datamart_use_api` to choose the source in `extract_category_rules`. |
| Incremental daily load | A daily file with the date in its name (`ventas_{{ ds }}.csv`) and delete-insert of only the `data_interval_start`–`data_interval_end` range. |
| Category classification | 17 % of products (680 of 3,927) stay `Uncategorized`; this can be lowered by extending the seed or with the master catalog when it exists. |
| Returns that cross days | Link each cancellation to its original invoice (customer + code + price) for a net per sale and not only per day. |
| Alerts | `on_failure_callback` with a Slack or email notice. |
