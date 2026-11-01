-- RedFlag - Fraud Detection Submission
-- Student: Srushti
-- Batch: DA-DS-1

USE redflag;

-- ============================================
-- PATTERN 1 - VELOCITY FRAUD
-- ============================================
-- What I'm looking for: users with 30+ transactions in a single day.
-- A normal user makes 3-8 txns per day. 30+ means bot or stolen account.
-- Expected suspects: ~50

SELECT user_id,
       DATE(txn_time) AS attack_date,
       COUNT(*) AS daily_txn_count
FROM transactions
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY daily_txn_count DESC;

-- My findings: 50 suspect user-days flagged.
-- Top 3 fraudsters: user 14509 (36 txns on 02/06/2024), user 14515 (36 txns on 03/23/2024), user 14528 (36 txns on 06/08/2024).

-- ============================================
-- PATTERN 2 - ROUND-AMOUNT CLUSTERING
-- ============================================
-- What I'm looking for: users with 15+ transactions of exact round numbers.
-- Money launderers use clean amounts like 100, 500, 1000 instead of real prices with taxes.
-- Expected suspects: exactly 25

SELECT user_id, COUNT(*) AS round_txn_count
FROM transactions
WHERE amount IN (100, 200, 500, 1000, 2000, 5000, 10000)
GROUP BY user_id
HAVING COUNT(*) >= 15
ORDER BY round_txn_count DESC;

-- My findings: 25 suspect users flagged.

-- ============================================
-- PATTERN 3 - CARD TESTING
-- ============================================
-- What I'm looking for: users with 30+ tiny transactions (under Rs 10) in one day.
-- Fraudsters test stolen cards with small amounts before making big purchases.
-- Expected suspects: 20

SELECT user_id, DATE(txn_time) AS test_date, COUNT(*) AS tiny_txn_count
FROM transactions
WHERE amount < 10
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY tiny_txn_count DESC;

-- My findings: 20 suspect user-days flagged.
-- Top 3 testers: user 14573 (50 txns on 04/01/2024), user 14565 (45 txns on 03/04/2024), user 14574 (43 txns on 05/06/2024).

-- ============================================
-- PATTERN 4 - FAILED-THEN-SUCCEEDED
-- ============================================
-- What I'm looking for: users with many failed transactions.
-- Fraudsters test stolen cards and repeatedly fail until they get a success.
-- Expected suspects: (Simplified version catches 25+ users)

SELECT user_id, COUNT(*) AS failed_count
FROM transactions
WHERE status = 'FAILED'
GROUP BY user_id
HAVING COUNT(*) >= 5
ORDER BY failed_count DESC;

-- My findings: 25 suspect users flagged with 5 or more failed transactions.
-- Top 3 repeat failures: user 14594 (31), user 14592 (30), user 14597 (29).

-- ============================================
-- PATTERN 5 - ODD-HOUR CONCENTRATION
-- ============================================
-- What I'm looking for: users where 80%+ of their transactions occur between 2 AM and 5 AM (hours 2, 3, 4) and they have at least 30 total transactions.
-- Fraud scripts often run in the middle of the night in India.
-- Expected suspects: exactly 20

SELECT user_id, 
       COUNT(*) AS total_txns,
       SUM(CASE WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1 ELSE 0 END) AS odd_hour_txns
FROM transactions
GROUP BY user_id
HAVING COUNT(*) >= 30 
   AND SUM(CASE WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1 ELSE 0 END) / COUNT(*) >= 0.80
ORDER BY odd_hour_txns DESC;

-- My findings: Exactly 20 suspect users flagged.
-- Top 3 bots: user 14613 (42 odd-hour txns), user 14615 (41 odd-hour txns), user 14614 (40 odd-hour txns).

-- ============================================
-- PATTERN 6 - MULE ACCOUNTS (ADVANCED)
-- ============================================
-- What I'm looking for: users with 5+ instances where a CREDIT is followed within 30 minutes by a DEBIT of at least 70% of the credit amount.
-- Mules receive stolen money and quickly send it out to another account.
-- Expected suspects: exactly 30

