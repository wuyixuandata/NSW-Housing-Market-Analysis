-- ============================================================
-- NSW Housing Market Analysis & Development Recommendation
-- Personal Data Analytics Portfolio Project
-- Tool: MySQL
--
-- Business Objective:
-- Compare Kellyville, Blacktown and Castle Hill using
-- residential property data from 2021–2023 to support
-- an initial mid-market residential development decision.
--
-- SQL Workflow:
-- 1. Database and table setup
-- 2. Import validation
-- 3. Data quality checks
-- 4. Basic querying
-- 5. Aggregation
-- 6. Ranking and window functions
-- 7. Year-on-year growth analysis
-- 8. Land-size segmentation
-- 9. Macroeconomic data integration
-- 10. Final suburb comparison
-- ============================================================


-- ============================================================
-- 1. DATABASE & TABLE SETUP
-- ============================================================

CREATE DATABASE IF NOT EXISTS nsw_housing_project;
USE nsw_housing_project;

CREATE TABLE IF NOT EXISTS housing_sales (
    id INT AUTO_INCREMENT PRIMARY KEY,
    sold_date DATE,
    suburb VARCHAR(50),
    year SMALLINT,
    sold_price DECIMAL(12,2),
    land_size DECIMAL(10,2),
    rooms TINYINT
);

-- Data import:
-- Import the cleaned CSV into housing_sales using
-- MySQL Workbench -> Table Data Import Wizard.

DESCRIBE housing_sales;


-- ============================================================
-- 2. IMPORT VALIDATION
-- ============================================================

SELECT COUNT(*) AS total_rows
FROM housing_sales;

SELECT *
FROM housing_sales
LIMIT 10;


-- ============================================================
-- 3. DATA QUALITY CHECKS
-- ============================================================

-- 3.1 Missing values
SELECT
    COUNT(*) AS total_rows,
    SUM(sold_date IS NULL) AS null_sold_date,
    SUM(suburb IS NULL) AS null_suburb,
    SUM(year IS NULL) AS null_year,
    SUM(sold_price IS NULL) AS null_sold_price,
    SUM(land_size IS NULL) AS null_land_size,
    SUM(rooms IS NULL) AS null_rooms
FROM housing_sales;

-- 3.2 Fully duplicated business records
-- id is excluded because it is an auto-generated unique key.
SELECT
    sold_date,
    suburb,
    year,
    sold_price,
    land_size,
    rooms,
    COUNT(*) AS duplicate_count
FROM housing_sales
GROUP BY
    sold_date,
    suburb,
    year,
    sold_price,
    land_size,
    rooms
HAVING COUNT(*) > 1;

-- 3.3 Unexpected years
SELECT *
FROM housing_sales
WHERE year NOT BETWEEN 2021 AND 2023;

-- 3.4 Clearly invalid numeric values
SELECT *
FROM housing_sales
WHERE sold_price <= 0
   OR land_size <= 0
   OR rooms <= 0;

-- 3.5 Room-count distribution
SELECT
    rooms,
    COUNT(*) AS sample_count
FROM housing_sales
GROUP BY rooms
ORDER BY rooms;

-- 3.6 Check whether sold_date year matches year
SELECT *
FROM housing_sales
WHERE YEAR(sold_date) <> year;

-- Only correct a mismatch after checking the source / business owner.
-- If the exact corrected date is confirmed as 2023-12-21, then run:
-- UPDATE housing_sales
-- SET sold_date = '2023-12-21'
-- WHERE id = 261;

-- Re-check after any validated correction
SELECT *
FROM housing_sales
WHERE YEAR(sold_date) <> year;


-- ============================================================
-- 4. BASIC QUERYING
-- ============================================================

SELECT
    suburb,
    sold_price,
    rooms
FROM housing_sales
WHERE year = 2021
  AND rooms >= 4
ORDER BY sold_price DESC;


-- ============================================================
-- 5. AGGREGATION
-- ============================================================

-- 5.1 Average sale price by suburb and year
SELECT
    suburb,
    year,
    ROUND(AVG(sold_price), 2) AS avg_price
FROM housing_sales
GROUP BY suburb, year
ORDER BY year, avg_price DESC;

-- 5.2 Sample count by suburb
SELECT
    suburb,
    COUNT(*) AS sample_count
FROM housing_sales
GROUP BY suburb
ORDER BY sample_count DESC;

-- 5.3 Room count and corresponding average price
SELECT
    rooms,
    COUNT(*) AS sample_count,
    ROUND(AVG(sold_price), 2) AS avg_price
FROM housing_sales
GROUP BY rooms
ORDER BY rooms;


-- ============================================================
-- 6. PRICE RANKING / WINDOW FUNCTIONS
-- ============================================================

