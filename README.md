# Azure Monitor PoC — SCOM to Azure Monitor Migration

A complete, deployment-ready toolkit for migrating from SCOM to Azure Monitor. Includes ARM templates for alerts, Data Collection Rules, workbooks, KQL queries, and step-by-step guides for Arc onboarding, AMA deployment, and ServiceNow integration.

## Repository Structure

```
├── README.md                          # This file
├── docs/
│   ├── runbook.md                     # End-to-end deployment runbook
│   ├── ama-deployment-guide.md        # Azure Monitor Agent deployment (5 methods)
│   └── servicenow-integration-guide.md # ServiceNow ITSM integration
├── deploy/
│   ├── README.md                      # Deploy folder reference
│   ├── azuredeploy.json               # Action Group + 9 alert rules (ARM template)
│   ├── azuredeploy.parameters.json    # Parameters file for CLI deployment
│   ├── deploy.sh                      # CLI deployment script
│   ├── associate-dcrs.sh              # DCR-to-server association helper
│   ├── alerts/                        # Individual alert rule templates
│   ├── dcrs/                          # Data Collection Rule templates
│   └── diagnostic-settings/           # Activity Log & Entra ID log routing
└── workbooks/
    ├── README.md                      # Workbook deployment instructions
    ├── deploy-workbooks.json          # ARM template — deploys all 5 workbooks
    ├── kql-query-library.md           # 10 ad-hoc KQL queries for investigation
    ├── server-health-overview.workbook
    ├── performance-deep-dive.workbook
    ├── security-audit.workbook
    ├── windows-services-monitoring.workbook
    └── alert-overview-operations.workbook
```

## Quick Start

### 1. Prerequisites

- Azure subscription with an existing Log Analytics Workspace
- Azure Arc-enabled servers (or Azure VMs)
- RBAC: Monitoring Contributor + Log Analytics Contributor on the target resource group

### 2. Deploy Data Collection Rules

Create DCRs in the Azure Portal using the reference templates in [`deploy/dcrs/`](deploy/dcrs/):

| DCR | What It Collects |
|---|---|
| Performance Counters | CPU, Memory, Disk (space + latency + IOPS), Network — 60s intervals |
| Windows Event Logs | Application/System errors, Service Control Manager events |
| Security Events | Privileged group changes, lockouts, failed logons, account lifecycle |
| Directory Service | AD DS event log — DC health, replication, LDAP |
| VM Insights | VM metrics + dependency map (network connections) |
| Change Tracking | File, registry, software, and service change detection |

### 3. Deploy Alerts

Deploy all alert rules and the action group via ARM template:

```bash
az deployment group create \
  -g <resource-group> \
  --template-file deploy/azuredeploy.json \
  --parameters workspaceName=<workspace> \
               workspaceResourceGroup=<rg> \
               notificationEmail=admin@contoso.com \
               notificationEmailOps=ops@contoso.com
```

### 4. Deploy Workbooks

Deploy all 5 workbooks at once:

```bash
az deployment group create \
  -g <resource-group> \
  --template-file workbooks/deploy-workbooks.json \
  --parameters workspaceName=<workspace> \
               workspaceResourceGroup=<rg>
```

Or import individually via **Azure Monitor → Workbooks → New → Advanced Editor** — paste any `.workbook` file.

## Workbooks

| Workbook | Purpose |
|---|---|
| **Server Health Overview** | Availability, CPU, memory, disk, network — replaces SCOM State view |
| **Performance Deep Dive** | Percentile stats, queue lengths, disk latency, IOPS |
| **Security & Compliance Audit** | Privileged group changes, lockouts, failed logons |
| **Windows Services Monitoring** | Service state, crashes, new installs — replaces SCOM service monitors |
| **Alert Overview & Operations** | Fleet status, error trends, threshold breaches, ingestion health |

## Alert Rules

| Alert | Severity | Threshold |
|---|---|---|
| Server Unreachable | Sev 1 | No heartbeat > 5 min |
| CPU Warning / Critical | Sev 2 / 1 | > 85% / > 95% sustained |
| Memory Warning / Critical | Sev 2 / 1 | < 1 GB / < 500 MB available |
| Disk Warning / Critical | Sev 2 / 1 | < 15% / < 10% free |
| Critical Service Stopped | Sev 1 | DHCP, DNS, AD, SCCM service stop |
| Privileged Group Change | Sev 2 | Member added/removed from Domain/Enterprise/Schema Admins |

## Documentation

| Guide | Description |
|---|---|
| [Runbook](docs/runbook.md) | End-to-end deployment — Arc onboarding, AMA, DCRs, alerts, workbooks, network monitoring |
| [AMA Deployment Guide](docs/ama-deployment-guide.md) | 5 methods for deploying Azure Monitor Agent (Portal, CLI, Policy) with troubleshooting |
| [ServiceNow Integration](docs/servicenow-integration-guide.md) | Webhook and Logic App integration for alert-to-incident automation |
| [KQL Query Library](workbooks/kql-query-library.md) | 10 ad-hoc investigation queries (heartbeat gaps, baselines, lockout timelines, cost analysis) |

## Prerequisites by Phase

| Phase | What to Configure |
|---|---|
| **Phase 1** | Resource group, Log Analytics Workspace, Azure Arc onboarding, AMA deployment, DCRs |
| **Phase 2** | Action group, alert rules (CPU, memory, disk, heartbeat, services, security) |
| **Phase 3** | ServiceNow integration, workbooks, VM Insights, Connection Monitor, diagnostic settings |
