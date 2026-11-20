
-- ============================================
-- 1. CREATE DIMENSION TABLES
-- ============================================

CREATE TABLE dim_date AS
SELECT DISTINCT
    day,
    week_no,
    ((day - 1) / 30 + 1) AS month_approx,
    ((day - 1) / 91 + 1) AS quarter_approx
FROM transaction_data
ORDER BY day;

ALTER TABLE dim_date ADD PRIMARY KEY (day);

CREATE TABLE dim_week AS
SELECT DISTINCT week_no
FROM transaction_data
ORDER BY week_no;

ALTER TABLE dim_week ADD PRIMARY KEY (week_no);


CREATE TABLE dim_store AS
SELECT DISTINCT store_id
FROM transaction_data
ORDER BY store_id;

ALTER TABLE dim_store ADD PRIMARY KEY (store_id);


CREATE TABLE dim_household AS
SELECT
    t.household_id,
    h.age_group,
    h.marital_status,
    h.income_group,
    h.homeowner_status,
    h.household_composition,
    h.household_size,
    h.kids_category
FROM (
    SELECT DISTINCT household_id
    FROM transaction_data
) t
LEFT JOIN hh_demographic h
    ON t.household_id = h.household_id;

ALTER TABLE dim_household ADD PRIMARY KEY (household_id);


-- ============================================
-- 2. CHECK PRIMARY KEYS
-- ============================================

ALTER TABLE product ADD PRIMARY KEY (product_id);
ALTER TABLE campaign_desc ADD PRIMARY KEY (campaign_id);

SELECT
    conrelid::regclass AS table_name,
    conname
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
AND contype = 'p'
ORDER BY 1;


-- ============================================
-- 3. FOREIGN KEY RELATIONSHIPS
-- ============================================

-- Transaction_data

ALTER TABLE transaction_data
ADD CONSTRAINT fk_trans_household
FOREIGN KEY (household_id)
REFERENCES dim_household(household_id) NOT VALID;

ALTER TABLE transaction_data
ADD CONSTRAINT fk_trans_store
FOREIGN KEY (store_id)
REFERENCES dim_store(store_id) NOT VALID;

ALTER TABLE transaction_data
ADD CONSTRAINT fk_trans_date
FOREIGN KEY (day)
REFERENCES dim_date(day) NOT VALID;

ALTER TABLE transaction_data
ADD CONSTRAINT fk_trans_week
FOREIGN KEY (week_no)
REFERENCES dim_week(week_no) NOT VALID;

ALTER TABLE transaction_data
ADD CONSTRAINT fk_trans_product
FOREIGN KEY (product_id)
REFERENCES product(product_id) NOT VALID;


-- causal_data

ALTER TABLE causal_data
ADD CONSTRAINT fk_causal_product
FOREIGN KEY (product_id)
REFERENCES product(product_id) NOT VALID;

ALTER TABLE causal_data
ADD CONSTRAINT fk_causal_store
FOREIGN KEY (store_id)
REFERENCES dim_store(store_id) NOT VALID;

ALTER TABLE causal_data
ADD CONSTRAINT fk_causal_week
FOREIGN KEY (week_no)
REFERENCES dim_week(week_no) NOT VALID;


-- campaign_table

ALTER TABLE campaign_table
ADD CONSTRAINT fk_camp_table_hh
FOREIGN KEY (household_id)
REFERENCES dim_household(household_id) NOT VALID;

ALTER TABLE campaign_table
ADD CONSTRAINT fk_camp_table_desc
FOREIGN KEY (campaign_id)
REFERENCES campaign_desc(campaign_id) NOT VALID;


-- coupon

ALTER TABLE coupon
ADD CONSTRAINT fk_coupon_product
FOREIGN KEY (product_id)
REFERENCES product(product_id) NOT VALID;

ALTER TABLE coupon
ADD CONSTRAINT fk_coupon_campaign
FOREIGN KEY (campaign_id)
REFERENCES campaign_desc(campaign_id) NOT VALID;


