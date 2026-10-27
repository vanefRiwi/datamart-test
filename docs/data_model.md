# Analytical warehouse data model

**English** | [Español](data_model.es.md)

Dimensional model of the `dwh` schema in the analytical PostgreSQL. It has **two fact tables** (`sales_fact` and `returns_fact`) that share four **conformed dimensions** (`dates_dim`, `products_dim`, `customers_dim` and `countries_dim`), plus a product-day aggregate. That makes the full model a **fact constellation** (*galaxy schema*): each business process, seen on its own, is a star. Why it is designed this way: [technical decisions, section 2](technical_decisions.md#2-analytical-warehouse-model).

For the interactive version, import [`data_model.dbml`](data_model.dbml) at [dbdiagram.io](https://dbdiagram.io/d). The full DDL is in [`sql/ddl/`](../sql/ddl).

## Entity-relationship diagram

Each line is a one-to-many relationship: one dimension row relates to many fact rows. `rejected_records` and `pipeline_runs` (`audit` schema) have no relationships because they are for traceability, not analysis.

![Data model](data_model.png)

The same diagram in Mermaid (GitHub renders it; `data_model.png` was generated from it):

```mermaid
erDiagram
    dates_dim ||--o{ sales_fact : id_date
    products_dim ||--o{ sales_fact : id_product
    customers_dim ||--o{ sales_fact : id_customer
    countries_dim ||--o{ sales_fact : id_country
    dates_dim ||--o{ returns_fact : id_date
    products_dim ||--o{ returns_fact : id_product
    customers_dim ||--o{ returns_fact : id_customer
    countries_dim ||--o{ returns_fact : id_country
    dates_dim ||--o{ daily_product_revenue_agg : id_date
    products_dim ||--o{ daily_product_revenue_agg : id_product

    dates_dim {
        int id_date PK "YYYYMMDD"
        date full_date UK
        smallint year
        smallint quarter
        smallint month
        char year_month
        smallint day_of_week
        boolean is_weekend
    }
    products_dim {
        serial id_product PK
        varchar stock_code UK
        varchar product_description "canonical name"
        varchar category
        smallint description_variants
    }
    customers_dim {
        serial id_customer PK "-1 = ANONYMOUS"
        varchar customer_code UK
        boolean is_identified
    }
    countries_dim {
        serial id_country PK
        varchar country_name UK
    }
    sales_fact {
        char row_hash PK "MD5 of the natural key"
        varchar source_system
        varchar invoice_no
        timestamptz invoice_ts_utc
        int id_date FK
        int id_product FK
        int id_customer FK
        int id_country FK
        int quantity "greater than 0"
        numeric unit_price "greater than 0"
        numeric gross_revenue
        char currency
    }
    returns_fact {
        char row_hash PK
        varchar source_system
        varchar invoice_no
        varchar return_type "cancellation or adjustment"
        timestamptz invoice_ts_utc
        int id_date FK
        int id_product FK
        int id_customer FK
        int id_country FK
        int quantity_returned
        numeric unit_price
        numeric return_amount
        char currency
    }
    daily_product_revenue_agg {
        int id_date PK
        int id_product PK
        int units_sold
        numeric gross_revenue
        int units_returned
        numeric returns_amount
        numeric net_revenue "gross - returns"
    }
    rejected_records {
        varchar source_system PK "source and CSV row"
        int source_row PK
        varchar reason
        jsonb raw_record "original record"
        varchar run_id
    }
    pipeline_runs {
        varchar run_id PK
        timestamptz logical_date
        int rows_read_sales
        int rows_read_history
        int rows_valid
        int rows_rejected
        int duplicates_cross_source
        varchar status
    }
```

## Table dictionary

| Table | Grain (one row per...) | Analytical use |
|---|---|---|
| `dwh.dates_dim` | Calendar day | Filter and group by year, quarter, month or weekday. |
| `dwh.products_dim` | Product code (`stock_code`) | Analyze sales and returns by product and category; `description_variants` answers question 6. |
| `dwh.customers_dim` | Customer, plus the anonymous member | Compare identified customers with transactions without `CustomerID` (question 5). |
| `dwh.countries_dim` | Normalized country | Geographic distribution and ticket per country (question 4). |
| `dwh.sales_fact` | Valid invoice line with quantity > 0 | Units sold and gross revenue. |
| `dwh.returns_fact` | Return or adjustment line (quantity ≤ 0, stored as positive) | Units and amounts returned, by type. |
| `dwh.daily_product_revenue_agg` | Product + day combination | Gross, returns and net (questions 1, 2, 3 and 7). |

> **Conventions:** `id_date` is a `YYYYMMDD` integer computed on the UTC date; `customers_dim.id_customer = -1` is `ANONYMOUS`; amounts are in GBP (`currency` column); `row_hash` is the MD5 of the line's natural key and the primary key of the facts, so it identifies each row deterministically across runs.

## Constraints that enforce the model

Every line in the diagram is a physical `FOREIGN KEY` in [`sql/ddl/03_facts.sql`](../sql/ddl/03_facts.sql):

| Table | Primary key | Foreign keys |
|---|---|---|
| `sales_fact` | `row_hash` | `fk_fact_sales_date`, `fk_fact_sales_product`, `fk_fact_sales_customer`, `fk_fact_sales_country` |
| `returns_fact` | `row_hash` | `fk_fact_returns_date`, `fk_fact_returns_product`, `fk_fact_returns_customer`, `fk_fact_returns_country` |
| `daily_product_revenue_agg` | `pk_daily_product_revenue` (`id_date`, `id_product`) | `fk_fact_agg_date`, `fk_fact_agg_product` |

`CHECK` constraints also enforce the business rules: `ck_sales_quantity_positive` and `ck_sales_price_positive` on sales, `ck_returns_type_valid` on returns and `ck_agg_net_matches` (`net_revenue = gross_revenue - returns_amount`) on the aggregate. Dimensions have unique natural keys (`uq_products_stock_code`, `uq_customers_code`, `uq_countries_name`, `uq_dates_full_date`).

## Support tables (outside the dimensional model)

| Schema | Table | Content |
|---|---|---|
| `staging` | `products_stg`, `sales_stg`, `returns_stg` | `UNLOGGED` landing tables for the bulk `COPY`; emptied on every run. Not dimensions or facts. |
| `audit` | `rejected_records` | Rejected row: source, row number in the CSV, reason and original record as `JSONB`. |
| `audit` | `pipeline_runs` | Run log: rows read, valid, rejected, duplicated across sources and status. |
