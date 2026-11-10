-- PA1 Task 1 — Profiling of raw Olist CSVs and the nested seller JSON
-- Run from the repository root:
--   python src/run_profiling.py
-- All paths are relative to the repository root (data/source/).

-- =============================================================================
-- 1) Row and column counts
-- =============================================================================

-- 1.1 Row counts of every source file
SELECT 'customers' AS tabela, count(*) AS total_linhas FROM read_csv_auto('data/source/olist_customers_dataset.csv')
UNION ALL
SELECT 'geolocation', count(*) FROM read_csv_auto('data/source/olist_geolocation_dataset.csv')
UNION ALL
SELECT 'orders', count(*) FROM read_csv_auto('data/source/olist_orders_dataset.csv')
UNION ALL
SELECT 'order_items', count(*) FROM read_csv_auto('data/source/olist_order_items_dataset.csv')
UNION ALL
SELECT 'order_payments', count(*) FROM read_csv_auto('data/source/olist_order_payments_dataset.csv')
UNION ALL
SELECT 'order_reviews', count(*) FROM read_csv_auto('data/source/olist_order_reviews_dataset.csv')
UNION ALL
SELECT 'products', count(*) FROM read_csv_auto('data/source/olist_products_dataset.csv')
UNION ALL
SELECT 'sellers', count(*) FROM read_csv_auto('data/source/olist_sellers_dataset.csv')
UNION ALL
SELECT 'category_translation', count(*) FROM read_csv_auto('data/source/product_category_name_translation.csv')
UNION ALL
SELECT 'seller_profiles_json', count(*) FROM read_json_auto('data/source/json_northmart_seller_profiles.json')
ORDER BY tabela;

-- 1.2 Column counts (schema width)
SELECT 'customers' AS tabela, count(*) AS n_colunas FROM (DESCRIBE SELECT * FROM read_csv_auto('data/source/olist_customers_dataset.csv'))
UNION ALL
SELECT 'geolocation', count(*) FROM (DESCRIBE SELECT * FROM read_csv_auto('data/source/olist_geolocation_dataset.csv'))
UNION ALL
SELECT 'orders', count(*) FROM (DESCRIBE SELECT * FROM read_csv_auto('data/source/olist_orders_dataset.csv'))
UNION ALL
SELECT 'order_items', count(*) FROM (DESCRIBE SELECT * FROM read_csv_auto('data/source/olist_order_items_dataset.csv'))
UNION ALL
SELECT 'order_payments', count(*) FROM (DESCRIBE SELECT * FROM read_csv_auto('data/source/olist_order_payments_dataset.csv'))
UNION ALL
SELECT 'order_reviews', count(*) FROM (DESCRIBE SELECT * FROM read_csv_auto('data/source/olist_order_reviews_dataset.csv'))
UNION ALL
SELECT 'products', count(*) FROM (DESCRIBE SELECT * FROM read_csv_auto('data/source/olist_products_dataset.csv'))
UNION ALL
SELECT 'sellers', count(*) FROM (DESCRIBE SELECT * FROM read_csv_auto('data/source/olist_sellers_dataset.csv'))
UNION ALL
SELECT 'category_translation', count(*) FROM (DESCRIBE SELECT * FROM read_csv_auto('data/source/product_category_name_translation.csv'))
UNION ALL
SELECT 'seller_profiles_json', count(*) FROM (DESCRIBE SELECT * FROM read_json_auto('data/source/json_northmart_seller_profiles.json'))
ORDER BY tabela;

-- =============================================================================
-- 2) Candidate primary keys: uniqueness and duplicates
-- =============================================================================

-- 2.1 Key uniqueness for each natural key
SELECT 'customers.customer_id' AS chave,
       count(*) AS total,
       count(DISTINCT customer_id) AS distintos,
       count(*) - count(DISTINCT customer_id) AS duplicadas
FROM read_csv_auto('data/source/olist_customers_dataset.csv')
UNION ALL
SELECT 'customers.customer_unique_id',
       count(*), count(DISTINCT customer_unique_id), count(*) - count(DISTINCT customer_unique_id)
FROM read_csv_auto('data/source/olist_customers_dataset.csv')
UNION ALL
SELECT 'orders.order_id',
       count(*), count(DISTINCT order_id), count(*) - count(DISTINCT order_id)
FROM read_csv_auto('data/source/olist_orders_dataset.csv')
UNION ALL
SELECT 'order_items.(order_id, order_item_id)',
       count(*), count(DISTINCT (order_id, order_item_id)), count(*) - count(DISTINCT (order_id, order_item_id))
