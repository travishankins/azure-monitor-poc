# ServiceNow Integration Guide — Azure Monitor Alerts to ITSM

> Configure alert-to-ticket integration for your Azure Monitor deployment

---

## Documentation References

| Topic                                  | URL                                                                                                               |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Common alert schema                    | https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-common-schema                                 |
| Action groups overview                 | https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/action-groups                                        |
| Logic App with common alert schema     | https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-common-schema-integrations                    |
| ServiceNow connector for Logic Apps    | https://learn.microsoft.com/en-us/connectors/service-now/                                                         |
| ITSM Connector (legacy)                | https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/itsmc-overview                                       |
| Secure webhook for ITSM                | https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/itsmc-secure-webhook-connections-azure-configuration |
| Connect ServiceNow with ITSM Connector | https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/itsmc-connections-servicenow                         |
| Logic Apps overview                    | https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-overview                                            |
| Create a Consumption logic app         | https://learn.microsoft.com/en-us/azure/logic-apps/quickstart-create-first-logic-app-workflow                     |

---

## Overview

When an Azure Monitor alert fires → automatically create an incident in ServiceNow.
When the alert resolves → automatically update/close the ServiceNow incident.

**Recommended approach: Logic App** (most flexible, supports auto-resolve, no deprecated components).

---

## Prerequisites (Customer Provides)

| Item                          | Details                                           |
| ----------------------------- | ------------------------------------------------- |
| ServiceNow instance URL       | `https://<instance>.service-now.com`              |
| ServiceNow credentials        | Username + password, OR OAuth app registration    |
| Target assignment group       | The group that should receive the incidents       |
| Incident category/subcategory | How to categorize Azure Monitor incidents         |
| Caller / opened by            | Service account or user to attribute incidents to |

> Ask Contoso for these before starting. The ServiceNow admin may need to create a service account with the `itil` role.

---

## Option A: Logic App (Recommended)

### Step 1: Create the Logic App

1. **Portal → Logic Apps → + Add**
2. Basics:
   - Subscription: customer's
   - Resource Group: `rg-monitoring-poc-il-01`
   - Logic App name: `la-snow-alerts-il-01`
   - Region: `Canada Central`
   - Plan type: **Consumption** (pay per execution, fine for PoC)
3. **Review + create**

### Step 2: Design the Workflow

1. Open the Logic App → **Logic App Designer**
2. Click **+ Add a trigger** → search **"When an HTTP request is received"** → select it

#### 2a. Configure the HTTP Trigger

1. In the trigger box, click **"Use sample payload to generate schema"**
2. Paste this common alert schema sample:

```json
{
  "schemaId": "azureMonitorCommonAlertSchema",
  "data": {
    "essentials": {
      "alertId": "/subscriptions/.../providers/Microsoft.AlertsManagement/alerts/...",
      "alertRule": "alrt-cpu-critical-il-01",
      "severity": "Sev1",
      "signalType": "Log",
      "monitorCondition": "Fired",
      "monitoringService": "Log Alerts V2",
      "alertTargetIDs": [
        "/subscriptions/.../resourceGroups/.../providers/Microsoft.OperationalInsights/workspaces/..."
      ],
      "firedDateTime": "2026-04-09T14:30:00.000Z",
      "resolvedDateTime": null,
      "description": "Average CPU exceeds 95% over 5 minutes.",
      "essentialsVersion": "1.0",
      "alertContextVersion": "1.0"
    },
    "alertContext": {}
  }
}
```

3. Click **Done** — the schema auto-generates
4. Click **Save** (top left) — this generates the **HTTP POST URL**
5. **Copy the HTTP POST URL** and save it — you'll paste it into the Action Group later

> The URL looks like: `https://prod-xx.canadacentral.logic.azure.com:443/workflows/...`

#### 2b. Parse the Alert Payload

1. Click **+ New step** → search **"Parse JSON"** → select it
2. **Content**: click the field → **Dynamic content** tab → select **Body** (from the HTTP trigger)
3. **Schema**: click **"Use sample payload to generate schema"**
4. Paste the same sample JSON from Step 2a:

