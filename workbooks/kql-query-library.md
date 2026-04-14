# Contoso Azure Monitor PoC — KQL Query Library

10 ad-hoc KQL queries for operational investigation, troubleshooting, and reporting. These complement the deployed workbooks by providing queries you run on-demand in the **Log Analytics Workspace > Logs** blade for deeper analysis.

> **Note:** The workbooks already cover real-time dashboards for server health, performance trends, service monitoring, and security events. These queries are for **targeted investigation** scenarios the workbooks don't cover.

---

## 1. Heartbeat Gap Report — Find Servers That Had Outages in the Last 7 Days

Scans the last 7 days for any server that had a gap of 10+ minutes between heartbeats, revealing intermittent connectivity or restart events that a point-in-time dashboard would miss.

```kusto
Heartbeat
| where TimeGenerated > ago(7d)
| order by Computer asc, TimeGenerated asc
| serialize
| extend PrevHeartbeat = prev(TimeGenerated), PrevComputer = prev(Computer)
| where Computer == PrevComputer
| extend GapMinutes = datetime_diff('minute', TimeGenerated, PrevHeartbeat)
| where GapMinutes > 10
| project Computer, GapStart = PrevHeartbeat, GapEnd = TimeGenerated, GapMinutes
| sort by GapMinutes desc
```

**Use Case:** Post-incident review. Identify servers that experienced connectivity blips, reboots, or AMA restarts over the past week — even if they're currently online.

---

## 2. Performance Baseline Report — Percentile Summary Per Server (Last 7 Days)

Generates a baseline report showing the P50, P90, P95, and Max for CPU, memory, and disk across all servers. Use this to establish thresholds and share with the customer as a sizing reference.

```kusto
let cpu = Perf
| where TimeGenerated > ago(7d)
| where ObjectName == "Processor" and CounterName == "% Processor Time" and InstanceName == "_Total"
| summarize CPU_P50 = round(percentile(CounterValue, 50), 1), CPU_P90 = round(percentile(CounterValue, 90), 1), CPU_P95 = round(percentile(CounterValue, 95), 1), CPU_Max = round(max(CounterValue), 1) by Computer;
let mem = Perf
| where TimeGenerated > ago(7d)
| where ObjectName == "Memory" and CounterName == "Available MBytes"
| summarize Mem_P50 = round(percentile(CounterValue, 50), 0), Mem_P5 = round(percentile(CounterValue, 5), 0), Mem_Min = round(min(CounterValue), 0) by Computer;
let disk = Perf
| where TimeGenerated > ago(7d)
| where ObjectName == "LogicalDisk" and CounterName == "% Free Space"
| where InstanceName !in ("_Total", "HarddiskVolume1")
| summarize Disk_MinFree = round(min(CounterValue), 1) by Computer;
cpu
| join kind=leftouter mem on Computer
| join kind=leftouter disk on Computer
| project Computer, CPU_P50, CPU_P90, CPU_P95, CPU_Max, Mem_P50, Mem_P5, Mem_Min, Disk_MinFree
| sort by CPU_P95 desc
```

**Use Case:** Capacity planning handoff. Share this with the customer to justify alert thresholds and right-size VMs. Export to Excel via the **Export** button.

---

## 3. Service Account Logon Audit — Who Logged In With Service Accounts

Finds interactive and network logons by known service accounts. Useful for detecting misuse of service credentials or mapping which servers a service account is active on.

```kusto
SecurityEvent
| where EventID == 4624
| where LogonType in (2, 3, 10)
| where TargetUserName endswith "$" or TargetUserName has_any ("svc", "service", "admin")
| summarize
    LogonCount = count(),
    Servers = make_set(Computer, 10),
    SourceIPs = make_set(IpAddress, 10),
    LastLogon = max(TimeGenerated)
    by TargetUserName, TargetDomainName, LogonType
| extend LogonTypeDesc = case(
    LogonType == 2, "Interactive",
    LogonType == 3, "Network",
    LogonType == 10, "RemoteDesktop",
    tostring(LogonType))
| sort by LogonCount desc
```

