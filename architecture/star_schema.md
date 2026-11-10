# PA1 — Star schema (NorthMart sales)

## Grain

**One row in `mart.fact_order_item` = one order item** (`order_id` + `order_item_id`).

This matches the Olist `olist_order_items_dataset.csv` grain (112 650 rows). Quantity is always 1 per row in this extract, so we do not store a separate quantity measure.

Orders that never received an item row (775 orders, mostly `unavailable` / `canceled`) are **out of the fact**. That is correct for this grain: there is nothing to sell-analyse.

## Fact table

`mart.fact_order_item`

| Kind | Column | Source |
| --- | --- | --- |
| Surrogate FKs | `date_sk`, `customer_sk`, `product_sk`, `seller_sk`, `order_status_sk` | dimensions |
| Degenerate | `order_id`, `order_item_id` | order items |
| Measures | `item_price`, `freight_value`, `gross_value` (= price + freight) | order items |
| Audit | `shipping_limit_ts`, `purchase_ts` | items / orders |

## Dimensions (5)

1. **`mart.dim_date`** (required) — calendar attributes for the **purchase** date. `date_sk` = `YYYYMMDD`.
2. **`mart.dim_customer`** — one row per `customer_id` (the key that sits on the order). `customer_unique_id` is kept as an attribute so repeat buyers can be counted without collapsing location history.
3. **`mart.dim_product`** — product attributes plus English category (`unknown` when the Portuguese name is missing; fallback to Portuguese when the translation table has no match).
4. **`mart.dim_seller`** — seller location from the CSV **plus** flattened JSON profile: `seller_tier`, `joined_on`, `handling_days`. Duplicate JSON rows are reduced to the latest `updated_at`.
5. **`mart.dim_order_status`** — small status dimension (`delivered`, `shipped`, `canceled`, …).

```mermaid
erDiagram
    DIM_DATE ||--o{ FACT_ORDER_ITEM : "purchase date"
    DIM_CUSTOMER ||--o{ FACT_ORDER_ITEM : "placed by"
    DIM_PRODUCT ||--o{ FACT_ORDER_ITEM : "sold"
    DIM_SELLER ||--o{ FACT_ORDER_ITEM : "fulfilled by"
    DIM_ORDER_STATUS ||--o{ FACT_ORDER_ITEM : "order status"

    FACT_ORDER_ITEM {
        INTEGER date_sk FK
        INTEGER customer_sk FK
        INTEGER product_sk FK
        INTEGER seller_sk FK
        INTEGER order_status_sk FK
        VARCHAR order_id degenerate
        INTEGER order_item_id degenerate
        DECIMAL item_price measure
        DECIMAL freight_value measure
        DECIMAL gross_value measure
    }

    DIM_DATE {
        INTEGER date_sk PK
        DATE date_day
        INTEGER year
        INTEGER quarter
        INTEGER month
        VARCHAR month_name
        INTEGER day_of_week
        BOOLEAN is_weekend
    }

    DIM_CUSTOMER {
        INTEGER customer_sk PK
        VARCHAR customer_id NK
        VARCHAR customer_unique_id
        VARCHAR zip_code
        VARCHAR city
        VARCHAR state
    }

    DIM_PRODUCT {
        INTEGER product_sk PK
        VARCHAR product_id NK
        VARCHAR category_pt
        VARCHAR category_en
        INTEGER weight_g
    }

    DIM_SELLER {
        INTEGER seller_sk PK
        VARCHAR seller_id NK
        VARCHAR city
        VARCHAR state
        VARCHAR seller_tier
        DATE joined_on
        INTEGER handling_days
    }

    DIM_ORDER_STATUS {
        INTEGER order_status_sk PK
        VARCHAR order_status NK
    }
```

## Measures (business)

- **`item_price`** — merchandise revenue of the line.
- **`freight_value`** — shipping charged on the line.
- **`gross_value`** — `item_price + freight_value` (the figure used for “revenue per month” style reports).

Payment amounts are **not** measures of this fact (see modelling decision).

## Modelling decision that was not obvious

**Keep payments out of the order-item fact.**

`olist_order_payments_dataset.csv` is at **order** grain and 2 961 orders have more than one payment row (installments / split methods). Joining payments onto 112 650 item rows would either duplicate item revenue or force an arbitrary allocation of `payment_value` across items. Analysts already complained that everyone joins the CSVs differently; baking that allocation into the warehouse would freeze a bad join. Item `price` + `freight_value` already answer the three PA1 analytical questions (monthly revenue, one month, top categories). Payments can become a **second fact** later (`fact_payment` at payment-sequential grain) without breaking this star.

A related JSON decision: the profile export is not 1:1 with `seller_id` (3 095 rows, 3 070 distinct ids, 7 sellers with conflicting `tier`). The seller dimension keeps **one** row per seller, preferring the latest `updated_at` and lower-casing `tier`.