-- coupon_redempt

ALTER TABLE coupon_redempt
ADD CONSTRAINT fk_redempt_hh
FOREIGN KEY (household_id)
REFERENCES dim_household(household_id) NOT VALID;

ALTER TABLE coupon_redempt
ADD CONSTRAINT fk_redempt_day
FOREIGN KEY (day)
REFERENCES dim_date(day) NOT VALID;

ALTER TABLE coupon_redempt
ADD CONSTRAINT fk_redempt_campaign
FOREIGN KEY (campaign_id)
REFERENCES campaign_desc(campaign_id) NOT VALID;


-- ============================================
-- 4. CHECK CONSTRAINTS
-- ============================================

SELECT
    contype,
    COUNT(*)
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
GROUP BY contype;


SELECT
    constraint_type,
    COUNT(*) AS total
FROM information_schema.table_constraints
WHERE table_name IN (
    'dim_household',
    'dim_date',
    'dim_week',
    'dim_store',
    'product',
    'campaign_desc',
    'transaction_data',
    'causal_data',
    'campaign_table',
    'coupon',
    'coupon_redempt'
)
AND constraint_type IN ('PRIMARY KEY', 'FOREIGN KEY')
GROUP BY constraint_type;


SELECT constraint_name
FROM information_schema.table_constraints
WHERE constraint_type = 'FOREIGN KEY'
AND constraint_name LIKE 'fk%'
ORDER BY constraint_name;


-- ============================================
-- 5. TOP DEPARTMENTS BY SALES
-- ============================================

SELECT
    p.department,
    ROUND(SUM(t.sales_value)::numeric, 2) AS total_sales
FROM transaction_data t
JOIN product p
    ON p.product_id = t.product_id
GROUP BY p.department
ORDER BY total_sales DESC
LIMIT 10;


-- ============================================
-- 6. SALES DATA QUALITY AUDIT
-- ============================================

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (
        WHERE sales_value <= 0
    ) AS zero_or_negative_sales,

    COUNT(*) FILTER (
        WHERE quantity <= 0
    ) AS zero_or_negative_qty,

    COUNT(*) FILTER (
        WHERE household_id IS NULL
    ) AS null_households,

    COUNT(DISTINCT household_id) AS customers,
    COUNT(DISTINCT product_id) AS products,
    MIN(day) AS first_day,
    MAX(day) AS last_day

FROM transaction_data;


-- ============================================
-- 7. NON-POSITIVE VALUES ANALYSIS
-- ============================================

SELECT
    COUNT(*) FILTER (
        WHERE sales_value < 0
    ) AS negative_sales,

    COUNT(*) FILTER (
        WHERE sales_value = 0
    ) AS zero_sales,

    COUNT(*) FILTER (
        WHERE quantity < 0
    ) AS negative_qty,

    COUNT(*) FILTER (
        WHERE quantity = 0
    ) AS zero_qty

FROM transaction_data;


-- ============================================
-- 8. ZERO QUANTITY VS SALES ANALYSIS
-- ============================================

SELECT
    COUNT(*) FILTER (
        WHERE quantity = 0 AND sales_value > 0
    ) AS zero_qty_with_sales,

    COUNT(*) FILTER (
        WHERE quantity = 0 AND sales_value = 0
    ) AS zero_qty_zero_sales,

    COUNT(*) FILTER (
        WHERE sales_value = 0 AND quantity > 0
    ) AS free_items

FROM transaction_data;


-- ============================================
-- 9. VIEW 1: WEEKLY SALES
-- ============================================

CREATE OR REPLACE VIEW v_weekly_sales AS

SELECT
    week_no,
    ROUND(SUM(sales_value)::numeric, 2) AS sales,
    COUNT(DISTINCT basket_id) AS baskets,
    COUNT(DISTINCT household_id) AS customers

