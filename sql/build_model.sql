-- PA1 Task 3 — Build the NorthMart star schema in DuckDB from the raw files.
-- Run from the repository root:
--   python src/run_build.py
--
-- Layers:
--   raw.*   = 1:1 load of source files (CSV + flattened JSON)
--   mart.*  = dimensions + fact, with surrogate keys

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS mart;

-- ---------------------------------------------------------------------------
-- RAW LAYER (unchanged content; types only)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE raw.customers AS
SELECT *
FROM read_csv(
    'data/source/olist_customers_dataset.csv',
    header = true,
    auto_detect = true,
    types = {'customer_zip_code_prefix': 'VARCHAR'}
);

CREATE OR REPLACE TABLE raw.geolocation AS
SELECT *
FROM read_csv(
    'data/source/olist_geolocation_dataset.csv',
    header = true,
    auto_detect = true,
    types = {'geolocation_zip_code_prefix': 'VARCHAR'}
);

CREATE OR REPLACE TABLE raw.orders AS
SELECT *
FROM read_csv('data/source/olist_orders_dataset.csv', header = true, auto_detect = true);

CREATE OR REPLACE TABLE raw.order_items AS
SELECT *
FROM read_csv('data/source/olist_order_items_dataset.csv', header = true, auto_detect = true);

CREATE OR REPLACE TABLE raw.order_payments AS
SELECT *
FROM read_csv('data/source/olist_order_payments_dataset.csv', header = true, auto_detect = true);

CREATE OR REPLACE TABLE raw.order_reviews AS
SELECT *
FROM read_csv('data/source/olist_order_reviews_dataset.csv', header = true, auto_detect = true);

CREATE OR REPLACE TABLE raw.products AS
SELECT *
FROM read_csv('data/source/olist_products_dataset.csv', header = true, auto_detect = true);

CREATE OR REPLACE TABLE raw.sellers AS
SELECT *
FROM read_csv(
    'data/source/olist_sellers_dataset.csv',
    header = true,
    auto_detect = true,
    types = {'seller_zip_code_prefix': 'VARCHAR'}
);

CREATE OR REPLACE TABLE raw.category_translation AS
SELECT *
FROM read_csv('data/source/product_category_name_translation.csv', header = true, auto_detect = true);

-- Flatten the nested seller JSON. Keep every raw record (including duplicates)
-- so the mart layer can apply the "one row per seller" rule explicitly.
CREATE OR REPLACE TABLE raw.seller_profiles AS
SELECT
    seller_id,
    updated_at,
    profile.tier AS tier,
    profile.joined_on AS joined_on,
    contact.email AS email,
    contact.phone AS phone,
    shipping.carriers AS carriers,
    shipping.handling_days AS handling_days
FROM read_json_auto('data/source/json_northmart_seller_profiles.json');

-- ---------------------------------------------------------------------------
-- STAGING: one JSON profile per seller (latest updated_at wins)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE raw.seller_profiles_latest AS
SELECT
    seller_id,
    updated_at,
    lower(trim(tier)) AS seller_tier,
    CAST(joined_on AS DATE) AS joined_on,
    handling_days
FROM raw.seller_profiles
QUALIFY row_number() OVER (
    PARTITION BY seller_id
    ORDER BY updated_at DESC NULLS LAST
) = 1;

-- ---------------------------------------------------------------------------
-- DIMENSIONS
-- ---------------------------------------------------------------------------

-- Date dimension covering the observed purchase window (with a small calendar buffer).
CREATE OR REPLACE TABLE mart.dim_date AS
SELECT
    CAST(strftime(d, '%Y%m%d') AS INTEGER) AS date_sk,
    d AS date_day,
    year(d) AS year,
    quarter(d) AS quarter,
    month(d) AS month,
    monthname(d) AS month_name,
    week(d) AS week_of_year,
    day(d) AS day_of_month,
    isodow(d) AS day_of_week,
    dayname(d) AS day_name,
    (isodow(d) >= 6) AS is_weekend
FROM generate_series(DATE '2016-09-01', DATE '2018-10-31', INTERVAL 1 DAY) AS t(d);

CREATE OR REPLACE TABLE mart.dim_customer AS
SELECT
    row_number() OVER (ORDER BY customer_id) AS customer_sk,
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix AS zip_code,
    customer_city AS city,
    customer_state AS state
FROM raw.customers;

CREATE OR REPLACE TABLE mart.dim_product AS
SELECT
    row_number() OVER (ORDER BY p.product_id) AS product_sk,
    p.product_id,
    p.product_category_name AS category_pt,
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category_en,
    p.product_name_lenght AS name_length,
    p.product_description_lenght AS description_length,
    p.product_photos_qty AS photos_qty,
    p.product_weight_g AS weight_g,
    p.product_length_cm AS length_cm,
    p.product_height_cm AS height_cm,
    p.product_width_cm AS width_cm
FROM raw.products p
LEFT JOIN raw.category_translation t
  ON p.product_category_name = t.product_category_name;

