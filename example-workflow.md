# Example Workflow: What the AI Does Behind Each Request

This shows the exact tool calls the agent makes for a first week of operation, following `SKILL.md`. The owner only types the quoted lines; everything else is the agent's work. Assumes setup from `QUICKSTART.md` is complete (both MCP servers configured, `schema.sql` loaded, `SKILL.md` given as instructions).

IDs and responses are illustrative. ZenSched IDs are integers. Watch what does **not** cross to ZenSched: names of conditions, medications, the door code, the family's phone number. ZenSched sees `Client 1 - Alvarez`, a street address, and a checklist.

## Session start (every session)

```
sqlite_execute: PRAGMA foreign_keys = ON;
sqlite_query:   SELECT key, value FROM settings;
  → business_name = My Home Care Agency, timezone_offset = -05:00,
    default_visit_minutes = 240, invoice_due_days = 14, invoice_prefix = INV,
    visit_record_form_id = NULL, event_window_days = 60,
    default_bill_rate = 32.00, default_pay_rate = 18.00
sqlite_query:   SELECT * FROM open_concerns;   → (none)
```

## "We're Bright Path Home Care in Austin, Texas, Central time. We bill $30 an hour and pay caregivers $18 unless I say otherwise."

```
sqlite_execute: UPDATE settings SET value = 'Bright Path Home Care' WHERE key = 'business_name';
sqlite_execute: UPDATE settings SET value = '-05:00' WHERE key = 'timezone_offset';
sqlite_execute: UPDATE settings SET value = '30.00' WHERE key = 'default_bill_rate';
sqlite_execute: UPDATE settings SET value = '18.00' WHERE key = 'default_pay_rate';
```

> Saved. I'll schedule everything in Central time (-05:00). You don't have a Visit Record form yet; it's free to create and every visit comes back with a task checklist, a client-status flag, and an optional family signature. It collects no medical detail. Want me to set it up now?

Owner: *"yes"*

```
form_create:
  title: "Visit Record"
  idempotency_key: "form-visit-record"
  fields_json: (the JSON below, passed as one string)
```

```json
[
  {"type": "section", "label": "Visit record", "text": "Complete before you leave. Tick every task you did. Do not write diagnoses or medication names here."},
  {"type": "multi_select", "label": "Tasks completed", "identifier": "tasks_completed", "required": true,
   "options": ["Bathing/Hygiene", "Dressing", "Toileting", "Meal prepared", "Fed / hydration", "Medication reminder given",
               "Mobility / transfer assist", "Light housekeeping", "Laundry", "Transportation / errand", "Companionship / activity", "Exercise"]},
  {"type": "select", "label": "Client status", "identifier": "client_status", "required": true,
   "options": ["As usual", "Some concern", "Urgent - call office"]},
  {"type": "textarea", "label": "Concern details", "identifier": "concern_details",
   "show_if": {"field": "client_status", "op": "not_equals", "value": "as_usual", "action": "show"}},
  {"type": "select", "label": "Client ate", "identifier": "client_ate", "required": true,
   "options": ["Yes", "Partially", "No", "Not applicable"]},
  {"type": "textarea", "label": "Note for family (optional)", "identifier": "note_for_family"},
  {"type": "signature", "label": "Client or family signature", "identifier": "client_signature"}
]
```

```
  → form_id: 301, fields: [ ...7 fields echoed with identifiers... ]

sqlite_execute: UPDATE settings SET value = '301' WHERE key = 'visit_record_form_id';
```

> Visit Record form created. I'll attach it to every client's home automatically. One thing to know: on the phone the signature step is what submits the form, so if a client can't sign, the caregiver signs and says so in the note.

## "Add a client: Roberto Alvarez, born 1941-03-12, 118 Elm Street, Austin TX 78704. Daughter Lucia Alvarez pays, 512-555-0101, lucia@example.com. Parkinson's, mild dementia, fall risk, uses a walker. Meds are carbidopa-levodopa 8am and 2pm, donepezil at night; we remind, we don't administer. Allergic to penicillin. Door code 2468, small dog is friendly. Personal care Mon/Wed/Fri 9 to 1 starting Monday 9/7, $34 an hour. Give him to Maria once she's set up."

