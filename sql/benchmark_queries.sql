-- PA1 Task 4 — three analytical queries run against each storage layout.
-- The Python runner substitutes the fact scan (CSV / Parquet / partitioned Parquet).
-- dim_product is always the same Parquet file so only the fact layout varies.
--
-- Single-month filter: 2017-11 (Olist Black Friday peak, year_month = 201711).

-- Q1: revenue per month over the whole period
SELECT year_month,
       round(sum(gross_value), 2) AS revenue
FROM {fact}
GROUP BY year_month
ORDER BY year_month;

-- Q2: revenue and item count for one month
SELECT round(sum(gross_value), 2) AS revenue,
       count(*) AS item_count
FROM {fact}
WHERE year_month = 201711;

-- Q3: five product categories with the highest revenue
SELECT p.category_en,
       round(sum(f.gross_value), 2) AS revenue
FROM {fact} f
JOIN read_parquet('data/curated/dim_product.parquet') p
  ON f.product_sk = p.product_sk
GROUP BY p.category_en
ORDER BY revenue DESC
LIMIT 5;
