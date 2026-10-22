-- 06_dw_load.sql
-- Mengisi dimensi dan fakta dari staging. Full reload (DELETE lalu INSERT);
-- pemuatan inkremental per periode cukup menambah filter period.

DELETE FROM fact_upload_submission;
DELETE FROM fact_audit_exception;
DELETE FROM fact_refund;
DELETE FROM fact_bank_mutation;
DELETE FROM fact_ticket_sale;
DELETE FROM dim_audit_rule;
DELETE FROM dim_source_dept;
DELETE FROM dim_group_order;
DELETE FROM dim_customer;
DELETE FROM dim_discount;
DELETE FROM dim_payment_method;
DELETE FROM dim_channel;
DELETE FROM dim_employee;
DELETE FROM dim_station;
DELETE FROM dim_date;

INSERT INTO dim_date
SELECT CAST(EXTRACT(YEAR FROM d) * 10000 + EXTRACT(MONTH FROM d) * 100 + EXTRACT(DAY FROM d) AS INTEGER),
       d, EXTRACT(YEAR FROM d), EXTRACT(QUARTER FROM d), EXTRACT(MONTH FROM d), EXTRACT(DAY FROM d),
       CAST(EXTRACT(YEAR FROM d) AS VARCHAR) || '-' || LPAD(CAST(EXTRACT(MONTH FROM d) AS VARCHAR), 2, '0')
FROM (
    SELECT purchase_date AS d FROM stg_ticket_sales
    UNION SELECT departure_date FROM stg_ticket_sales
    UNION SELECT posting_date FROM stg_bank_statement
    UNION SELECT refund_date FROM stg_refund
) x
WHERE d IS NOT NULL;

INSERT INTO dim_station
SELECT ROW_NUMBER() OVER (ORDER BY station_code), station_code, station_name, business_area, is_physical
FROM (
    SELECT DISTINCT origin_code AS station_code, origin_name AS station_name, business_area, 'Y' AS is_physical
    FROM stg_ticket_sales
    UNION
    SELECT 'ONLINE', 'Kanal online', NULL, 'N'
) s;

INSERT INTO dim_employee
SELECT ROW_NUMBER() OVER (ORDER BY employee_id), employee_id, employee_name, department, station_code, position
FROM stg_employee;

INSERT INTO dim_channel
SELECT ROW_NUMBER() OVER (ORDER BY ticketing_channel), ticketing_channel,
       CASE ticketing_channel WHEN 'COUNTER' THEN 'LOKET' WHEN 'TVM' THEN 'MESIN'
                              WHEN 'B2B' THEN 'B2B' ELSE 'ONLINE' END
FROM (SELECT DISTINCT ticketing_channel FROM stg_ticket_sales) c;

INSERT INTO dim_payment_method
SELECT ROW_NUMBER() OVER (ORDER BY payment_method, payment_gateway), payment_method, payment_gateway,
       CASE WHEN payment_method = 'CASH' THEN 'Y' ELSE 'N' END
FROM (SELECT DISTINCT payment_method, payment_gateway FROM stg_ticket_sales) p;

INSERT INTO dim_discount
SELECT ROW_NUMBER() OVER (ORDER BY discount_type, discount_rate), discount_type, discount_rate
FROM (SELECT DISTINCT discount_type, discount_rate FROM stg_ticket_sales) d;

INSERT INTO dim_customer
SELECT ROW_NUMBER() OVER (ORDER BY customer_hash), customer_hash, nationality,
       CASE WHEN nationality = 'IDN' THEN 'N' ELSE 'Y' END
FROM (SELECT customer_hash, MIN(nationality) AS nationality FROM stg_ticket_sales GROUP BY customer_hash) c;

INSERT INTO dim_group_order
SELECT ROW_NUMBER() OVER (ORDER BY bak_id), bak_id, bak_no, order_no, counterparty_name,
       discount_rate, ticket_count, total_amount
FROM stg_bak;

INSERT INTO dim_source_dept
SELECT ROW_NUMBER() OVER (ORDER BY department), department
FROM (SELECT DISTINCT department FROM ref_upload_obligation
      UNION SELECT DISTINCT source_dept FROM audit_exception) d;

