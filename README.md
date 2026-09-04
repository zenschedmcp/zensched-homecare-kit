# ZenSched Home-Care Reference Kit

A copy-pasteable setup for a small non-medical home care agency (1–10 caregivers; companion care, personal care and ADL assistance, respite, overnight and live-in, private-duty; mostly private-pay families) that wants an AI assistant to run caregiver scheduling, GPS-verified visit records, client tracking, payroll hours, and family invoicing. ZenSched handles the live schedule, the caregiver's phone app, GPS check-ins at the client's door, the task-checklist Visit Record, and timesheets. A small local database on your computer holds your clients, care plans, caregivers, rates, recurring schedule, visit log, and invoices.

**You do not need to know how to program or write SQL to use this.** You type plain English to your AI assistant ("schedule next week", "add a new client", "did Maria stay the full shift at the Alvarez house?", "run payroll", "draft the Chen invoice") and the AI does the work using two tools you set up once. Setup takes about 15 minutes and is the only technical part.

If you *are* a developer, skip to [For developers](#for-developers).

## EVV and HIPAA — read this first

**What this kit is:** a way for a small agency to get GPS-verified, timestamped, caregiver-signed records of every visit, keep client information on the agency's own computer, and turn those records into payroll hours and family invoices with an AI assistant doing the clerical work.

**What it is not:**

- **ZenSched is not a HIPAA business associate and does not sign a BAA.** So this kit is built so that no protected health information ever reaches ZenSched. Care plans, diagnoses, medication lists, allergies, mobility notes, emergency contacts, dates of birth, and door codes are stored **only** in the local SQLite database on your computer. ZenSched receives, per client, a short de-identified label (initials or a house nickname such as `Client 12 - Alvarez`), the street address for the GPS pin, and the Visit Record the caregiver fills in, which is a task checklist, a status flag, an optional short note, and an optional signature. `SKILL.md` makes this a hard rule the AI will refuse to break. You are still responsible for your own HIPAA obligations (the local database, your email, your caregivers' phones); this kit narrows what a third party sees, it does not make you compliant by itself.
- **ZenSched is not a certified EVV vendor and does not submit to any state aggregator** (Sandata, HHAeXchange, Netsmart, Tellus, or a state-run system). What the kit gives you is an `evv_visit_log` view that produces the six 21st Century Cures Act elements for every visit (type of service, individual receiving service, date, location, individual providing service, time in and time out) from your local visit records joined to the GPS-verified times the AI recorded from ZenSched. For a private-pay agency that means EVV-grade records without an EVV contract. For an agency with Medicaid clients it means an export you can hand to an alternate-EVV-vendor integration later; it does not replace one today.

If either of those is a deal-breaker, this kit is not for you yet. If you run private-pay and want proof-of-visit that families and long-term-care insurers accept, read on.

## What lives where

**ZenSched (source of truth for what happened, when, and where):**

- Locations (client homes with GPS coordinates; the check-in radius is a policy setting)
- Workers (caregivers with the mobile app)
- Events (one "Home care" job per client address, renewed every 60 days)
- Shifts (each visit, 2–12 hours, with push notifications to the caregiver)
- GPS punches (check-in/check-out with distance-from-the-door verification)
- The Visit Record form (tasks completed, client status, client ate, note for family, signature) and every submission
- Timesheets (verified hours worked, exportable for payroll)

**Local SQLite database (`homecare-ops.db`, on your computer):**

- Clients: name, date of birth, the family member or payer who is billed, payer type (private pay, LTC insurance, VA, Medicaid, other), bill rate
- Care plan, diagnoses, medications, allergies, mobility notes, emergency contact — **never leave your computer**
- Addresses, including access notes (door code, alarm, key, parking) — **never leave your computer**
- Care tasks expected per client (what the Visit Record checklist is checked against)
- Caregivers: contact, pay rate, certifications (CNA, HHA, CPR)
- The recurring schedule (which weekdays, what time, how long, which service, preferred caregiver) per client
- Completed visits with hours, rates, and a summary of each Visit Record; payroll runs; invoices
- Your settings (timezone, default rates, default visit length, invoice prefix, Visit Record form id)

**Never duplicated:** the live schedule, punches, timesheets, and signature images stay in ZenSched. The local database only stores *references* to them plus a per-visit summary so you can answer "how has Mr. Alvarez been this week" without paying to re-read records.

### Privacy note

Everything that could identify a client's health condition, and every access code, lives only in the local database: `clients.care_plan`, `diagnoses`, `medications`, `allergies`, `mobility_notes`, `emergency_contact`, `dob`, the `care_tasks` table, and `addresses.access_notes`. `SKILL.md` forbids the AI from putting any of them into any ZenSched field, including location names, event titles, notes, and cancellation reasons (caregivers see those). Give care plans and door codes to your caregivers yourself, by whatever channel you trust. ZenSched only ever sees the de-identified label, the street address, and the GPS pin. The Visit Record form itself tells caregivers not to write diagnoses or medication names in it.

## How it works day to day

Your AI assistant has two sets of tools:

1. **ZenSched tools** (`location_create`, `shift_create`, `form_submissions`, `shift_list`, `timesheet_export`, ...) that talk to ZenSched over the internet.
2. **A SQLite tool** (`sqlite_query`, `sqlite_execute`) that reads and writes `homecare-ops.db` on your computer.

When you say "schedule next week," the AI expands your recurring schedule for the next 7 days from the local database, gives each visit to the client's preferred caregiver, creates one shift per visit on ZenSched, and tells you what it did. Your caregiver sees the visits in the app, checks in at the door (GPS-verified), does the visit, fills in the Visit Record, has the client or family member sign, and checks out. Later you say "record this week's visits" and the AI pulls the completed shifts, the verified times, and the records, saves a summary locally, and leads with anything the caregiver flagged as a concern. "Run payroll" totals verified hours per caregiver; "draft invoices" produces a per-visit invoice for each family. You never run SQL yourself. `SKILL.md` in this repo is the instruction sheet that teaches the AI how to do all of this; you paste it into your AI tool once.

## Setup

### 0. What you need

- **An AI tool that supports MCP.** These instructions use Claude Desktop (Windows or Mac). Cursor works too.
- **Node.js 20 or newer.** The SQLite tool runs on it. Download the LTS installer from [nodejs.org](https://nodejs.org/) and run it with the defaults. This is the only software install.
- You do **not** need the `sqlite3` command-line program, Python, or Git.

### 1. Make a folder for your data

Create a folder where the database will live and write down its full path. Examples:

- Windows: `C:\Users\YourName\homecare-ops`
- Mac: `/Users/yourname/homecare-ops`

The database file will be created automatically inside this folder the first time the AI uses it. This folder will contain client health information; treat it like a filing cabinet (encrypted disk, backed up, not in a shared Dropbox folder).

### 2. Add both tools to your AI's config file

Open the MCP configuration file for your AI tool:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json` (paste that into the File Explorer address bar)
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json` (in Claude Desktop: Settings → Developer → Edit Config)
- **Cursor:** Settings → MCP → Add new global MCP server

Paste in the contents of `mcp.json.example` from this repo, then change one line, the `SQLITE_PATH`, to point at your folder from step 1 plus `\homecare-ops.db` (Windows) or `/homecare-ops.db` (Mac):

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    },
    "homecare-ops-db": {
      "command": "npx",
      "args": ["-y", "easy-sqlite-mcp"],
      "env": { "SQLITE_PATH": "/Users/yourname/homecare-ops/homecare-ops.db" }
    }
  }
}
```

**Windows path gotcha:** inside a JSON file every backslash must be doubled. Write `"C:\\Users\\YourName\\homecare-ops\\homecare-ops.db"`, not `"C:\Users\..."`. A single backslash will silently break the config.

**Leave `zsc_your_key_here` exactly as it is for now.** You do not have a key yet. The ZenSched tools that create your account work without one, and you will fill this in during step 3.

Save the file and **fully quit and reopen** your AI tool (on Mac, Cmd-Q; on Windows, right-click the tray icon → Quit). It only reads this file on startup.

### 3. Create your ZenSched account

In a new chat, type:

> Call `zensched_guide`, then call `account_create` with org_name "My Home Care Agency" (use my real business name if I told you one). Show me the `zsc_` key it returns.

Copy the `zsc_` key. Go back to the config file from step 2, replace `zsc_your_key_here` with your real key, save, and fully quit and reopen the AI tool again.

Some clients can adopt the key mid-session with `account_use_key`; you can ask the AI to try that to keep going immediately, but still update the config file so the key survives restarts. Keep the key private; it is the password to your account.

### 4. Create the database tables

Open `schema.sql` from this repo in any text editor, copy the whole thing, and paste it into the chat with this message in front of it:

> Create these tables in my homecare-ops database. Run each statement one at a time using the SQLite tool, then list the tables to confirm.

The AI will run 44 statements and confirm the tables exist. The `homecare-ops.db` file now exists in your folder with default settings ($32/h bill, $18/h pay, 4-hour visits) you can change.

If you happen to have the `sqlite3` command-line tool, `sqlite3 homecare-ops.db < schema.sql` does the same thing, but it is not required.

### 5. Teach the AI the workflow

Paste the contents of `SKILL.md` into your AI tool as standing instructions. In Claude Desktop, create a Project and put it in the project instructions; in Cursor, save it as a rule. Then tell it your basics once:

> We're Bright Path Home Care in Austin, Texas, Central time. We bill $30 an hour and pay $18 unless I say otherwise. Save that in settings and set up the Visit Record form.

It writes those to the `settings` table, creates the Visit Record form on ZenSched (free), and saves the form id so every client's visits get it automatically.

**Check-in radius.** The default is 75 m around the geocoded pin. ZenSched enforces the radius through the account's policy, not per home, and with geofencing on it raises anything under 100 m to about 91 m (300 ft), so 75 behaves as roughly a house-and-driveway circle. For an assisted-living campus, a large rural lot, or a home where the pin lands on the road, ask the AI to "set the check-in radius to 200 m" (`policy_update`) or to move the pin onto the building (`location_update`, free). `remote_checkin` turns GPS verification off for every home and should be a last resort, because it also turns off the proof.

**Forgotten check-outs.** Ask the AI to "remind caregivers to check out 15 minutes after the shift ends" (`checkout_reminder_min_after`). If you would rather caregivers fix their own missed check-out in the app, ask for "let caregivers edit their times" (`timesheet_edit: "times_only"`); it is off by default.

### 6. Funding (only when asked)

The first 200 ZenSched tool calls per day are free. Some things are metered: creating a location (geocoding, $0.03), inviting a caregiver ($0.25), each GPS-verified check-in or check-out ($0.10), reading a Visit Record ($0.05, or $0.15 when it has a signature image; each record is billed once, ever), and a processed timesheet with breaks and overtime ($0.10; the plain hours export is free). When a metered call happens without funds, the AI will get a `payment_required` response and tell you how to add the $5 activation deposit, which is credited to your balance. You will not be charged without seeing this first.

For a client on three visits a week that is $0.60 in GPS verification plus $0.45 in record reads per week, about $4.50 a month per client; the AI states the cost before it spends.

## Using it

Everything after setup is plain English. Examples:

- "Add a client: Roberto Alvarez, 118 Elm Street, Austin TX 78704. Daughter Lucia pays, 512-555-0101. Parkinson's, fall risk, uses a walker. Med reminders 8am and 2pm. Door code 2468. Personal care Mon/Wed/Fri 9 to 1 at $34 an hour, give him to Maria."
- "Add Mei Chen at 42 Cedar Avenue, companion care Tue/Thu 1 to 4, son David pays, standard rate."
- "Invite Maria Lopez, maria@example.com, CNA, $19.50 an hour."
- "Schedule next week."
- "Record this week's visits."
- "Did Maria stay the full shift at the Alvarez house on Wednesday?"
- "Anything I should worry about?" (open concerns)
- "Run payroll for last week."
- "Draft invoices for everyone with uninvoiced hours."
- "Who still owes me money?"
- "Mr. Alvarez is in the hospital, hold his visits."
- "Swap James for Maria on Thursday."
- "Keep Maria till 2 on Friday."
- "Add an overnight for Mrs. Chen Saturday 8pm to 8am."

See `QUICKSTART.md` for the first-week walkthrough and `example-workflow.md` for exactly which tools the AI calls behind each of these.

### What "invoice" means here

"Draft an invoice" records the invoice in your database (number, date, due date, hours, amount, which visits) and the AI writes out a plain-text invoice you can paste into an email or text to the family, with a line per visit (date, service, caregiver, hours, rate) and a note that the visits were GPS-verified and signed. It does **not** generate a PDF, email it for you, bill an insurer, or collect payment. Invoices never mention diagnoses or the care plan. When the family pays, tell the AI ("Lucia paid INV-2026-0003") and it marks it paid. If you outgrow this, the invoice records are simple enough to import into any accounting tool.

### What "payroll" means here

"Run payroll" totals GPS-verified hours per caregiver from the local visit log, cross-checks them against ZenSched's free hours export, and writes a per-caregiver summary (hours × pay rate = gross) you hand to whoever runs your payroll. If you want ZenSched to apply break and overtime rules and produce a CSV, the AI can run the processed timesheet ($0.10) once you tell it your pay week. The kit does not calculate taxes or pay anyone.

## Mobile app for caregivers

- **Android:** [Google Play](https://play.google.com/store/apps/details?id=com.zensched.app)
- **iOS:** [App Store](https://apps.apple.com/us/app/zensched/id6800081657)

When you invite a caregiver, they get an email, install the app, and can immediately see their visits, check in and out with GPS verification, and fill in the Visit Record. On the phone the client-or-family signature is the last step and submits the form; if the client cannot sign, the caregiver signs and notes it.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| AI says it has no ZenSched tools | Config file not saved, or the app was not fully restarted | Check the JSON is valid (paste it into [jsonlint.com](https://jsonlint.com)), then quit and reopen the app |
| AI says it has no SQLite / `homecare-ops-db` tools | Node.js not installed, or bad `SQLITE_PATH` | Install Node.js LTS; on Windows check every backslash is doubled |
| `SQLITE_PATH` points nowhere / "unable to open database" | Folder from step 1 does not exist | Create the folder; the file is created automatically but the folder is not |
| ZenSched tools return an auth error | Key still says `zsc_your_key_here`, or was pasted with a space | Re-paste the key, restart |
| `payment_required` | Metered call with no balance | Follow the instructions in the response; $5 deposit |
| AI creates shifts at the wrong hour | Timezone not set | "Set my timezone offset to -05:00 in settings" (use your own offset) |
| Shift creation fails for dates a couple of months out | The client's 60-day ZenSched event has expired | Say "renew the events"; the AI runs the roll-over in `SKILL.md` and retries |
| Caregiver's check-in not GPS-verified at a house | Pin is at the road, caregiver parked far away, or a campus | "Set the check-in radius to 200 m" (`policy_update`), or "move the pin onto the building" (`location_update`, free), or `location_refine` ($0.10) |
| Caregiver forgot to check out | Shift still `checked_in` | Tell the AI the real end time; ask for a 15-minute check-out reminder, or enable caregiver time edits |
| Caregiver does not see the Visit Record | Form not assigned to that client's event | "Attach the Visit Record to the Alvarez event" (`form_assign`) |
| "Concern details" shows even when status is "As usual" | Conditional fields are web-only on ZenSched | Harmless; caregivers leave it blank |
| "How has Mr. Alvarez been" comes back empty | Visits not recorded yet | "Record this week's visits" first; reading records is metered, so the AI asks before doing it |
| AI refuses to put a door code or diagnosis in ZenSched | Working as intended | Give it to the caregiver directly |
| Payroll hours differ from ZenSched | Caregiver punched far off schedule, or hours were entered by hand | The AI shows both; tell it which to keep |
| AI asks you to run SQL yourself | It does not have `SKILL.md` loaded | Re-paste `SKILL.md` as project instructions |

If something is confusing or broken in ZenSched itself, ask the AI to call `feedback_submit` with a description. It is free, needs no account, and a human reads every submission.

## For developers

**Architecture.** Two MCP servers, no application code. The agent is the integration layer; `SKILL.md` is the spec it follows. ZenSched is authoritative for operations (schedule, punches, forms, timesheets); SQLite is authoritative for client records (including all PHI), care plans, roster, recurrence, payroll flags, and billing; each side stores only the other's IDs, plus a per-visit summary cached locally because submission reads are metered. The PHI boundary is enforced by data placement (PHI columns exist only locally) and by `SKILL.md` rule 1; there is no technical control stopping a misbehaving agent, so review the rule if you swap models.

**Data model decisions.**

- One ZenSched **location** per address, permanent, stored on `addresses.zensched_location_id`. Created with `location_create(name=<zensched_label>, street_address=..., checkin_radius_m=75, idempotency_key=...)`. `addresses.zensched_label` is the only name that crosses to ZenSched. `checkin_radius_m` on `location_create` is informational; the enforced radius is `policy_update(0, '{"checkin_radius_m": N}')`, and with geofencing on the platform raises values under 100 m to 300 ft.
- **Events are capped at 60 days by ZenSched**, so an event cannot be a permanent job template. Each address holds its *current* event in `addresses.zensched_event_id` and its last covered date in `addresses.event_valid_until`. The agent creates a new event (`event_create(location_id, title="Home care - <label>", start_date, end_date=start+59 days, idempotency_key="event-address-{address_id}-{YYYYMMDD}")`) whenever a shift date is later than `event_valid_until`, calls `form_assign(form_id, event_id=...)` on it, and updates the row. `visits_due_this_week` exposes `event_needs_roll` per row and `events_expiring` lists addresses due for renewal within 14 days. Shifts already created on the old event remain valid. When recording a completed visit whose `event_id` no longer matches an address, the agent falls back to `event_get(event_id).location_id` against `addresses.zensched_location_id`.
- **Recurrence is per weekday.** `visit_schedule.weekdays` is a 7-character `0/1` mask, Monday first, `CHECK`-constrained; `start_time` is `HH:MM`; `duration_minutes` is `CHECK`-constrained to 30–1440 so a 12-hour overnight or a 24-hour live-in day is one row. The view expands with a recursive CTE over the next seven days, joins to the mask with `strftime('%w')` (remapping Sunday from `0` to position 7), honours `start_date`/`end_date`, drops rows whose date already exists in `visits` for that `schedule_id`, and emits `start_iso` and `end_iso` (via `datetime(... '+N minutes')`, so overnights cross midnight correctly), plus the shift `idempotency_key`.
- **Continuity of care.** `visit_schedule.preferred_worker_id` is a ZenSched worker id. The view's `worker_id` is `COALESCE(preferred_worker_id, <zensched_worker_id of the most recent visit on this schedule row>)`, with `caregiver_name` joined from `caregivers` and an `unassigned` flag when both are NULL. There is deliberately no global default caregiver; `SKILL.md` rule 11 makes the agent ask rather than guess.
- **Visits carry snapshots.** `visits.hours`, `bill_rate`, `pay_rate`, `bill_amount`, and `caregiver_id` are filled by the `fill_visit_derived` trigger when left NULL: hours from `actual_in`/`actual_out` (SQLite `julianday` handles ISO strings with a `-05:00` offset, so midnight crossings work), falling back to `scheduled_start`/`scheduled_end`; rates from `clients.bill_rate` / `caregivers.pay_rate`, then `settings` defaults; `caregiver_id` from `zensched_worker_id`. Rate changes therefore never rewrite history. The agent overrides `hours` when the agency rounds to quarter hours or bills scheduled time. One `hours` column serves both billing and payroll; if an agency bills scheduled hours but pays actual, add a `pay_hours` column.
- `visits.zensched_shift_id` and `caregivers.zensched_worker_id` are `UNIQUE`. `visits.report_dc_id` holds the form `submission_id`. `client_status` (`ok | concern | urgent`) and `client_ate` are `CHECK`-constrained; `tasks_done` is a JSON array of the form's option keys so it can be diffed against `care_tasks`.
- `invoices.invoice_number` is auto-assigned by trigger as `{prefix}-{YYYY}-{0001}`; `total_hours` is stored alongside `total_amount`; `line_items` carries hours and rate per visit.
- `clients.payer_type` (`private_pay | ltc_insurance | va | medicaid | other`) and `service_type` (`companion | personal_care | respite | overnight | live_in | transport`, on both `visit_schedule` and `visits`) are `CHECK`-constrained.
- **`evv_visit_log`** exposes `evv_service_type`, `evv_individual_receiving`, `evv_date_of_service`, `evv_location`, `evv_individual_providing`, `evv_time_in`, `evv_time_out` plus `gps_verified`, `signed`, and the ZenSched shift, worker, and submission IDs. It is a view over `visits`; it does not transmit anything.
- `payroll_hours_unpaid` groups `visits` with `paid_out = 0` by caregiver and computes `SUM(round(hours × pay_rate, 2))`; `open_concerns` is `client_status <> 'ok'` in the last 14 days, urgent first.
- `PRAGMA foreign_keys = ON` is in `schema.sql` and `SKILL.md` tells the agent to run it per session; SQLite does not persist it. Deleting a client cascades to addresses, care tasks, schedule rows, visits, and invoices; deleting a caregiver sets `visits.caregiver_id` NULL.

**Visit Record form.** Created once with `form_create(title, fields_json, idempotency_key="form-visit-record")`; the exact `fields_json` is in `SKILL.md` and was validated against ZenSched's form validator. Every field carries an explicit `identifier` so submission `data` keys are stable (`tasks_completed`, `client_status`, `concern_details`, `client_ate`, `note_for_family`, `client_signature`). Option keys are derived by ZenSched from the labels (lowercase, non-alphanumerics → `_`), which is why `Fed / hydration` comes back as `fed___hydration` and `Urgent - call office` as `urgent___call_office`; `SKILL.md` lists the mapping. One `show_if` references `client_status` with value `as_usual`; ZenSched documents conditionals as web-only, so the phone may show "Concern details" unconditionally. The form has a `signature` field, and on ZenSched a signature field replaces the submit button (signature completion is the submit), so "optional" means the field is not flagged required, not that the form can be submitted without touching it. Attaching is `form_assign(form_id, event_id=...)`, which resolves event → brand → policy and installs the form on the phone for every subsequent `shift_create`.

**Idempotency keys.** Deterministic, derived from local IDs so a retried or re-run agent turn cannot duplicate:

- location: `loc-address-{address_id}`
- event: `event-address-{address_id}-{YYYYMMDD window start}`
- shift: `shift-address-{address_id}-{YYYYMMDD}-{HHMM}` (date and start time, because two visits a day is normal)
- cancel: `cancel-{shift_id}`
- worker: `worker-{email}`
- form: `form-visit-record`; assignment: `assign-visit-record-{event_id}`

ZenSched caches idempotent responses for 24 hours.

**Timestamps.** `shift_create` takes `start` and `end` in ISO 8601 with an explicit offset. Always use the business's local offset from `settings.timezone_offset` (e.g. `2026-09-07T09:00:00-05:00`), never `Z`. The view builds these strings so the agent does not have to. `visits.scheduled_*` and `actual_*` use the same format so the trigger's `julianday` arithmetic is exact.

**Metered reads.** `form_submissions` and `form_export` bill $0.05 per submission read ($0.15 with media; a signature image counts as media), once per submission ever; `form_export` is preferred for a week or month at a time. `shift_list`, `shift_status`, `event_get`, and `timesheet_export(mode="hours"|"raw")` are free; `mode="processed"` is $0.10 and needs `account_set_payroll_period`. The hours export returns `worker_id, worker_name, event_id, date, hours, gps_verified` per row plus `summary_hours_per_worker`, which is what "Run payroll" reconciles against.

**SQLite MCP server.** `mcp.json.example` uses [`easy-sqlite-mcp`](https://github.com/chenkumi/easy-sqlite-mcp) (Node, `better-sqlite3`, `SQLITE_PATH` env var). Its `sqlite_execute` calls `prepare()`, so it accepts **one statement per call**; `schema.sql` is written so every statement stands alone and is idempotent. Any SQLite MCP server with read and write tools will work; adjust the tool names in `SKILL.md`.

**Schema test.** The schema was verified by splitting the file into its 44 statements with `sqlite3.complete_statement` and executing each individually (as the MCP server does) twice for idempotency (seed rows not duplicated), then exercising: all 8 tables, 7 views, and 6 triggers present; every view on an empty database; the recursive-CTE view against Mon/Wed/Fri, Tue/Thu, and daily-overnight masks (3, 2, and 7 rows on the right weekdays); an overnight `end_iso` crossing midnight; the `idempotency_key` format; `worker_id` from `preferred_worker_id`, the continuity fallback, and the `unassigned` flag; exclusion of already-recorded dates; `event_needs_roll` flipping exactly after `event_valid_until` and `events_expiring`; the `fill_visit_derived` trigger (hours from punches to 2 dp including across midnight, scheduled fallback, rate fallbacks through client / caregiver / settings, `bill_amount`); `UNIQUE` on `zensched_shift_id` and `zensched_worker_id`; every `CHECK` (payer type, weekday mask length and characters, start time, duration, service type on both tables, client status, client ate); foreign keys and cascade / set-null; the `updated_at` and invoice-numbering triggers; `visits_to_invoice`, `invoices_outstanding`, `evv_visit_log` (six populated elements), `payroll_hours_unpaid` math and the `paid_out` filter, and the `open_concerns` 14-day window. 57 checks, all passing.

## Support

- ZenSched docs: <https://www.zensched.com/docs/>
- Tool reference: <https://www.zensched.com/docs/tools/>
- Feedback: ask your AI to call `feedback_submit` (categories: `bug`, `friction`, `missing_capability`, `docs`, `billing`, `feature`, `other`)

## License

MIT. See `LICENSE`.