SELECT c.user_id, COUNT(*) AS mule_instances
FROM transactions c
WHERE c.txn_type = 'CREDIT'
  AND EXISTS (
      SELECT 1 
      FROM transactions d
      WHERE d.user_id = c.user_id
        AND d.txn_type = 'DEBIT'
        AND d.txn_time > c.txn_time
        AND d.txn_time <= c.txn_time + INTERVAL 30 MINUTE
        AND d.amount >= (c.amount * 0.70)
  )
GROUP BY c.user_id
HAVING COUNT(*) >= 5
ORDER BY mule_instances DESC;

-- My findings: 30 mule accounts flagged.
-- Top 3 mules: user 14638 (9 instances), user 14627 (9), user 14635 (9).

-- ============================================
-- PATTERN 7 - REFUND ABUSE
-- ============================================
-- What I'm looking for: users with 20+ total transactions and a refund ratio greater than 40%.
-- Normal users almost never ask for refunds. Fraudsters abuse the chargeback system.
-- Expected suspects: 24-25

SELECT user_id, 
       COUNT(*) AS total_txns,
       SUM(CASE WHEN txn_type = 'REFUND' THEN 1 ELSE 0 END) AS refund_count,
       SUM(CASE WHEN txn_type = 'REFUND' THEN 1 ELSE 0 END) / COUNT(*) AS refund_ratio
FROM transactions
GROUP BY user_id
HAVING COUNT(*) >= 20 
   AND SUM(CASE WHEN txn_type = 'REFUND' THEN 1 ELSE 0 END) / COUNT(*) > 0.40
ORDER BY refund_ratio DESC;

-- My findings: 24 suspects flagged. 
-- Top 3 abusers: user 14672 (53.8% refund rate), user 14669 (53.5%), user 14654 (51.3%).

-- ============================================
-- PATTERN 8 - MERCHANT COLLUSION
-- ============================================
-- What I'm looking for: merchants where the top 5 users account for more than 60% of the volume.
-- Normal merchants have thousands of customers. If 5 people make up 60% of the money, they are colluding.
-- Expected suspects: exactly 15

WITH user_merchant_totals AS (
    SELECT merchant_id, user_id, SUM(amount) AS user_total
    FROM transactions
    GROUP BY merchant_id, user_id
),
ranked_users AS (
    SELECT merchant_id, user_id, user_total,
           ROW_NUMBER() OVER (PARTITION BY merchant_id ORDER BY user_total DESC) AS rnk
    FROM user_merchant_totals
),
top5_per_merchant AS (
    SELECT merchant_id, SUM(user_total) AS top5_total
    FROM ranked_users
    WHERE rnk <= 5
    GROUP BY merchant_id
),
merchant_total AS (
    SELECT merchant_id, SUM(amount) AS total_amount
    FROM transactions
    GROUP BY merchant_id
)
SELECT m.merchant_id,
       m.total_amount,
       t.top5_total,
       t.top5_total / m.total_amount AS top5_ratio
FROM merchant_total m
JOIN top5_per_merchant t ON m.merchant_id = t.merchant_id
WHERE t.top5_total / m.total_amount > 0.60
ORDER BY top5_ratio DESC;

-- My findings: Exactly 15 colluding merchants flagged (IDs 1-15).
-- Merchant 3 has 99.79% of volume from just 5 users. Merchant 15 is at 99.78%.

-- ============================================
-- PATTERN 9 - JUST-UNDER-THRESHOLD (STRUCTURING)
-- ============================================
-- What I'm looking for: users with 10+ transactions of exactly 9999.00.
-- Indian law requires extra checks for amounts of 10,000+. Fraudsters use 9999 to avoid this.
-- Expected suspects: exactly 20

