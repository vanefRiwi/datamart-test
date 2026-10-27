-- Idempotency check: run before and after re-running the DAG. Every row must be identical.
SELECT 'daily_product_revenue_agg' AS table_name, COUNT(*) AS row_count,
       md5(string_agg(id_date || '-' || id_product || '-' || net_revenue, '' ORDER BY id_date, id_product)) AS fingerprint
FROM dwh.daily_product_revenue_agg
UNION ALL
SELECT 'products_dim', COUNT(*), md5(string_agg(id_product || '-' || stock_code, '' ORDER BY id_product))
FROM dwh.products_dim
UNION ALL
SELECT 'returns_fact', COUNT(*), md5(string_agg(row_hash, '' ORDER BY row_hash))
FROM dwh.returns_fact
UNION ALL
SELECT 'sales_fact', COUNT(*), md5(string_agg(row_hash, '' ORDER BY row_hash))
FROM dwh.sales_fact
ORDER BY 1;