FROM read_csv_auto('data/source/olist_order_items_dataset.csv')
UNION ALL
SELECT 'products.product_id',
       count(*), count(DISTINCT product_id), count(*) - count(DISTINCT product_id)
FROM read_csv_auto('data/source/olist_products_dataset.csv')
UNION ALL
SELECT 'sellers.seller_id',
       count(*), count(DISTINCT seller_id), count(*) - count(DISTINCT seller_id)
FROM read_csv_auto('data/source/olist_sellers_dataset.csv')
UNION ALL
SELECT 'payments.(order_id, payment_sequential)',
       count(*), count(DISTINCT (order_id, payment_sequential)), count(*) - count(DISTINCT (order_id, payment_sequential))
FROM read_csv_auto('data/source/olist_order_payments_dataset.csv')
UNION ALL
SELECT 'reviews.review_id',
       count(*), count(DISTINCT review_id), count(*) - count(DISTINCT review_id)
FROM read_csv_auto('data/source/olist_order_reviews_dataset.csv')
UNION ALL
SELECT 'reviews.order_id',
       count(*), count(DISTINCT order_id), count(*) - count(DISTINCT order_id)
FROM read_csv_auto('data/source/olist_order_reviews_dataset.csv')
UNION ALL
SELECT 'geolocation.zip_prefix',
       count(*), count(DISTINCT geolocation_zip_code_prefix), count(*) - count(DISTINCT geolocation_zip_code_prefix)
FROM read_csv_auto('data/source/olist_geolocation_dataset.csv')
UNION ALL
SELECT 'category_translation.product_category_name',
       count(*), count(DISTINCT product_category_name), count(*) - count(DISTINCT product_category_name)
FROM read_csv_auto('data/source/product_category_name_translation.csv')
UNION ALL
SELECT 'json.seller_id',
       count(*), count(DISTINCT seller_id), count(*) - count(DISTINCT seller_id)
FROM read_json_auto('data/source/json_northmart_seller_profiles.json');

-- =============================================================================
-- 3) Null rates (columns with at least one null)
-- =============================================================================

-- 3.1 Orders — timestamp and status nulls
SELECT
    count(*) AS n,
    round(100.0 * count(*) FILTER (WHERE order_approved_at IS NULL) / count(*), 4) AS pct_approved_null,
    round(100.0 * count(*) FILTER (WHERE order_delivered_carrier_date IS NULL) / count(*), 4) AS pct_carrier_null,
    round(100.0 * count(*) FILTER (WHERE order_delivered_customer_date IS NULL) / count(*), 4) AS pct_delivered_null,
    round(100.0 * count(*) FILTER (WHERE order_estimated_delivery_date IS NULL) / count(*), 4) AS pct_estimated_null,
    round(100.0 * count(*) FILTER (WHERE order_purchase_timestamp IS NULL) / count(*), 4) AS pct_purchase_null
FROM read_csv_auto('data/source/olist_orders_dataset.csv');

-- 3.2 Orders — delivery dates missing by status (expected for non-delivered)
SELECT order_status,
       count(*) AS n,
       count(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS delivered_date_null
FROM read_csv_auto('data/source/olist_orders_dataset.csv')
GROUP BY order_status
ORDER BY n DESC;

-- 3.3 Products — category and physical attributes
SELECT
    count(*) AS n,
    count(*) FILTER (WHERE product_category_name IS NULL) AS category_null,
    round(100.0 * count(*) FILTER (WHERE product_category_name IS NULL) / count(*), 4) AS pct_category_null,
    count(*) FILTER (WHERE product_weight_g IS NULL) AS weight_null,
    count(*) FILTER (WHERE product_name_lenght IS NULL) AS name_length_null
FROM read_csv_auto('data/source/olist_products_dataset.csv');

-- 3.4 Order items — price / freight / keys
SELECT
    count(*) AS n,
    count(*) FILTER (WHERE order_id IS NULL) AS order_id_null,
    count(*) FILTER (WHERE product_id IS NULL) AS product_id_null,
    count(*) FILTER (WHERE seller_id IS NULL) AS seller_id_null,
    count(*) FILTER (WHERE price IS NULL) AS price_null,
    count(*) FILTER (WHERE freight_value IS NULL) AS freight_null,
    count(*) FILTER (WHERE price < 0) AS price_negative,
    count(*) FILTER (WHERE freight_value < 0) AS freight_negative
FROM read_csv_auto('data/source/olist_order_items_dataset.csv');

-- =============================================================================
-- 4) Foreign-key integrity (orphans)
-- =============================================================================