```
sqlite_execute:
  INSERT INTO clients (client_name, dob, payer_name, payer_relationship, payer_phone, payer_email, payer_type,
                       care_plan, diagnoses, medications, allergies, mobility_notes, emergency_contact, bill_rate)
  VALUES ('Roberto Alvarez', '1941-03-12', 'Lucia Alvarez', 'daughter', '512-555-0101', 'lucia@example.com', 'private_pay',
          'Morning routine: bathing, dressing, breakfast, med reminder 8am, light housekeeping, lunch prep. Encourage walker use.',
          'Parkinson''s disease; mild dementia; fall risk', 'Carbidopa-levodopa 8am and 2pm; donepezil at night (reminder only)',
          'Penicillin', 'Uses walker; needs standby assist for transfers', 'Lucia Alvarez 512-555-0101', 34.00);
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO addresses (client_id, address, city, state, zip, access_notes, zensched_label)
  VALUES (1, '118 Elm Street', 'Austin', 'TX', '78704', 'Door code 2468. Small friendly dog (Pepe).', 'Client 1 - Alvarez');
  → lastInsertRowid = 1

sqlite_execute: INSERT INTO care_tasks (client_id, task, frequency_note) VALUES (1, 'Bathing/Hygiene', 'every visit');
sqlite_execute: INSERT INTO care_tasks (client_id, task, frequency_note) VALUES (1, 'Dressing', 'every visit');
sqlite_execute: INSERT INTO care_tasks (client_id, task, frequency_note) VALUES (1, 'Meal prepared', 'breakfast and lunch');
sqlite_execute: INSERT INTO care_tasks (client_id, task, frequency_note) VALUES (1, 'Medication reminder given', '8am dose');
sqlite_execute: INSERT INTO care_tasks (client_id, task, frequency_note) VALUES (1, 'Mobility / transfer assist', 'as needed, standby');
sqlite_execute: INSERT INTO care_tasks (client_id, task, frequency_note) VALUES (1, 'Light housekeeping', 'every visit');

sqlite_execute:
  INSERT INTO visit_schedule (client_id, address_id, weekdays, start_time, duration_minutes, service_type, start_date)
  VALUES (1, 1, '1010100', '09:00', 240, 'personal_care', '2026-09-07');
  → lastInsertRowid = 1
```

`preferred_worker_id` is left NULL for now; Maria has not been invited yet.

Agent (first metered call this session, rule 9):

> Creating the Alvarez home on ZenSched costs $0.03 for geocoding. If your account isn't funded yet you'll get a prompt for the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
location_create:
  name: "Client 1 - Alvarez"
  street_address: "118 Elm Street, Austin, TX 78704"
  checkin_radius_m: 75
  idempotency_key: "loc-address-1"
  → location_id: 9001, lat: 30.2450, lng: -97.7620, pin_quality: "street",
    radius_note: "Check-in radius is enforced by the talent policy ...",
    billing: { meter: "geocode", units: 1, price: 0.03 }
```

Nothing about Parkinson's, the medications, or the door code is in `name` or `notes`. Those live only in `clients` and `addresses.access_notes`.

```
event_create:
  location_id: 9001
  title: "Home care - Client 1 - Alvarez"
  start_date: "2026-09-07"
  end_date:   "2026-11-05"          ← start + 59 days (60-day cap)
  idempotency_key: "event-address-1-20260907"
  → event_id: 7001

form_assign:
  form_id: 301
  event_id: 7001
  idempotency_key: "assign-visit-record-7001"
  → status: "assigned", form_id: 301, event_id: 7001, policy_id: 0

sqlite_execute:
  UPDATE addresses SET zensched_location_id = 9001, zensched_event_id = 7001, event_valid_until = '2026-11-05'
  WHERE address_id = 1;
