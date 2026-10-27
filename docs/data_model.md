# Data model diagram

**English** | [Español](data_model.es.md)

Star schema in the `dwh` schema of the analytical PostgreSQL. GitHub draws the diagram below automatically. For the dbdiagram.io version, import [`data_model.dbml`](data_model.dbml). The full DDL is in [`sql/ddl/`](../sql/ddl). Why it is designed this way: [technical decisions, section 2](technical_decisions.md#2-analytical-warehouse-model).

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

## Support tables (not related to the star schema)

| Schema | Table | Content |
|---|---|---|
| `staging` | `products_stg`, `sales_stg`, `returns_stg` | `UNLOGGED` landing tables for the bulk `COPY`; emptied on every run. |
| `audit` | `rejected_records` | Rejected row: source, row number in the CSV, reason and original record as `JSONB`. |
| `audit` | `pipeline_runs` | Run log: rows read, valid, rejected, duplicated across sources and status. |