INSERT INTO dim_audit_rule
SELECT ROW_NUMBER() OVER (ORDER BY rule_code), rule_code, rule_name, category, severity
FROM ref_audit_rule;

INSERT INTO fact_ticket_sale
SELECT t.ticket_no, t.order_no,
       CAST(EXTRACT(YEAR FROM t.purchase_date) * 10000 + EXTRACT(MONTH FROM t.purchase_date) * 100 + EXTRACT(DAY FROM t.purchase_date) AS INTEGER),
       CAST(EXTRACT(YEAR FROM t.departure_date) * 10000 + EXTRACT(MONTH FROM t.departure_date) * 100 + EXTRACT(DAY FROM t.departure_date) AS INTEGER),
       ss.station_key, so.station_key, sd.station_key,
       c.channel_key, p.payment_key, d.discount_key, e.employee_key, cu.customer_key, g.group_order_key,
       t.shift_no, t.seat_class,
       t.original_ticket_price,
       t.original_ticket_price - t.before_tax_price,
       t.before_tax_price,
       t.after_tax_price - t.before_tax_price,
       t.after_tax_price
FROM cur_ticket t
JOIN dim_station ss ON ss.station_code = t.ticketing_station
JOIN dim_station so ON so.station_code = t.origin_code
JOIN dim_station sd ON sd.station_code = t.destination_code
JOIN dim_channel c ON c.channel_code = t.ticketing_channel
JOIN dim_payment_method p ON p.payment_method = t.payment_method
                         AND COALESCE(p.payment_gateway, '-') = COALESCE(t.payment_gateway, '-')
JOIN dim_discount d ON d.discount_type = t.discount_type AND d.discount_rate = t.discount_rate
JOIN dim_customer cu ON cu.customer_hash = t.customer_hash
LEFT JOIN dim_employee e ON UPPER(e.employee_name) = UPPER(t.operator_name)
LEFT JOIN dim_group_order g ON g.bak_id = t.bak_id;

INSERT INTO fact_bank_mutation
SELECT bank_ref,
       CAST(EXTRACT(YEAR FROM posting_date) * 10000 + EXTRACT(MONTH FROM posting_date) * 100 + EXTRACT(DAY FROM posting_date) AS INTEGER),
       txn_category, debit, credit
FROM stg_bank_statement;

INSERT INTO fact_refund
SELECT f.refund_id, f.ticket_no,
       CAST(EXTRACT(YEAR FROM f.refund_date) * 10000 + EXTRACT(MONTH FROM f.refund_date) * 100 + EXTRACT(DAY FROM f.refund_date) AS INTEGER),
       s.station_key, t.customer_key, f.refund_method, f.ticket_price, f.refund_amount
FROM stg_refund f
JOIN dim_station s ON s.station_code = f.station_code
LEFT JOIN (SELECT ft.ticket_no, ft.customer_key FROM fact_ticket_sale ft) t ON t.ticket_no = f.ticket_no;

INSERT INTO fact_audit_exception
SELECT r.rule_key, d.dept_key, a.period, a.entity_type, a.entity_id, 1
FROM audit_exception a
JOIN dim_audit_rule r ON r.rule_code = a.rule_code
JOIN dim_source_dept d ON d.department = a.source_dept;

INSERT INTO fact_upload_submission
SELECT d.dept_key, u.source_type, u.station_code, u.period, u.revisions,
       CASE WHEN u.revisions > 0 THEN 1 ELSE 0 END,
       CASE WHEN u.first_passed_at <= u.deadline_at THEN 1 ELSE 0 END,
       CASE WHEN u.final_validation = 'PASSED' THEN 1 ELSE 0 END,
       CASE WHEN u.final_approval = 'APPROVED' THEN 1 ELSE 0 END,
       CASE WHEN u.storage_sha256 = u.checksum_sha256 THEN 1 ELSE 0 END
FROM upload_submission u
JOIN dim_source_dept d ON d.department = u.department;
