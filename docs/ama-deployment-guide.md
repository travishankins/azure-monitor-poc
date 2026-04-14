# AMA Deployment Guide — Azure Monitor Agent

> How to deploy the Azure Monitor Agent (AMA) to on-premises servers (via Arc) and Azure VMs. AMA is required before any DCR can collect data.

---

## Prerequisites

| Requirement                                          | On-Premises Servers           | Azure VMs           |
| ---------------------------------------------------- | ----------------------------- | ------------------- |
| Azure Arc agent installed                            | ✅ Required                   | ❌ Not needed       |
| Arc agent connected (status: Connected)              | ✅ Required                   | N/A                 |
| Firewall: `*.handler.control.monitor.azure.com:443`  | ✅ Required                   | ✅ Required         |
| Firewall: `*.ods.opinsights.azure.com:443`           | ✅ Required                   | ✅ Required         |
| RBAC: Azure Connected Machine Resource Administrator | ✅ Required                   | ❌ Not needed       |
| RBAC: Virtual Machine Contributor (or equivalent)    | ❌ Not needed                 | ✅ Required         |
| Local admin on the server                            | ✅ Required (for Arc install) | ❌ Managed by Azure |

---

## Part 1 — On-Premises Servers (Arc + AMA)

### Step 1: Install the Azure Arc Agent

> Skip this if the server already shows as "Connected" in **Azure Arc → Servers**.

#### Single Server (Interactive)

1. **Portal → Azure Arc → Servers → + Add → Add a single server**
2. Fill in: Subscription, Resource Group, Region (`Canada Central`), OS (Windows)
3. **Download** the generated script
4. **RDP into the server** and run the script in an elevated PowerShell:

```powershell
# The portal generates this — download and run it
& "$env:TEMP\install_windows_azcmagent.ps1"

# The script will open a browser for Azure authentication
# After auth, the agent connects automatically
```

5. Verify:

```powershell
azcmagent show
# Status should be: Connected
# Verify the resource group and subscription are correct
```

#### Multiple Servers (Service Principal — No Browser Needed)

1. **Portal → Azure Arc → Servers → + Add → Add multiple servers**
2. Create or select a **Service Principal** (the portal guides you)
3. Download the script — it includes the service principal credentials
4. Deploy the script to servers via:
   - **Group Policy** (startup script)
   - **SCCM** (package/task sequence)
   - **Manual copy** to each server and run

```powershell
# Example — service principal based (no browser popup)
& "$env:TEMP\install_windows_azcmagent.ps1"

azcmagent connect `
  --service-principal-id "<app-id>" `
  --service-principal-secret "<secret>" `
  --resource-group "rg-contoso-monitor-poc" `
  --tenant-id "<tenant-id>" `
  --location "canadacentral" `
  --subscription-id "<subscription-id>"
```

5. Verify in Portal: **Azure Arc → Servers** — all servers show **Connected**

### Step 2: Deploy AMA to Arc Servers

Once Arc is connected, deploy AMA via one of these methods:

#### Method A: Portal — Per Server

1. **Azure Arc → Servers** → click the server
2. **Settings → Extensions** → **+ Add**
3. Search for **Azure Monitor Windows Agent** → **Next**
4. No configuration needed → **Review + create**
5. Wait ~2-3 minutes for "Provisioning succeeded"

#### Method B: Portal — Via DCR Creation (Automatic)

When you create a DCR and add servers in the **Resources** tab, the Portal **automatically deploys AMA** to any server that doesn't have it. This is the recommended approach for initial setup — you get AMA + DCR in one step.

#### Method C: Azure CLI — Single Server

```bash
az connectedmachine extension create \
  --machine-name "dc01" \
  --resource-group "rg-contoso-monitor-poc" \
  --name "AzureMonitorWindowsAgent" \
  --type "AzureMonitorWindowsAgent" \
  --publisher "Microsoft.Azure.Monitor" \
  --location "canadacentral"
```

#### Method D: Azure CLI — Multiple Servers (Loop)

```bash
RG="rg-contoso-monitor-poc"
LOCATION="canadacentral"

# List of Arc server names
SERVERS=("dc01" "dhcp01" "sccm01" "winsrv01")

for SERVER in "${SERVERS[@]}"; do
  echo "Deploying AMA to $SERVER..."
  az connectedmachine extension create \
    --machine-name "$SERVER" \
    --resource-group "$RG" \
    --name "AzureMonitorWindowsAgent" \
    --type "AzureMonitorWindowsAgent" \
    --publisher "Microsoft.Azure.Monitor" \
    --location "$LOCATION" \
    --no-wait
done

echo "Deployments initiated. Check status with:"
echo "az connectedmachine extension list --machine-name <name> -g $RG -o table"
```

#### Method D2: Azure CLI — All Arc Servers in a Resource Group (Dynamic)

Pulls every Arc server from the RG automatically — no hardcoded list needed.

