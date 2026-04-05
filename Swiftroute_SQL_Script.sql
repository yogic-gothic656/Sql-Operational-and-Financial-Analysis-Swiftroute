Schema -

CREATE TABLE carriers (
	carrier_id INT NOT NULL PRIMARY KEY,
	carrier_name VARCHAR(50) NOT NULL,
	carrier_type VARCHAR(10) NOT NULL CHECK(carrier_type IN ('Air','Road','Sea'))
);

CREATE TABLE routes (
	route_id INT NOT NULL PRIMARY KEY,
	origin_hub VARCHAR(50) NOT NULL,
	destination_hub VARCHAR(50) NOT NULL,
	corridor VARCHAR(50) NOT NULL CHECK(corridor IN ('GCC','South Asia','East Africa')),
	distance_km INT NOT NULL,
	standard_transit_days INT NOT NULL
);

CREATE TABLE shipments (
	shipments_id INT NOT NULL PRIMARY KEY,
	carrier_id INT REFERENCES carriers(carrier_id),
	route_id INT REFERENCES routes(route_id),
	origin VARCHAR(50),
	destination VARCHAR(50),
	ship_date DATE,
	expected_delivery DATE,
	actual_delivery DATE,
	status VARCHAR(10),
	weight_kg NUMERIC(10,2),
	freight_charge_aed NUMERIC(10,2)
);

CREATE TABLE charges (
	shipment_id INT NOT NULL,
	charge_type VARCHAR(50) NOT NULL,
	amount_aed NUMERIC(10,2) NOT NULL,
	PRIMARY KEY (shipment_id,charge_type)
);

—- What is the on-time delivery rate by carrier  —-

WITH difference AS (
SELECT 
	shipment_id,
	carrier_id,
	expected_delivery,
	actual_delivery,
	actual_delivery - expected_delivery AS difference
FROM shipments
WHERE actual_delivery IS NOT NULL
),
on_time_deliveries AS (
SELECT
	carrier_id,
	COUNT(CASE WHEN difference <= 0 THEN 1 END) AS on_time_deliveries,
	COUNT(*) AS total_deliveries
FROM difference
GROUP BY carrier_id
)
SELECT 
	carrier_id,
	carrier_name,
	carrier_type,
	on_time_deliveries,
	total_deliveries,
	ROUND((on_time_deliveries * 100.0 /total_deliveries),2) AS on_time_pct
FROM on_time_deliveries
JOIN carriers
USING (carrier_id)
ORDER BY on_time_pct DESC;

—- What is the on-time delivery rate by corridor —-

WITH difference AS (
SELECT 
	routes.corridor,
	shipments.expected_delivery,
	shipments.actual_delivery,
	actual_delivery - expected_delivery AS difference
FROM shipments 
JOIN routes
USING (route_id)
WHERE actual_delivery IS NOT NULL
),
on_time_deliveries AS (
SELECT
	corridor,
	COUNT(CASE WHEN difference <= 0 THEN 1 END) AS on_time_deliveries,
	COUNT(*) AS total_deliveries
FROM difference 
GROUP BY corridor
)
SELECT 
	corridor,
	on_time_deliveries,
	total_deliveries,
	ROUND((on_time_deliveries*100.0/total_deliveries),2) AS on_time_pct
FROM on_time_deliveries;

—- How has monthly shipment volume and revenue trended across the year —-

WITH part1 AS (
SELECT
	shipment_id,
	TO_CHAR(ship_date,'YYYY-MM') AS "month",
	freight_charge_aed
FROM shipments
),
part2 AS (
SELECT
	"month",
	COUNT(*) AS total_shipments,
	SUM(freight_charge_aed) AS total_revenue
FROM part1
GROUP BY "month"
),
part3 as (
SELECT
	"month",
	total_shipments,
	LAG(total_shipments) OVER(ORDER BY "month") AS last_month_total,
	total_revenue,
	LAG(total_revenue) OVER(ORDER BY "month") AS last_month_revenue
FROM part2
),
part4 AS (
SELECT
	"month",
	total_shipments,
	total_shipments - last_month_total AS shipment_difference,
	total_revenue,
	total_revenue - last_month_revenue AS revenue_difference
FROM part3
)
SELECT
	"month",
	total_shipments,
	shipment_difference,
	CASE 
		WHEN shipment_difference > 0 THEN 'GROWTH'
		WHEN shipment_difference < 0 THEN 'DECLINE'
		WHEN shipment_difference = 0 THEN 'STABLE'
		ELSE 'N/A'
	END AS volume_trend,
	total_revenue,
	revenue_difference,
	CASE 
		WHEN revenue_difference > 0 THEN 'GROWTH'
		WHEN revenue_difference < 0 THEN 'DECLINE'
		WHEN revenue_difference = 0 THEN 'STABLE'
		ELSE 'N/A'
	END AS revenue_trend
