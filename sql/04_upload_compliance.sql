-- 04_upload_compliance.sql
-- Kepatuhan unggah lewat portal: satu baris per kewajiban (departemen, sumber,
-- stasiun, periode), lalu aturan U01-U06 dan indikator kepatuhan per departemen.

-- Periode yang wajib diunggah = periode yang ada di export ticketing.
CREATE VIEW upload_submission AS
WITH periods AS (
    SELECT DISTINCT period FROM stg_ticket_sales
),
expected AS (
    SELECT o.department, o.source_type, o.station_code, p.period, o.max_revision
    FROM ref_upload_obligation o CROSS JOIN periods p
),
agg AS (
    SELECT department, source_type, station_code, period,
           COUNT(*)                                                         AS revisions,
           MAX(revision_no)                                                 AS last_revision,
           MIN(CASE WHEN validation_status = 'PASSED' THEN uploaded_at END) AS first_passed_at,
           MAX(deadline_at)                                                 AS deadline_at
    FROM stg_upload_log
    GROUP BY department, source_type, station_code, period
)
SELECT e.department, e.source_type, e.station_code, e.period, e.max_revision,
       e.department || '|' || e.source_type || '|' || e.station_code || '|' || e.period AS submission_id,
       COALESCE(a.revisions, 0) AS revisions,
       a.first_passed_at, a.deadline_at,
       l.validation_status AS final_validation,
       l.approval_status   AS final_approval,
       l.file_name, l.checksum_sha256,
       i.sha256            AS storage_sha256
FROM expected e
LEFT JOIN agg a
  ON a.department = e.department AND a.source_type = e.source_type
 AND a.station_code = e.station_code AND a.period = e.period
LEFT JOIN stg_upload_log l
  ON l.department = e.department AND l.source_type = e.source_type
 AND l.station_code = e.station_code AND l.period = e.period AND l.revision_no = a.last_revision
LEFT JOIN stg_object_inventory i
  ON i.file_name = l.file_name;

INSERT INTO audit_exception
SELECT 'U01_LATE_UPLOAD', 'submission', submission_id, department, period,
       'Lolos validasi pertama ' || CAST(first_passed_at AS VARCHAR) || ', tenggat ' || CAST(deadline_at AS VARCHAR)
FROM upload_submission
WHERE first_passed_at > deadline_at;

INSERT INTO audit_exception
SELECT 'U02_MISSING_UPLOAD', 'submission', submission_id, department, period, 'Tidak ada unggahan'
FROM upload_submission
WHERE revisions = 0;

INSERT INTO audit_exception
SELECT 'U03_VALIDATION_FAILED', 'submission', submission_id, department, period,
       'Revisi terakhir gagal validasi'
FROM upload_submission
WHERE final_validation = 'FAILED';

INSERT INTO audit_exception
SELECT 'U04_NOT_APPROVED', 'submission', submission_id, department, period,
       'Status persetujuan: ' || COALESCE(final_approval, '-')
FROM upload_submission
WHERE final_validation = 'PASSED' AND COALESCE(final_approval, '') <> 'APPROVED';

INSERT INTO audit_exception
SELECT 'U05_EXCESSIVE_REVISION', 'submission', submission_id, department, period,
       CAST(revisions AS VARCHAR) || ' revisi, batas ' || CAST(max_revision AS VARCHAR)
FROM upload_submission
WHERE revisions > max_revision;

INSERT INTO audit_exception
SELECT 'U06_CHECKSUM_MISMATCH', 'submission', submission_id, department, period,
       'Checksum unggah ' || SUBSTRING(checksum_sha256 FROM 1 FOR 12) || '..., storage ' ||
       SUBSTRING(COALESCE(storage_sha256, '-') FROM 1 FOR 12) || '...'
FROM upload_submission
WHERE revisions > 0 AND (storage_sha256 IS NULL OR storage_sha256 <> checksum_sha256);

-- Indikator kepatuhan unggah per departemen dan periode (untuk dashboard).
CREATE VIEW upload_compliance_kpi AS
SELECT department, period,
       COUNT(*)                                                                    AS obligations,
       SUM(CASE WHEN revisions > 0 THEN 1 ELSE 0 END)                              AS submitted,
       SUM(CASE WHEN first_passed_at <= deadline_at THEN 1 ELSE 0 END)             AS on_time,
       SUM(CASE WHEN final_validation = 'PASSED' AND final_approval = 'APPROVED'
                 AND storage_sha256 = checksum_sha256 THEN 1 ELSE 0 END)           AS accepted,
       ROUND(100.0 * SUM(CASE WHEN first_passed_at <= deadline_at THEN 1 ELSE 0 END) / COUNT(*), 1)
                                                                                   AS on_time_pct,
       ROUND(AVG(CAST(revisions AS DECIMAL(5,2))), 2)                              AS avg_revisions
FROM upload_submission
GROUP BY department, period;