FROM transaction_data
GROUP BY week_no;


SELECT *
FROM v_weekly_sales
ORDER BY week_no
LIMIT 5;


-- ============================================
-- 10. VIEW 2: SALES BY DEPARTMENT
-- ============================================

CREATE OR REPLACE VIEW v_sales_by_department AS

SELECT
    p.department,
    ROUND(SUM(t.sales_value)::numeric, 2) AS total_sales,
    SUM(t.quantity) AS units_sold

FROM transaction_data t
JOIN product p
    ON p.product_id = t.product_id

GROUP BY p.department;


SELECT *
FROM v_sales_by_department
ORDER BY total_sales DESC
LIMIT 10;


-- ============================================
-- 11. VIEW 3: SALES BY INCOME GROUP
-- ============================================

CREATE OR REPLACE VIEW v_sales_by_income AS

SELECT
    COALESCE(h.income_group, 'Unknown') AS income_group,
    COUNT(DISTINCT t.household_id) AS households,
    ROUND(SUM(t.sales_value)::numeric, 2) AS total_spent

FROM transaction_data t
JOIN dim_household h
    ON h.household_id = t.household_id

GROUP BY 1;


SELECT *
FROM v_sales_by_income
ORDER BY total_spent DESC;


-- ============================================
-- 12. VIEW 4: RFM CUSTOMER SEGMENTATION
-- ============================================

CREATE OR REPLACE VIEW v_rfm_segments AS

WITH base AS (

    SELECT
        household_id,
        MAX(day) AS last_day,
        COUNT(DISTINCT basket_id) AS frequency,
        SUM(sales_value)::numeric AS monetary

    FROM transaction_data
    GROUP BY household_id

),

scored AS (

    SELECT
        b.*,
        NTILE(5) OVER (ORDER BY b.last_day) AS r,
        NTILE(5) OVER (ORDER BY b.frequency) AS f,
        NTILE(5) OVER (ORDER BY b.monetary) AS m

    FROM base b

)

SELECT
    household_id,
    last_day,
    frequency,
    ROUND(monetary, 2) AS monetary,
    r,
    f,
    m,

    CASE
        WHEN r >= 4 AND f >= 4 AND m >= 4
            THEN 'Champions'

        WHEN r <= 2 AND m >= 4
            THEN 'At Risk (high value)'

        WHEN r >= 4 AND f <= 2
            THEN 'New / Low frequency'

        WHEN r <= 2 AND f <= 2
            THEN 'Lost'

        ELSE 'Regular'
    END AS segment

FROM scored;


SELECT
    segment,
    COUNT(*) AS households,
    ROUND(AVG(monetary), 2) AS avg_spend

FROM v_rfm_segments
GROUP BY segment
ORDER BY avg_spend DESC;


-- ============================================
-- 13. VIEW 5: CAMPAIGN REDEMPTION RATE
-- ============================================

CREATE OR REPLACE VIEW v_campaign_redemption AS

SELECT
    c.campaign_id,
    d.campaign_type,

    COUNT(DISTINCT c.household_id) AS targeted,

    COUNT(DISTINCT r.household_id) AS redeemed,

    ROUND(
        100.0 * COUNT(DISTINCT r.household_id)
        / NULLIF(COUNT(DISTINCT c.household_id), 0),
        1
    ) AS redeem_pct

FROM campaign_table c

JOIN campaign_desc d
    ON d.campaign_id = c.campaign_id

LEFT JOIN coupon_redempt r
    ON r.household_id = c.household_id
    AND r.campaign_id = c.campaign_id

GROUP BY
    c.campaign_id,
    d.campaign_type;


SELECT *
FROM v_campaign_redemption
ORDER BY campaign_id;


-- ============================================
-- 14. FINAL VIEWS CHECK
-- ============================================

SELECT table_name
FROM information_schema.views
WHERE table_schema = 'public'
ORDER BY table_name;