```bash
RG="rg-Arc-il-01"
LOCATION="canadacentral"

# Pull all Arc server names from the resource group
SERVERS=$(az connectedmachine list \
  --resource-group "$RG" \
  --query "[].name" \
  -o tsv)

# Count them
TOTAL=$(echo "$SERVERS" | wc -l | tr -d ' ')
echo "Found $TOTAL Arc servers in $RG"
echo ""

# Deploy AMA to each
COUNT=0
for SERVER in $SERVERS; do
  COUNT=$((COUNT + 1))
  echo "[$COUNT/$TOTAL] Deploying AMA to $SERVER..."
  az connectedmachine extension create \
    --machine-name "$SERVER" \
    --resource-group "$RG" \
    --name "AzureMonitorWindowsAgent" \
    --type "AzureMonitorWindowsAgent" \
    --publisher "Microsoft.Azure.Monitor" \
    --location "$LOCATION" \
    --no-wait 2>/dev/null
done

echo ""
echo "All $TOTAL deployments initiated."
echo ""
echo "Check progress:"
echo "  az connectedmachine extension list --machine-name <name> -g $RG -o table"
echo ""
echo "Bulk status check (wait ~5 min, then run):"
echo "  az graph query -q \"Resources | where type == 'microsoft.hybridcompute/machines/extensions' | where name == 'AzureMonitorWindowsAgent' | summarize count() by tostring(properties.provisioningState)\" --first 1000"
```

#### Method D3: Azure CLI — All Arc Servers, Skip Already Installed

For re-runs — only targets servers that don't already have AMA:

```bash
RG="rg-Arc-il-01"
LOCATION="canadacentral"

# Get all Arc servers
ALL_SERVERS=$(az connectedmachine list \
  --resource-group "$RG" \
  --query "[].name" \
  -o tsv)

# Filter out servers that already have AMA
NEEDS_AMA=()
for SERVER in $ALL_SERVERS; do
  HAS_AMA=$(az connectedmachine extension list \
    --machine-name "$SERVER" \
    --resource-group "$RG" \
    --query "[?name=='AzureMonitorWindowsAgent'].provisioningState" \
    -o tsv 2>/dev/null)
  if [ -z "$HAS_AMA" ]; then
    NEEDS_AMA+=("$SERVER")
  fi
done

echo "${#NEEDS_AMA[@]} servers need AMA (out of $(echo "$ALL_SERVERS" | wc -l | tr -d ' ') total)"
echo ""

# Deploy to those that need it
COUNT=0
for SERVER in "${NEEDS_AMA[@]}"; do
  COUNT=$((COUNT + 1))
  echo "[$COUNT/${#NEEDS_AMA[@]}] Deploying AMA to $SERVER..."
  az connectedmachine extension create \
    --machine-name "$SERVER" \
    --resource-group "$RG" \
    --name "AzureMonitorWindowsAgent" \
    --type "AzureMonitorWindowsAgent" \
    --publisher "Microsoft.Azure.Monitor" \
    --location "$LOCATION" \
    --no-wait 2>/dev/null
done
```

> **Note:** Method D3 takes longer to start because it checks each server first. For 101 servers, the check phase takes ~3-5 minutes. Use Method D2 if you're doing a fresh deployment — `--no-wait` + `az connectedmachine extension create` is idempotent and will skip servers that already have AMA.

#### Method E: Azure Policy — Automatic (Recommended for Production)

1. **Policy → Assignments → + Assign policy**
2. Search for: **"Configure Windows Arc-enabled machines to run Azure Monitor Agent"**
   - Policy definition ID: `94f686d6-9a24-4e19-91f1-de9f6c23d2e5`
3. Scope: PoC resource group
4. **Remediation** tab:
   - ☑ Create a remediation task
   - Managed identity location: `Canada Central`
5. **Review + create**

This auto-deploys AMA to every Arc server in the scope — including future ones.

```bash
# CLI equivalent
az policy assignment create \
  --name "deploy-ama-arc-windows" \
  --display-name "Deploy AMA to Arc Windows Servers" \
  --policy "94f686d6-9a24-4e19-91f1-de9f6c23d2e5" \
  --scope "/subscriptions/<sub-id>/resourceGroups/rg-contoso-monitor-poc" \
  --mi-system-assigned \
  --location "canadacentral"

# Trigger remediation for existing servers
az policy remediation create \
  --name "remediate-ama-arc" \
  --policy-assignment "deploy-ama-arc-windows" \
  --resource-group "rg-contoso-monitor-poc"
```

### Verify AMA on Arc Servers

```powershell
# On the server itself
Get-Service -Name "AzureMonitorAgent"
# Status should be: Running

# Check version
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Azure Monitor Agent" | Select-Object Version
```

```bash
# From Azure CLI
az connectedmachine extension list \
  --machine-name "dc01" \
  --resource-group "rg-contoso-monitor-poc" \
  -o table

# Expected output:
# Name                        Type                          ProvisioningState
# --------------------------  ----------------------------  -------------------
# AzureMonitorWindowsAgent    AzureMonitorWindowsAgent      Succeeded
```

---

## Part 2 — Azure VMs

### Method A: Portal — Per VM

1. **Virtual Machines** → click the VM
2. **Settings → Extensions + applications** → **+ Add**
3. Search for **Azure Monitor Windows Agent** → **Next** → **Create**