```

> Added Roberto Alvarez, 118 Elm Street. Personal care Mon/Wed/Fri 9:00–13:00 at $34/h, billed to Lucia. Six care tasks on his plan. His care plan, medications, allergy, and the door code are saved on your computer only; ZenSched knows him as "Client 1 - Alvarez". I'll assign Maria once she's invited. His ZenSched event runs through Nov 5; I'll renew it automatically when scheduling gets that far.

## "Add Mei Chen, 42 Cedar Avenue, Austin TX 78704. Son David Chen pays, 512-555-0202, david.chen@example.com. Companion care Tue/Thu 1 to 4 starting 9/8, standard rate. Mostly conversation, a walk if she's up for it, lunch cleanup. Hearing aids, otherwise independent. Key is under the ceramic frog."

Same pattern. The agent does not re-ask about the $0.03 (owner already approved geocoding this session).

```
sqlite_execute: INSERT INTO clients (client_name, payer_name, payer_relationship, payer_phone, payer_email, payer_type, care_plan, mobility_notes, emergency_contact)
                VALUES ('Mei Chen', 'David Chen', 'son', '512-555-0202', 'david.chen@example.com', 'private_pay',
                        'Companionship, conversation, short walk if willing, lunch cleanup', 'Independent; wears hearing aids', 'David Chen 512-555-0202');   → 2
sqlite_execute: INSERT INTO addresses (client_id, address, city, state, zip, access_notes, zensched_label)
                VALUES (2, '42 Cedar Avenue', 'Austin', 'TX', '78704', 'Key under the ceramic frog by the step', 'Client 2 - Chen');   → 2
sqlite_execute: INSERT INTO care_tasks (client_id, task, frequency_note) VALUES (2, 'Companionship / activity', 'every visit');
sqlite_execute: INSERT INTO care_tasks (client_id, task, frequency_note) VALUES (2, 'Exercise', 'short walk if willing');
sqlite_execute: INSERT INTO care_tasks (client_id, task, frequency_note) VALUES (2, 'Light housekeeping', 'lunch cleanup');
sqlite_execute: INSERT INTO visit_schedule (client_id, address_id, weekdays, start_time, duration_minutes, service_type, start_date)
                VALUES (2, 2, '0101000', '13:00', 180, 'companion', '2026-09-08');   → 2

location_create: name "Client 2 - Chen", street_address "42 Cedar Avenue, Austin, TX 78704", checkin_radius_m 75, idempotency_key "loc-address-2"  → location_id 9002
event_create:    location_id 9002, title "Home care - Client 2 - Chen", start_date "2026-09-08", end_date "2026-11-06", idempotency_key "event-address-2-20260908"  → event_id 7002
form_assign:     form_id 301, event_id 7002, idempotency_key "assign-visit-record-7002"
sqlite_execute:  UPDATE addresses SET zensched_location_id = 9002, zensched_event_id = 7002, event_valid_until = '2026-11-06' WHERE address_id = 2;
```

`bill_rate` is left NULL, so Mrs. Chen bills at the $30 default.

## "Invite Maria Lopez, maria@example.com, she's a CNA, $19.50 an hour, she takes Mr. Alvarez. And James Okafor, james@example.com, standard pay, he takes Mrs. Chen."

> Inviting two caregivers costs $0.50. OK?

Owner: *"yes"*

```
worker_invite:
  email: "maria@example.com"
  first_name: "Maria"
  last_name: "Lopez"
  idempotency_key: "worker-maria@example.com"
  → worker_id: 501, status: "invited", invitation_sent: true
    billing: { meter: "worker_invite", units: 1, price: 0.25 }

worker_invite: email "james@example.com", first_name "James", last_name "Okafor", idempotency_key "worker-james@example.com"  → worker_id 502

sqlite_execute: INSERT INTO caregivers (caregiver_name, email, zensched_worker_id, pay_rate, certifications) VALUES ('Maria Lopez', 'maria@example.com', 501, 19.50, 'CNA');   → 1
sqlite_execute: INSERT INTO caregivers (caregiver_name, email, zensched_worker_id) VALUES ('James Okafor', 'james@example.com', 502);   → 2
sqlite_execute: UPDATE visit_schedule SET preferred_worker_id = 501 WHERE schedule_id = 1;
sqlite_execute: UPDATE visit_schedule SET preferred_worker_id = 502 WHERE schedule_id = 2;
```

> Invited Maria and James. Each gets an email with the app link and an activation code. Maria is set as the regular caregiver for Mr. Alvarez, James for Mrs. Chen. Please give Maria the Alvarez care plan and door code and James the key location yourself; I keep those off ZenSched on purpose.

## "Schedule next week."

```
sqlite_query: SELECT * FROM visits_due_this_week;
  → 2026-09-07 | sched 1 | Roberto Alvarez | addr 1 | Client 1 - Alvarez | evt 7001 | event_needs_roll 0 | personal_care | 09:00 | 240 min
               | worker 501 Maria Lopez | unassigned 0
               | start_iso 2026-09-07T09:00:00-05:00 | end_iso 2026-09-07T13:00:00-05:00 | shift-address-1-20260907-0900
    2026-09-08 | sched 2 | Mei Chen        | addr 2 | Client 2 - Chen    | evt 7002 | event_needs_roll 0 | companion | 13:00 | 180 min
               | worker 502 James Okafor | unassigned 0
               | start_iso 2026-09-08T13:00:00-05:00 | end_iso 2026-09-08T16:00:00-05:00 | shift-address-2-20260908-1300
    2026-09-09 | sched 1 | Roberto Alvarez ... 09:00 | shift-address-1-20260909-0900
    2026-09-10 | sched 2 | Mei Chen        ... 13:00 | shift-address-2-20260910-1300
    2026-09-11 | sched 1 | Roberto Alvarez ... 09:00 | shift-address-1-20260911-0900
  (5 rows)

