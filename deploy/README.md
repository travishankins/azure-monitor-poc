# Azure Monitor PoC — Deployment Templates

See also: [Runbook](../docs/runbook.md) | [AMA Deployment Guide](../docs/ama-deployment-guide.md) | [ServiceNow Integration](../docs/servicenow-integration-guide.md)

## Delivery Model

This deployment is designed for guided delivery where the operator configures the customer's environment:

| Step                       | Who          | How                               | What                                                 |
| -------------------------- | ------------ | --------------------------------- | ---------------------------------------------------- |
| 1. Create workspace + DCRs | **Operator** | Azure Portal UI                   | Log Analytics Workspace, 3 DCRs, server associations |
| 2. Deploy alerts           | **Operator** | Portal Custom Template (ARM JSON) | Action Group + 9 alert rules via `azuredeploy.json`  |

## Structure

```
deploy/
├── azuredeploy.json                  # Action Group + Alert Rules (deploy via Portal or CLI)
├── azuredeploy.parameters.json       # Parameters reference — for Cloud Shell deployments
├── deploy.sh                         # CLI deployment script
├── associate-dcrs.sh                 # Associate DCRs with servers (CLI helper)
├── dcrs/                             # DCR reference templates (guide Portal configuration)
│   ├── dcr-windows-perf-counters.json
│   ├── dcr-windows-event-logs.json
│   ├── dcr-windows-security-events.json
│   ├── dcr-windows-directory-service.json
│   ├── dcr-vm-insights.json
│   └── dcr-change-tracking.json
├── diagnostic-settings/              # Subscription & tenant-level log routing
│   ├── ds-activity-log.json
│   └── ds-entra-id-logs.json
└── alerts/                           # Individual alert templates (standalone use)
    ├── action-group.json
    ├── alert-server-unreachable.json
    ├── alert-high-cpu.json
    ├── alert-low-memory.json
    ├── alert-low-disk.json
    ├── alert-service-stopped.json
    └── alert-privileged-group-change.json
```

## Quick Start

### Step 1 — Create Data Collection Rules in Portal

Guide the customer through **Monitor → Data Collection Rules → + Create** for each:

| DCR                  | Portal Steps                                                                                                                      | Reference File                          |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| Performance Counters | Data source: **Performance Counters** → select CPU, Memory, Disk, Network at 60s                                                  | `dcrs/dcr-windows-perf-counters.json`   |
| Windows Events       | Data source: **Windows Event Logs** → Application, System (Warning+Error+Critical) + add custom XPath for Service Control Manager | `dcrs/dcr-windows-event-logs.json`      |
| Security Events      | Data source: **Windows Event Logs** → Security (filtered by Event IDs 4728, 4729, 4732, etc.)                                     | `dcrs/dcr-windows-security-events.json` |

During DCR creation, the customer also **selects target servers** in the Resources tab — this handles the DCR-to-server association automatically.

### Step 2 — Deploy Action Group + Alerts via Portal

1. Customer opens: **https://portal.azure.com/#create/Microsoft.Template**
2. Click **"Build your own template in the editor"**
3. Paste the contents of `azuredeploy.json` (share via Teams chat)
4. Click **Save** → fill in parameters:
   - `workspaceName` — their existing Log Analytics workspace
   - `workspaceResourceGroup` — the RG containing the workspace
   - `notificationEmail` / `notificationEmailOps` — their team emails
   - Adjust thresholds together on screen
5. **Review + create** → **Create** (~1-2 min)

### Alternative: Deploy via Cloud Shell

```bash
# Customer uploads azuredeploy.json to Cloud Shell, then:
az deployment group create \
  -g <their-resource-group> \
  --template-file azuredeploy.json \
  --parameters workspaceName=<their-workspace> \
               workspaceResourceGroup=<their-rg> \
               notificationEmail=admin@contoso.com \
               notificationEmailOps=ops@contoso.com
```

## What Gets Deployed

### Data Collection Rules — Created via Portal

The `dcrs/` folder contains **reference ARM templates** showing the exact configuration. Use these as a guide when walking the customer through the Portal UI.

| DCR                  | What It Collects                                                                                                                             |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Performance Counters | CPU, Memory, Disk (space + latency + IOPS), Network (throughput + queue) — 60s intervals                                                     |
| Windows Events       | Application/System errors & warnings, Service Control Manager events (7036, 7040, 7045, 7034), DHCP Server events                            |
| Security Events      | Privileged group changes (4728-4757), Account lockouts (4740, 4767), Logon failures (4625, 4771), User account changes, Audit policy changes |
| Directory Service    | Active Directory Directory Service event log — domain controller health, replication, LDAP                                                   |
| VM Insights          | VM performance metrics + dependency map (process/network connections) — for network traffic visibility                                       |
| Change Tracking      | File, registry, software, Windows service, and Linux daemon changes — drift detection and audit trail                                        |

### Diagnostic Settings — Subscription & Tenant Level

These are **not DCRs** — they route platform logs to the Log Analytics workspace via diagnostic settings.

| Setting       | What It Captures                                                               | How to Configure                                                                                                     |
| ------------- | ------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------- |
| Activity Log  | Resource create/delete, RBAC changes, policy compliance, all ARM operations    | **Subscription → Activity log → Diagnostic settings → + Add** or deploy `ds-activity-log.json` at subscription scope |
| Entra ID Logs | Sign-in logs, audit logs, risky users, risky sign-ins, MFA events, app consent | **Entra ID → Diagnostic settings → + Add** (requires Global Admin or Security Admin)                                 |

### Action Group + Alert Rules — Deployed via `azuredeploy.json`

The template references an **existing** Log Analytics Workspace (does not create one).

| Alert                   | Severity | Threshold                          | SCOM Equivalent            |
| ----------------------- | -------- | ---------------------------------- | -------------------------- |
| Server Unreachable      | Sev 1    | No heartbeat > 5 min               | Agent Heartbeat            |
| CPU Warning             | Sev 2    | > 85% sustained 10 min             | Processor\% Processor Time |
| CPU Critical            | Sev 1    | > 95% sustained 5 min              | Processor\% Processor Time |
| Memory Warning          | Sev 2    | < 1 GB available 10 min            | Memory\Available MBytes    |
| Memory Critical         | Sev 1    | < 500 MB available 5 min           | Memory\Available MBytes    |
| Disk Warning            | Sev 2    | < 15% free 10 min                  | LogicalDisk\% Free Space   |
| Disk Critical           | Sev 1    | < 10% free 5 min                   | LogicalDisk\% Free Space   |
| Service Stopped         | Sev 1    | DHCP/SCCM/DNS/W32Time/NTDS stopped | Windows Service Monitor    |
| Privileged Group Change | Sev 1    | Any add/remove to DA/EA/SA groups  | Custom Security Rule       |

### Alert Design Patterns

- **Warning alerts** (Sev 2): require 2 consecutive evaluation failures to fire (reduces flapping)
- **Critical alerts** (Sev 1): fire on first evaluation failure (fast response)
- **autoMitigate: true** on all performance alerts — auto-resolves when condition clears
- **autoMitigate: false** on privileged group change — stays fired until manually reviewed
- **Dimensions split by Computer** — each server fires its own independent alert instance
- **No workspace dependency** — template points at existing workspace via resource ID reference