**Use Case:** Security hygiene. In a school board environment, service accounts logging in interactively is a red flag. Customize the `has_any` filter with Contoso's actual service account naming convention.

---

## 4. DHCP Server Event Summary — Health Check for DHCP Infrastructure

Aggregates DHCP-specific events to quickly assess DHCP server health, scope exhaustion, and configuration changes.

```kusto
Event
| where Source has "DHCP" or EventLog has "DHCP"
| summarize EventCount = count() by Computer, Source, EventID, EventLevelName
| sort by EventLevelName asc, EventCount desc
```

**Use Case:** Contoso runs DHCP on Windows Server. This query surfaces DHCP-specific errors (scope full, authorization issues, failover problems) that would otherwise be buried in the System log. Filter further by adding `| where EventLevelName in ("Error", "Warning")`.

---

## 5. Correlate Service Crash With Performance — Was the Server Under Stress?

When a critical service crashes (Event ID 7034), this query checks whether the server was experiencing high CPU or low memory in the 30 minutes before the crash.

```kusto
let crashes = Event
| where EventLog == "System" and Source == "Service Control Manager" and EventID == 7034
| project CrashTime = TimeGenerated, Computer, RenderedDescription;
let perfWindow = Perf
| where ObjectName in ("Processor", "Memory")
| where CounterName in ("% Processor Time", "Available MBytes")
| where InstanceName == "_Total" or ObjectName == "Memory"
| project TimeGenerated, Computer, CounterName, CounterValue;
crashes
| join kind=inner (
    perfWindow
) on Computer
| where TimeGenerated between (datetime_add('minute', -30, CrashTime) .. CrashTime)
| summarize
    AvgCPU = round(avgif(CounterValue, CounterName == "% Processor Time"), 1),
    MinMemMB = round(minif(CounterValue, CounterName == "Available MBytes"), 0)
    by Computer, CrashTime, RenderedDescription
| project Computer, CrashTime, RenderedDescription, ['CPU 30min Before'] = AvgCPU, ['Min Memory MB 30min Before'] = MinMemMB
| sort by CrashTime desc
```

**Use Case:** Root cause analysis. When a service crashes, the first question is "was the box out of resources?" This answers it instantly.

---

## 6. Stale or Missing DCR Data — Detect Collection Gaps by Table

Checks when each key table last received data from each server, revealing broken DCR associations or AMA issues before they cause alert blind spots.

```kusto
let tables = union
    (Heartbeat | project Computer, Table = "Heartbeat", TimeGenerated),
    (Perf | project Computer, Table = "Perf", TimeGenerated),
    (Event | project Computer, Table = "Event", TimeGenerated);
tables
| summarize LastRecord = max(TimeGenerated) by Computer, Table
| extend MinutesSinceData = datetime_diff('minute', now(), LastRecord)
| where MinutesSinceData > 15
| project Computer, Table, LastRecord, MinutesSinceData
| sort by MinutesSinceData desc
```

**Use Case:** Operational hygiene. If a server is sending Heartbeat but no Perf data, the performance DCR association is broken. Run this daily during the PoC to catch collection issues early.

---

## 7. Repeated Account Lockout + Failed Logon Correlation — Incident Timeline

Builds a combined timeline of failed logon attempts (4625) and lockouts (4740) for a specific user. Replace the username to investigate any locked-out account.

```kusto
let targetUser = "jsmith";  // <-- Replace with the account to investigate
SecurityEvent
| where EventID in (4625, 4740)
| where TargetUserName =~ targetUser
| project
    TimeGenerated,
    Computer,
    EventID,
    EventType = case(EventID == 4625, "Failed Logon", EventID == 4740, "Account Locked", tostring(EventID)),
    SourceIP = IpAddress,
    LogonType,
    TargetUserName
| sort by TimeGenerated asc
```