shift_create:
  event_id: 7001
  worker_id: 501
  start: "2026-09-07T09:00:00-05:00"
  end:   "2026-09-07T13:00:00-05:00"
  idempotency_key: "shift-address-1-20260907-0900"
  → shift_id: 88001, status: "scheduled", forms_installed: [301]

shift_create:
  event_id: 7002
  worker_id: 502
  start: "2026-09-08T13:00:00-05:00"
  end:   "2026-09-08T16:00:00-05:00"
  idempotency_key: "shift-address-2-20260908-1300"
  → shift_id: 88002, status: "scheduled", forms_installed: [301]

(... three more shift_create calls → 88003 (Wed Alvarez), 88004 (Thu Chen), 88005 (Fri Alvarez))
```

> Scheduled 5 visits for the week of Sep 7:
> - Maria: Mon, Wed, Fri 9:00–13:00 personal care, Alvarez home
> - James: Tue, Thu 13:00–16:00 companion care, Chen home
>
> Both have been notified in the app and every visit has the Visit Record attached.

Nothing is written to SQLite here. If the owner asks "schedule next week" again, the identical idempotency keys make ZenSched return the same five shifts instead of creating duplicates.

## The caregivers do the work

Monday 8:57, at 118 Elm Street, in the ZenSched app: Maria taps **Check in** (GPS: 11 m from the pin, verified, $0.10). Helps Mr. Alvarez bathe and dress, makes breakfast, reminds him of the 8 am dose he had already taken with Lucia, tidies, makes lunch. Opens **Visit Record**: Tasks completed = Bathing/Hygiene, Dressing, Meal prepared, Medication reminder given, Mobility / transfer assist, Light housekeeping; Client status = As usual; Client ate = Yes; Note for family = "Good morning, walked to the mailbox and back with the walker." Mr. Alvarez signs on the phone, which submits the form. **Check out** 13:03.

Tuesday 12:57, James at 42 Cedar Avenue: check in, two hours of conversation and photo albums, a short walk to the corner, lunch dishes. Record: Companionship / activity, Exercise, Light housekeeping; As usual; Ate = Yes; Mrs. Chen signs. Check out 16:04.

Wednesday, Mr. Alvarez again. Maria marks Client status = **Some concern**, Concern details: "Ate about half of lunch. More unsteady than usual on the transfer from the recliner, needed two hands instead of standby. No fall." Client ate = Partially.

Thursday and Friday: routine.

## "Record this week's visits."

```
shift_list:
  date_from: "2026-09-07"
  date_to:   "2026-09-13"
  status:    "checked_out"
  → shifts: [
      { shift_id: 88001, event_id: 7001, worker_id: 501, date: "2026-09-07", start: "09:00", end: "13:00", status: "checked_out" },
      { shift_id: 88002, event_id: 7002, worker_id: 502, date: "2026-09-08", start: "13:00", end: "16:00", status: "checked_out" },
      { shift_id: 88003, event_id: 7001, worker_id: 501, date: "2026-09-09", ... },
      { shift_id: 88004, event_id: 7002, worker_id: 502, date: "2026-09-10", ... },
      { shift_id: 88005, event_id: 7001, worker_id: 501, date: "2026-09-11", ... }
    ], count: 5

