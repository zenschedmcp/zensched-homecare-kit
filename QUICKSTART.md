# Quickstart

Setup is about 15 minutes, once. After that everything is plain English to your AI. Each step below tells you what to do and, where relevant, exactly what to type to the AI.

You need: Claude Desktop (or Cursor) and [Node.js LTS](https://nodejs.org/) installed. Nothing else.

Before you start, read the "EVV and HIPAA" section of `README.md`. Short version: client health information stays on your computer, ZenSched only ever sees a label, an address, and a task checklist, and this is not a certified EVV system.

## 1. Make a data folder

Create a folder such as `C:\Users\YourName\homecare-ops` (Windows) or `/Users/yourname/homecare-ops` (Mac). Note the full path. It will hold client health information, so keep it on an encrypted, backed-up disk.

## 2. Add the two tools to your AI's config

Open the config file:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** Settings → MCP → Add new global MCP server

Paste this in and fix only the `SQLITE_PATH` line to match your folder from step 1:

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

- On Windows, double every backslash: `"C:\\Users\\YourName\\homecare-ops\\homecare-ops.db"`.
- Leave `zsc_your_key_here` as it is. You get the real key in the next step.

Save, then **fully quit and reopen** the AI app.

## 3. Create your ZenSched account

Type to the AI:

> Call zensched_guide, then account_create with org_name "My Home Care Agency". Show me the zsc_ key.

Copy the key into the config file in place of `zsc_your_key_here`. Save. Quit and reopen the app once more. (You can also ask the AI to call `account_use_key` with the key to continue right away, but update the file anyway so it sticks.)

## 4. Create the database tables

Copy the full contents of `schema.sql` and paste it into the chat with this line above it:

> Create these tables in my homecare-ops database. Run each statement one at a time with the SQLite tool, then list the tables to confirm.

## 5. Give the AI its instructions

Paste `SKILL.md` into the AI as standing instructions (Claude Desktop: a Project's instructions; Cursor: a rule). Then:

> We're Bright Path Home Care in Austin, Texas, Central time. We bill $30 an hour and pay caregivers $18 unless I say otherwise. Save that to settings and create the Visit Record form.

The AI saves your settings and calls `form_create` once (free) to build the Visit Record your caregivers fill in: tasks completed, client status (As usual / Some concern / Urgent), client ate, a note for the family, and a client-or-family signature. It collects no diagnoses or medications. It stores the form id so every client gets it.

## 6. Add your first client

> Add a client: Roberto Alvarez, born 1941-03-12, 118 Elm Street, Austin TX 78704. Daughter Lucia Alvarez pays, 512-555-0101, lucia@example.com. Parkinson's, mild dementia, fall risk, uses a walker. Med reminders 8am and 2pm. Allergic to penicillin. Door code 2468. Personal care Mon/Wed/Fri 9 to 1 starting Monday 2026-09-07, $34 an hour.

Behind the scenes the AI inserts the client (care plan, diagnoses, meds, allergy, door code all local), his care tasks, and the recurring schedule; calls `location_create` for "Client 1 - Alvarez" (geocode, $0.03, may trigger the $5 activation deposit the first time); creates a 60-day `event_create` for the home; attaches the Visit Record with `form_assign`; and saves the IDs. ZenSched never sees his name, condition, or door code. You just see a confirmation.

## 7. Invite your caregivers

> Invite Maria Lopez, maria@example.com, CNA, $19.50 an hour. She takes Mr. Alvarez.

Maria gets an email ($0.25), installs the app ([Android](https://play.google.com/store/apps/details?id=com.zensched.app) / [iOS App Store](https://apps.apple.com/us/app/zensched/id6800081657)), and activates. Give her the care plan and door code yourself; the AI will not put them in ZenSched.

## 8. Schedule the week

> Schedule next week.

The AI expands the recurring schedule for the next 7 days, gives each visit to the client's preferred caregiver, creates one shift per visit on ZenSched, and summarizes by caregiver and day. Maria gets a push notification for each, with the Visit Record attached. She checks in at the door (GPS-verified), does the visit, ticks the tasks, has Mr. Alvarez sign, and checks out.

## 9. After the work is done

> Record this week's visits.

The AI pulls the completed, GPS-verified shifts and their times from ZenSched (free), then the Visit Records (metered, so it tells you the cost first), saves a per-visit summary with hours and rates, and leads with anything a caregiver flagged as a concern.

> Did Maria stay the full shift on Wednesday?

Answered from the local record, free: scheduled vs actual in/out, GPS-verified or not.

> Run payroll for last week.

Verified hours per caregiver times their pay rate, cross-checked against ZenSched's free hours export. Say "paid" and it marks those hours done.

> Draft the Alvarez invoice.

A plain-text invoice to Lucia with one line per visit (date, caregiver, hours, rate), the total, and a note that every visit was GPS-verified and signed. Nothing medical on it.

> Lucia paid INV-2026-0001.

Marks it paid.

## What next

- `README.md` for the full explanation, the EVV/HIPAA boundaries, troubleshooting table, and developer notes
- `example-workflow.md` to see the exact tool calls behind each step above