SELECT user_id, COUNT(*) AS structuring_count
FROM transactions
WHERE amount = 9999.00
GROUP BY user_id
HAVING COUNT(*) >= 10
ORDER BY structuring_count DESC;

-- My findings: Exactly 20 suspects flagged. 
-- Top 3 launderers: user 14678 (15 times), user 14677 (14 times), user 14692 (14 times).

-- ============================================
-- PATTERN 10 - DORMANT-THEN-ACTIVE
-- ============================================
-- What I'm looking for: users with a 90+ day gap between transactions, followed by 15+ transactions (Account Takeover).
-- Expected suspects: 25-27

WITH gaps AS (
    SELECT user_id, txn_time,
           LAG(txn_time) OVER (PARTITION BY user_id ORDER BY txn_time) AS prev_time
    FROM transactions
),
dormant_users AS (
    SELECT DISTINCT user_id
    FROM gaps
    WHERE TIMESTAMPDIFF(DAY, prev_time, txn_time) >= 90
)
SELECT user_id, COUNT(*) AS post_gap_count
FROM transactions
WHERE user_id IN (SELECT user_id FROM dormant_users)
GROUP BY user_id
HAVING COUNT(*) >= 15
ORDER BY post_gap_count DESC;

-- My findings: 27 suspect users flagged. 
-- Top 3 suspicious accounts: user 14713 (27 txns), user 14715 (27 txns), user 14717 (26 txns).

-- ============================================
-- PATTERN 11 - VELOCITY SPIKE
-- ============================================
-- What I'm looking for: users whose peak monthly transaction count is at least 5x their average monthly count, and peak is at least 20 transactions.
-- Expected suspects: (The PDF said 35-45, but this specific dataset yielded 3 extreme outliers).

WITH monthly_counts AS (
    SELECT user_id, 
           DATE_FORMAT(txn_time, '%Y-%m') AS month,
           COUNT(*) AS txn_count
    FROM transactions
    GROUP BY user_id, DATE_FORMAT(txn_time, '%Y-%m')
),
user_stats AS (
    SELECT user_id,
           AVG(txn_count) AS avg_monthly,
           MAX(txn_count) AS peak_monthly
    FROM monthly_counts
    GROUP BY user_id
)
SELECT user_id, 
       avg_monthly, 
       peak_monthly, 
       peak_monthly / avg_monthly AS spike_ratio
FROM user_stats
WHERE peak_monthly >= 20
  AND peak_monthly / avg_monthly >= 5
ORDER BY spike_ratio DESC;

-- My findings: 3 extreme suspects flagged. 
-- Top 3: user 14517 (5.12x spike), user 14504 (5.09x spike), user 14528 (5.08x spike).

-- ============================================
-- PATTERN 12 - GEOGRAPHIC IMPOSSIBILITY
-- ============================================
-- What I'm looking for: users with consecutive transactions in different cities within 60 minutes.
-- This is physically impossible and indicates account takeover or card sharing.
-- Expected suspects: exactly 15 distinct users.

WITH txns_with_prev AS (
    SELECT user_id, txn_time, city,
           LAG(city) OVER (PARTITION BY user_id ORDER BY txn_time) AS prev_city,
           LAG(txn_time) OVER (PARTITION BY user_id ORDER BY txn_time) AS previous_time
    FROM transactions
)
SELECT DISTINCT user_id, 
       city AS curr_city, 
       prev_city, 
       txn_time AS curr_time, 
       previous_time AS prev_t, 
       TIMESTAMPDIFF(MINUTE, previous_time, txn_time) AS gap_minutes
FROM txns_with_prev
WHERE prev_city IS NOT NULL 
  AND city != prev_city 
  AND TIMESTAMPDIFF(MINUTE, previous_time, txn_time) <= 60
ORDER BY gap_minutes ASC;

-- My findings: 15 distinct suspect users flagged (80 total impossible travel events).
-- Top 3: user 14747 (Bhopal/Coimbatore), user 14750 (Chennai/Pune), user 14743 (Ahmedabad/Kolkata).