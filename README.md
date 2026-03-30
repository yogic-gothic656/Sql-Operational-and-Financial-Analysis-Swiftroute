# SQL Logistics Analytics — SwiftRoute Freight Forwarding

End to end SQL analytical work simulating the shipment performance and carrier analysis workflow for a Dubai-based freight forwarding company. Built in PostgreSQL using pgAdmin.

---

## Business Context

SwiftRoute Logistics is a Dubai-based freight forwarder managing shipments across three corridors — GCC, South Asia, and East Africa. The operations team tracks shipment performance across eight carriers spanning air, sea, and road freight modes.

This showcases the workflow of analysing raw shipment and carrier data from a freight management system, structuring it into a relational model, and answering the key questions an operations manager or logistics analyst would ask:

- Which carriers are meeting on-time delivery targets and which are underperforming?
- How has shipment volume and revenue trended across the year?
- Which shipments are delayed and by how many days?
- How does each carrier's transit time compare month on month?
- What is the true cost of each shipment once all surcharges are included?
- Which corridors are generating the most revenue?

---

## Database Schema

The analysis is built across four related tables:

| Table | Description | Rows |
|---|---|---|
| `carriers` | Master list of 8 carriers across Air, Sea, and Road modes | 8 |
| `routes` | 15 trade routes across GCC, South Asia, and East Africa corridors | 15 |
| `shipments` | Individual shipment records including dates, status, weight, and freight charge | 500 |
| `charges` | Surcharge line items per shipment — fuel, customs, handling, and insurance | 2,000 |

**Relationships:**
- `carriers` → `shipments` (one to many on `carrier_id`)
- `routes` → `shipments` (one to many on `route_id`)
- `shipments` → `charges` (one to many on `shipment_id`)

**Grain:** One row per shipment in the shipments table. One row per charge type per shipment in the charges table — four rows per shipment covering fuel surcharge, customs, handling, and insurance.

---

## Analysis Queries & SQL Techniques

### Q1 — On-Time Delivery Rate by Carrier and Corridor
*Which carriers and corridors are meeting delivery commitments?*

Two separate queries — one grouped by carrier, one grouped by corridor. In Transit shipments with no actual delivery date are excluded using a NULL filter before aggregation. On-time condition uses `<= 0` day difference to count early arrivals as on-time, not just exact-date matches.

<img width="775" height="309" alt="Screenshot 2026-03-28 191957" src="https://github.com/user-attachments/assets/ff8a6b00-93c9-490a-b588-06274c280216" />

<img width="677" height="161" alt="Screenshot 2026-03-28 192716" src="https://github.com/user-attachments/assets/321f683b-2031-42fa-913e-b70d4d33ffaf" />

**Techniques:** Conditional aggregation · CASE WHEN · NULL handling · Multi-table JOIN · ROUND

---

### Q2 — Monthly Shipment Volume and Revenue Trend
*How has shipment volume and revenue moved across 2024?*

Extracts year-month from ship date for grouping, then calculates month-on-month differences for both volume and revenue using LAG. CASE WHEN logic classifies each month as GROWTH, DECLINE, or STABLE. Revenue and volume trends are tracked independently — a key finding is that they frequently diverge, indicating shipment mix drives revenue more than raw volume.

<img width="1028" height="434" alt="Screenshot 2026-03-28 195026" src="https://github.com/user-attachments/assets/d6bf0cfe-8ac8-4ba2-8ce0-53698065230b" />

**Techniques:** DATE![Uploading Screenshot 2026-03-28 195026.png…]()
 functions · TO_CHAR · LAG / LEAD · Conditional CASE WHEN trend classification

---

### Q3 — Delayed Shipment Identification
*Which shipments are delayed and by how many days?*

Filters to delayed shipments using status and calculates delay in days by subtracting expected from actual delivery. A delay severity label — Minor, Moderate, Severe — is added using CASE WHEN banding to make results immediately actionable.

<img width="1011" height="493" alt="Screenshot 2026-03-27 220326" src="https://github.com/user-attachments/assets/4524f408-a6f0-4278-baa9-384fa1284b8c" />