-- 4.1 order_items -> orders
SELECT count(*) AS itens_sem_pedido
FROM read_csv_auto('data/source/olist_order_items_dataset.csv') i
ANTI JOIN read_csv_auto('data/source/olist_orders_dataset.csv') o USING (order_id);

-- 4.2 order_items -> products
SELECT count(*) AS itens_sem_produto
FROM read_csv_auto('data/source/olist_order_items_dataset.csv') i
ANTI JOIN read_csv_auto('data/source/olist_products_dataset.csv') p USING (product_id);

-- 4.3 order_items -> sellers
SELECT count(*) AS itens_sem_seller
FROM read_csv_auto('data/source/olist_order_items_dataset.csv') i
ANTI JOIN read_csv_auto('data/source/olist_sellers_dataset.csv') s USING (seller_id);

-- 4.4 orders -> customers
SELECT count(*) AS pedidos_sem_cliente
FROM read_csv_auto('data/source/olist_orders_dataset.csv') o
ANTI JOIN read_csv_auto('data/source/olist_customers_dataset.csv') c USING (customer_id);

-- 4.5 payments -> orders
SELECT count(*) AS pagamentos_sem_pedido
FROM read_csv_auto('data/source/olist_order_payments_dataset.csv') p
ANTI JOIN read_csv_auto('data/source/olist_orders_dataset.csv') o USING (order_id);

-- 4.6 orders without items (status-related)
SELECT o.order_status, count(*) AS pedidos_sem_itens
FROM read_csv_auto('data/source/olist_orders_dataset.csv') o
ANTI JOIN read_csv_auto('data/source/olist_order_items_dataset.csv') i USING (order_id)
GROUP BY o.order_status
ORDER BY pedidos_sem_itens DESC;

-- 4.7 products whose Portuguese category has no English translation
SELECT count(*) AS produtos_sem_traducao
FROM read_csv_auto('data/source/olist_products_dataset.csv') p
ANTI JOIN read_csv_auto('data/source/product_category_name_translation.csv') t
  ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL;

-- 4.8 Distinct untranslated categories
SELECT DISTINCT p.product_category_name
FROM read_csv_auto('data/source/olist_products_dataset.csv') p
ANTI JOIN read_csv_auto('data/source/product_category_name_translation.csv') t
  ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL;

-- =============================================================================
-- 5) Extra CSV findings useful for the star schema
-- =============================================================================

-- 5.1 Orders without items vs total
SELECT
    (SELECT count(*) FROM read_csv_auto('data/source/olist_orders_dataset.csv')) AS n_orders,
    (SELECT count(DISTINCT order_id) FROM read_csv_auto('data/source/olist_order_items_dataset.csv')) AS n_orders_with_items;

-- 5.2 Payments grain vs order grain (why payment_value must not sit on the fact)
SELECT
    (SELECT count(*) FROM read_csv_auto('data/source/olist_order_payments_dataset.csv')) AS n_payment_rows,
    count(*) AS n_orders_with_payment,
    count(*) FILTER (WHERE n_pay > 1) AS orders_with_multiple_payments
FROM (
    SELECT order_id, count(*) AS n_pay
    FROM read_csv_auto('data/source/olist_order_payments_dataset.csv')
    GROUP BY order_id
);

-- 5.3 Purchase date range (feeds dim_date)
SELECT min(order_purchase_timestamp) AS min_purchase,
       max(order_purchase_timestamp) AS max_purchase,
       count(DISTINCT CAST(order_purchase_timestamp AS DATE)) AS distinct_days
FROM read_csv_auto('data/source/olist_orders_dataset.csv');

-- 5.4 Review duplicates (review_id is not a reliable PK)
SELECT review_id, count(*) AS n
FROM read_csv_auto('data/source/olist_order_reviews_dataset.csv')
GROUP BY review_id
HAVING count(*) > 1
ORDER BY n DESC
LIMIT 10;

-- =============================================================================
-- 6) JSON seller profiles — flattening, duplicates, quality
-- =============================================================================

-- 6.1 JSON schema after auto-detect (nested STRUCT / LIST)
DESCRIBE SELECT * FROM read_json_auto('data/source/json_northmart_seller_profiles.json');

-- 6.2 Duplicate seller_id in the JSON export (keep-one-record rule)
SELECT seller_id, count(*) AS n_records, count(DISTINCT updated_at) AS n_updated_at
FROM read_json_auto('data/source/json_northmart_seller_profiles.json')
GROUP BY seller_id
HAVING count(*) > 1
ORDER BY n_records DESC
LIMIT 20;