-- Seller dimension: CSV location + flattened JSON attributes.
-- Unknown member (-1) absorbs any future unmatched seller_id.
CREATE OR REPLACE TABLE mart.dim_seller AS
SELECT
    -1 AS seller_sk,
    'UNKNOWN' AS seller_id,
    NULL::VARCHAR AS zip_code,
    NULL::VARCHAR AS city,
    NULL::VARCHAR AS state,
    'unknown' AS seller_tier,
    NULL::DATE AS joined_on,
    NULL::BIGINT AS handling_days,
    NULL::TIMESTAMP AS profile_updated_at
UNION ALL
SELECT
    row_number() OVER (ORDER BY COALESCE(s.seller_id, j.seller_id)) AS seller_sk,
    COALESCE(s.seller_id, j.seller_id) AS seller_id,
    s.seller_zip_code_prefix AS zip_code,
    s.seller_city AS city,
    s.seller_state AS state,
    COALESCE(j.seller_tier, 'unknown') AS seller_tier,
    j.joined_on,
    j.handling_days,
    j.updated_at AS profile_updated_at
FROM raw.sellers s
FULL OUTER JOIN raw.seller_profiles_latest j USING (seller_id);

CREATE OR REPLACE TABLE mart.dim_order_status AS
SELECT
    row_number() OVER (ORDER BY order_status) AS order_status_sk,
    order_status
FROM (SELECT DISTINCT order_status FROM raw.orders);

-- ---------------------------------------------------------------------------
-- FACT (order-item grain)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE mart.fact_order_item AS
SELECT
    d.date_sk,
    c.customer_sk,
    p.product_sk,
    COALESCE(sel.seller_sk, -1) AS seller_sk,
    st.order_status_sk,
    i.order_id,
    i.order_item_id,
    i.price AS item_price,
    i.freight_value,
    i.price + i.freight_value AS gross_value,
    i.shipping_limit_date AS shipping_limit_ts,
    o.order_purchase_timestamp AS purchase_ts
FROM raw.order_items i
INNER JOIN raw.orders o USING (order_id)
INNER JOIN mart.dim_date d
  ON d.date_day = CAST(o.order_purchase_timestamp AS DATE)
INNER JOIN mart.dim_customer c
  ON c.customer_id = o.customer_id
INNER JOIN mart.dim_product p
  ON p.product_id = i.product_id
LEFT JOIN mart.dim_seller sel
  ON sel.seller_id = i.seller_id
INNER JOIN mart.dim_order_status st
  ON st.order_status = o.order_status;

-- ---------------------------------------------------------------------------
-- REFERENTIAL CHECKS (must all return 0 orphans; fact rows = 112650)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE mart.ref_checks AS
SELECT 'fact_rowcount_vs_items' AS check_name,
       (SELECT count(*) FROM mart.fact_order_item) AS actual,
       (SELECT count(*) FROM raw.order_items) AS expected,
       (SELECT count(*) FROM mart.fact_order_item) - (SELECT count(*) FROM raw.order_items) AS delta
UNION ALL
SELECT 'fact_orphan_date',
       count(*) FILTER (WHERE d.date_sk IS NULL),
       0,
       count(*) FILTER (WHERE d.date_sk IS NULL)
FROM mart.fact_order_item f
LEFT JOIN mart.dim_date d ON f.date_sk = d.date_sk
UNION ALL
SELECT 'fact_orphan_customer',
       count(*) FILTER (WHERE c.customer_sk IS NULL),
       0,
       count(*) FILTER (WHERE c.customer_sk IS NULL)
FROM mart.fact_order_item f
LEFT JOIN mart.dim_customer c ON f.customer_sk = c.customer_sk
UNION ALL
SELECT 'fact_orphan_product',
       count(*) FILTER (WHERE p.product_sk IS NULL),
       0,
       count(*) FILTER (WHERE p.product_sk IS NULL)
FROM mart.fact_order_item f
LEFT JOIN mart.dim_product p ON f.product_sk = p.product_sk
UNION ALL
SELECT 'fact_orphan_seller',
       count(*) FILTER (WHERE s.seller_sk IS NULL),
       0,
       count(*) FILTER (WHERE s.seller_sk IS NULL)
FROM mart.fact_order_item f
LEFT JOIN mart.dim_seller s ON f.seller_sk = s.seller_sk
UNION ALL
SELECT 'fact_orphan_status',
       count(*) FILTER (WHERE st.order_status_sk IS NULL),
       0,
       count(*) FILTER (WHERE st.order_status_sk IS NULL)
FROM mart.fact_order_item f
LEFT JOIN mart.dim_order_status st ON f.order_status_sk = st.order_status_sk
UNION ALL
SELECT 'seller_unknown_member_used',
       count(*) FILTER (WHERE f.seller_sk = -1),
       0,
       count(*) FILTER (WHERE f.seller_sk = -1)
FROM mart.fact_order_item f
UNION ALL
SELECT 'dim_seller_duplicate_nk',
       count(*) - count(DISTINCT seller_id),
       0,
       count(*) - count(DISTINCT seller_id)
FROM mart.dim_seller
UNION ALL
SELECT 'json_extra_rows_before_dedup',
       (SELECT count(*) FROM raw.seller_profiles) - (SELECT count(*) FROM raw.seller_profiles_latest),
       25,
       (SELECT count(*) FROM raw.seller_profiles) - (SELECT count(*) FROM raw.seller_profiles_latest) - 25;
