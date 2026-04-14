# Contoso Azure Monitor PoC — Workbooks & KQL Query Library

## Contents

```
workbooks/
├── README.md                              # This file
├── deploy-workbooks.json                  # ARM template — deploys all 5 workbooks at once
├── kql-query-library.md                   # 10 production-ready KQL queries
├── server-health-overview.workbook        # Workbook 1: Server availability + perf summary
├── performance-deep-dive.workbook         # Workbook 2: CPU, memory, disk I/O, network detail
├── security-audit.workbook                # Workbook 3: Privileged group changes, lockouts, failed logons
├── windows-services-monitoring.workbook   # Workbook 4: Service state, crashes, new installs
└── alert-overview-operations.workbook     # Workbook 5: Operational dashboard, errors, ingestion health
```

## Workbook Descriptions

| Workbook | Purpose | Data Tables |
|---|---|---|
| **Server Health Overview** | At-a-glance server availability, CPU, memory, disk, network — replaces SCOM "State" view | Heartbeat, Perf |
| **Performance Deep Dive** | Percentile stats, trends, queue lengths, disk latency, IOPS — for investigation and baselining | Perf |
| **Security & Compliance Audit** | Privileged group changes, account lockouts, failed logons, user lifecycle, audit policy changes | SecurityEvent |
| **Windows Services Monitoring** | Critical service state, stops, crashes, new installs, start type changes — replaces SCOM service monitors | Event |
| **Alert Overview & Operations** | Fleet status, error trends, threshold breach detection, data ingestion health, agent health | Heartbeat, Event, Perf, Usage |

## Deployment Options

### Option A: Import via Azure Portal (Recommended for PoC)

1. Navigate to **Azure Monitor → Workbooks → + New**
2. Click the **Advanced Editor** button (`</>`) on the toolbar
3. Select the **Gallery Template** tab
4. Paste the contents of any `.workbook` file
5. Click **Apply**, then **Save** — choose the resource group and give it a name

Repeat for each workbook.

### Option B: Deploy All Workbooks via ARM Template

Use `deploy-workbooks.json` to deploy all 5 workbooks at once.

**Via Azure Portal:**

1. Open: **https://portal.azure.com/#create/Microsoft.Template**
2. Click **"Build your own template in the editor"**
3. Paste the contents of `deploy-workbooks.json`
4. Click **Save** → fill in parameters:
   - `workspaceName` — their existing Log Analytics workspace name
   - `workspaceResourceGroup` — the RG containing the workspace
5. **Review + Create** → **Create** (~1 min)

**Via Azure CLI:**

```bash
az deployment group create \
  -g <resource-group> \
  --template-file workbooks/deploy-workbooks.json \
  --parameters workspaceName=<workspace-name> \
               workspaceResourceGroup=<workspace-rg>
```

### Option C: Deploy via Cloud Shell

```bash
# Customer uploads deploy-workbooks.json to Cloud Shell, then:
az deployment group create \
  -g rg-contoso-monitor-poc \
  --template-file deploy-workbooks.json \
  --parameters workspaceName=law-contoso-poc \
               workspaceResourceGroup=rg-contoso-monitor-poc
```

## KQL Query Library

See [`kql-query-library.md`](kql-query-library.md) for 10 ready-to-use queries covering:

1. Server availability (offline detection)
2. CPU hotspots (>85% sustained)
3. Low memory detection (<500 MB)
4. Disk space critical (<10% free)
5. Critical Windows service stops
6. Privileged group membership changes
7. Account lockout investigation
8. Failed logon heatmap (brute-force detection)
9. Windows event error surge detection
10. Data ingestion & cost monitoring

## Prerequisites

These workbooks require the following DCRs to be configured and active:

| DCR | Required For |
|---|---|
| `dcr-contoso-perf-counters` | Workbooks 1, 2, 5 |
| `dcr-contoso-windows-events` | Workbooks 4, 5 |
| `dcr-contoso-security-events` | Workbook 3 |

All DCRs are defined in the `deploy/dcrs/` folder of this repository.

## Customization

All workbooks include parameter dropdowns for **Time Range** and **Server** (where applicable). To customize:

- **Add services to monitor:** Edit the `ServiceName in (...)` list in the Windows Services workbook
- **Change thresholds:** Modify the `where` clause values (e.g., CPU > 85, Memory < 500)
- **Add servers to exclude:** Add exclusions to the `where Computer` clauses
- **Export as ARM template:** Open any workbook in the portal → Edit → Advanced Editor → ARM Template tab