sqlite_query: SELECT zensched_shift_id FROM visits WHERE zensched_shift_id IN (88001, 88002, 88003, 88004, 88005);
  → (none; not yet recorded)

sqlite_query: SELECT a.address_id, a.client_id, s.schedule_id, s.service_type
              FROM addresses a JOIN visit_schedule s ON s.address_id = a.address_id
              WHERE a.zensched_event_id = 7001 AND s.start_time = '09:00';
  → 1, 1, 1, personal_care
(same for event 7002 / 13:00 → 2, 2, 2, companion)

timesheet_export:
  period: "2026-09-07:2026-09-13"
  mode:   "hours"
  format: "json"
  → mode "hours", row_count 5, rows: [
      { worker_id: 501, worker_name: "Maria Lopez", event_id: 7001, date: "2026-09-07", hours: 4.10, gps_verified: true },
      { worker_id: 502, worker_name: "James Okafor", event_id: 7002, date: "2026-09-08", hours: 3.12, gps_verified: true },
      { worker_id: 501, worker_name: "Maria Lopez", event_id: 7001, date: "2026-09-09", hours: 4.05, gps_verified: true },
      { worker_id: 502, worker_name: "James Okafor", event_id: 7002, date: "2026-09-10", hours: 3.00, gps_verified: true },
      { worker_id: 501, worker_name: "Maria Lopez", event_id: 7001, date: "2026-09-11", hours: 4.05, gps_verified: true }
    ],
    summary_hours_per_worker: { 501: { worker_name: "Maria Lopez", hours: 12.2, days: 3 }, 502: { worker_name: "James Okafor", hours: 6.12, days: 2 } }
(free)

shift_status: shift_id 88001
  → status "checked_out", actual_in "2026-09-07T08:57:30-05:00", actual_out "2026-09-07T13:03:30-05:00",
    punches: [ { type: "in", gps_verified: true, distance_from_site_m: 11 }, { type: "out", gps_verified: true, distance_from_site_m: 8 } ]
(free; repeated for 88002–88005 to get exact in/out stamps)
```

Agent (metered read, rule 9):

> There are 5 Visit Records to pull. Reading them costs $0.05 each, or $0.15 when they carry a signature image; all five were signed, so about $0.75. I'll read them once and keep the summaries locally. OK?

Owner: *"go"*

```
form_export:
  form_id: 301
  since: "2026-09-07"
  until: "2026-09-13"
  format: "json"
  → row_count: 5, rows (inline for small exports, otherwise a download_url): [
      { submission_id: 3301, worker_id: 501, event_id: 7001, submitted_at: "2026-09-07 13:01:12",
        data: { tasks_completed: ["bathing_hygiene", "dressing", "meal_prepared", "medication_reminder_given", "mobility___transfer_assist", "light_housekeeping"],
                client_status: "as_usual", client_ate: "yes",
                note_for_family: "Good morning, walked to the mailbox and back with the walker." },
        media: [ { field: "client_signature", cdn_url: "https://cdn.zensched.com/m/.../sig1.png" } ] },
      { submission_id: 3302, worker_id: 502, event_id: 7002, submitted_at: "2026-09-08 16:02:40",
        data: { tasks_completed: ["companionship___activity", "exercise", "light_housekeeping"], client_status: "as_usual", client_ate: "yes",
                note_for_family: "Looked at the Taiwan albums, walked to the corner and back." },
        media: [ { field: "client_signature", cdn_url: "https://cdn.zensched.com/m/.../sig2.png" } ] },
      { submission_id: 3303, worker_id: 501, event_id: 7001, submitted_at: "2026-09-09 13:00:05",
        data: { tasks_completed: ["bathing_hygiene", "dressing", "meal_prepared", "medication_reminder_given", "mobility___transfer_assist", "light_housekeeping"],
                client_status: "some_concern",
                concern_details: "Ate about half of lunch. More unsteady than usual on the transfer from the recliner, needed two hands instead of standby. No fall.",
                client_ate: "partially" },
        media: [ { field: "client_signature", cdn_url: "https://cdn.zensched.com/m/.../sig3.png" } ] },
      ... 3304, 3305 ...
    ]
    billing: { meter: "form_media", units: 5, price: 0.75 }

