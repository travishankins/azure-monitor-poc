#!/bin/bash
# ============================================================================
# Contoso Azure Monitor PoC — DCR Association Script
# ============================================================================
# Associates all three Data Collection Rules with a target server
# (Azure Arc-enabled or Azure VM).
#
# Usage:
#   ./associate-dcrs.sh --server <server-name>
#   ./associate-dcrs.sh --server dc01 --type arc
#   ./associate-dcrs.sh --server azvm01 --type vm
#   ./associate-dcrs.sh --list-all                    # Show all associations
# ============================================================================

set -euo pipefail

# ---- Defaults ----
RESOURCE_GROUP="rg-contoso-monitor-poc"
SERVER_NAME=""
SERVER_TYPE="arc"   # "arc" or "vm"
LIST_ALL=false

# ---- Parse arguments ----
while [[ $# -gt 0 ]]; do
  case $1 in
    --server|-s)         SERVER_NAME="$2"; shift 2 ;;
    --resource-group|-g) RESOURCE_GROUP="$2"; shift 2 ;;
    --type|-t)           SERVER_TYPE="$2"; shift 2 ;;
    --list-all)          LIST_ALL=true; shift ;;
    --help|-h)
      echo "Usage: $0 --server <name> [--type arc|vm] [--resource-group RG]"
      echo "       $0 --list-all [--resource-group RG]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ---- List all associations ----
if [ "$LIST_ALL" = true ]; then
  echo "Current DCR associations in '$RESOURCE_GROUP':"
  echo ""
  for DCR_NAME in dcr-contoso-perf-counters dcr-contoso-windows-events dcr-contoso-security-events; do
    echo "--- $DCR_NAME ---"
    az monitor data-collection rule association list-by-rule \
      --data-collection-rule-name "$DCR_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --output table 2>/dev/null || echo "  (none found)"
    echo ""
  done
  exit 0
fi

# ---- Validate ----
if [ -z "$SERVER_NAME" ]; then
  echo "Error: --server is required."
  echo "Usage: $0 --server <name> [--type arc|vm]"
  exit 1
fi

# ---- Determine resource path ----
SUB_ID=$(az account show --query id -o tsv)

if [ "$SERVER_TYPE" = "arc" ]; then
  RESOURCE_URI="/subscriptions/$SUB_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.HybridCompute/machines/$SERVER_NAME"
elif [ "$SERVER_TYPE" = "vm" ]; then
  RESOURCE_URI="/subscriptions/$SUB_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$SERVER_NAME"
else
  echo "Error: --type must be 'arc' or 'vm'"
  exit 1
fi

echo "============================================"
echo "  Associating DCRs with: $SERVER_NAME"
echo "  Server Type: $SERVER_TYPE"
echo "  Resource Group: $RESOURCE_GROUP"
echo "============================================"

# ---- DCR IDs ----
DCR_PERF_ID="/subscriptions/$SUB_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/dataCollectionRules/dcr-contoso-perf-counters"
DCR_EVENTS_ID="/subscriptions/$SUB_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/dataCollectionRules/dcr-contoso-windows-events"
DCR_SECURITY_ID="/subscriptions/$SUB_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/dataCollectionRules/dcr-contoso-security-events"

# ---- Associate each DCR ----
echo ""
echo "[1/3] Associating Performance Counters DCR..."
az monitor data-collection rule association create \
  --name "assoc-${SERVER_NAME}-perf" \
  --rule-id "$DCR_PERF_ID" \
  --resource "$RESOURCE_URI" \
  --output none
echo "  Done."

echo ""
echo "[2/3] Associating Windows Events DCR..."
az monitor data-collection rule association create \
  --name "assoc-${SERVER_NAME}-events" \
  --rule-id "$DCR_EVENTS_ID" \
  --resource "$RESOURCE_URI" \
  --output none
echo "  Done."

echo ""
echo "[3/3] Associating Security Events DCR..."
az monitor data-collection rule association create \
  --name "assoc-${SERVER_NAME}-security" \
  --rule-id "$DCR_SECURITY_ID" \
  --resource "$RESOURCE_URI" \
  --output none
echo "  Done."

echo ""
echo "============================================"
echo "  All 3 DCRs associated with $SERVER_NAME"
echo ""
echo "  Verify with:"
echo "    az monitor data-collection rule association list \\"
echo "      --resource \"$RESOURCE_URI\" -o table"
echo ""
echo "  Test data ingestion (run in Log Analytics):"
echo "    Heartbeat | where Computer == \"$SERVER_NAME\" | take 5"
echo "============================================"
