-- 1. Customers
CREATE TABLE customers (
    customer_id TEXT PRIMARY KEY,
    customer_unique_id TEXT,
    customer_zip_code_prefix INTEGER,
    customer_city TEXT,
    customer_state TEXT
);

-- 2. Sellers
CREATE TABLE sellers (
    seller_id TEXT PRIMARY KEY,
    seller_zip_code_prefix INTEGER,
    seller_city TEXT,
    seller_state TEXT
);

-- 3. Products
CREATE TABLE products (
    product_id TEXT PRIMARY KEY,
    product_category_name TEXT,
    product_name_length INTEGER,
    product_description_length INTEGER,
    product_photos_qty INTEGER,
    product_weight_g REAL,
    product_length_cm REAL,
    product_height_cm REAL,
    product_width_cm REAL
);

-- 4. Orders
CREATE TABLE orders (
    order_id TEXT PRIMARY KEY,
    customer_id TEXT,
    order_status TEXT,
    order_purchase_timestamp TEXT,
    order_approved_at TEXT,
    order_delivered_carrier_date TEXT,
    order_delivered_customer_date TEXT,
    order_estimated_delivery_date TEXT,

    FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id)
);

-- 5. Order Items
CREATE TABLE order_items (
    order_id TEXT,
    order_item_id INTEGER,
    product_id TEXT,
    seller_id TEXT,
    shipping_limit_date TEXT,
    price REAL,
    freight_value REAL,

    PRIMARY KEY (order_id, order_item_id),

    FOREIGN KEY (order_id)
        REFERENCES orders(order_id),

    FOREIGN KEY (product_id)
        REFERENCES products(product_id),

    FOREIGN KEY (seller_id)
        REFERENCES sellers(seller_id)
);

-- 6
CREATE TABLE order_reviews (
    review_id TEXT,
    order_id TEXT,
    review_score INTEGER,
    review_comment_title TEXT,
    review_comment_message TEXT,
    review_creation_date TEXT,
    review_answer_timestamp TEXT,

    FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
);
-- 7. Product Category Translation
CREATE TABLE product_category_name_translation (
    product_category_name TEXT PRIMARY KEY,
    product_category_name_english TEXT
);



-- Q1: Row counts for all tables

SELECT 'customers' AS table_name, COUNT(*) AS row_count
FROM customers
UNION ALL

SELECT 'sellers', COUNT(*)
FROM sellers
UNION ALL

SELECT 'products', COUNT(*)
FROM products
UNION ALL

SELECT 'orders', COUNT(*)
FROM orders
UNION ALL

SELECT 'order_items', COUNT(*)
FROM order_items
UNION ALL

SELECT 'order_reviews', COUNT(*)
FROM order_reviews
UNION ALL

SELECT 'category_translation', COUNT(*)
FROM product_category_name_translation;



-- Q1.2 — Orders to Order Items Join Cardinality
-- ============================================================

SELECT
    COUNT(*) AS joined_rows,
    COUNT(DISTINCT o.order_id) AS distinct_orders,
    COUNT(DISTINCT oi.order_id) AS orders_with_items
FROM orders AS o
INNER JOIN order_items AS oi
    ON o.order_id = oi.order_id;
	
-- Average number of items per order

SELECT
    COUNT(*) * 1.0 / COUNT(DISTINCT order_id) AS average_items_per_order
FROM order_items;	
	
-- Q2 — Analytical Base
-- ============================================================

DROP VIEW IF EXISTS analytical_base;

CREATE VIEW analytical_base AS

WITH review_agg AS (
    SELECT
        order_id,
        AVG(review_score) AS avg_review_score,
        COUNT(*) AS review_count
    FROM order_reviews
    GROUP BY order_id
)

SELECT
    o.order_id,
    o.customer_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    oi.price,
    oi.freight_value,

    p.product_category_name,

    COALESCE(
        pct.product_category_name_english,
        p.product_category_name
    ) AS category_name,

    r.avg_review_score,
    r.review_count,

    julianday(o.order_delivered_customer_date)
        - julianday(o.order_purchase_timestamp)
        AS delivery_days,

    julianday(o.order_delivered_customer_date)
        - julianday(o.order_estimated_delivery_date)
        AS delivery_vs_estimated_days

FROM orders AS o

INNER JOIN order_items AS oi
    ON o.order_id = oi.order_id

INNER JOIN products AS p
    ON oi.product_id = p.product_id

LEFT JOIN product_category_name_translation AS pct
    ON p.product_category_name = pct.product_category_name

LEFT JOIN review_agg AS r
    ON o.order_id = r.order_id

WHERE o.order_status = 'delivered';



-- Q3.1 — Direct Revenue
-- ============================================================

SELECT
    SUM(oi.price) AS direct_revenue
FROM order_items AS oi
INNER JOIN orders AS o
    ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered';


-- Q3.2 — Naive Joined Revenue
-- Demonstrates revenue inflation caused by review duplication
-- ============================================================

SELECT
    SUM(oi.price) AS naive_joined_revenue
FROM orders AS o