**Use Case:** Helpdesk escalation. When a user reports repeated lockouts, paste this query and change the `targetUser` variable. It shows the exact timeline of failed logons leading to the lockout, including source IPs and which DC processed it.

---

## 8. Windows Update / Patch Reboot Detection — Recent Server Restarts

Identifies servers that rebooted recently by looking for Event ID 6005 (Event Log service started — indicates OS boot) and 6006 (Event Log service stopped — indicates clean shutdown).

```kusto
Event
| where EventLog == "System"
| where EventID in (6005, 6006, 6008, 1074)
| extend EventDesc = case(
    EventID == 6005, "System Boot (Event Log Started)",
    EventID == 6006, "Clean Shutdown (Event Log Stopped)",
    EventID == 6008, "Unexpected Shutdown",
    EventID == 1074, "User-Initiated Restart/Shutdown",
    "Other")
| project TimeGenerated, Computer, EventID, EventDesc, RenderedDescription
| sort by TimeGenerated desc
```

**Use Case:** Post-patch validation. After a patch cycle, run this to confirm which servers actually rebooted. Event ID 6008 (unexpected shutdown) flags servers that crashed rather than shutting down cleanly.

---

## 9. Top Noisy Event Sources — Identify Log Noise for DCR Tuning

Finds the most verbose event sources and IDs to help tune DCR filters and reduce Log Analytics ingestion costs.

```kusto
Event
| where TimeGenerated > ago(24h)
| summarize EventCount = count() by EventLog, Source, EventID, EventLevelName
| sort by EventCount desc
| take 50
| extend RecommendedAction = case(
    EventCount > 10000 and EventLevelName == "Information", "🔴 Consider filtering in DCR",
    EventCount > 5000 and EventLevelName == "Information", "🟡 Review — may be noise",
    EventCount > 1000 and EventLevelName in ("Warning", "Error"), "🟢 Keep — actionable events",
    "🟢 OK")
```

**Use Case:** Cost optimization. During the PoC, run this to identify noisy Information-level events that inflate ingestion costs. Use the results to add XPath exclusions to the Windows Event DCR before production rollout.

---

## 10. Change Tracking Summary — Recent Software, Service, and Registry Changes

If the Change Tracking DCR is active, this surfaces the most recent changes detected across the environment — software installs, service modifications, and registry edits.

```kusto
ConfigurationChange
| where TimeGenerated > ago(7d)
| summarize ChangeCount = count() by Computer, ConfigChangeType, ChangeCategory
| sort by ChangeCount desc
```

To see the actual change details:

```kusto
ConfigurationChange
| where TimeGenerated > ago(7d)
| project TimeGenerated, Computer, ConfigChangeType, ChangeCategory,
    SoftwareType, SoftwareName, CurrentVersion = Current, PreviousVersion = Previous
| sort by TimeGenerated desc
| take 200
```

**Use Case:** Drift detection and audit trail. When a server starts misbehaving, check what changed recently. Also useful for compliance — proving that only authorized changes were made during a maintenance window.

---

## How to Use These Queries

1. **Azure Portal** → **Monitor** → **Logs** (or navigate to your Log Analytics Workspace → **Logs**)
2. Select the appropriate time range in the time picker
3. Paste the query and click **Run**
4. To save: Click **Save** → **Save as query** → choose a category (e.g., "Contoso PoC")
5. To create an alert from any query: Click **+ New alert rule** directly from the query results
6. To export results: Click **Export** → CSV or Power BI

## Tips

- All queries use tables populated by the Contoso PoC DCRs (Perf, Event, SecurityEvent, Heartbeat, Usage, ConfigurationChange)
- Query 7 requires editing the `targetUser` variable before running
- Query 10 requires the Change Tracking DCR (`dcr-change-tracking`) to be active
- Use `| take 100` at the end of any query to limit results during initial exploration
- For queries referencing `SecurityEvent`, ensure the Security Events DCR is associated with domain controllers