sqlite_execute:
  INSERT INTO visits (client_id, address_id, schedule_id, zensched_worker_id, zensched_shift_id, zensched_event_id,
                      visit_date, service_type, scheduled_start, scheduled_end, actual_in, actual_out, gps_verified,
                      report_dc_id, tasks_done, client_status, concern_details, client_ate, note, signed)
  VALUES (1, 1, 1, 501, 88001, 7001,
          '2026-09-07', 'personal_care', '2026-09-07T09:00:00-05:00', '2026-09-07T13:00:00-05:00',
          '2026-09-07T08:57:30-05:00', '2026-09-07T13:03:30-05:00', 1,
          3301, '["bathing_hygiene","dressing","meal_prepared","medication_reminder_given","mobility___transfer_assist","light_housekeeping"]',
          'ok', NULL, 'Yes', 'Good morning, walked to the mailbox and back with the walker.', 1);
  (trigger fills: caregiver_id 1, hours 4.10, bill_rate 34.00, pay_rate 19.50, bill_amount 139.40)

sqlite_execute:
  INSERT INTO visits (...) VALUES (2, 2, 2, 502, 88002, 7002, '2026-09-08', 'companion',
          '2026-09-08T13:00:00-05:00', '2026-09-08T16:00:00-05:00', '2026-09-08T12:57:00-05:00', '2026-09-08T16:04:12-05:00', 1,
          3302, '["companionship___activity","exercise","light_housekeeping"]', 'ok', NULL, 'Yes',
          'Looked at the Taiwan albums, walked to the corner and back.', 1);
  (trigger fills: caregiver_id 2, hours 3.12, bill_rate 30.00, pay_rate 18.00, bill_amount 93.60)

sqlite_execute:
  INSERT INTO visits (...) VALUES (1, 1, 1, 501, 88003, 7001, '2026-09-09', 'personal_care',
          '2026-09-09T09:00:00-05:00', '2026-09-09T13:00:00-05:00', '2026-09-09T08:59:10-05:00', '2026-09-09T13:02:20-05:00', 1,
          3303, '["bathing_hygiene","dressing","meal_prepared","medication_reminder_given","mobility___transfer_assist","light_housekeeping"]',
          'concern', 'Ate about half of lunch. More unsteady than usual on the transfer from the recliner, needed two hands instead of standby. No fall.',
          'Partially', NULL, 1);
  (trigger fills: caregiver_id 1, hours 4.05, bill_rate 34.00, pay_rate 19.50, bill_amount 137.70)

(... two more inserts for 88004 and 88005)

sqlite_query: SELECT task FROM care_tasks WHERE client_id = 1 AND is_active = 1;
  → all six tasks appear in every Alvarez tasks_done this week
```

> Recorded 5 visits, all GPS-verified at the door, all signed.
>
> **One concern — Wednesday, Mr. Alvarez.** Maria marked "Some concern": *"Ate about half of lunch. More unsteady than usual on the transfer from the recliner, needed two hands instead of standby. No fall."* Friday's record is back to "As usual" and he ate. Worth a call to Lucia; want me to draft a text?
>
> Everything else routine. Maria did all six of Mr. Alvarez's care-plan tasks every visit; James did companionship, a walk, and lunch cleanup both days. Hours: Maria 12.2 (Mon 4.10, Wed 4.05, Fri 4.05), James 6.12 (Tue 3.12, Thu 3.00).

## "Did Maria stay the full shift on Wednesday?"

```
sqlite_query:
  SELECT visit_date, scheduled_start, scheduled_end, actual_in, actual_out, hours, gps_verified
  FROM visits WHERE client_id = 1 AND caregiver_id = 1 AND visit_date = '2026-09-09';
  → 2026-09-09 | 09:00 | 13:00 | 08:59:10 | 13:02:20 | 4.05 | 1
```

No ZenSched call, no cost.

> Yes. Scheduled 9:00–13:00; she checked in at 8:59 and out at 13:02, both GPS-verified at the house (within about 10 m). 4.05 hours.

## "Run payroll for last week."

```
sqlite_query: SELECT * FROM payroll_hours_unpaid;
  → Maria Lopez  | worker 501 | 3 visits | 12.2 h  | gross 237.90 | 2026-09-07 .. 2026-09-11
    James Okafor | worker 502 | 2 visits | 6.12 h  | gross 110.16 | 2026-09-08 .. 2026-09-10