INNER JOIN order_items AS oi
    ON o.order_id = oi.order_id

INNER JOIN products AS p
    ON oi.product_id = p.product_id

LEFT JOIN product_category_name_translation AS pct
    ON p.product_category_name = pct.product_category_name

LEFT JOIN order_reviews AS r
    ON o.order_id = r.order_id

WHERE o.order_status = 'delivered';


-- Q3.3 — Corrected Revenue
-- ============================================================
SELECT
    SUM(price) AS corrected_revenue
FROM analytical_base;


-- Q3.4 — Revenue Reconciliation
-- ============================================================

WITH direct AS (
    SELECT
        SUM(oi.price) AS direct_revenue
    FROM order_items AS oi
    INNER JOIN orders AS o
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
),

corrected AS (
    SELECT
        SUM(price) AS corrected_revenue
    FROM analytical_base
)

SELECT
    direct.direct_revenue,
    corrected.corrected_revenue,
    corrected.corrected_revenue - direct.direct_revenue
        AS difference
FROM direct
CROSS JOIN corrected;



-- Q4 — Overall Core KPIs
-- ============================================================

WITH order_level AS (
    SELECT
        order_id,
        SUM(price) AS order_revenue,
        MAX(delivery_days) AS delivery_days,
        MAX(avg_review_score) AS review_score
    FROM analytical_base
    GROUP BY order_id
)

SELECT
    SUM(order_revenue) AS total_revenue,
    AVG(order_revenue) AS average_order_value,
    AVG(delivery_days) AS average_delivery_days,
    AVG(review_score) AS average_review_score
FROM order_level;



-- Q5 — Category KPIs
-- ============================================================

WITH category_order AS (
    SELECT
        category_name,
        order_id,
        SUM(price) AS order_revenue,
        MAX(delivery_days) AS delivery_days,
        MAX(avg_review_score) AS review_score
    FROM analytical_base
    GROUP BY category_name, order_id
)

SELECT
    category_name,
    SUM(order_revenue) AS revenue,
    AVG(order_revenue) AS average_order_value,
    AVG(delivery_days) AS average_delivery_days,
    AVG(review_score) AS average_review_score,
    COUNT(*) AS order_count
FROM category_order
GROUP BY category_name
ORDER BY revenue DESC;



-- Q6 — Monthly KPIs
-- ============================================================

WITH order_month AS (
    SELECT
        strftime('%Y-%m', order_purchase_timestamp) AS month,
        order_id,
        SUM(price) AS order_revenue,
        MAX(delivery_days) AS delivery_days,
        MAX(avg_review_score) AS review_score
    FROM analytical_base
    GROUP BY
        strftime('%Y-%m', order_purchase_timestamp),
        order_id
)

SELECT
    month,
    SUM(order_revenue) AS revenue,
    AVG(order_revenue) AS average_order_value,
    AVG(delivery_days) AS average_delivery_days,
    AVG(review_score) AS average_review_score,
    COUNT(*) AS order_count
FROM order_month
GROUP BY month
ORDER BY month;




-- Q7 — Top and Bottom 5 Categories by Revenue
-- Low-volume categories are excluded using HAVING.
-- ============================================================

WITH category_order AS (
    SELECT
        category_name,
        order_id,
        SUM(price) AS order_revenue
    FROM analytical_base
    GROUP BY
        category_name,
        order_id
),

category_kpi AS (
    SELECT
        category_name,
        SUM(order_revenue) AS revenue,
        COUNT(*) AS order_count
    FROM category_order
    GROUP BY category_name
    HAVING COUNT(*) >= 100
)

-- Top 5
SELECT
    'Top 5' AS ranking_group,
    category_name,
    revenue,
    order_count
FROM category_kpi
ORDER BY revenue DESC
LIMIT 5;


-- Bottom 5

WITH category_order AS (
    SELECT
        category_name,
        order_id,
        SUM(price) AS order_revenue
    FROM analytical_base
    GROUP BY
        category_name,
        order_id
),

category_kpi AS (
    SELECT
        category_name,
        SUM(order_revenue) AS revenue,
        COUNT(*) AS order_count
    FROM category_order
    GROUP BY category_name
    HAVING COUNT(*) >= 100
)

SELECT
    'Bottom 5' AS ranking_group,
    category_name,
    revenue,
    order_count
FROM category_kpi
ORDER BY revenue ASC
LIMIT 5;



-- Q8: TOP AND BOTTOM 5 CATEGORIES BY AVERAGE REVIEW SCORE
-- =====================================================

-- Top 5 Categories by Average Review Score

WITH category_order AS (
    SELECT
        category_name,
        order_id,
        MAX(avg_review_score) AS review_score
    FROM analytical_base
    GROUP BY category_name, order_id
),
category_review AS (
    SELECT
        category_name,
        AVG(review_score) AS average_review_score,
        COUNT(DISTINCT order_id) AS order_count
    FROM category_order
    GROUP BY category_name
    HAVING COUNT(DISTINCT order_id) >= 100
)
SELECT
    'Top 5' AS ranking_group,
    category_name,
    average_review_score,
    order_count