FROM part4;

—- Which shipments are delayed and by how many days —-

WITH part1 AS (
SELECT 
	shipment_id,
	carrier_id,
	carrier_name,
	actual_delivery,
	expected_delivery,
	actual_delivery - expected_delivery AS delay_time
FROM shipments
JOIN carriers
USING (carrier_id)
WHERE status = 'Delayed'
)
SELECT 
	shipment_id,
	carrier_id,
	carrier_name,
	actual_delivery,
	expected_delivery,	
	delay_time,
	CASE
		WHEN delay_time = 1 THEN 'MINOR'
		WHEN delay_time <= 3 THEN 'MODERATE'
		ELSE 'SEVERE'
	END AS delay_severity
FROM part1
ORDER BY delay_time;

—- How does each carrier's average transit time compare month on month —-

WITH part1 AS (
    SELECT 
        shipment_id,
        carrier_id,
        TO_CHAR(ship_date,'YYYY-MM') AS "month",
        actual_delivery,
        actual_delivery - ship_date AS actual_transit_time
    FROM shipments
    WHERE actual_delivery IS NOT NULL
),
part2 AS (
    SELECT 
        "month",
        carrier_id,
        ROUND(AVG(actual_transit_time),2) AS avg_actual_transit_time
    FROM part1
    GROUP BY "month", carrier_id
),
part3 AS (
    SELECT
        "month",
        carrier_id,
        avg_actual_transit_time,
        LAG(avg_actual_transit_time) OVER(PARTITION BY carrier_id ORDER BY "month") AS prev_month_transit_time
    FROM part2
)
SELECT
    "month",
    carrier_id,
    carrier_name,
    avg_actual_transit_time,
    prev_month_transit_time,
    ROUND(avg_actual_transit_time - prev_month_transit_time, 2) AS transit_time_change,
    CASE
        WHEN avg_actual_transit_time < prev_month_transit_time THEN 'IMPROVED'
        WHEN avg_actual_transit_time > prev_month_transit_time THEN 'DECLINED'
        WHEN avg_actual_transit_time = prev_month_transit_time THEN 'STABLE'
        ELSE 'N/A'
    END AS trend
FROM part3
JOIN carriers USING (carrier_id)
ORDER BY carrier_id, "month";

—- What is the total cost breakdown per shipment including all surcharges —-

WITH part1 AS (
SELECT 
	shipment_id,
	SUM(CASE WHEN charge_type = 'Fuel Surcharge' THEN amount_aed END) AS fuel_surcharge,
	SUM(CASE WHEN charge_type = 'Customs' THEN amount_aed END) AS customs,
	SUM(CASE WHEN charge_type = 'Handling' THEN amount_aed END) AS handling,
	SUM(CASE WHEN charge_type = 'Insurance' THEN amount_aed END) AS insurance
FROM charges
GROUP BY shipment_id
)
SELECT
	shipment_id,
	freight_charge_aed,
	fuel_surcharge,
	customs,
	handling,
	insurance,
	(freight_charge_aed + fuel_surcharge + customs + handling + insurance) AS grand_total
FROM part1
JOIN shipments
USING(shipment_id);

—- Which corridors generate the most revenue after all surcharges are included —-

Query -

