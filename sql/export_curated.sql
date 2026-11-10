-- PA1 Task 4 — export the fact table (plus dim_product for the category query).
-- year_month = YYYYMM from date_sk, used as the partition column.
-- Run via: python src/run_benchmark.py

COPY (
    SELECT
        date_sk,
        customer_sk,
        product_sk,
        seller_sk,
        order_status_sk,
        order_id,
        order_item_id,
        item_price,
        freight_value,
        gross_value,
        shipping_limit_ts,
        purchase_ts,
        date_sk // 100 AS year_month
    FROM mart.fact_order_item
) TO 'data/curated/fact_order_item.csv' (HEADER, DELIMITER ',', OVERWRITE_OR_IGNORE);

COPY (
    SELECT
        date_sk,
        customer_sk,
        product_sk,
        seller_sk,
        order_status_sk,
        order_id,
        order_item_id,
        item_price,
        freight_value,
        gross_value,
        shipping_limit_ts,
        purchase_ts,
        date_sk // 100 AS year_month
    FROM mart.fact_order_item
) TO 'data/curated/fact_order_item.parquet' (FORMAT PARQUET, COMPRESSION SNAPPY, OVERWRITE_OR_IGNORE);

COPY (
    SELECT
        date_sk,
        customer_sk,
        product_sk,
        seller_sk,
        order_status_sk,
        order_id,
        order_item_id,
        item_price,
        freight_value,
        gross_value,
        shipping_limit_ts,
        purchase_ts,
        date_sk // 100 AS year_month
    FROM mart.fact_order_item
) TO 'data/curated/fact_order_item_partitioned'
  (FORMAT PARQUET, COMPRESSION SNAPPY, PARTITION_BY (year_month), OVERWRITE_OR_IGNORE);

COPY (SELECT * FROM mart.dim_product)
TO 'data/curated/dim_product.parquet' (FORMAT PARQUET, COMPRESSION SNAPPY, OVERWRITE_OR_IGNORE);
