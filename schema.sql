-- ZenSched Home-Care Local Database Schema
-- SQLite database for client records, care plans, caregiver roster, recurring
-- visit schedule, completed-visit log, payroll hours, and family invoicing.
-- DO NOT duplicate live schedule data from ZenSched (shifts, punches, timesheets).
--
-- HOW TO LOAD THIS FILE
--   Normal path: paste this whole file into your AI chat and say
--   "Create these tables in my homecare-ops database. Run each statement one at a time."
--   The AI runs each statement through the SQLite MCP tool (sqlite_execute).
--   Most SQLite MCP tools accept ONE statement per call, so every statement
--   below ends with a semicolon and stands alone.
--
--   Alternative (if you have the sqlite3 command-line tool):
--     sqlite3 homecare-ops.db < schema.sql
--
-- Every statement is idempotent (IF NOT EXISTS / INSERT OR IGNORE), so it is
-- safe to run this file again on an existing database.
--
-- PRIVACY / PHI: ZenSched does not sign a HIPAA Business Associate Agreement.
-- Everything that could identify a client's health condition lives ONLY in this
-- file on your computer: clients.care_plan, diagnoses, medications, allergies,
-- mobility_notes, emergency_contact, and addresses.access_notes (door codes,
-- alarm, parking). ZenSched receives only a short label per home (initials or a
-- house nickname), the street address for the GPS pin, and the Visit Record
-- form (task checklist, status flag, short note, optional signature).
-- SKILL.md forbids the agent from putting any of the local-only columns into a
-- ZenSched field.

-- Foreign keys are OFF by default in SQLite. This must be run once per
-- connection for ON DELETE CASCADE to work. SKILL.md tells the agent to run it
-- at the start of each session.
PRAGMA foreign_keys = ON;

-- Settings: small key/value store so the agent does not have to be re-told the
-- basics every session (timezone, rates, business name, form id).
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT OR IGNORE INTO settings (key, value) VALUES ('business_name', 'My Home Care Agency');
INSERT OR IGNORE INTO settings (key, value) VALUES ('timezone_offset', '-05:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_visit_minutes', '240');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_due_days', '14');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_prefix', 'INV');
INSERT OR IGNORE INTO settings (key, value) VALUES ('visit_record_form_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('event_window_days', '60');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_bill_rate', '32.00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_pay_rate', '18.00');