```

The hours match the free `timesheet_export(mode="hours")` pulled earlier (12.2 and 6.12), so there is nothing to reconcile.

> Payroll for Sep 7–13:
>
> ```
> Maria Lopez    12.20 h  x  $19.50  =  $237.90   (Mon 4.10, Wed 4.05, Fri 4.05 — Alvarez)
> James Okafor    6.12 h  x  $18.00  =  $110.16   (Tue 3.12, Thu 3.00 — Chen)
> Total gross                           $348.06
> ```
>
> All five shifts GPS-verified in and out. If you want ZenSched to apply break and overtime rules and give you a CSV, I can run the processed timesheet ($0.10) once you tell me your pay week; not needed for two part-time caregivers under 40 hours. Say "paid" when payroll is done and I'll mark these hours.

Owner: *"paid"*

```
sqlite_execute: UPDATE visits SET paid_out = 1 WHERE paid_out = 0 AND visit_date BETWEEN '2026-09-07' AND '2026-09-13';
```

## "Draft the Alvarez invoice."

```
sqlite_query: SELECT * FROM visits_to_invoice;
  → Roberto Alvarez | payer Lucia Alvarez, lucia@example.com | 3 visits | 12.2 h  | 414.80 | 2026-09-07 .. 2026-09-11
    Mei Chen        | payer David Chen, david.chen@example.com | 2 visits | 6.12 h  | 183.60 | 2026-09-08 .. 2026-09-10

sqlite_execute:
  INSERT INTO invoices (client_id, invoice_date, due_date, total_hours, total_amount, line_items)
  SELECT v.client_id, date('now'),
         date('now', '+' || (SELECT value FROM settings WHERE key = 'invoice_due_days') || ' days'),
         SUM(v.hours), SUM(v.bill_amount),
         json_group_array(json_object('visit_id', v.visit_id, 'date', v.visit_date, 'service', v.service_type,
                                      'hours', v.hours, 'rate', v.bill_rate, 'amount', v.bill_amount, 'shift_id', v.zensched_shift_id))
  FROM visits v WHERE v.invoiced = 0 AND v.client_id = 1 GROUP BY v.client_id;

sqlite_execute: UPDATE visits SET invoiced = 1 WHERE invoiced = 0 AND client_id = 1;
sqlite_query:   SELECT invoice_number, invoice_date, due_date, total_hours, total_amount FROM invoices WHERE invoice_id = last_insert_rowid();
  → INV-2026-0001 | 2026-09-13 | 2026-09-27 | 12.2 | 414.80     (number assigned by trigger)
```

The agent then writes the invoice out as text:

> Here's the Alvarez invoice, ready to paste into an email to Lucia.
>
> ```
> Bright Path Home Care
> Invoice INV-2026-0001
> Care for Roberto
> To: Lucia Alvarez (lucia@example.com)
> Date: Sep 13, 2026    Due: Sep 27, 2026
>
>   Mon Sep 7    Personal care, Maria    4.10 h  x  $34.00    $139.40
>   Wed Sep 9    Personal care, Maria    4.05 h  x  $34.00    $137.70
>   Fri Sep 11   Personal care, Maria    4.05 h  x  $34.00    $137.70
>
> Total hours: 12.20
> Total due: $414.80
> Every visit was GPS-verified at 118 Elm Street and signed on the caregiver's phone.
> ```
>
> Mrs. Chen has 6.12 hours ($183.60) uninvoiced too; say the word and I'll do hers. Say "sent" when this one's out and I'll note the date.

Nothing on the invoice mentions Parkinson's, medications, or the care plan.

## "Sent. And Lucia already paid by Zelle."

```
sqlite_execute: UPDATE invoices SET sent_date = date('now') WHERE invoice_number = 'INV-2026-0001';
sqlite_execute: UPDATE invoices SET paid = 1, paid_date = date('now') WHERE invoice_number = 'INV-2026-0001';
```

> Marked INV-2026-0001 sent and paid. Nothing outstanding.

## "Mr. Alvarez is in the hospital. Hold his visits until I say."

```
sqlite_execute: UPDATE clients SET is_active = 0 WHERE client_id = 1;

shift_list: event_id 7001, date_from "2026-09-14", status "scheduled"
  → shifts: [ { shift_id: 88006, date: "2026-09-14", ... }, { shift_id: 88008, date: "2026-09-16", ... }, { shift_id: 88010, date: "2026-09-18", ... } ]