WITH part1 AS (
SELECT 
	shipment_id,
	SUM(CASE WHEN charge_type = 'Fuel Surcharge' THEN amount_aed END) AS fuel_surcharge,
	SUM(CASE WHEN charge_type = 'Customs' THEN amount_aed END) AS customs,
	SUM(CASE WHEN charge_type = 'Handling' THEN amount_aed END) AS handling,
	SUM(CASE WHEN charge_type = 'Insurance' THEN amount_aed END) AS insurance
FROM charges
GROUP BY shipment_id
),
part2 AS (
SELECT
	shipment_id,
	route_id,
	freight_charge_aed,
	fuel_surcharge,
	customs,
	handling,
	insurance,
	(freight_charge_aed + fuel_surcharge + customs + handling + insurance) AS grand_total
FROM part1
JOIN shipments
USING(shipment_id)
),
part3 AS (
SELECT 
	shipment_id,
	corridor,
	freight_charge_aed,
	fuel_surcharge,
	customs,
	handling,
	insurance,
	grand_total
FROM part2
JOIN routes
USING (route_id)
)
SELECT
	corridor,
	SUM(grand_total) AS total_revenue
FROM part3
GROUP BY corridor
ORDER BY total_revenue DESC;

—- Create a reusable carrier performance summary —-

Query -

CREATE VIEW overview AS
WITH all_shipments AS (
    SELECT
        s.shipment_id,
        s.carrier_id,
        s.ship_date,
        s.expected_delivery,
        s.actual_delivery,
        s.freight_charge_aed,
        CASE WHEN s.actual_delivery IS NOT NULL
             THEN s.actual_delivery - s.ship_date END AS time_taken_days,
        CASE WHEN s.actual_delivery IS NOT NULL
             THEN s.actual_delivery - s.expected_delivery END AS difference_days
    FROM shipments s
),
charges_agg AS (
    SELECT
        shipment_id,
        SUM(CASE WHEN charge_type = 'Fuel Surcharge' THEN amount_aed END) AS fuel_surcharge,
        SUM(CASE WHEN charge_type = 'Customs' THEN amount_aed END) AS customs,
        SUM(CASE WHEN charge_type = 'Handling' THEN amount_aed END) AS handling,
        SUM(CASE WHEN charge_type = 'Insurance' THEN amount_aed END) AS insurance,
        SUM(amount_aed) AS total_charges
    FROM charges
    GROUP BY shipment_id
),
carrier_summary AS (
    SELECT
        a.carrier_id,
        COUNT(a.shipment_id) AS total_shipments,
        COUNT(a.actual_delivery) AS completed_shipments,
        COUNT(CASE WHEN difference_days <= 0 THEN 1 END) AS on_time_deliveries,
        ROUND(COUNT(CASE WHEN difference_days <= 0 THEN 1 END) * 100.0 /NULLIF(COUNT(a.actual_delivery), 0), 2) AS on_time_pct,
        ROUND(AVG(time_taken_days), 2) AS avg_days_taken,
        ROUND(AVG(difference_days), 2) AS avg_difference_days,
        ROUND(SUM(a.freight_charge_aed), 2) AS total_freight_charges,
        ROUND(SUM(c.fuel_surcharge), 2) AS total_fuel_surcharge,
        ROUND(SUM(c.customs), 2) AS total_customs,
        ROUND(SUM(c.handling), 2) AS total_handling,
        ROUND(SUM(c.insurance), 2) AS total_insurance,
        ROUND(SUM(c.total_charges), 2) AS total_overhead_charges,
        ROUND(SUM(a.freight_charge_aed + c.total_charges), 2) AS total_revenue

    FROM all_shipments a
    JOIN charges_agg c USING (shipment_id)
    GROUP BY a.carrier_id
)
SELECT
    cs.carrier_id,
    ca.carrier_name,
    ca.carrier_type,
    cs.total_shipments,
    cs.completed_shipments,
    cs.on_time_deliveries,
    cs.on_time_pct,
    cs.avg_days_taken,
    cs.avg_difference_days,
    cs.total_freight_charges,
    cs.total_fuel_surcharge,
    cs.total_customs,
    cs.total_handling,
    cs.total_insurance,
    cs.total_overhead_charges,
    cs.total_revenue
FROM carrier_summary cs
JOIN carriers ca USING (carrier_id)
ORDER BY cs.total_revenue DESC;

