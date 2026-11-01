# RedFlag - Fraud Detection Engine

A pure SQL fraud detection engine built on 200,000 transactions from a simulated Indian payment aggregator (PayFast). 

## The Mission
Detect 12 distinct real-world fraud patterns using only SQL. No Python. No Machine Learning. 

## Fraud Patterns Detected
1. Velocity Fraud
2. Round-Amount Clustering
3. Card Testing
4. Failed-Then-Succeeded
5. Odd-Hour Concentration
6. Mule Accounts (Advanced)
7. Refund Abuse
8. Merchant Collusion
9. Just-Under-Threshold (Structuring)
10. Dormant-Then-Active
11. Velocity Spike
12. Geographic Impossibility

## Tech Stack
- MySQL (CTEs, Subqueries, Window Functions: LAG, ROW_NUMBER)

## Note
The 18MB dataset file (`redflag_transactions.sql`) is not included in this repo, but can be requested.
