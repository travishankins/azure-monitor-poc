# Azure Monitor Proof of Concept – Runbook

---

## Phase 1 – Prerequisites, Arc Onboarding & AMA Deployment

### 1.1 Validate Prerequisites

#### Azure Resource Requirements

| Requirement                   | Action                                                        | Docs                                                                                                                              |
| ----------------------------- | ------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Log Analytics Workspace       | Create or identify existing workspace                         | [Create a Log Analytics workspace](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/quick-create-workspace)             |
| Resource Group                | Create dedicated PoC resource group                           | [Manage resource groups](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-portal) |
| Sentinel Workspace (optional) | Enable Sentinel on the LAW if security scenarios are in scope | [Quickstart: Onboard Microsoft Sentinel](https://learn.microsoft.com/en-us/azure/sentinel/quickstart-onboard)                     |

#### RBAC Permissions Required

Ensure the PoC operator has the following roles on the target resource group/subscription:

| Role                                               | Purpose                            | Docs                                                                                                                    |
| -------------------------------------------------- | ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| **Monitoring Contributor**                         | Create alerts, action groups, DCRs | [Azure Monitor roles and permissions](https://learn.microsoft.com/en-us/azure/azure-monitor/roles-permissions-security) |
| **Azure Connected Machine Resource Administrator** | Onboard Arc servers                | [Azure Arc RBAC](https://learn.microsoft.com/en-us/azure/azure-arc/servers/security-overview)                           |
| **Log Analytics Contributor**                      | Manage workspace and DCRs          | [Manage access to Log Analytics](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/manage-access)              |
| **Microsoft Sentinel Contributor** (if Sentinel)   | Configure analytics rules          | [Roles and permissions in Sentinel](https://learn.microsoft.com/en-us/azure/sentinel/roles)                             |

> **WAF Alignment (Security Pillar):** Use least-privilege RBAC. Create a dedicated PoC resource group to scope permissions. Avoid granting subscription-wide Owner/Contributor.

#### Firewall / Network Requirements

The following endpoints must be reachable from on-premises servers (port 443 outbound):

| Service             | Endpoints                                                                                                    | Docs                                                                                                                                |
| ------------------- | ------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| Azure Arc           | `*.his.arc.azure.com`, `*.guestconfiguration.azure.com`, `management.azure.com`, `login.microsoftonline.com` | [Azure Arc network requirements](https://learn.microsoft.com/en-us/azure/azure-arc/servers/network-requirements)                    |
| Azure Monitor Agent | `*.ods.opinsights.azure.com`, `*.oms.opinsights.azure.com`, `*.monitor.azure.com`                            | [AMA network configuration](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-network-configuration) |
| Microsoft Entra ID  | `login.microsoftonline.com`, `*.aadcdn.microsoftonline-p.com`                                                | Included in Arc requirements                                                                                                        |

**Validation command (run on target server):**

```powershell
# Test Arc connectivity
Test-NetConnection -ComputerName "management.azure.com" -Port 443
Test-NetConnection -ComputerName "login.microsoftonline.com" -Port 443
Test-NetConnection -ComputerName "gbl.his.arc.azure.com" -Port 443

# Test AMA connectivity
Test-NetConnection -ComputerName "global.handler.control.monitor.azure.com" -Port 443
```

> **WAF Alignment (Security Pillar):** If a proxy is required, configure the Arc agent and AMA to use it. Consider Azure Private Link for private connectivity.
>
> Docs: [Use Azure Private Link for Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/private-link-security)

---

### 1.2 Azure Arc Onboarding

#### Step-by-Step: Single Server Onboarding

1. **Generate the onboarding script** in the Azure Portal:
   - Navigate to **Azure Arc > Servers > + Add**
   - Select **Add a single server** (or **Add multiple servers** for at-scale)
   - Fill in: Subscription, Resource Group, Region, OS (Windows), Connectivity method
   - Download the generated script

2. **Run the script on the target server** (elevated PowerShell):

```powershell
# Example — the portal generates this for you
& "$env:TEMP\install_windows_azcmagent.ps1"

# Connect the agent
azcmagent connect `
  --resource-group "rg-contoso-monitor-poc" `
  --tenant-id "<tenant-id>" `
  --location "canadacentral" `
  --subscription-id "<subscription-id>"
```

3. **Validate Arc connectivity:**

```powershell
azcmagent show
# Status should be "Connected"
```

4. **Verify in Portal:** Azure Arc > Servers — confirm the server appears and status is **Connected**.

**Docs:**

- [Quickstart: Connect hybrid machines with Azure Arc](https://learn.microsoft.com/en-us/azure/azure-arc/servers/learn/quick-enable-hybrid-vm)
- [Connect machines at scale using a service principal](https://learn.microsoft.com/en-us/azure/azure-arc/servers/onboard-service-principal)

#### At-Scale Onboarding (Multiple Servers)

For multiple servers, consider:

| Method                     | Best For                      | Docs                                                                                                                             |
| -------------------------- | ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Service Principal + script | 10-50 servers                 | [Onboard at scale with service principal](https://learn.microsoft.com/en-us/azure/azure-arc/servers/onboard-service-principal)   |
| Group Policy               | Domain-joined Windows servers | [Connect machines using Group Policy](https://learn.microsoft.com/en-us/azure/azure-arc/servers/onboard-group-policy-powershell) |
| Ansible/SCCM               | Existing config management    | [Connect machines using Ansible](https://learn.microsoft.com/en-us/azure/azure-arc/servers/onboard-ansible-playbooks)            |

> **WAF Alignment (Operational Excellence):** Use automated onboarding methods to reduce configuration drift and manual errors. Tag all Arc servers with environment, role, and owner.

---

### 1.3 Deploy Azure Monitor Agent (AMA)

#### Option A: Deploy via Azure Portal

1. Navigate to **Monitor > Data Collection Rules > + Create**
2. This will auto-deploy AMA to any machine that doesn't already have it

#### Option B: Deploy AMA Directly (Azure CLI)

```bash
# For Arc-enabled servers
az connectedmachine extension create \
  --machine-name "<server-name>" \
  --resource-group "rg-contoso-monitor-poc" \
  --name "AzureMonitorWindowsAgent" \
  --type "AzureMonitorWindowsAgent" \
  --publisher "Microsoft.Azure.Monitor" \
  --location "canadacentral"
```

#### Option C: Deploy via Azure Policy (Recommended for Production)

| Policy                                                              | Purpose                        |
| ------------------------------------------------------------------- | ------------------------------ |
| `Configure Windows Arc-enabled machines to run Azure Monitor Agent` | Auto-deploy AMA to Arc servers |

```bash
# Assign the built-in policy
az policy assignment create \
  --name "deploy-ama-arc-windows" \
  --policy "845857af-0333-4c5d-bbbc-6076697da122" \
  --scope "/subscriptions/<sub-id>/resourceGroups/rg-contoso-monitor-poc"
```

**Validation:**

```powershell
# On the target server — check AMA is running
Get-Service -Name "AzureMonitorAgent"

# In Azure CLI — verify extension status
az connectedmachine extension list \
  --machine-name "<server-name>" \
  --resource-group "rg-contoso-monitor-poc" \
  -o table
```

**Docs:**

- [Azure Monitor Agent overview](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-overview)
- [Install Azure Monitor Agent](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-manage)
- [Azure Monitor Agent supported OS](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/agents-overview)

> **WAF Alignment (Operational Excellence):** Use Azure Policy for consistent AMA deployment. This ensures new machines automatically get the agent — critical for production rollout.

---

### 1.4 Create Data Collection Rules (DCRs)

DCRs define **what** to collect, **how** to transform it, and **where** to send it.

#### DCR 1: Performance Counters

```json
{
  "properties": {
    "dataSources": {
      "performanceCounters": [
        {
          "name": "perfCounterDataSource",
          "streams": ["Microsoft-Perf"],
          "samplingFrequencyInSeconds": 60,
          "counterSpecifiers": [
            "\\Processor(_Total)\\% Processor Time",
            "\\Memory\\% Committed Bytes In Use",
            "\\Memory\\Available MBytes",
            "\\LogicalDisk(*)\\% Free Space",
            "\\LogicalDisk(*)\\Free Megabytes",
            "\\LogicalDisk(*)\\Avg. Disk sec/Read",
            "\\LogicalDisk(*)\\Avg. Disk sec/Write",
            "\\Network Interface(*)\\Bytes Total/sec",
            "\\System\\Processor Queue Length"
          ]
        }
      ]
    },
    "destinations": {
      "logAnalytics": [
        {
          "workspaceResourceId": "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<workspace>",
          "name": "la-destination"
        }
      ]
    },
    "dataFlows": [
      {
        "streams": ["Microsoft-Perf"],
        "destinations": ["la-destination"]
      }
    ]
  }
}
```

#### DCR 2: Windows Event Logs

```json
{
  "properties": {
    "dataSources": {
      "windowsEventLogs": [
        {
          "name": "eventLogsDataSource",
          "streams": ["Microsoft-Event"],
          "xPathQueries": [
            "Application!*[System[(Level=1 or Level=2 or Level=3)]]",
            "System!*[System[(Level=1 or Level=2 or Level=3)]]",
            "Security!*[System[(EventID=4728 or EventID=4732 or EventID=4756 or EventID=4735 or EventID=4737 or EventID=4755)]]",
            "Security!*[System[(EventID=7036 or EventID=7040)]]",
            "System!*[System[Provider[@Name='Service Control Manager']]]"
          ]
        }
      ]
    },
    "destinations": {
      "logAnalytics": [
        {
          "workspaceResourceId": "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<workspace>",
          "name": "la-destination"
        }
      ]
    },
    "dataFlows": [
      {
        "streams": ["Microsoft-Event"],
        "destinations": ["la-destination"]
      }
    ]
  }
}
```

> **Key Security Event IDs for Privileged Group Changes:**
>
> - **4728** — Member added to a security-enabled global group
> - **4732** — Member added to a security-enabled local group
> - **4756** — Member added to a security-enabled universal group
> - **4735** — Security-enabled local group was changed
> - **4737** — Security-enabled global group was changed
> - **4755** — Security-enabled universal group was changed

#### DCR 3: Windows Services (via Event Log)

Windows service start/stop events are captured via:

- **Event ID 7036** (Service Control Manager) — service entered running/stopped state
- **Event ID 7040** — service start type was changed

These are already included in DCR 2 above.

#### Apply DCRs to Servers (Azure CLI)

```bash
# Create the DCR
az monitor data-collection rule create \
  --resource-group "rg-contoso-monitor-poc" \
  --name "dcr-contoso-perf" \
  --location "canadacentral" \
  --rule-file "dcr-perf.json"

# Associate the DCR with an Arc server
az monitor data-collection rule association create \
  --name "assoc-perf" \
  --rule-id "/subscriptions/<sub>/resourceGroups/rg-contoso-monitor-poc/providers/Microsoft.Insights/dataCollectionRules/dcr-contoso-perf" \
  --resource "/subscriptions/<sub>/resourceGroups/rg-contoso-monitor-poc/providers/Microsoft.HybridCompute/machines/<server-name>"
```

**Docs:**

- [Data collection rules overview](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-overview)
- [Collect Windows events with AMA](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/data-collection-windows-events)
- [Collect performance counters with AMA](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/data-collection-performance)
- [Data collection rule structure](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-structure)

> **WAF Alignment (Cost Optimization):** Collect only the data you need. Use DCR transformations to filter/drop noisy events before ingestion to reduce Log Analytics costs.
>
> Docs: [Data collection transformations](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-transformations)

---

## Phase 2 – SCOM Scenario Recreation & Alerting

### 2.1 Availability Monitoring — Detect Unreachable Servers

#### Option A: Heartbeat-Based Alert

The AMA sends a heartbeat every 60 seconds. If a heartbeat is missing, the server is likely unreachable.

**Create a log search alert rule (Azure CLI):**

```bash
az monitor scheduled-query create \
  --name "alert-server-unreachable" \
  --resource-group "rg-contoso-monitor-poc" \
  --scopes "/subscriptions/<sub>/resourceGroups/rg-contoso-monitor-poc/providers/Microsoft.OperationalInsights/workspaces/<workspace>" \
  --condition "count 'Heartbeat | summarize LastHeartbeat = max(TimeGenerated) by Computer | where LastHeartbeat < ago(5m)' > 0" \
  --severity 1 \
  --evaluation-frequency "5m" \
  --window-size "10m" \
  --action-groups "/subscriptions/<sub>/resourceGroups/rg-contoso-monitor-poc/providers/Microsoft.Insights/actionGroups/ag-contoso-poc"
```

**KQL for the alert:**

```kusto
Heartbeat
| summarize LastHeartbeat = max(TimeGenerated) by Computer
| where LastHeartbeat < ago(5m)
| project Computer, LastHeartbeat, MinutesSinceLastHeartbeat = datetime_diff('minute', now(), LastHeartbeat)
```

#### Option B: VM Availability Metric (Azure VMs Only)

For Azure VMs, use the native **VM Availability** metric:

- Navigate to **Monitor > Alerts > + Create alert rule**
- Signal: `VM Availability Metric (Preview)`
- Condition: Average < 1
- Severity: Sev 1

**Docs:**

- [Heartbeat solution in Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/insights/solution-agenthealth)
- [Create log search alert rules](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-create-log-alert-rule)

---

### 2.2 Performance Monitoring Alerts

#### CPU Usage Alert

```kusto
// Alert KQL: CPU > 90% sustained for 10 min
Perf
| where ObjectName == "Processor" and CounterName == "% Processor Time" and InstanceName == "_Total"
| summarize AvgCPU = avg(CounterValue) by Computer, bin(TimeGenerated, 5m)
| where AvgCPU > 90
```

**Portal steps:**

1. **Monitor > Alerts > + Create > Alert rule**
2. Scope: Log Analytics Workspace
3. Condition: Custom log search → paste KQL above
4. Threshold: > 0 results
5. Evaluation: every 5 min, lookback 10 min
6. Severity: Sev 2
7. Action Group: `ag-contoso-poc`

#### Memory Usage Alert

```kusto
// Alert KQL: Available Memory < 500 MB
Perf
| where ObjectName == "Memory" and CounterName == "Available MBytes"
| summarize AvgAvailMB = avg(CounterValue) by Computer, bin(TimeGenerated, 5m)
| where AvgAvailMB < 500
```

#### Disk Space Alert

```kusto
// Alert KQL: Disk free space < 10%
Perf
| where ObjectName == "LogicalDisk" and CounterName == "% Free Space"
| where InstanceName !in ("_Total", "HarddiskVolume1")
| summarize AvgFreePercent = avg(CounterValue) by Computer, InstanceName, bin(TimeGenerated, 5m)
| where AvgFreePercent < 10
```

**Recommended Thresholds (aligned with SCOM defaults):**

| Metric               | Warning          | Critical        | SCOM Equivalent                 |
| -------------------- | ---------------- | --------------- | ------------------------------- |
| CPU % Processor Time | > 85% for 10 min | > 95% for 5 min | Processor\% Processor Time      |
| Available Memory MB  | < 1 GB           | < 500 MB        | Memory\Available MBytes         |
| Disk % Free Space    | < 15%            | < 10%           | LogicalDisk\% Free Space        |
| Disk Avg sec/Read    | > 25 ms          | > 50 ms         | LogicalDisk\Avg. Disk sec/Read  |
| Disk Avg sec/Write   | > 25 ms          | > 50 ms         | LogicalDisk\Avg. Disk sec/Write |

**Docs:**

- [Azure Monitor alert types](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-types)
- [Best practices for Azure Monitor alerts](https://learn.microsoft.com/en-us/azure/azure-monitor/best-practices-alerts)
- [Log search alert rules](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-create-log-alert-rule)

> **WAF Alignment (Reliability Pillar):** Set appropriate severity levels. Sev 0/1 for critical infrastructure alerts; Sev 2/3 for warnings. Avoid alert fatigue by tuning thresholds to Contoso's actual baselines.

---

### 2.3 Windows Services Monitoring

Monitor critical services: **DHCP**, **SCCM Executive Service**, and others provided by Contoso.

#### KQL: Detect Service Stops

```kusto
Event
| where EventLog == "System" and Source == "Service Control Manager" and EventID == 7036
| parse EventData with * '<Data Name="param1">' ServiceName '</Data><Data Name="param2">' ServiceState '</Data>' *
| where ServiceState =~ "stopped"
| where ServiceName in ("DHCP Server", "CcmExec", "SMS_EXECUTIVE", "W32Time", "DNS", "NTDS")
| project TimeGenerated, Computer, ServiceName, ServiceState
```

#### Create the Alert

1. **Monitor > Alerts > + Create alert rule**
2. Scope: Log Analytics Workspace
3. Signal: Custom log search
4. KQL: Use the query above (adjust `ServiceName` list per Contoso)
5. Threshold: > 0 results
6. Frequency: Every 5 min
7. Severity: Sev 1 (critical services should be high severity)

> **Tip for Contoso:** Ask them for the exact Windows service **names** (not display names) from their SCOM management packs. Run `Get-Service | Select-Object Name, DisplayName, Status` on target servers to get the mapping.

**Docs:**

- [Collect Windows event logs with AMA](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/data-collection-windows-events)
- [Log search alerts](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-create-log-alert-rule)

---

### 2.4 Privileged Group Change Alerts

Monitor changes to **Domain Admins**, **Enterprise Admins**, **Schema Admins**, and **Schedule Server Maintenance** group.

#### KQL: Privileged Group Membership Changes

```kusto
SecurityEvent
| where EventID in (4728, 4732, 4756)
| extend TargetGroup = tostring(EventData.TargetUserName)
| where TargetGroup in ("Domain Admins", "Enterprise Admins", "Schema Admins", "Schedule Server Maintenance")
| project
    TimeGenerated,
    Computer,
    Activity,
    Account,
    TargetGroup,
    MemberAdded = tostring(EventData.MemberName),
    SubjectAccount = tostring(EventData.SubjectUserName)
```

> **Note:** `SecurityEvent` table requires the **Windows Security Events via AMA** data connector. If using Sentinel, install the connector. If using only Azure Monitor, ensure the DCR collects Security log events with those Event IDs.

#### Alternative KQL (using Event table if SecurityEvent is not available)

```kusto
Event
| where EventLog == "Security"
| where EventID in (4728, 4732, 4756, 4735, 4737, 4755)
| project TimeGenerated, Computer, EventID, RenderedDescription, EventData
```

**DCR requirement:** Ensure Security Event collection is configured:

```json
"xPathQueries": [
    "Security!*[System[(EventID=4728 or EventID=4732 or EventID=4756 or EventID=4735 or EventID=4737 or EventID=4755)]]"
]
```

**Docs:**

- [Windows Security Events via AMA connector](https://learn.microsoft.com/en-us/azure/sentinel/data-connectors/windows-security-events-via-ama)
- [Audit Security Group Management](https://learn.microsoft.com/en-us/windows/security/threat-protection/auditing/audit-security-group-management)

> **WAF Alignment (Security Pillar):** Privileged group change monitoring is a critical security control. In production, route these to Sentinel for automated investigation with Analytics Rules and SOAR playbooks.

---

### 2.5 Action Groups Configuration

Action Groups define **who** gets notified and **how**.

```bash
# Create an Action Group
az monitor action-group create \
  --resource-group "rg-contoso-monitor-poc" \
  --name "ag-contoso-poc" \
  --short-name "ContosoPoC" \
  --action email contoso-admin admin@contoso.com \
  --action email contoso-ops ops@contoso.com
```

**For ServiceNow integration, add an ITSM action (covered in Phase 3).**

| Notification Type     | Use Case                     |
| --------------------- | ---------------------------- |
| Email                 | All alert severities         |
| SMS                   | Sev 0 only (critical)        |
| Azure Mobile App Push | On-call staff                |
| ITSM (ServiceNow)     | Auto-create incident tickets |
| Webhook               | Custom integrations          |

**Docs:**

- [Create and manage action groups](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/action-groups)
- [Action groups overview](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/action-groups)

> **WAF Alignment (Operational Excellence):** Use alert processing rules to suppress alerts during planned maintenance windows. This prevents noise and false-positive tickets.
>
> Docs: [Alert processing rules](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-processing-rules)

---

## Phase 3 – ITSM Integration, Dashboards & Network Monitoring

### 3.1 ServiceNow ITSM Integration

#### Option A: ITSM Connector (Legacy)

> **Important:** The legacy ITSM Connector for Azure Monitor is being deprecated. Evaluate whether to use the newer Secure Webhook approach.

#### Option B: Secure Webhook (Recommended)

1. **Register an App in Microsoft Entra ID** for ServiceNow
2. **Configure ServiceNow** to accept the webhook
3. **Add a Webhook action** to the Action Group:

```bash
az monitor action-group update \
  --resource-group "rg-contoso-monitor-poc" \
  --name "ag-contoso-poc" \
  --add-action webhook snow-webhook "https://<instance>.service-now.com/api/sn_em_connector/em/inbound_event?source=azuremonitor"
```

#### Option C: Logic App Integration (Most Flexible)

1. **Create a Logic App** triggered by Azure Monitor alert
2. **Parse the alert payload**
3. **Create incident in ServiceNow** via the ServiceNow connector
4. **Add auto-resolve logic**: When alert condition resolves → update/close the ServiceNow incident

**Logic App flow:**

```
Azure Monitor Alert → Logic App (HTTP trigger)
  → Parse JSON (common alert schema)
  → Condition: monitorCondition == "Fired"
    → Yes: Create ServiceNow Incident
    → No (Resolved): Update/Close ServiceNow Incident
```

> **Key validation points for Contoso:**
>
> - Incident creation when alert fires ✓
> - Automatic closure when condition resolves ✓
> - Correct assignment group and category ✓

**Docs:**

- [Connect ServiceNow with ITSM Connector](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/itsmc-connections-servicenow)
- [ITSM Connector overview](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/itsmc-overview)
- [Secure Webhook for ITSM integration](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/itsmc-secure-webhook-connections-azure-configuration)
- [Common alert schema](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-common-schema)

> **WAF Alignment (Operational Excellence):** Use the common alert schema for all Action Group integrations. This ensures a consistent payload format regardless of alert type, simplifying ServiceNow mapping.

---

### 3.2 Azure Monitor Workbooks & Dashboards

#### Workbook 1: Server Health Overview

Create a workbook that replicates SCOM "State" view:

1. **Monitor > Workbooks > + New**
2. Add the following sections:

**Section: Server Availability (Heartbeat)**

```kusto
Heartbeat
| summarize LastHeartbeat = max(TimeGenerated) by Computer
| extend Status = iff(LastHeartbeat < ago(5m), "Offline", "Online")
| project Computer, LastHeartbeat, Status
| order by Status asc, Computer asc
```

**Section: CPU Usage (Last 24h)**

```kusto
Perf
| where ObjectName == "Processor" and CounterName == "% Processor Time" and InstanceName == "_Total"
| summarize AvgCPU = avg(CounterValue), MaxCPU = max(CounterValue) by Computer, bin(TimeGenerated, 1h)
| render timechart
```

**Section: Memory Usage**

```kusto
Perf
| where ObjectName == "Memory" and CounterName == "Available MBytes"
| summarize AvgAvailMB = avg(CounterValue) by Computer, bin(TimeGenerated, 1h)
| render timechart
```

**Section: Disk Free Space**

```kusto
Perf
| where ObjectName == "LogicalDisk" and CounterName == "% Free Space"
| where InstanceName !in ("_Total", "HarddiskVolume1")
| summarize AvgFree = avg(CounterValue) by Computer, InstanceName
| order by AvgFree asc
| render barchart
```

**Section: Critical Service Status**

```kusto
Event
| where EventLog == "System" and Source == "Service Control Manager" and EventID == 7036
| parse EventData with * '<Data Name="param1">' ServiceName '</Data><Data Name="param2">' ServiceState '</Data>' *
| where ServiceName in ("DHCP Server", "CcmExec", "SMS_EXECUTIVE", "W32Time", "DNS")
| summarize arg_max(TimeGenerated, *) by Computer, ServiceName
| project Computer, ServiceName, ServiceState, TimeGenerated
| order by ServiceState asc
```

**Section: Active Alert Summary**

```kusto
AlertsManagementResources
| where type == "microsoft.alertsmanagement/alerts"
| where properties.essentials.monitorCondition == "Fired"
| project
    AlertName = properties.essentials.alertRule,
    Severity = properties.essentials.severity,
    TargetResource = properties.essentials.targetResource,
    FiredTime = properties.essentials.startDateTime
| order by Severity asc
```

#### Workbook 2: Privileged Group Audit

```kusto
SecurityEvent
| where EventID in (4728, 4732, 4756, 4735, 4737, 4755)
| extend TargetGroup = tostring(EventData.TargetUserName)
| extend MemberChanged = tostring(EventData.MemberName)
| extend ChangedBy = tostring(EventData.SubjectUserName)
| project TimeGenerated, Computer, EventID, Activity, TargetGroup, MemberChanged, ChangedBy
| order by TimeGenerated desc
```

**Docs:**

- [Azure Monitor Workbooks overview](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview)
- [Create a workbook](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-create-workbook)
- [Workbook visualizations](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-visualizations)
- [Azure Monitor Workbook templates](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-templates)

> **WAF Alignment (Operational Excellence):** Export workbooks as ARM/Bicep templates for version control and repeatable deployment. Use parameterized workbooks so Contoso can filter by server, time range, or service.

---

### 3.3 Network Monitoring

#### VM Network Connectivity Insights

1. **Enable VM Insights** on the target machines:
   - Navigate to **Monitor > Virtual Machines > Configure Insights**
   - This deploys the Dependency Agent alongside AMA
   - Provides **Map** view showing network connections to/from VMs

**Docs:**

- [VM Insights overview](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vminsights-overview)
- [Enable VM Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vminsights-enable-overview)

#### Connection Monitor (Azure ↔ On-Premises Latency)

1. Navigate to **Network Watcher > Connection Monitor**
2. Create a test group:
   - Source: Azure VM (with Network Watcher extension)
   - Destination: On-premises server IP
   - Protocol: TCP / ICMP
   - Test frequency: every 30 seconds

```bash
# Install Network Watcher extension on Azure VM
az vm extension set \
  --vm-name "<azure-vm>" \
  --resource-group "rg-contoso-monitor-poc" \
  --name "NetworkWatcherAgentWindows" \
  --publisher "Microsoft.Azure.NetworkWatcher"
```

**Docs:**

- [Connection Monitor overview](https://learn.microsoft.com/en-us/azure/network-watcher/connection-monitor-overview)
- [Create a Connection Monitor](https://learn.microsoft.com/en-us/azure/network-watcher/connection-monitor-create-using-portal)

#### Cisco / Palo Alto Network Devices

| Capability          | Support Level             | Approach                                                                    |
| ------------------- | ------------------------- | --------------------------------------------------------------------------- |
| Syslog ingestion    | ✅ Supported              | Configure devices to send syslog to a Linux forwarder → AMA → Log Analytics |
| SNMP polling        | ❌ Not natively supported | Requires third-party (e.g., SNMP trap → syslog converter)                   |
| Cisco ASA/Firepower | ✅ Via Sentinel connector | CEF/Syslog data connector                                                   |
| Palo Alto Networks  | ✅ Via Sentinel connector | Palo Alto Networks (Firewall) connector or CEF                              |

**Syslog Collection Architecture:**

```
[Cisco/PaloAlto] --syslog--> [Linux VM with AMA (syslog forwarder)] --DCR--> [Log Analytics Workspace]
```

**Setup steps:**

1. Deploy a Linux VM (or Arc-enabled Linux server) as syslog forwarder
2. Install AMA on the forwarder
3. Create a DCR for syslog collection (facilities: `auth`, `authpriv`, `local0`–`local7`)
4. Configure the network devices to send syslog to the forwarder IP on port 514

**Docs:**

- [Collect syslog with AMA](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/data-collection-syslog)
- [CEF/Syslog via AMA connector for Sentinel](https://learn.microsoft.com/en-us/azure/sentinel/cef-syslog-ama-overview)
- [Palo Alto Networks connector](https://learn.microsoft.com/en-us/azure/sentinel/data-connectors/palo-alto-networks)

> **WAF Alignment (Reliability Pillar):** Clarify to Contoso that native SNMP polling is not available. For comprehensive network device monitoring, syslog/CEF is the supported path. Deep SNMP-based monitoring would require a partner solution.

---

### 3.4 Security Event Monitoring (Optional Sentinel Track)

If Contoso opts for Sentinel:

#### Enable Sentinel

```bash
az sentinel onboarding-state create \
  --resource-group "rg-contoso-monitor-poc" \
  --workspace-name "<workspace-name>" \
  --name "default"
```

#### Install Key Data Connectors

| Connector                       | Docs                                                                                                               |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Windows Security Events via AMA | [Connector docs](https://learn.microsoft.com/en-us/azure/sentinel/data-connectors/windows-security-events-via-ama) |
| Syslog via AMA                  | [Connector docs](https://learn.microsoft.com/en-us/azure/sentinel/cef-syslog-ama-overview)                         |

#### Create Analytics Rules for Privileged Group Monitoring

Use the built-in Sentinel template: **"Security Group Management Changes"** or create a custom one:

1. **Sentinel > Analytics > + Create > Scheduled query rule**
2. KQL: Use the privileged group change query from Section 2.4
3. Entity mapping: Map `Account`, `Computer`, `TargetGroup`
4. Incident settings: Auto-create incidents
5. Automated response: (Optional) attach a playbook for notification

**Docs:**

- [Microsoft Sentinel overview](https://learn.microsoft.com/en-us/azure/sentinel/overview)
- [Create custom analytics rules](https://learn.microsoft.com/en-us/azure/sentinel/detect-threats-custom)
- [Microsoft Sentinel SOAR](https://learn.microsoft.com/en-us/azure/sentinel/automation)

---

## KQL Query Library

A quick-reference collection of all KQL queries used in this PoC.

### Availability

```kusto
// Server heartbeat status
Heartbeat
| summarize LastHeartbeat = max(TimeGenerated) by Computer
| extend Status = iff(LastHeartbeat < ago(5m), "🔴 Offline", "🟢 Online")
| project Computer, Status, LastHeartbeat
| order by Status asc
```

### Performance

```kusto
// Top 10 CPU consumers (last 1h)
Perf
| where ObjectName == "Processor" and CounterName == "% Processor Time" and InstanceName == "_Total"
| where TimeGenerated > ago(1h)
| summarize AvgCPU = avg(CounterValue) by Computer
| top 10 by AvgCPU desc

// Servers with low disk space
Perf
| where ObjectName == "LogicalDisk" and CounterName == "% Free Space"
| where InstanceName !in ("_Total", "HarddiskVolume1")
| where TimeGenerated > ago(1h)
| summarize AvgFree = avg(CounterValue) by Computer, InstanceName
| where AvgFree < 15
| order by AvgFree asc

// Memory pressure
Perf
| where ObjectName == "Memory" and CounterName == "Available MBytes"
| where TimeGenerated > ago(1h)
| summarize AvgAvailMB = avg(CounterValue) by Computer
| where AvgAvailMB < 1024
| order by AvgAvailMB asc
```

### Services

```kusto
// Last known state of critical services
Event
| where EventLog == "System" and Source == "Service Control Manager" and EventID == 7036
| parse EventData with * '<Data Name="param1">' ServiceName '</Data><Data Name="param2">' ServiceState '</Data>' *
| summarize arg_max(TimeGenerated, *) by Computer, ServiceName
| where ServiceName in ("DHCP Server", "CcmExec", "SMS_EXECUTIVE", "W32Time", "DNS", "NTDS")
| project Computer, ServiceName, ServiceState, TimeGenerated
| order by ServiceState asc, Computer asc
```

### Security

```kusto
// Privileged group membership changes (last 24h)
SecurityEvent
| where TimeGenerated > ago(24h)
| where EventID in (4728, 4732, 4756, 4735, 4737, 4755)
| project TimeGenerated, Computer, EventID, Activity, Account
| order by TimeGenerated desc

// Failed logon attempts (brute force detection)
SecurityEvent
| where EventID == 4625
| where TimeGenerated > ago(1h)
| summarize FailedAttempts = count() by TargetAccount, Computer, IpAddress
| where FailedAttempts > 10
| order by FailedAttempts desc
```

---

## WAF Alignment Checklist

This section maps each PoC component to the [Azure Well-Architected Framework](https://learn.microsoft.com/en-us/azure/well-architected/) pillars.

### Reliability

| Practice                    | Implementation                                                    |
| --------------------------- | ----------------------------------------------------------------- |
| Multi-signal monitoring     | Heartbeat (availability) + Perf (performance) + Events (services) |
| Alert severity levels       | Sev 0-1 for critical, Sev 2-3 for warnings                        |
| Redundant notifications     | Email + SMS + ITSM for critical alerts                            |
| Maintenance window handling | Alert processing rules to suppress during planned maintenance     |

**Docs:** [Well-Architected: Reliability — Monitoring](https://learn.microsoft.com/en-us/azure/well-architected/reliability/monitoring-alerting-strategy)

### Security

| Practice                        | Implementation                                          |
| ------------------------------- | ------------------------------------------------------- |
| Least-privilege RBAC            | Scoped roles per resource group                         |
| Privileged group audit          | Event ID monitoring for Domain/Enterprise/Schema Admins |
| Security event collection       | Security log forwarding to LAW/Sentinel                 |
| Private connectivity (optional) | Azure Private Link for Monitor/Arc                      |

**Docs:** [Well-Architected: Security — Monitoring](https://learn.microsoft.com/en-us/azure/well-architected/security/monitor-threats)

### Cost Optimization

| Practice                   | Implementation                                     |
| -------------------------- | -------------------------------------------------- |
| Data collection filtering  | DCR XPath filters to collect only needed events    |
| Transformation rules       | Drop noisy logs before ingestion                   |
| Commitment tier evaluation | Basic vs. Analytics logs, commitment tiers for LAW |
| Retention policies         | Set appropriate retention per table                |

**Docs:** [Well-Architected: Cost Optimization](https://learn.microsoft.com/en-us/azure/well-architected/cost-optimization/optimize-monitoring-costs)

### Operational Excellence

| Practice                          | Implementation                               |
| --------------------------------- | -------------------------------------------- |
| Infrastructure as Code            | Export DCRs, alerts, workbooks as ARM/Bicep  |
| Azure Policy for agent deployment | Auto-remediate AMA installation              |
| Common alert schema               | Consistent payload for all integrations      |
| Workbook templates                | Parameterized, version-controlled dashboards |

**Docs:** [Well-Architected: Operational Excellence — Monitoring](https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/observability)

### Performance Efficiency

| Practice           | Implementation                                               |
| ------------------ | ------------------------------------------------------------ |
| Sampling frequency | 60-second perf counter intervals (balanced cost/granularity) |
| KQL optimization   | Use `summarize`, `where` early, avoid `*` projections        |
| Workspace design   | Single workspace for PoC; consider multi-workspace for prod  |

**Docs:** [Well-Architected: Performance Efficiency](https://learn.microsoft.com/en-us/azure/well-architected/performance-efficiency/checklist)

---

## Reference Links

### Core Azure Monitor

| Topic                        | URL                                                                                              |
| ---------------------------- | ------------------------------------------------------------------------------------------------ |
| Azure Monitor overview       | https://learn.microsoft.com/en-us/azure/azure-monitor/overview                                   |
| Azure Monitor Agent overview | https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-overview        |
| Data Collection Rules        | https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-overview   |
| DCR transformations          | https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-transformations |
| Alert types                  | https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-types                        |
| Alert best practices         | https://learn.microsoft.com/en-us/azure/azure-monitor/best-practices-alerts                      |
| Action Groups                | https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/action-groups                       |
| Alert processing rules       | https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-processing-rules             |

### Azure Arc

| Topic                              | URL                                                                                    |
| ---------------------------------- | -------------------------------------------------------------------------------------- |
| Arc-enabled servers overview       | https://learn.microsoft.com/en-us/azure/azure-arc/servers/overview                     |
| Arc server prerequisites           | https://learn.microsoft.com/en-us/azure/azure-arc/servers/prerequisites                |
| Arc network requirements           | https://learn.microsoft.com/en-us/azure/azure-arc/servers/network-requirements         |
| Connect hybrid machines quickstart | https://learn.microsoft.com/en-us/azure/azure-arc/servers/learn/quick-enable-hybrid-vm |

### Data Collection

| Topic                          | URL                                                                                         |
| ------------------------------ | ------------------------------------------------------------------------------------------- |
| Windows event collection       | https://learn.microsoft.com/en-us/azure/azure-monitor/agents/data-collection-windows-events |
| Performance counter collection | https://learn.microsoft.com/en-us/azure/azure-monitor/agents/data-collection-performance    |
| Syslog collection              | https://learn.microsoft.com/en-us/azure/azure-monitor/agents/data-collection-syslog         |

### Visualizations

| Topic              | URL                                                                                |
| ------------------ | ---------------------------------------------------------------------------------- |
| Workbooks overview | https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview |
| VM Insights        | https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vminsights-overview       |

### ITSM & ServiceNow

| Topic                   | URL                                                                                                               |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------- |
| ITSM Connector overview | https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/itsmc-overview                                       |
| ServiceNow connection   | https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/itsmc-connections-servicenow                         |
| Secure webhook          | https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/itsmc-secure-webhook-connections-azure-configuration |
| Common alert schema     | https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-common-schema                                 |

### Network Monitoring

| Topic              | URL                                                                                 |
| ------------------ | ----------------------------------------------------------------------------------- |
| Connection Monitor | https://learn.microsoft.com/en-us/azure/network-watcher/connection-monitor-overview |
| VM Insights Map    | https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vminsights-maps            |

### Microsoft Sentinel (Optional)

| Topic                             | URL                                                                                              |
| --------------------------------- | ------------------------------------------------------------------------------------------------ |
| Sentinel overview                 | https://learn.microsoft.com/en-us/azure/sentinel/overview                                        |
| Windows Security Events connector | https://learn.microsoft.com/en-us/azure/sentinel/data-connectors/windows-security-events-via-ama |
| Custom analytics rules            | https://learn.microsoft.com/en-us/azure/sentinel/detect-threats-custom                           |
| Palo Alto connector               | https://learn.microsoft.com/en-us/azure/sentinel/data-connectors/palo-alto-networks              |
| CEF/Syslog via AMA                | https://learn.microsoft.com/en-us/azure/sentinel/cef-syslog-ama-overview                         |

### SCOM Migration

| Topic                              | URL                                                                                        |
| ---------------------------------- | ------------------------------------------------------------------------------------------ |
| SCOM MI overview                   | https://learn.microsoft.com/en-us/azure/azure-monitor/scom-manage-instance/overview        |
| Migrate from SCOM to Azure Monitor | https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-migration |

### Well-Architected Framework

| Topic                    | URL                                                                                                  |
| ------------------------ | ---------------------------------------------------------------------------------------------------- |
| WAF overview             | https://learn.microsoft.com/en-us/azure/well-architected/                                            |
| Reliability — Monitoring | https://learn.microsoft.com/en-us/azure/well-architected/reliability/monitoring-alerting-strategy    |
| Security — Monitoring    | https://learn.microsoft.com/en-us/azure/well-architected/security/monitor-threats                    |
| Cost Optimization        | https://learn.microsoft.com/en-us/azure/well-architected/cost-optimization/optimize-monitoring-costs |
| Operational Excellence   | https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/observability        |

---

## Appendix: PoC Checklist

Use this checklist to track deployment progress.

### Phase 1 — Foundation

- [ ] Validate Azure permissions (RBAC)
- [ ] Validate firewall/network connectivity
- [ ] Create resource group `rg-contoso-monitor-poc`
- [ ] Create/confirm Log Analytics Workspace
- [ ] Onboard servers to Azure Arc
- [ ] Validate Arc connectivity (`azcmagent show`)
- [ ] Deploy AMA to all PoC servers
- [ ] Create and apply DCR: Performance counters
- [ ] Create and apply DCR: Windows Event Logs
- [ ] Create and apply DCR: Security Events
- [ ] Verify data flowing into Log Analytics (run test KQL queries)

### Phase 2 — Alerts & SCOM Parity

- [ ] Create Action Group (`ag-contoso-poc`)
- [ ] Configure alert: Server unreachable (heartbeat)
- [ ] Configure alert: High CPU
- [ ] Configure alert: Low memory
- [ ] Configure alert: Low disk space
- [ ] Configure alert: Critical service stopped
- [ ] Configure alert: Privileged group membership change
- [ ] Test alert fire → notification flow
- [ ] Review and tune thresholds with Contoso team

### Phase 3 — Integration, Dashboards & Network

- [ ] Configure ServiceNow integration (webhook or Logic App)
- [ ] Test: Alert → ServiceNow incident creation
- [ ] Test: Alert resolution → ServiceNow incident update/close
- [ ] Build Workbook: Server Health Overview
- [ ] Build Workbook: Privileged Group Audit
- [ ] Demo Connection Monitor (Azure ↔ on-prem latency)
- [ ] Demo VM Insights (network map)
- [ ] Discuss Cisco/Palo Alto syslog approach and limitations
- [ ] (Optional) Enable Sentinel and demo analytics rules
- [ ] Document architecture diagram
- [ ] Document configuration details (DCRs, alerts, sources)
- [ ] Identify gaps and recommend next steps
- [ ] Handoff documentation package to Contoso