```json
{
  "schemaId": "azureMonitorCommonAlertSchema",
  "data": {
    "essentials": {
      "alertId": "/subscriptions/.../providers/Microsoft.AlertsManagement/alerts/...",
      "alertRule": "alrt-cpu-critical-il-01",
      "severity": "Sev1",
      "signalType": "Log",
      "monitorCondition": "Fired",
      "monitoringService": "Log Alerts V2",
      "alertTargetIDs": [
        "/subscriptions/.../resourceGroups/.../providers/Microsoft.OperationalInsights/workspaces/..."
      ],
      "firedDateTime": "2026-04-09T14:30:00.000Z",
      "resolvedDateTime": null,
      "description": "Average CPU exceeds 95% over 5 minutes.",
      "essentialsVersion": "1.0",
      "alertContextVersion": "1.0"
    },
    "alertContext": {}
  }
}
```

5. Click **Done** — the schema generates automatically
6. Now in every subsequent step, the **Dynamic content** panel shows parsed fields:
   - `alertRule`, `severity`, `monitorCondition`, `description`, `firedDateTime`, `resolvedDateTime`, `alertId`

#### 2c. Condition: Fired vs Resolved

1. **+ New step** → search **"Condition"** → select **Control → Condition**
2. Click the left value field → **Dynamic content** tab → select **monitorCondition**
3. Operator: **is equal to**
4. Right value: type `Fired`

#### 2d. If True (Fired) → Create ServiceNow Incident

1. In the **True** branch → **+ Add an action**
2. Search for **"ServiceNow"** → select **"Create Record"**
3. Configure the connection (first time only):
   - Connection name: `snow-contoso`
   - Instance URL: `https://<instance>.service-now.com`
   - Authentication: **Basic** (username + password) or **OAuth2**
   - Enter credentials → click **Create**
4. Configure the record fields:

| Field             | How to Set It                                                                         |
| ----------------- | ------------------------------------------------------------------------------------- |
| Record Type       | Select **Incident** from the dropdown                                                 |
| Short description | Type `Azure Alert: ` then click **Dynamic content** → select **alertRule**            |
| Description       | See note below — use **Additional comments** (work_notes) as the primary detail field |
| Impact            | Type `1` (High) — or `2` for Medium if mapping from Sev 2 warnings                    |
| Urgency           | Type `2` (Medium)                                                                     |
| Assignment group  | Type the exact group name Contoso provides (e.g., `IT Operations`)                       |
| Category          | Type the category Contoso uses (e.g., `Infrastructure`)                                  |
| Caller            | Type the service account username                                                     |

> **Important: Description field limitation.** The ServiceNow Logic App connector's Create Record action may not reliably set the `description` field due to ServiceNow REST API limitations. The value can be silently ignored. To work around this:
>
> - Put essential info in **Short description** (this always works)
> - After the Create Record step, add a **second action**: **ServiceNow → "Update Record"** using the **Sys ID** from the Create Record output, and set the **Additional comments** (`work_notes`) field with the full detail:
>   - Type `Severity: ` → select **severity** → Enter → `Description: ` → select **description** → Enter → `Fired at: ` → select **firedDateTime** → Enter → `Alert ID: ` → select **alertId**
> - This ensures the detail always appears on the incident as a work note.

5. **Add a correlation field** for reliable incident matching:
   - In the Create Record, look for a custom field or use **Correlation ID** (if available in your ServiceNow instance)
   - Set it to the **alertId** from dynamic content
   - This gives each incident a unique identifier tied to the specific alert instance
   - If no Correlation ID field is available, include the **alertId** in the short description instead:
     - Short description: `Azure Alert: ` + **alertRule** + `|` + **alertId**

6. The Create Record output includes **Sys ID** and **Number** — used by the Update Record step above for adding work notes.

#### 2e. If False (Resolved) → Update/Close ServiceNow Incident

1. In the **False** branch → **+ Add an action**
2. **ServiceNow → "List Records"**
   - Record type: **Incident**
   - Query field: click into it → **Expression** tab → paste:
     `concat('short_descriptionLIKEAzure Alert: ', body('Parse_JSON')?['data']?['essentials']?['alertRule'], '^stateNOT IN6,7,8')`
     → click **OK**
   - This finds the open incident matching the alert rule name (excludes Resolved=6, Closed=7, Canceled=8)

> **Correlation caveat:** Matching by `short_description` is acceptable for a PoC but is weak correlation. If the same alert rule fires for multiple servers, you could match the wrong incident. For production, use the **alertId** (included in the short description if you followed step 2d.5) or store it in a custom ServiceNow field and query by that instead. 3. **+ Add an action** → Logic App auto-adds a **For each** loop (since List Records can return multiple results) 4. Inside the loop → **ServiceNow → "Update Record"**

