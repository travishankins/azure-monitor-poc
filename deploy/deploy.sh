#!/bin/bash
# ============================================================================
# Contoso Azure Monitor PoC — Deployment Script
# ============================================================================
# Deploys the Action Group and Alert Rules. DCRs are created separately
# via the Azure Portal.
#
# Prerequisites:
#   - Azure CLI installed and logged in (az login)
#   - Correct subscription selected (az account set -s <sub-id>)
#
# Usage:
#   ./deploy.sh                           # Deploy with defaults
#   ./deploy.sh --what-if                 # Preview changes only
#   ./deploy.sh --resource-group myRG     # Override resource group
# ============================================================================

set -euo pipefail

# ---- Defaults (override with flags) ----
RESOURCE_GROUP="rg-contoso-monitor-poc"
LOCATION="canadacentral"
DEPLOYMENT_NAME="contoso-monitor-poc-$(date +%Y%m%d-%H%M%S)"
TEMPLATE_FILE="$(dirname "$0")/azuredeploy.json"
PARAMETERS_FILE="$(dirname "$0")/azuredeploy.parameters.json"
WHAT_IF=false

# ---- Parse arguments ----
while [[ $# -gt 0 ]]; do
  case $1 in
    --resource-group|-g) RESOURCE_GROUP="$2"; shift 2 ;;
    --location|-l)       LOCATION="$2"; shift 2 ;;
    --what-if)           WHAT_IF=true; shift ;;
    --help|-h)
      echo "Usage: $0 [--resource-group RG] [--location LOCATION] [--what-if]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "============================================"
echo "  Contoso Azure Monitor PoC — Alert Deployment"
echo "============================================"
echo "  Resource Group : $RESOURCE_GROUP"
echo "  Location       : $LOCATION"
echo "  Template       : $TEMPLATE_FILE"
echo "  Parameters     : $PARAMETERS_FILE"
echo "  What-If        : $WHAT_IF"
echo ""
echo "  NOTE: This deploys the Action Group and"
echo "  Alert Rules only. DCRs are created"
echo "  separately via the Azure Portal."
echo "============================================"
echo ""

# ---- Verify parameters file has been updated ----
if grep -q "UPDATE-ME" "$PARAMETERS_FILE" 2>/dev/null; then
  echo "ERROR: azuredeploy.parameters.json still contains UPDATE-ME placeholders."
  echo "Please update workspaceName, workspaceResourceGroup, and email addresses first."
  exit 1
fi

# ---- Ensure resource group exists ----
echo "[1/3] Ensuring resource group '$RESOURCE_GROUP' exists..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --tags project=contoso-monitor-poc createdBy=deploy-script \
  --output none

# ---- Deploy (or What-If) ----
if [ "$WHAT_IF" = true ]; then
  echo "[2/3] Running What-If analysis..."
  az deployment group what-if \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@$PARAMETERS_FILE" \
    --result-format FullResourcePayloads
  echo ""
  echo "What-If complete. No changes were made."
else
  echo "[2/3] Deploying Action Group + Alert Rules..."
  az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DEPLOYMENT_NAME" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@$PARAMETERS_FILE" \
    --output table

  echo ""
  echo "[3/3] Deployment outputs:"
  az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DEPLOYMENT_NAME" \
    --query "properties.outputs" \
    --output table
fi

echo ""
echo "============================================"
echo "  Deployment complete!"
echo ""
echo "  Deployed: 1 Action Group + 9 Alert Rules"
echo ""
echo "  Verify in Portal:"
echo "    Monitor → Alerts → Alert rules"
echo "============================================"