**Techniques:** DATE functions · Date subtraction · CASE WHEN severity banding · ORDER BY

---

### Q4 — Carrier Transit Time Comparison Month on Month
*Is each carrier getting faster or slower over time?*

Calculates average actual transit time per carrier per month, then uses LAG partitioned by carrier to compare each month against the previous month. A trend label — IMPROVED, DECLINED, STABLE — is derived from the month-on-month difference. NULL handling excludes In Transit shipments from transit time calculations.

<img width="1118" height="678" alt="Screenshot 2026-03-27 231905" src="https://github.com/user-attachments/assets/6390ff92-141d-4e6f-b676-ddf09d8edbba" />

**Techniques:** LAG / LEAD · PARTITION BY · TO_CHAR · AVG · NULL handling · CTE chaining

---

### Q5 — Total Cost Breakdown Per Shipment
*What is the true cost of each shipment including all surcharges?*

Pivots the charges table from long format (four rows per shipment) to wide format (one row per shipment with four charge columns) using conditional aggregation. Joins to shipments to add the base freight charge and computes a grand total combining freight and all surcharges.

<img width="896" height="682" alt="Screenshot 2026-03-28 103444" src="https://github.com/user-attachments/assets/9eb56079-97d6-4bcc-a2c2-14cdc1380b8a" />

**Techniques:** Multi-table JOIN · CTE · Conditional aggregation pivot · SUM · ROUND

---

### Q6 — Revenue by Corridor
*Which corridors generate the most total revenue after all charges are included?*

Extends the Q5 cost breakdown logic by joining to the routes table to bring in corridor. Aggregates grand total revenue by corridor. Note — this reflects total billed revenue, not true profitability, as carrier operating costs are outside the scope of this dataset.

<img width="380" height="156" alt="Screenshot 2026-03-28 111444" src="https://github.com/user-attachments/assets/5eb119f8-e778-41cb-b51b-c9a3d0670107" />

**Techniques:** GROUP BY · Multi-table JOIN · CTE chaining · Aggregation · ORDER BY

---

### Q7 — Carrier Performance Summary View
*A reusable carrier performance summary for operational reporting and BI integration.*

Creates a PostgreSQL VIEW consolidating all key carrier metrics into a single reusable object. Revenue metrics are calculated across all shipments including In Transit, while delivery performance and transit time metrics apply NULL filtering scoped only to completed shipments.

**Techniques:** CREATE VIEW · CTE · Conditional aggregation · NULLIF for division by zero protection · NULL scoping

<img width="1469" height="312" alt="Screenshot 2026-03-28 185629" src="https://github.com/user-attachments/assets/16845e4f-bd92-4eb5-895f-1de8500f8331" />

---

## Key Findings

- **No carrier exceeded a 62% on-time delivery rate** — with Freightworks UAE at the bottom at 28.6%, indicating a network-wide reliability problem rather than isolated underperformance
- **Road carriers occupy three of the bottom four positions** on on-time rate, suggesting GCC road freight carries the highest scheduling risk across SwiftRoute's network
- **On-time rates are consistent across corridors**, ranging narrowly from 38% to 44% — corridor type does not explain the delivery reliability gap, pointing to carrier execution as the root cause
- **Revenue and shipment volume frequently diverge** — July delivered the highest monthly revenue at AED 164,107 despite not being the highest volume month, confirming that shipment mix and corridor type drive revenue more than raw shipment count
- **August recorded the steepest revenue decline** at -AED 68,958 month on month — the lowest revenue month of the year despite mid-range shipment volume
- **June and July represent the strongest consecutive months** on both volume and revenue — a potential seasonal peak worth planning carrier capacity around
- **Emirates SkyCargo leads on-time performance** at 61.4%, while all three road carriers underperform the network average — a finding that supports prioritising air freight for time-sensitive GCC shipments

---

## Files

```
├── schema_and_seed_data.sql
├── solution_script.sql
├── carriers.csv
├── charges.csv
├── routes.csv
└── shipments.csv
```

---

## Tools Used

- **PostgreSQL** — database and query execution
- **pgAdmin 4** — query development and result validation