- Record type: **Incident**
- Sys ID: click **Dynamic content** → select **Sys Id** (from the List Records output)
- State: type `6` (Resolved)
- Close code: type `Closed/Resolved by Caller`
- Close notes: type `Alert auto-resolved at ` then click **Dynamic content** → select **resolvedDateTime**

> **Note on resolvedDateTime:** This field is reliably populated for metric alerts but may be `null` for log-based alerts. If the close notes show "auto-resolved at null", add a condition or use an expression to fall back to the current time:
> **Expression** tab → `if(empty(body('Parse_JSON')?['data']?['essentials']?['resolvedDateTime']), utcNow(), body('Parse_JSON')?['data']?['essentials']?['resolvedDateTime'])`

### Step 3: Save and Test the Logic App

1. **Save** the Logic App (top left)
2. Click **Run Trigger → Run with payload** (top bar)
3. Paste a test payload to verify the flow works:

```json
{
  "schemaId": "azureMonitorCommonAlertSchema",
  "data": {
    "essentials": {
      "alertId": "/subscriptions/test/providers/Microsoft.AlertsManagement/alerts/test-alert-001",
      "alertRule": "alrt-cpu-critical-il-01",
      "severity": "Sev1",
      "signalType": "Log",
      "monitorCondition": "Fired",
      "monitoringService": "Log Alerts V2",
      "alertTargetIDs": [
        "/subscriptions/test/resourceGroups/test/providers/Microsoft.OperationalInsights/workspaces/test"
      ],
      "firedDateTime": "2026-04-10T14:30:00.000Z",
      "resolvedDateTime": null,
      "description": "TEST — Average CPU exceeds 95% over 5 minutes.",
      "essentialsVersion": "1.0",
      "alertContextVersion": "1.0"
    },
    "alertContext": {}
  }
}
```

4. Check the **Run history** — each step should show a green checkmark
5. Check ServiceNow — a test incident should appear
6. **Delete the test incident** in ServiceNow after verifying

### Step 4: Connect the Logic App to the Action Group

1. **Monitor → Alerts → Action groups → `ag-email-il-01`** → Edit
2. **Actions** tab → **+ Add action**
   - Action type: **Logic App**
   - Select the Logic App: `la-snow-alerts-il-01`
   - Name: `ServiceNow-CreateIncident`
   - ☑ **Enable common alert schema** — strongly recommended for this design; without it, each alert type (metric, log, activity log) sends a different payload structure, and the Parse JSON schema won't match
3. **Save**