FROM category_review
ORDER BY average_review_score DESC
LIMIT 5;


-- Bottom 5 Categories by Average Review Score

WITH category_order AS (
    SELECT
        category_name,
        order_id,
        MAX(avg_review_score) AS review_score
    FROM analytical_base
    GROUP BY category_name, order_id
),
category_review AS (
    SELECT
        category_name,
        AVG(review_score) AS average_review_score,
        COUNT(DISTINCT order_id) AS order_count
    FROM category_order
    GROUP BY category_name
    HAVING COUNT(DISTINCT order_id) >= 100
)
SELECT
    'Bottom 5' AS ranking_group,
    category_name,
    average_review_score,
    order_count
FROM category_review
ORDER BY average_review_score ASC
LIMIT 5;


-- =====================================================
-- Q9: SELLER KPIs + REVENUE RANK
-- =====================================================

WITH seller_order AS (
    SELECT
        seller_id,
        order_id,
        SUM(price) AS order_revenue,
        MAX(delivery_days) AS delivery_days,
        MAX(avg_review_score) AS review_score
    FROM analytical_base
    GROUP BY seller_id, order_id
),
seller_kpi AS (
    SELECT
        seller_id,
        SUM(order_revenue) AS revenue,
        COUNT(DISTINCT order_id) AS order_count,
        AVG(delivery_days) AS average_delivery_days,
        AVG(review_score) AS average_review_score
    FROM seller_order
    GROUP BY seller_id
    HAVING COUNT(DISTINCT order_id) >= 100
)
SELECT
    seller_id,
    revenue,
    order_count,
    average_delivery_days,
    average_review_score,
    RANK() OVER (ORDER BY revenue DESC) AS revenue_rank
FROM seller_kpi
ORDER BY revenue DESC;




-- Q10: CATEGORY DELIVERY DAYS + REVIEW SCORE
-- =====================================================

WITH category_order AS (
    SELECT
        category_name,
        order_id,
        MAX(delivery_days) AS delivery_days,
        MAX(avg_review_score) AS review_score
    FROM analytical_base
    GROUP BY category_name, order_id
)

SELECT
    category_name,
    AVG(delivery_days) AS average_delivery_days,
    AVG(review_score) AS average_review_score,
    COUNT(DISTINCT order_id) AS order_count
FROM category_order
GROUP BY category_name
HAVING COUNT(DISTINCT order_id) >= 100
ORDER BY average_delivery_days;



-- Bonus 2

SELECT
    product_category_name,
    ROUND(SUM(price), 2) AS total_revenue
FROM analytical_base
GROUP BY product_category_name
ORDER BY total_revenue DESC;


-- Bonus 3

SELECT
    ROUND(
        100.0 * SUM(
            CASE
                WHEN order_delivered_customer_date <= order_estimated_delivery_date
                THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS on_time_delivery_rate
FROM (
    SELECT DISTINCT
        order_id,
        order_delivered_customer_date,
        order_estimated_delivery_date
    FROM analytical_base
    WHERE order_delivered_customer_date IS NOT NULL
) AS orders;



-- Bonus 4

SELECT
    COUNT(*) AS orders_without_reviews
FROM orders o
LEFT JOIN (
    SELECT DISTINCT order_id
    FROM order_reviews
) r
    ON o.order_id = r.order_id
WHERE r.order_id IS NULL;


SELECT
    ROUND(
        100.0 * COUNT(*) / (SELECT COUNT(*) FROM orders),
        2
    ) AS no_review_share
FROM orders o
LEFT JOIN (
    SELECT DISTINCT order_id
    FROM order_reviews
) r
    ON o.order_id = r.order_id
WHERE r.order_id IS NULL;



-- Bonus 5


SELECT
    product_category_name,
    ROUND(SUM(price), 2) AS revenue,
    ROUND(SUM(freight_value), 2) AS freight_cost,
    ROUND(
        100.0 * SUM(freight_value) / NULLIF(SUM(price), 0),
        2
    ) AS freight_revenue_ratio,
    CASE
        WHEN 100.0 * SUM(freight_value) / NULLIF(SUM(price), 0) > 25
        THEN 'High Shipping Impact'
        ELSE 'Normal'
    END AS shipping_flag
FROM analytical_base
WHERE product_category_name IS NOT NULL
GROUP BY product_category_name
ORDER BY freight_revenue_ratio DESC;


-- Bonus 6

WITH monthly_category_revenue AS (
    SELECT
        strftime('%Y-%m', order_purchase_timestamp) AS month,
        product_category_name AS category,
        SUM(price) AS revenue
    FROM analytical_base
    WHERE product_category_name IS NOT NULL
    GROUP BY month, category
)

SELECT
    month,
    category,
    ROUND(revenue, 2) AS revenue,
    ROUND(
        100.0 * revenue /
        SUM(revenue) OVER (PARTITION BY month),
        2
    ) AS monthly_revenue_share
FROM monthly_category_revenue
ORDER BY month, monthly_revenue_share DESC;