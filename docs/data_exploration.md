# Source data exploration

**English** | [Español](data_exploration.es.md)

Results of `uv run python scripts/explore_sources.py` on the files in `data/raw/`. Each problem found has its treatment in the pipeline (**Decision** column).

## 1. Source profile

| Attribute | Daily sales | History |
|---|---|---|
| Kaggle | carrie1/ecommerce-data | thedevastator/online-retail-transaction-dataset |
| File in the repo | `data/raw/data.csv` | `data/raw/online_retail.csv` |
| `source_system` | `daily_sales` | `history` |
| Encoding | ISO-8859-1 (fails as UTF-8) | UTF-8 |
| Rows | 541,909 | 541,909 |
| Columns | `InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice, CustomerID, Country` | `index` + the same 8 |
| Date format | `12/1/2010 8:26` (M/D/YYYY H:MM) | `12/1/2010 8:26` |
| CustomerID | Integer (`17850`) | Decimal (`17850.0`) |
| Period | 2010-12-01 08:26 to 2011-12-09 12:50 | Same |
| Grain | One row = one invoice line | Same |

> **Main finding.** The history file does not bring two extra years: it is **the same record** in a different format. The 536,480 unique combinations of invoice, code, quantity and date are in both files. That is why the cross-source deduplication is the decision with the biggest impact (see [technical decisions, 4.3](technical_decisions.md#43-overlap-and-duplicates-between-the-two-sources)). The pipeline also accepts the original `online_retail_II.csv` (columns `Invoice`, `Price`, `Customer ID` and ISO dates).

## 2. Nulls per column (the same in both sources)

| Column | Nulls | % |
|---|---:|---:|
| `Description` | 1,454 | 0.27 % |
| `CustomerID` | 135,080 | **24.93 %** |
| Others | 0 | 0 % |

## 3. Ranges and distributions

| Field | Minimum | Maximum | Comment |
|---|---:|---:|---|
| `Quantity` | -80,995 | 80,995 | The same order of 80,995 units is cancelled the same day |
| `UnitPrice` | -11,062.06 | 38,970.00 | The negative ones are `Adjust bad debt` adjustments (invoice `A`) |
| Countries | 38 | | United Kingdom = 495,478 rows (91.4 %) |

## 4. Quality problems and decision

| Problem | Rows (per source) | Decision |
|---|---:|---|
| Quantity ≤ 0 | 10,624 | Return or adjustment → `dwh.returns_fact` |
| Invoices with a `C` prefix | 9,288 | `return_type = cancellation` |
| Price ≤ 0 | 2,517 | If it is a sale (1,181): rejected as `non_positive_price`. If it is a return with price 0: valid stock adjustment |
| No CustomerID | 135,080 | Generic `ANONYMOUS` customer (`id_customer = -1`) |
| Codes that are not products | 2,950 | Rejected as `not_a_product_code` (POST 1,256, DOT 710, M 572, C2 144, D 77, S 63, BANK CHARGES 37, AMAZONFEE 34, CRUK 16, GIFT_0001_* 34, PADS 4...) |
| Exact duplicate rows | 5,268 | Rejected as `duplicate_in_source` (5,259 after normalizing; the rest already had another reason) |
| Codes with more than one description | 645 | Canonical name = most frequent description |
| Lowercase codes or codes with spaces | | Normalized to uppercase without spaces |
| Countries with aliases (`EIRE`, `RSA`, `USA`, `Unspecified`) | | `seeds/country_mapping.csv` |

## 5. Cleaning result (one DAG run)

| Concept | Rows |
|---|---:|
| Read (both sources) | 1,083,818 |
| Rejected (`audit.rejected_records`) | 18,740 (1.73 %) |
| Duplicated across sources (not loaded) | 532,539 |
| Sales loaded (`dwh.sales_fact`) | 522,535 |
| Returns and adjustments (`dwh.returns_fact`) | 10,004 |
| Products (`dwh.products_dim`) | 3,927 |
| Identified customers (`dwh.customers_dim`) | 4,362 + ANONYMOUS |
| Countries (`dwh.countries_dim`) | 38 |
| Calendar days covered (`dwh.dates_dim`) | 374 |