> **Docs:** [Action groups — Logic App action](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/action-groups#logic-app)

### Step 5: Test End-to-End

1. **Trigger a test alert:**
   - Temporarily lower a threshold (e.g., CPU warning to 1%)
   - Wait for the alert to fire (~5-10 min)
2. **Verify in ServiceNow:**
   - New incident created with correct assignment group, category, description
3. **Verify auto-resolve:**
   - Revert the threshold back to normal
   - Wait for the alert to resolve (autoMitigate)
   - Check ServiceNow — incident should be updated to Resolved

---

## Option B: Webhook (Simpler, Less Control)

If the customer's ServiceNow instance has the **Event Management** plugin or an inbound REST endpoint:

### Step 1: Get the ServiceNow Webhook URL

ServiceNow's inbound event API:

```
https://<instance>.service-now.com/api/sn_em_connector/em/inbound_event?source=azuremonitor
```

Or for direct incident creation (Scripted REST API or Import Set):

```
https://<instance>.service-now.com/api/now/import/<import_set_table>
```

### Step 2: Add Webhook to Action Group

1. **Monitor → Alerts → Action groups → `ag-email-il-01`** → Edit
2. **Actions** tab → **+ Add action**
   - Action type: **Webhook**
   - URI: the ServiceNow URL above
   - ☑ Enable common alert schema
   - Authentication: **Basic Auth** (if required by ServiceNow)
3. **Save**

### Limitations of Webhook vs Logic App

| Feature                                              | Logic App                                              | Webhook                                             |
| ---------------------------------------------------- | ------------------------------------------------------ | --------------------------------------------------- |
| Create incident on fire                              | ✅                                                     | ✅                                                  |
| Auto-close on resolve                                | ✅ (built into workflow)                               | ⚠️ Requires ServiceNow-side scripting               |
| Field mapping (severity, category, assignment group) | ✅ Full control                                        | ⚠️ Limited — depends on ServiceNow inbound config   |
| Retry on failure                                     | ✅ Built-in (up to 4 retries with exponential backoff) | ✅ Azure retries webhook up to 3 times              |
| Logging / debugging                                  | ✅ Full run history in Logic App                       | ❌ Fire and forget (check Action Group run history) |
| Cost                                                 | ~$0.0025/execution                                     | Free                                                |

---

## Option C: ITSM Connector (Legacy — Not Recommended)

> The ITSM Connector (ITSMC) for Azure Monitor is **deprecated as of March 2025**. Microsoft recommends using Logic Apps or Secure Webhook for new integrations. Existing ITSMC connections will continue to work but no new features or fixes will be provided.
>
> **Docs:** [ITSM Connector overview](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/itsmc-overview)

---

## Mapping Azure Monitor Severity to ServiceNow

| Azure Monitor         | ServiceNow Impact | ServiceNow Urgency | ServiceNow Priority |
| --------------------- | ----------------- | ------------------ | ------------------- |
| Sev 0 (Critical)      | 1 - High          | 1 - High           | 1 - Critical        |
| Sev 1 (Error)         | 1 - High          | 2 - Medium         | 2 - High            |
| Sev 2 (Warning)       | 2 - Medium        | 2 - Medium         | 3 - Moderate        |
| Sev 3 (Informational) | 3 - Low           | 3 - Low            | 4 - Low             |

> Adjust this mapping based on Contoso's existing SCOM→ServiceNow workflow.

---

## Logic App Designer — Quick Reference

Here's the complete flow in pseudocode:

```
TRIGGER: When an HTTP request is received (Common Alert Schema)
  │
  ├── PARSE JSON: Extract essentials (alertRule, severity, monitorCondition, description)
  │
  ├── CONDITION: monitorCondition == "Fired"?
  │     │
  │     ├── TRUE: ServiceNow → Create Record (Incident)
  │     │     • Short description: "Azure Alert: {alertRule}"
  │     │     • Description: {description} + severity + timestamps
  │     │     • Impact/Urgency: mapped from severity
  │     │     • Assignment group: Contoso ops team
  │     │
  │     └── FALSE: ServiceNow → List Records (find matching open incident)
  │           └── For Each result:
  │                 └── ServiceNow → Update Record
  │                       • State: Resolved
  │                       • Close notes: "Auto-resolved at {resolvedDateTime}"
```

---

## Validation Checklist

| Test                                           | Expected Result                               | Status |
| ---------------------------------------------- | --------------------------------------------- | ------ |
| Alert fires → ServiceNow incident created      | New incident with correct fields              | ☐      |
| Incident has correct assignment group          | Matches Contoso target group                     | ☐      |
| Incident has correct category                  | Matches Contoso categorization                   | ☐      |
| Incident severity matches alert severity       | Sev 1 → High, Sev 2 → Medium                  | ☐      |
| Alert description appears in incident          | Full context in description field             | ☐      |
| Alert resolves → incident updated/closed       | State changes to Resolved                     | ☐      |
| Close notes reference auto-resolution          | "Auto-resolved at [timestamp]"                | ☐      |
| Multiple alerts → separate incidents           | Each alert rule creates its own incident      | ☐      |
| Same alert re-fires → doesn't create duplicate | Logic should check for existing open incident | ☐      |

---

## Troubleshooting

### Logic App Not Triggering

- Check the Action Group has the Logic App action enabled
- **Monitor → Alerts → Alert rules** → click an alert → **History** — verify it shows "Action Group triggered"
- **Logic Apps → la-snow-alerts-il-01 → Run history** — check for runs

### ServiceNow Connection Failed

- Verify the instance URL is correct (no trailing slash)
- Check the service account has the `itil` role in ServiceNow
- If using OAuth: verify the client ID/secret and token endpoint
- Test the connection: **Logic App Designer → ServiceNow connector → "..." → Test connection"**

### Incident Created But Wrong Fields

- Open the Logic App run history → click the failed/succeeded run
- Expand each action to see the exact input/output payloads
- Adjust the field mappings in the Create Record action

### Auto-Close Not Working

- Verify the List Records query matches the short description pattern
- Check that the query excludes already-closed incidents (`state NOT IN 6,7,8`)
- Verify `autoMitigate: true` is set on the alert rule (it is for all performance alerts)
- Note: `alrt-privgroup-il-01` has `autoMitigate: false` — it won't auto-close by design