### Method B: Portal — Via DCR Creation (Automatic)

Same as Arc — when creating a DCR and adding Azure VMs in the **Resources** tab, AMA is deployed automatically.

### Method C: Azure CLI — Single VM

```bash
az vm extension set \
  --vm-name "azvm01" \
  --resource-group "rg-contoso-monitor-poc" \
  --name "AzureMonitorWindowsAgent" \
  --publisher "Microsoft.Azure.Monitor"
```

### Method D: Azure CLI — Multiple VMs (Loop)

```bash
RG="rg-contoso-monitor-poc"

# List of Azure VM names
VMS=("azvm01" "azvm02")

for VM in "${VMS[@]}"; do
  echo "Deploying AMA to $VM..."
  az vm extension set \
    --vm-name "$VM" \
    --resource-group "$RG" \
    --name "AzureMonitorWindowsAgent" \
    --publisher "Microsoft.Azure.Monitor" \
    --no-wait
done
```

### Method E: Azure Policy — Automatic (Recommended for Production)

1. **Policy → Assignments → + Assign policy**
2. Search for: **"Configure Windows virtual machines to run Azure Monitor Agent using system-assigned managed identity"**
3. Scope: PoC resource group
4. ☑ Create remediation task

```bash
az policy assignment create \
  --name "deploy-ama-vm-windows" \
  --display-name "Deploy AMA to Windows VMs" \
  --policy "ca817e41-e85a-4783-bc7f-dc532d36235e" \
  --scope "/subscriptions/<sub-id>/resourceGroups/rg-contoso-monitor-poc" \
  --mi-system-assigned \
  --location "canadacentral"
```

### Verify AMA on Azure VMs

```bash
az vm extension list \
  --vm-name "azvm01" \
  --resource-group "rg-contoso-monitor-poc" \
  -o table
```

---

## Part 3 — Bulk Verification (All Servers)

### KQL: Which Servers Have AMA Running

Run this in **Log Analytics → Logs** after ~5 minutes:

```kusto
Heartbeat
| where TimeGenerated > ago(15m)
| summarize LastHeartbeat = max(TimeGenerated) by Computer, Category, OSType
| order by Computer asc
```

If a server appears in the `Heartbeat` table, AMA is running and connected.

### KQL: Which Servers Are Missing AMA

```kusto
// Compare Arc servers vs heartbeats
let ArcServers = AzureActivity
| where ResourceProviderValue == "MICROSOFT.HYBRIDCOMPUTE"
| distinct Resource;
let MonitoredServers = Heartbeat
| where TimeGenerated > ago(1h)
| distinct Computer;
ArcServers
| where Resource !in (MonitoredServers)
```

### Portal: Quick Visual Check

1. **Monitor → Virtual Machines → Overview**
2. Shows **Monitored** vs **Not Monitored** counts
3. Click **Not Monitored** to see which servers still need AMA

---

## Recommended Approach

| Scenario                          | Best Method                                  | Why                                                                  |
| --------------------------------- | -------------------------------------------- | -------------------------------------------------------------------- |
| PoC (5-10 servers)                | **DCR creation auto-deploys AMA** (Method B) | Zero extra steps — AMA deploys when you add servers to the first DCR |
| Existing Arc servers, bulk deploy | **Azure CLI loop** (Method D)                | Fast, scriptable, visible progress                                   |
| Production rollout                | **Azure Policy** (Method E)                  | Automatic for all current + future servers                           |
| Single server troubleshooting     | **Portal per-server** (Method A)             | Click and verify on the spot                                         |

**Quickest path:** Just create the first DCR (Performance Counters) and add all PoC servers in the Resources tab. AMA will auto-deploy to every server that doesn't have it. No separate AMA deployment step needed.

---

## Troubleshooting

### AMA Extension Shows "Failed"

```powershell
# Check the extension log on the server
Get-Content "C:\ProgramData\GuestConfig\ext_mgr_logs\gc_ext.log" -Tail 50

# Check AMA-specific logs
Get-Content "C:\WindowsAzure\Logs\Plugins\Microsoft.Azure.Monitor.AzureMonitorWindowsAgent\*\CommandExecution.log" -Tail 20
```

### AMA Running But No Data in Log Analytics

1. Verify a DCR is associated with the server:
   - **Monitor → Data Collection Rules** → click DCR → **Resources** — is the server listed?
2. Verify firewall connectivity from the server:
   ```powershell
   Test-NetConnection -ComputerName "global.handler.control.monitor.azure.com" -Port 443
   Test-NetConnection -ComputerName "<workspace-id>.ods.opinsights.azure.com" -Port 443
   ```
3. Restart the AMA service:
   ```powershell
   Restart-Service -Name "AzureMonitorAgent"
   ```

### Arc Agent Not Connected

```powershell
# Check Arc agent status
azcmagent show

# If disconnected, reconnect
azcmagent connect `
  --resource-group "rg-contoso-monitor-poc" `
  --tenant-id "<tenant-id>" `
  --location "canadacentral" `
  --subscription-id "<subscription-id>"
```