-- 6.1 Overall property price ranking
SELECT
    suburb,
    year,
    sold_price,
    RANK() OVER (
        ORDER BY sold_price DESC
    ) AS price_rank
FROM housing_sales
ORDER BY price_rank, suburb;

-- 6.2 Price ranking within each suburb
SELECT
    suburb,
    year,
    sold_price,
    RANK() OVER (
        PARTITION BY suburb
        ORDER BY sold_price DESC
    ) AS suburb_price_rank
FROM housing_sales
ORDER BY suburb, suburb_price_rank;


-- ============================================================
-- 7. YEAR-ON-YEAR PRICE GROWTH
-- CTE + LAG + CASE WHEN
-- ============================================================

WITH yearly_avg AS (
    SELECT
        suburb,
        year,
        ROUND(AVG(sold_price), 2) AS avg_price
    FROM housing_sales
    GROUP BY suburb, year
),
with_previous AS (
    SELECT
        suburb,
        year,
        avg_price,
        LAG(avg_price) OVER (
            PARTITION BY suburb
            ORDER BY year
        ) AS previous_year_price
    FROM yearly_avg
)
SELECT
    suburb,
    year,
    avg_price,
    previous_year_price,
    ROUND(
        (avg_price - previous_year_price)
        / previous_year_price * 100,
        2
    ) AS growth_rate_percent,
    CASE
        WHEN previous_year_price IS NULL THEN 'Base year'
        WHEN avg_price > previous_year_price THEN 'Growth'
        WHEN avg_price < previous_year_price THEN 'Decline'
        ELSE 'Stable'
    END AS market_trend
FROM with_previous
ORDER BY suburb, year;


-- ============================================================
-- 8. LAND-SIZE QUARTILE ANALYSIS
-- CTE + NTILE
-- ============================================================

WITH land_groups AS (
    SELECT
        suburb,
        land_size,
        sold_price,
        NTILE(4) OVER (
            ORDER BY land_size
        ) AS land_size_quartile
    FROM housing_sales
)
SELECT
    land_size_quartile,
    COUNT(*) AS sample_count,
    ROUND(AVG(land_size), 2) AS avg_land_size,
    ROUND(AVG(sold_price), 2) AS avg_price
FROM land_groups
GROUP BY land_size_quartile
ORDER BY land_size_quartile;


-- ============================================================
-- 9. MACROECONOMIC DATA & JOIN
-- ============================================================

CREATE TABLE IF NOT EXISTS economic_data (
    year SMALLINT PRIMARY KEY,
    cash_rate DECIMAL(5,2),
    inflation DECIMAL(5,2),
    unemployment DECIMAL(5,2)
);

-- Units / timing used in this project:
-- cash_rate     = year-end RBA cash-rate target (%)
-- inflation     = December-quarter CPI year-on-year (%)
-- unemployment  = December seasonally adjusted unemployment rate (%)

INSERT INTO economic_data
    (year, cash_rate, inflation, unemployment)
VALUES
    (2021, 0.10, 3.50, 4.20),
    (2022, 3.10, 7.80, 3.50),
    (2023, 4.35, 4.10, 3.90);

SELECT *
FROM economic_data;

-- LEFT JOIN keeps all housing groups even if macro data is missing.
SELECT
    h.suburb,
    h.year,
    ROUND(AVG(h.sold_price), 2) AS avg_price,
    e.cash_rate,
    e.inflation,
    e.unemployment
FROM housing_sales AS h
LEFT JOIN economic_data AS e
    ON h.year = e.year
GROUP BY
    h.suburb,
    h.year,
    e.cash_rate,
    e.inflation,
    e.unemployment
ORDER BY h.year, avg_price DESC;


-- ============================================================
-- 10. FINAL BUSINESS SUMMARY:
-- YEARLY SUBURB AVERAGE-PRICE RANKING
-- ============================================================

WITH yearly_suburb_avg AS (
    SELECT
        year,
        suburb,
        ROUND(AVG(sold_price), 2) AS avg_price
    FROM housing_sales
    GROUP BY year, suburb
)
SELECT
    year,
    suburb,
    avg_price,
    RANK() OVER (
        PARTITION BY year
        ORDER BY avg_price DESC
    ) AS yearly_price_rank
FROM yearly_suburb_avg
ORDER BY year, yearly_price_rank;

-- ============================================================
-- KEY SQL TAKEAWAYS
-- ============================================================
-- The SQL analysis supports comparison of suburb-level
-- affordability, price trends, property characteristics,
-- and market changes across 2021–2023.
--
-- More detailed statistical analysis and business insights
-- are completed in Python and Power BI.
-- ============================================================

-- ============================================================
-- END
-- ============================================================