-- Clients: the people receiving care, plus the family member or payer who is
-- billed. Care-plan columns are LOCAL ONLY (PHI) and never leave this database.
CREATE TABLE IF NOT EXISTS clients (
  client_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_name TEXT NOT NULL,
  dob TEXT,                                         -- ISO date, optional
  payer_name TEXT,                                  -- family member / responsible party
  payer_relationship TEXT,                          -- 'daughter', 'spouse', 'POA', 'self'
  payer_phone TEXT,
  payer_email TEXT,
  payer_type TEXT NOT NULL DEFAULT 'private_pay'
    CHECK (payer_type IN ('private_pay', 'ltc_insurance', 'va', 'medicaid', 'other')),
  care_plan TEXT,                                   -- LOCAL ONLY: free-text plan of care
  diagnoses TEXT,                                   -- LOCAL ONLY
  medications TEXT,                                 -- LOCAL ONLY (caregiver reminds; does not administer)
  allergies TEXT,                                   -- LOCAL ONLY
  mobility_notes TEXT,                              -- LOCAL ONLY: walker, wheelchair, fall risk, transfer help
  emergency_contact TEXT,                           -- LOCAL ONLY: name + phone
  bill_rate REAL,                                   -- $/hour billed to payer; NULL = settings.default_bill_rate
  is_active INTEGER DEFAULT 1,                      -- 0 = on hold (hospital, respite elsewhere, discharged)
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Addresses: where care happens, with ZenSched references.
-- One ZenSched LOCATION per address, created once and kept forever.
-- One ZenSched EVENT per address per rolling window of at most 60 days
-- (ZenSched caps event length). zensched_event_id is the CURRENT event and
-- event_valid_until is its last valid date. When a visit date is later than
-- event_valid_until, the agent creates a new event and updates both columns.
-- zensched_label is the ONLY name sent to ZenSched for this home (initials or
-- a house nickname, e.g. 'Client 12 - Alvarez'); the full client name and
-- anything about their condition stay here.
CREATE TABLE IF NOT EXISTS addresses (
  address_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  label TEXT,                                       -- 'Home', 'Daughter''s house'
  address TEXT NOT NULL,
  address_line2 TEXT,
  city TEXT,
  state TEXT,
  zip TEXT,
  access_notes TEXT,                                -- LOCAL ONLY: door code, alarm, key, parking, dog
  zensched_label TEXT,                              -- de-identified name used on ZenSched
  zensched_location_id INTEGER,                     -- from location_create (permanent)
  zensched_event_id INTEGER,                        -- from event_create (current <=60-day window)
  event_valid_until TEXT,                           -- ISO date: last day the current event covers
  is_active INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE
);

-- Care tasks: what the caregiver is expected to do for this client (bathing,
-- meal prep, medication reminder, ...). The Visit Record checklist on the
-- phone confirms which of these were actually done each visit. LOCAL ONLY.
CREATE TABLE IF NOT EXISTS care_tasks (
  task_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  task TEXT NOT NULL,                               -- 'Bathing/Hygiene', 'Meal prepared', ...
  frequency_note TEXT,                              -- 'every visit', 'Mon and Fri only', 'as needed'
  is_active INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE
);

-- Caregivers: your roster. zensched_worker_id comes from worker_invite.
CREATE TABLE IF NOT EXISTS caregivers (
  caregiver_id INTEGER PRIMARY KEY AUTOINCREMENT,
  caregiver_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  zensched_worker_id INTEGER UNIQUE,                -- from worker_invite
  pay_rate REAL,                                    -- $/hour; NULL = settings.default_pay_rate
  certifications TEXT,                              -- 'CNA', 'HHA, CPR 2027-03'
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Visit schedule: the recurring template ("Mr. Alvarez: Mon/Wed/Fri 09:00, 4 h,
-- personal care, prefer Maria"). weekdays is a 7-character mask, Monday first:
-- '1010100' = Mon/Wed/Fri. A client with a morning AND an evening visit gets two
-- rows. Overnights are one row with start_time '20:00' and duration_minutes 720.
-- preferred_worker_id is the ZenSched worker id of the caregiver who should get
-- this visit (continuity of care). The agent expands this table into real
-- ZenSched shifts once a week using the visits_due_this_week view.
CREATE TABLE IF NOT EXISTS visit_schedule (
  schedule_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  address_id INTEGER NOT NULL,
  weekdays TEXT NOT NULL
    CHECK (length(weekdays) = 7 AND weekdays NOT GLOB '*[^01]*'),
  start_time TEXT NOT NULL                          -- 'HH:MM' 24-hour local time
    CHECK (start_time GLOB '[0-2][0-9]:[0-5][0-9]'),
  duration_minutes INTEGER NOT NULL DEFAULT 240
    CHECK (duration_minutes BETWEEN 30 AND 1440),
  preferred_worker_id INTEGER,                      -- ZenSched worker id; NULL = agent picks / flags unassigned
  service_type TEXT NOT NULL DEFAULT 'personal_care'
    CHECK (service_type IN ('companion', 'personal_care', 'respite', 'overnight', 'live_in', 'transport')),
  start_date TEXT,                                  -- first date this applies (NULL = already running)
  end_date TEXT,                                    -- last date (NULL = open-ended)
  is_active INTEGER DEFAULT 1,
  notes TEXT,                                       -- 'daughter home Fridays', 'bring groceries list'
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE,
  FOREIGN KEY (address_id) REFERENCES addresses(address_id) ON DELETE CASCADE
);

-- Visits: one row per COMPLETED visit, linked to the ZenSched shift and the
-- Visit Record submission. This is the billing record, the payroll record, and
-- the EVV-grade log (see evv_visit_log). Times are ISO 8601 with offset.
-- hours, bill_rate, pay_rate, and bill_amount are filled by trigger if left NULL
-- (hours from actual_in/actual_out, falling back to scheduled times; rates from
-- the client / caregiver / settings).
CREATE TABLE IF NOT EXISTS visits (
  visit_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  address_id INTEGER NOT NULL,
  schedule_id INTEGER,                              -- NULL for one-off visits
  caregiver_id INTEGER,                             -- local roster row (may be NULL if unknown)
  zensched_worker_id INTEGER,                       -- who ZenSched says did it
  zensched_shift_id INTEGER UNIQUE,                 -- prevents recording the same shift twice
  zensched_event_id INTEGER,
  visit_date TEXT NOT NULL,                         -- ISO date of the scheduled start
  service_type TEXT NOT NULL
    CHECK (service_type IN ('companion', 'personal_care', 'respite', 'overnight', 'live_in', 'transport')),
  scheduled_start TEXT,                             -- ISO datetime with offset
  scheduled_end TEXT,
  actual_in TEXT,                                   -- from shift_status / timesheet_export
  actual_out TEXT,
  gps_verified INTEGER,                             -- 1 if both punches were on site
  hours REAL,                                       -- billable/payable hours (trigger fills if NULL)
  bill_rate REAL,                                   -- $/h snapshot at recording time
  bill_amount REAL,                                 -- hours * bill_rate (trigger fills if NULL)
  pay_rate REAL,                                    -- $/h snapshot at recording time
  report_dc_id INTEGER,                             -- Visit Record submission_id
  tasks_done TEXT,                                  -- JSON array of option keys from the form
  client_status TEXT NOT NULL DEFAULT 'ok'
    CHECK (client_status IN ('ok', 'concern', 'urgent')),
  concern_details TEXT,
  client_ate TEXT CHECK (client_ate IS NULL OR client_ate IN ('Yes', 'Partially', 'No', 'Not applicable')),
  note TEXT,                                        -- "Note for family" from the form
  signed INTEGER DEFAULT 0,                         -- 1 if the client/family signature was captured
  invoiced INTEGER DEFAULT 0,                       -- 1 = included in an invoice
  paid_out INTEGER DEFAULT 0,                       -- 1 = included in a payroll export
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE,
  FOREIGN KEY (address_id) REFERENCES addresses(address_id) ON DELETE CASCADE,
  FOREIGN KEY (schedule_id) REFERENCES visit_schedule(schedule_id) ON DELETE SET NULL,
  FOREIGN KEY (caregiver_id) REFERENCES caregivers(caregiver_id) ON DELETE SET NULL
);

-- Invoices: billed to the family payer on the client row.
-- invoice_number is filled in automatically by a trigger if left NULL.
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  invoice_number TEXT UNIQUE,                       -- human-readable: 'INV-2026-0001'
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  total_hours REAL,
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,                           -- 1 = paid, 0 = unpaid
  paid_date TEXT,
  sent_date TEXT,                                   -- when you actually emailed/texted it
  line_items TEXT,                                  -- JSON array: one object per visit (date, hours, rate, amount)
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_addresses_client ON addresses(client_id);
CREATE INDEX IF NOT EXISTS idx_addresses_zensched_event ON addresses(zensched_event_id);
CREATE INDEX IF NOT EXISTS idx_addresses_zensched_location ON addresses(zensched_location_id);
CREATE INDEX IF NOT EXISTS idx_care_tasks_client ON care_tasks(client_id, is_active);
CREATE INDEX IF NOT EXISTS idx_schedule_client ON visit_schedule(client_id, is_active);
CREATE INDEX IF NOT EXISTS idx_schedule_address ON visit_schedule(address_id);
CREATE INDEX IF NOT EXISTS idx_visits_client_date ON visits(client_id, visit_date);
CREATE INDEX IF NOT EXISTS idx_visits_schedule_date ON visits(schedule_id, visit_date);
CREATE INDEX IF NOT EXISTS idx_visits_caregiver ON visits(caregiver_id, paid_out);
CREATE INDEX IF NOT EXISTS idx_visits_invoiced ON visits(invoiced);
CREATE INDEX IF NOT EXISTS idx_visits_status ON visits(client_status, visit_date);
CREATE INDEX IF NOT EXISTS idx_invoices_client ON invoices(client_id);
CREATE INDEX IF NOT EXISTS idx_invoices_paid ON invoices(paid);

-- Keep updated_at current
CREATE TRIGGER IF NOT EXISTS update_client_timestamp
AFTER UPDATE ON clients
BEGIN
  UPDATE clients SET updated_at = datetime('now') WHERE client_id = NEW.client_id;
END;

CREATE TRIGGER IF NOT EXISTS update_address_timestamp
AFTER UPDATE ON addresses
BEGIN
  UPDATE addresses SET updated_at = datetime('now') WHERE address_id = NEW.address_id;
END;

CREATE TRIGGER IF NOT EXISTS update_caregiver_timestamp
AFTER UPDATE ON caregivers
BEGIN
  UPDATE caregivers SET updated_at = datetime('now') WHERE caregiver_id = NEW.caregiver_id;
END;

CREATE TRIGGER IF NOT EXISTS update_schedule_timestamp
AFTER UPDATE ON visit_schedule
BEGIN
  UPDATE visit_schedule SET updated_at = datetime('now') WHERE schedule_id = NEW.schedule_id;
END;

-- Fill derived visit columns when the agent leaves them NULL:
--   caregiver_id  <- caregivers row whose zensched_worker_id matches
--   bill_rate     <- clients.bill_rate, else settings.default_bill_rate
--   pay_rate      <- caregivers.pay_rate, else settings.default_pay_rate
--   hours         <- actual_out - actual_in (2 dp), else scheduled_end - scheduled_start
--   bill_amount   <- hours * bill_rate
-- SQLite date functions understand ISO strings with a '-05:00' style offset, so
-- the subtraction is correct across midnight (overnight shifts) as long as both
-- ends carry an offset.
CREATE TRIGGER IF NOT EXISTS fill_visit_derived
AFTER INSERT ON visits
BEGIN
  UPDATE visits
  SET caregiver_id = COALESCE(NEW.caregiver_id,
                              (SELECT caregiver_id FROM caregivers WHERE zensched_worker_id = NEW.zensched_worker_id)),
      bill_rate = COALESCE(NEW.bill_rate,
                           (SELECT bill_rate FROM clients WHERE client_id = NEW.client_id),
                           (SELECT CAST(value AS REAL) FROM settings WHERE key = 'default_bill_rate')),
      pay_rate = COALESCE(NEW.pay_rate,
                          (SELECT pay_rate FROM caregivers WHERE caregiver_id = COALESCE(NEW.caregiver_id,
                             (SELECT caregiver_id FROM caregivers WHERE zensched_worker_id = NEW.zensched_worker_id))),
                          (SELECT CAST(value AS REAL) FROM settings WHERE key = 'default_pay_rate')),
      hours = COALESCE(NEW.hours,
                       CASE WHEN NEW.actual_in IS NOT NULL AND NEW.actual_out IS NOT NULL
                            THEN round((julianday(NEW.actual_out) - julianday(NEW.actual_in)) * 24.0, 2) END,
                       CASE WHEN NEW.scheduled_start IS NOT NULL AND NEW.scheduled_end IS NOT NULL
                            THEN round((julianday(NEW.scheduled_end) - julianday(NEW.scheduled_start)) * 24.0, 2) END)
  WHERE visit_id = NEW.visit_id;
  UPDATE visits
  SET bill_amount = COALESCE(NEW.bill_amount, round(hours * bill_rate, 2))
  WHERE visit_id = NEW.visit_id;
END;

-- Auto-number invoices: INV-2026-0001, INV-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_invoice
AFTER INSERT ON invoices
WHEN NEW.invoice_number IS NULL
BEGIN
  UPDATE invoices
  SET invoice_number = (SELECT COALESCE(value, 'INV') FROM settings WHERE key = 'invoice_prefix')
                       || '-' || strftime('%Y', NEW.invoice_date)
                       || '-' || printf('%04d', NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
END;

-- Every visit that should happen in the next 7 days (today + 6), expanded from
-- visit_schedule, minus dates already recorded in visits. The agent's weekly
-- scheduling query. One row = one shift_create call. Columns ending in _iso
-- are ready to pass as shift_create start/end; idempotency_key is ready too.
-- worker_id = preferred_worker_id, else the caregiver who most recently did
-- this schedule row (continuity), else NULL (unassigned = 1: the agent must ask).
-- event_needs_roll = 1 means create a new ZenSched event first (see SKILL.md).
CREATE VIEW IF NOT EXISTS visits_due_this_week AS
WITH RECURSIVE days(d) AS (
  SELECT date('now')
  UNION ALL
  SELECT date(d, '+1 day') FROM days WHERE d < date('now', '+6 days')
)
SELECT
  days.d                                     AS visit_date,
  s.schedule_id,
  c.client_id,
  c.client_name,
  a.address_id,
  a.address,
  a.city,
  a.zensched_label,
  a.zensched_location_id,
  a.zensched_event_id,
  a.event_valid_until,
  CASE WHEN a.event_valid_until IS NULL OR a.event_valid_until < days.d THEN 1 ELSE 0 END AS event_needs_roll,
  s.service_type,
  s.start_time,
  s.duration_minutes,
  COALESCE(s.preferred_worker_id,
           (SELECT v.zensched_worker_id FROM visits v
             WHERE v.schedule_id = s.schedule_id AND v.zensched_worker_id IS NOT NULL
             ORDER BY v.visit_date DESC LIMIT 1)) AS worker_id,
  (SELECT cg.caregiver_name FROM caregivers cg
    WHERE cg.zensched_worker_id = COALESCE(s.preferred_worker_id,
           (SELECT v.zensched_worker_id FROM visits v
             WHERE v.schedule_id = s.schedule_id AND v.zensched_worker_id IS NOT NULL
             ORDER BY v.visit_date DESC LIMIT 1))) AS caregiver_name,
  CASE WHEN COALESCE(s.preferred_worker_id,
           (SELECT v.zensched_worker_id FROM visits v
             WHERE v.schedule_id = s.schedule_id AND v.zensched_worker_id IS NOT NULL
             ORDER BY v.visit_date DESC LIMIT 1)) IS NULL THEN 1 ELSE 0 END AS unassigned,
  days.d || 'T' || s.start_time || ':00' || (SELECT value FROM settings WHERE key = 'timezone_offset') AS start_iso,
  strftime('%Y-%m-%dT%H:%M:%S', datetime(days.d || ' ' || s.start_time || ':00', '+' || s.duration_minutes || ' minutes'))
    || (SELECT value FROM settings WHERE key = 'timezone_offset') AS end_iso,
  'shift-address-' || a.address_id || '-' || strftime('%Y%m%d', days.d) || '-' || replace(s.start_time, ':', '') AS idempotency_key,
  s.notes                                    AS schedule_notes
FROM days
JOIN visit_schedule s
  ON s.is_active = 1
 AND substr(s.weekdays, CASE strftime('%w', days.d) WHEN '0' THEN 7 ELSE CAST(strftime('%w', days.d) AS INTEGER) END, 1) = '1'
 AND (s.start_date IS NULL OR s.start_date <= days.d)
 AND (s.end_date IS NULL OR s.end_date >= days.d)
JOIN clients c ON c.client_id = s.client_id AND c.is_active = 1
JOIN addresses a ON a.address_id = s.address_id AND a.is_active = 1
WHERE NOT EXISTS (
  SELECT 1 FROM visits v WHERE v.schedule_id = s.schedule_id AND v.visit_date = days.d
)
ORDER BY days.d, s.start_time, c.client_name;

-- Addresses whose current ZenSched event expires within 14 days (or has none)
-- and that still have an active recurring schedule. Roll these proactively.
CREATE VIEW IF NOT EXISTS events_expiring AS
SELECT
  a.address_id,
  c.client_name,
  a.zensched_label,
  a.address,
  a.zensched_location_id,
  a.zensched_event_id,
  a.event_valid_until
FROM addresses a
JOIN clients c ON c.client_id = a.client_id AND c.is_active = 1
WHERE a.is_active = 1
  AND EXISTS (SELECT 1 FROM visit_schedule s WHERE s.address_id = a.address_id AND s.is_active = 1)
  AND (a.event_valid_until IS NULL OR a.event_valid_until <= date('now', '+14 days'))
ORDER BY a.event_valid_until;

-- Completed visits that have not been invoiced yet, grouped by client, with the
-- payer contact the invoice goes to.
CREATE VIEW IF NOT EXISTS visits_to_invoice AS
SELECT
  c.client_id,
  c.client_name,
  c.payer_name,
  c.payer_email,
  c.payer_phone,
  c.payer_type,
  COUNT(v.visit_id)     AS visit_count,
  SUM(v.hours)          AS total_hours,
  SUM(v.bill_amount)    AS total_amount,
  MIN(v.visit_date)     AS first_visit_date,
  MAX(v.visit_date)     AS last_visit_date
FROM visits v
JOIN clients c ON c.client_id = v.client_id
WHERE v.invoiced = 0
GROUP BY c.client_id
ORDER BY c.client_name;

-- Unpaid invoices, oldest first.
CREATE VIEW IF NOT EXISTS invoices_outstanding AS
SELECT
  i.invoice_id,
  i.invoice_number,
  c.client_name,
  c.payer_name,
  c.payer_email,
  i.invoice_date,
  i.due_date,
  i.total_hours,
  i.total_amount,
  i.sent_date,
  CASE WHEN i.due_date < date('now') THEN 1 ELSE 0 END AS overdue
FROM invoices i
JOIN clients c ON c.client_id = i.client_id
WHERE i.paid = 0
ORDER BY i.due_date;

-- EVV-grade visit log: the six 21st Century Cures Act elements per visit
-- (type of service, individual receiving service, date, location, individual
-- providing service, time in / time out), from local visits joined to what the
-- agent recorded from ZenSched shift_status / timesheet_export. ZenSched is not
-- a certified EVV vendor and this view does not submit anywhere; it gives a
-- private-pay agency EVV-grade records and a Medicaid agency a CSV-ready export
-- for an alternate-EVV-vendor path.
CREATE VIEW IF NOT EXISTS evv_visit_log AS
SELECT
  v.visit_id,
  v.service_type                                   AS evv_service_type,
  c.client_name                                    AS evv_individual_receiving,
  v.visit_date                                     AS evv_date_of_service,
  a.address || COALESCE(', ' || a.city, '') || COALESCE(' ' || a.state, '') || COALESCE(' ' || a.zip, '') AS evv_location,
  COALESCE(cg.caregiver_name, 'worker ' || v.zensched_worker_id) AS evv_individual_providing,
  v.actual_in                                      AS evv_time_in,
  v.actual_out                                     AS evv_time_out,
  v.hours,
  v.gps_verified,
  v.zensched_shift_id,
  v.zensched_worker_id,
  v.report_dc_id,
  v.signed
FROM visits v
JOIN clients c ON c.client_id = v.client_id
JOIN addresses a ON a.address_id = v.address_id
LEFT JOIN caregivers cg ON cg.caregiver_id = v.caregiver_id
ORDER BY v.visit_date, v.actual_in;

-- Hours worked that have not yet been included in a payroll run, per caregiver.
-- pay_rate is the snapshot on the visit (falls back to the roster / default).
CREATE VIEW IF NOT EXISTS payroll_hours_unpaid AS
SELECT
  cg.caregiver_id,
  cg.caregiver_name,
  cg.zensched_worker_id,
  COUNT(v.visit_id)                                              AS visit_count,
  SUM(v.hours)                                                   AS total_hours,
  SUM(round(v.hours * COALESCE(v.pay_rate, cg.pay_rate,
        (SELECT CAST(value AS REAL) FROM settings WHERE key = 'default_pay_rate')), 2)) AS gross_pay,
  MIN(v.visit_date)                                              AS first_visit_date,
  MAX(v.visit_date)                                              AS last_visit_date
FROM visits v
JOIN caregivers cg ON cg.caregiver_id = v.caregiver_id
WHERE v.paid_out = 0
GROUP BY cg.caregiver_id
ORDER BY cg.caregiver_name;

-- Visits in the last 14 days where the caregiver flagged the client as
-- 'concern' or 'urgent'. Lead with these in every summary.
CREATE VIEW IF NOT EXISTS open_concerns AS
SELECT
  v.visit_id,
  v.visit_date,
  v.client_status,
  c.client_id,
  c.client_name,
  c.payer_name,
  c.payer_phone,
  cg.caregiver_name,
  v.concern_details,
  v.client_ate,
  v.note,
  v.zensched_shift_id,
  v.report_dc_id
FROM visits v
JOIN clients c ON c.client_id = v.client_id
LEFT JOIN caregivers cg ON cg.caregiver_id = v.caregiver_id
WHERE v.client_status <> 'ok'
  AND v.visit_date >= date('now', '-14 days')
ORDER BY CASE v.client_status WHEN 'urgent' THEN 0 ELSE 1 END, v.visit_date DESC;