shift_cancel: shift_id 88006, reason "client on hold", idempotency_key "cancel-88006"
shift_cancel: shift_id 88008, reason "client on hold", idempotency_key "cancel-88008"
shift_cancel: shift_id 88010, reason "client on hold", idempotency_key "cancel-88010"
```

> Mr. Alvarez is on hold. Cancelled Maria's three visits next week (Mon, Wed, Fri); she's been notified with the reason "client on hold", nothing more. His record and care plan are untouched. Say "resume Alvarez" when he's home and I'll schedule again. Maria now has 12 open hours next week if you want to offer her something else.

Note the cancellation reason: caregivers see it, so "hospital" is not sent.

## Eight weeks later: "Schedule next week."

```
sqlite_query: SELECT * FROM visits_due_this_week;
  → 2026-11-03 | sched 2 | Mei Chen | addr 2 | evt 7002 | event_valid_until 2026-11-06 | event_needs_roll 0 | ...
    2026-11-04 | sched 1 | Roberto Alvarez | addr 1 | evt 7001 | event_valid_until 2026-11-05 | event_needs_roll 0 | ...
    2026-11-05 | sched 2 | Mei Chen ... event_needs_roll 0
    2026-11-06 | sched 1 | Roberto Alvarez | addr 1 | evt 7001 | event_valid_until 2026-11-05 | event_needs_roll 1 | ...

event_create:
  location_id: 9001
  title: "Home care - Client 1 - Alvarez"
  start_date: "2026-11-06"
  end_date:   "2027-01-04"
  idempotency_key: "event-address-1-20261106"
  → event_id: 7150

form_assign: form_id 301, event_id 7150, idempotency_key "assign-visit-record-7150"
sqlite_execute: UPDATE addresses SET zensched_event_id = 7150, event_valid_until = '2027-01-04' WHERE address_id = 1;

shift_create: event_id 7001 for the Nov 2 and Nov 4 Alvarez visits (old event still valid for those dates)
shift_create: event_id 7150 for the Nov 6 visit, key "shift-address-1-20261106-0900"
shift_create: event_id 7002 for the Chen visits (valid through Nov 6)
```

> Scheduled the week. Mr. Alvarez's ZenSched event was about to expire (Nov 5), so I renewed it through Jan 4. Mrs. Chen's expires Nov 6; I'll renew it next week. Nothing changes for Maria or James.

## Summary of who stored what

| Thing | Where | Why |
|---|---|---|
| Mr. Alvarez's name, DOB, care plan, diagnoses, medications, allergy, mobility notes, emergency contact | SQLite **only** | PHI; ZenSched has no BAA |
| Door code, key location | SQLite **only** | Privacy; never sent to ZenSched |
| Lucia's and David's contact details, payer type, bill rates | SQLite | Billing; ZenSched does not model payers or rates |
| Care tasks per client, the Mon/Wed/Fri and Tue/Thu cadence, preferred caregiver | SQLite | Recurrence and continuity; ZenSched does not model them |
| Maria's and James's pay rates and certifications | SQLite | Payroll; ZenSched holds only the worker account |
| "Client 1 - Alvarez" and the street address, GPS pin | ZenSched (ID in `addresses`) | Needed for geofenced check-in; de-identified label |
| Each home's current ≤60-day event and its end date | ZenSched (ID + `event_valid_until` in `addresses`) | Shifts hang off events; renewed by the agent |
| The Visit Record form | ZenSched (ID in `settings`) | Installed on the caregiver's phone per shift |
| Maria, James, their invites, their apps | ZenSched (IDs in `caregivers`) | Workforce and notifications |
| The week's five shifts, and the three cancellations | ZenSched only | Live schedule; never copied |
| GPS punches, actual in/out times, distance from the door | ZenSched only | Verified record; queried via `shift_status` / `timesheet_export`, stamps copied to `visits` |
| Five Visit Records with signatures | ZenSched (originals); checklist, status, note, `signed` flag in `visits` | Read once (metered), then answered from SQLite for free |
| Five `visits` rows referencing shift and submission IDs, with hours and rates | SQLite | Billing, payroll, and the `evv_visit_log` six-element record |
| Payroll run (`paid_out`) and one invoice, paid | SQLite | Money |