-- 6.3 How many extra JSON rows are caused by seller_id duplicates
SELECT
    count(*) AS json_rows,
    count(DISTINCT seller_id) AS distinct_sellers,
    count(*) - count(DISTINCT seller_id) AS extra_rows_from_duplicates
FROM read_json_auto('data/source/json_northmart_seller_profiles.json');

-- 6.4 Nested-field nulls and empty values
SELECT
    count(*) AS n,
    count(*) FILTER (WHERE seller_id IS NULL OR seller_id = '') AS seller_id_missing,
    count(*) FILTER (WHERE updated_at IS NULL) AS updated_at_null,
    count(*) FILTER (WHERE profile IS NULL) AS profile_null,
    count(*) FILTER (WHERE profile.tier IS NULL OR profile.tier = '') AS tier_missing,
    count(*) FILTER (WHERE profile.joined_on IS NULL) AS joined_on_null,
    count(*) FILTER (WHERE contact IS NULL) AS contact_null,
    count(*) FILTER (WHERE contact.email IS NULL OR contact.email = '') AS email_missing,
    count(*) FILTER (WHERE contact.phone IS NULL OR contact.phone = '') AS phone_missing,
    count(*) FILTER (WHERE shipping IS NULL) AS shipping_null,
    count(*) FILTER (WHERE shipping.handling_days IS NULL) AS handling_days_null,
    count(*) FILTER (WHERE len(shipping.carriers) = 0 OR shipping.carriers IS NULL) AS no_carriers
FROM read_json_auto('data/source/json_northmart_seller_profiles.json');

-- 6.5 Tier distribution
SELECT profile.tier AS tier, count(*) AS n
FROM read_json_auto('data/source/json_northmart_seller_profiles.json')
GROUP BY profile.tier
ORDER BY n DESC;

-- 6.6 Handling days distribution
SELECT shipping.handling_days AS handling_days, count(*) AS n
FROM read_json_auto('data/source/json_northmart_seller_profiles.json')
GROUP BY shipping.handling_days
ORDER BY handling_days;

-- 6.7 Coverage vs the sellers CSV (orphans both ways)
SELECT
    (SELECT count(*) FROM read_csv_auto('data/source/olist_sellers_dataset.csv')) AS sellers_csv,
    (SELECT count(DISTINCT seller_id) FROM read_json_auto('data/source/json_northmart_seller_profiles.json')) AS sellers_json,
    (SELECT count(*)
     FROM read_csv_auto('data/source/olist_sellers_dataset.csv') s
     ANTI JOIN (SELECT DISTINCT seller_id FROM read_json_auto('data/source/json_northmart_seller_profiles.json')) j
       USING (seller_id)) AS csv_without_json,
    (SELECT count(*)
     FROM (SELECT DISTINCT seller_id FROM read_json_auto('data/source/json_northmart_seller_profiles.json')) j
     ANTI JOIN read_csv_auto('data/source/olist_sellers_dataset.csv') s
       USING (seller_id)) AS json_without_csv;

-- 6.8 Conflicting nested attributes for the same seller_id (real export noise)
SELECT seller_id,
       count(DISTINCT profile.tier) AS n_tiers,
       count(DISTINCT profile.joined_on) AS n_joined_on,
       count(DISTINCT shipping.handling_days) AS n_handling_days
FROM read_json_auto('data/source/json_northmart_seller_profiles.json')
GROUP BY seller_id
HAVING count(DISTINCT profile.tier) > 1
    OR count(DISTINCT profile.joined_on) > 1
    OR count(DISTINCT shipping.handling_days) > 1
LIMIT 20;

-- 6.9 How many sellers have conflicting attributes across duplicate rows
SELECT count(*) AS sellers_with_conflicts
FROM (
    SELECT seller_id
    FROM read_json_auto('data/source/json_northmart_seller_profiles.json')
    GROUP BY seller_id
    HAVING count(DISTINCT profile.tier) > 1
        OR count(DISTINCT profile.joined_on) > 1
        OR count(DISTINCT shipping.handling_days) > 1
);

-- 6.10 Emails that do not look like emails
SELECT count(*) AS emails_invalidos
FROM read_json_auto('data/source/json_northmart_seller_profiles.json')
WHERE contact.email IS NOT NULL
  AND contact.email NOT LIKE '%@%.%';

-- 6.11 joined_on after updated_at (temporal inconsistency)
SELECT count(*) AS joined_after_updated
FROM read_json_auto('data/source/json_northmart_seller_profiles.json')
WHERE CAST(profile.joined_on AS DATE) > CAST(updated_at AS TIMESTAMP);
