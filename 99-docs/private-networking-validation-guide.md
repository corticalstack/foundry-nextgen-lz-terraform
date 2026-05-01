# Private Networking Deployment — Validation Guide

This guide walks through verifying that the private networking deployment (GH-2) is fully operational. It covers infrastructure checks that can be run from any machine, plus in-network validation that requires connecting to the jump VM via Azure Bastion.

---

## Table of Contents

1. [Reference: Deployed Resources](#1-reference-deployed-resources)
2. [Pre-flight: Infrastructure State Checks](#2-pre-flight-infrastructure-state-checks)
   - [2.1 Terraform state is clean](#21-terraform-state-is-clean)
   - [2.2 Private endpoints are Approved](#22-private-endpoints-are-approved)
   - [2.3 Capability hosts are Succeeded](#23-capability-hosts-are-succeeded)
   - [2.4 DNS zones exist and have A-records](#24-dns-zones-exist-and-have-a-records)
3. [Network Isolation Checks (from your laptop)](#3-network-isolation-checks-from-your-laptop)
   - [3.1 AI Services accounts are unreachable from public internet](#31-ai-services-accounts-are-unreachable-from-public-internet)
   - [3.2 Dependent resources (CosmosDB, Storage, Search) block public access](#32-dependent-resources-cosmosdb-storage-search-block-public-access)
4. [Connect to the Jump VM via Azure Bastion](#4-connect-to-the-jump-vm-via-azure-bastion)
5. [In-Network Validation (from the jump VM)](#5-in-network-validation-from-the-jump-vm)
   - [5.1 DNS resolves to private IPs](#51-dns-resolves-to-private-ips)
   - [5.2 Core model responds via private endpoint](#52-core-model-responds-via-private-endpoint)
   - [5.3 AI Foundry portal loads](#53-ai-foundry-portal-loads)
   - [5.4 Agent Playground: create and run an agent](#54-agent-playground-create-and-run-an-agent)
   - [5.5 APIM gateway responds](#55-apim-gateway-responds)
6. [Known Issues](#6-known-issues)
   - [6.1 Agents page blocked in Microsoft Edge](#61-agents-page-blocked-in-microsoft-edge)
   - [6.2 Agents page returns 403 Forbidden on first load](#62-agents-page-returns-403-forbidden-on-first-load)
   - [6.5 Agent invocation returns generic error; logs show 403 on Agents_Wildcard_Get](#65-agent-invocation-returns-generic-error-diagnostic-logs-show-403-on-agents_wildcard_get)
7. [Jump VM Hygiene](#7-jump-vm-hygiene)
8. [Set Up VS Code Remote Tunnel (for Notebook Development)](#8-set-up-vs-code-remote-tunnel-for-notebook-development)
   - [8.1 Install developer tools on the jump VM](#81-install-developer-tools-on-the-jump-vm)
   - [8.2 Clone the repo and install dependencies](#82-clone-the-repo-and-install-dependencies)
   - [8.3 Install and start the tunnel service](#83-install-and-start-the-tunnel-service)
   - [8.4 Install VS Code extensions on the remote](#84-install-vs-code-extensions-on-the-remote)
   - [8.5 Connect from your local VS Code](#85-connect-from-your-local-vs-code)

---

## 1. Reference: Deployed Resources

| Resource | Name | Resource Group |
|----------|------|----------------|
| Core AI Services account | `aif-core-contoso-e84b7b` | `rg-contoso-core-e84b7b` |
| Research AI Services account | `aif-research-contoso-e84b7b` | `rg-contoso-core-e84b7b` |
| Spoke AI Services account | `aif-spk-contoso-e84b7b` | `rg-contoso-multi-e84b7b` |
| APIM gateway | `apim-contoso-e84b7b` | `rg-contoso-core-e84b7b` |
| Jump VM | `vm-jump` | `rg-contoso-core-e84b7b` |
| Azure Bastion | `bas-contoso` | `rg-contoso-core-e84b7b` |
| CosmosDB (agents) | `cosmos-contoso-e84b7b` | `rg-contoso-multi-e84b7b` |
| Storage (agents) | `stcontosoe84b7b` | `rg-contoso-multi-e84b7b` |
| AI Search (agents) | `srch-contoso-e84b7b` | `rg-contoso-multi-e84b7b` |
| VNet | `vnet-contoso` (`10.0.0.0/16`) | `rg-contoso-core-e84b7b` |

**Team project endpoints:**

| Team | Project Endpoint |
|------|-----------------|
| beta | `https://aif-spk-contoso-e84b7b.services.ai.azure.com/api/projects/project-beta-e84b7b` |
| delta | `https://aif-spk-contoso-e84b7b.services.ai.azure.com/api/projects/project-delta-e84b7b` |
| gamma | `https://aif-spk-contoso-e84b7b.services.ai.azure.com/api/projects/project-gamma-e84b7b` |

---

## 2. Pre-flight: Infrastructure State Checks

These checks run from your laptop using the Azure CLI and Terraform. They confirm the infrastructure was provisioned correctly before you connect to the jump VM.

### 2.1 Terraform state is clean

```bash
cd terraform/environments/dev
terraform plan
```

**Expected:** `No changes. Your infrastructure matches the configuration.`

Any diff here indicates configuration drift and should be resolved before proceeding.

---

### 2.2 Private endpoints are Approved

All 7 private endpoints must be in `Succeeded` provisioning state with an `Approved` connection.

```bash
# Hub resource group (3 endpoints: hub account, research account, APIM)
az network private-endpoint list \
  --resource-group rg-contoso-core-e84b7b \
  --query "[].{name:name,state:provisioningState,connection:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" \
  --output table

# Spoke resource group (4 endpoints: spoke account, CosmosDB, Storage, AI Search)
az network private-endpoint list \
  --resource-group rg-contoso-multi-e84b7b \
  --query "[].{name:name,state:provisioningState,connection:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" \
  --output table
```

**Expected:** All rows show `Succeeded` / `Approved`.

---

### 2.3 Capability hosts are Succeeded

All three Agent Service capability hosts must be in `Succeeded` state.

```bash
for TEAM in beta delta gamma; do
  echo -n "caphostproj-${TEAM}: "
  az rest \
    --method GET \
    --url "https://management.azure.com/subscriptions/025aba94-0c4a-443d-8826-466477e2850f/resourceGroups/rg-contoso-multi-e84b7b/providers/Microsoft.CognitiveServices/accounts/aif-spk-contoso-e84b7b/projects/project-${TEAM}-e84b7b/capabilityHosts/caphostproj-${TEAM}?api-version=2025-04-01-preview" \
    --query "properties.provisioningState" \
    --output tsv
done
```

**Expected:** All three print `Succeeded`.

---

### 2.4 DNS zones exist and have A-records

Eight private DNS zones should be present in `rg-contoso-core-e84b7b`.

```bash
az network private-dns zone list \
  --resource-group rg-contoso-core-e84b7b \
  --query "[].name" \
  --output tsv
```

**Expected zones (8):**
```
privatelink.azure-api.net
privatelink.blob.core.windows.net
privatelink.cognitiveservices.azure.com
privatelink.documents.azure.com
privatelink.file.core.windows.net
privatelink.openai.azure.com
privatelink.search.windows.net
privatelink.services.ai.azure.com
```

Spot-check A-records for the spoke account zone:

```bash
az network private-dns record-set a list \
  --resource-group rg-contoso-core-e84b7b \
  --zone-name privatelink.cognitiveservices.azure.com \
  --query "[].{name:name,ip:aRecords[0].ipv4Address}" \
  --output table
```

**Expected:** At least one A-record per PE target, each resolving to a `10.0.0.x` address (the `snet-pe` range).

---

## 3. Network Isolation Checks (from your laptop)

These checks confirm that the resources are genuinely inaccessible from the public internet.

### 3.1 AI Services accounts require auth from public internet

> **Important — AI Foundry account behaviour:** Azure AI Services accounts with `allowProjectManagement = true` (the AI Foundry type used here) do **not** return `403` for public requests even when `publicNetworkAccess = "Disabled"` is set. Requests from the public internet reach Azure's edge network and are evaluated against authentication before network access controls. This is a known behavioural difference from regular Cognitive Services/OpenAI accounts. The `publicNetworkAccess = "Disabled"` and `networkAcls.defaultAction = "Deny"` settings are still applied and confirmed in the Azure control plane (verify with `az cognitiveservices account show`) but do not produce `403` at the data plane layer for this account type.

The correct isolation test from your laptop is to confirm that the service requires authentication (returns `401`) and does **not** serve data unauthenticated (returns `200`):

```bash
# Spoke account — should return 401 (auth required), not 200
curl -s -o /dev/null -w "%{http_code}" \
  "https://aif-spk-contoso-e84b7b.cognitiveservices.azure.com/openai/models?api-version=2024-02-01"

# Hub account — should return 401 (auth required), not 200
curl -s -o /dev/null -w "%{http_code}" \
  "https://aif-core-contoso-e84b7b.cognitiveservices.azure.com/openai/models?api-version=2024-02-01"
```

**Expected:** `401` for both. A `200` response would mean the service is returning data without authentication — investigate immediately.

**The primary isolation test is section 5.1** (DNS resolves to private IPs from inside the VNet). Private DNS zones override public resolution inside the VNet so all traffic is routed through the private endpoints. This is the enforcement boundary, not a `403` HTTP response from the public edge.

**Residual risk (hub account):** The hub has live model deployments. A principal with a valid Entra token and the appropriate RBAC role could call the hub's OpenAI API directly from public internet, bypassing APIM rate-limiting and policies. This requires compromised credentials and is mitigated by `local_auth_enabled = false` (no API keys, Entra-only) and RBAC, but it is worth noting.

Confirm the control plane settings are correct:

```bash
az cognitiveservices account show \
  --name aif-spk-contoso-e84b7b \
  --resource-group rg-contoso-multi-e84b7b \
  --query "properties.{publicNetworkAccess:publicNetworkAccess,networkAcls:networkAcls}"

az cognitiveservices account show \
  --name aif-core-contoso-e84b7b \
  --resource-group rg-contoso-core-e84b7b \
  --query "properties.{publicNetworkAccess:publicNetworkAccess,networkAcls:networkAcls}"
```

**Expected for both:** `publicNetworkAccess: "Disabled"`, `networkAcls.defaultAction: "Deny"`.

---

### 3.2 Dependent resources (CosmosDB, Storage, Search) block public access

```bash
# CosmosDB data plane — should require auth (401), not serve data (200)
curl -s -o /dev/null -w "cosmosdb: %{http_code}\n" \
  https://cosmos-contoso-e84b7b.documents.azure.com/

# Storage blob endpoint — use a valid API path; root URL returns 400 (malformed) regardless of access settings
curl -s -o /dev/null -w "storage: %{http_code}\n" \
  "https://stcontosoe84b7b.blob.core.windows.net/?comp=list"

# AI Search — should return 403 (network-level block)
curl -s -o /dev/null -w "search: %{http_code}\n" \
  https://srch-contoso-e84b7b.search.windows.net/
```

**Expected:**
- CosmosDB: `401` — CosmosDB evaluates auth before network access at its public edge. Config is correct (`public_network_access_enabled = false`, `local_authentication_disabled = true`); only Entra tokens + RBAC are accepted, no connection strings.
- Storage: `403` — proper network-level block.
- AI Search: `403` — proper network-level block.

---

## 4. Connect to the Jump VM via Azure Bastion

The jump VM (`vm-jump`) is deployed inside the VNet with no public IP. Use Azure Bastion to open a browser-based RDP session.

**Steps:**

1. Open the [Azure Portal](https://portal.azure.com) in your browser.

2. Search for **Virtual machines** → select **`vm-jump`** (resource group `rg-contoso-core-e84b7b`).

3. In the left menu, select **Connect** → **Connect via Bastion**.

4. On the Bastion connection screen:
   - **Authentication Type:** `Password`
   - **Username:** `azureadmin`
   - **Password:** *(the `jump_vm_admin_password` value from [`private.auto.tfvars`](../terraform/environments/dev/private.auto.tfvars))*

5. Click **Connect**. A full Windows Server 2022 desktop opens in a new browser tab.

> **Tip:** If the connection fails, check that Azure Bastion (`bas-contoso`) is in `Succeeded` state: Azure Portal → **Bastions** → `bas-contoso` → Overview.

---

## 5. In-Network Validation (from the jump VM)

All commands in this section are run **inside the jump VM** (via the Bastion session). Open PowerShell or the pre-installed Terminal.

### 5.1 DNS resolves to private IPs

Each FQDN should resolve to an IP in the `10.0.0.0/24` range (`snet-pe`), not a public Microsoft IP.

> **Note:** Use the full FQDN including `.azure.com` — e.g. `aif-spk-contoso-e84b7b.cognitiveservices.azure.com`, not `...cognitiveservices.com`.

```powershell
# AI Services accounts
Resolve-DnsName aif-spk-contoso-e84b7b.cognitiveservices.azure.com
Resolve-DnsName aif-core-contoso-e84b7b.cognitiveservices.azure.com
Resolve-DnsName aif-research-contoso-e84b7b.cognitiveservices.azure.com

# APIM
Resolve-DnsName apim-contoso-e84b7b.azure-api.net

# CosmosDB
Resolve-DnsName cosmos-contoso-e84b7b.documents.azure.com

# Storage
Resolve-DnsName stcontosoe84b7b.blob.core.windows.net

# AI Search
Resolve-DnsName srch-contoso-e84b7b.search.windows.net
```

**Expected output pattern** (example for the spoke AI Services account — all resources follow the same pattern):

```
Name                                     Type   TTL   Section    NameHost
----                                     ----   ---   -------    --------
aif-spk-contoso-e84b7b.cognitiveservices CNAME  900   Answer     aif-spk-contoso-e84b7b.privatelink.cognitiveservices.azure.com
.azure.com

Name       : aif-spk-contoso-e84b7b.privatelink.cognitiveservices.azure.com
QueryType  : A
TTL        : 10
Section    : Answer
IP4Address : 10.0.0.10
```

Two records are returned for each hostname:
1. A `CNAME` from the public FQDN to the `privatelink.*` zone — this is the Azure Private DNS override that intercepts the public name inside the VNet.
2. An `A` record in the `privatelink.*` zone resolving to a `10.0.0.x` IP in `snet-pe` — this is the private endpoint NIC address.

**Expected for each:** `IP4Address` is in the `10.0.0.x` range. Any response showing a public IP (e.g. `52.x.x.x` or `20.x.x.x`) indicates a DNS zone or VNet link issue — check section 2.4.

---

### 5.2 Core model responds via private endpoint

This confirms the core AI Services account is reachable from inside the VNet through its private endpoint, and that the model deployments are operational.

> **Note:** The core account has an admin project (`project-admin-e84b7b`) with a capability host (`caphost-admin`), but the OpenAI endpoint is called directly here to isolate the private endpoint connectivity test from any Agent Service dependencies. Use PowerShell rather than the portal's Chat playground for this check.

From the jump VM, open PowerShell and run:

> **Reminder:** If this is a fresh session, authenticate first: `az login`

```powershell
$token = (az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv)

Invoke-RestMethod `
  -Uri "https://aif-core-contoso-e84b7b.cognitiveservices.azure.com/openai/deployments/gpt-4.1-mini/chat/completions?api-version=2024-10-21" `
  -Method POST `
  -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" } `
  -Body '{"messages":[{"role":"user","content":"What is the capital of France?"}],"max_tokens":50}'
```

**Expected:** A JSON response object containing `choices[0].message` with a reply naming Paris. Example output:

```
choices               : {@{content_filter_results=; finish_reason=stop; index=0; logprobs=; message=}}
created               : 1773852048
id                    : chatcmpl-DKoEqta7eLnhBX5y8Uv22RuJpjZsJ
model                 : gpt-4.1-mini-2025-04-14
object                : chat.completion
...
usage                 : @{completion_tokens=8; ... total_tokens=22}
```

A successful response confirms:
- DNS resolved the core endpoint to a private IP (via `privatelink.cognitiveservices.azure.com`)
- The private endpoint NIC in `snet-pe` is routing traffic correctly
- The `gpt-4.1-mini` model deployment is active and reachable

---

### 5.3 AI Foundry portal loads

1. Open **Microsoft Edge** (pre-installed on the jump VM).
2. Navigate to [https://ai.azure.com](https://ai.azure.com).
3. Sign in with your Azure credentials.
4. Select the subscription **`025aba94-0c4a-443d-8826-466477e2850f`**.
5. Locate the spoke account **`aif-spk-contoso-e84b7b`** — it should appear in the list of AI Foundry resources.
6. Navigate into the project for one of the teams (e.g. **`project-beta-e84b7b`**).

**Expected:** The project overview page loads without errors. The presence of the project confirms the Foundry management plane can reach the private endpoint from inside the VNet.

---

### 5.4 Agent Playground: create and run an agent

This is the primary end-to-end test. It exercises the full capability host stack: Foundry account → project → Agent Service → CosmosDB (thread storage) → AI Search (vector store) → Storage (blob).

1. Inside the Foundry project (e.g. `project-beta-e84b7b`), navigate to **Agents** in the left menu (or **Playgrounds** → **Agents playground**).

2. Click **New agent**.

3. Configure a minimal agent:
   - **Name:** `test-agent`
   - **Model:** select any available model deployment (routed via APIM)
   - Leave all other settings at their defaults

4. Click **Create**.

5. In the chat input at the bottom, type a simple prompt:
   ```
   Hello! What is 2 + 2?
   ```

6. Press Enter and wait for a response.

**Expected:** The agent replies with `4` (or equivalent). A successful response confirms:
- The capability host is active
- The project managed identity has correct RBAC on all dependent resources
- Thread storage (CosmosDB) is reachable via private endpoint
- The model deployment is accessible via APIM

**If the agent creation fails:** Check the capability host state ([section 2.3](#23-capability-hosts-are-succeeded)) and confirm all three connections (CosmosDB, Storage, Search) appear under the project's **Connections** tab in the portal.

---

### 5.5 APIM gateway responds

Test the APIM gateway from inside the VNet using `curl.exe` (use this instead of `Invoke-RestMethod` — PowerShell's line-continuation causes parsing errors on the Bastion terminal).

You will need an APIM subscription key — retrieve it from the Azure Portal:

1. Portal → **API Management services** → `apim-contoso-e84b7b` → **Subscriptions**
2. Select the subscription for your team (e.g. `foundry-gateway-beta`) → **Show/hide keys** → copy the **Primary key**

Write the request body to a file first (avoids JSON escaping issues in PowerShell):

```powershell
Set-Content C:\body.json '{"messages":[{"role":"user","content":"Say hello in one word."}],"max_tokens":10}'

curl.exe -s -X POST "https://apim-contoso-e84b7b.azure-api.net/openai/deployments/gpt-4.1-mini/chat/completions?api-version=2024-10-21" -H "api-key: <paste-primary-key-here>" -H "Content-Type: application/json" -d @C:\body.json
```

**Expected:** A JSON response containing `choices[0].message.content` with a greeting (e.g. `"Hello!"`).

**If APIM returns 401 (invalid subscription key):** The subscription keys may have been regenerated by a recent `terraform apply`. Retrieve the current key from Terraform state on your local machine:

```bash
terraform state pull | jq -r '.resources[] | select(.type == "azurerm_api_management_subscription") | .instances[] | "\(.index_key): \(.attributes.primary_key)"'
```

**If APIM is unreachable:** Confirm `Resolve-DnsName apim-contoso-e84b7b.azure-api.net` returns a private IP (see [section 5.1](#51-dns-resolves-to-private-ips)). Also confirm the APIM deployment name matches — hub models are `gpt-4.1-mini`, `gpt-4.1-nano`, and `text-embedding-3-large`.

---

## 6. Known Issues

### 6.1 APIM subscription keys rejected with 401 / backend returns 403

Two bugs were present in the initial private networking deployment that together prevented the APIM gateway from functioning end-to-end. Both are fixed in Terraform.

**Symptom A:** All team subscription keys return `401 Access denied due to invalid subscription key` even though the keys match what the portal shows. The master ("All APIs") subscription key succeeds.

**Cause:** The `azurerm_api_management_subscription` resource sets `api_id` to `azurerm_api_management_api.main.id`, which the Terraform AzureRM provider resolves to `.../apis/openai;rev=1` (revision-suffixed). APIM validates incoming requests against scope `.../apis/openai` (without revision suffix), so the team subscription scopes never match. The master subscription has no API scope so is unaffected.

**Resolution:** Fixed in `modules/core/main.tf` — the subscription `api_id` now strips the revision suffix:
```hcl
api_id = replace(azurerm_api_management_api.main.id, ";rev=${azurerm_api_management_api.main.revision}", "")
```
Note: this fix causes team subscriptions to be recreated on next `terraform apply`, regenerating the subscription keys. Retrieve current keys from Terraform state:
```bash
terraform state pull | jq -r '.resources[] | select(.type == "azurerm_api_management_subscription") | .instances[] | "\(.index_key): \(.attributes.primary_key)"'
```

---

**Symptom B:** After fixing the subscription keys, requests return `403 Public access is disabled. Please configure private endpoint.` from the backend.

**Cause:** APIM StandardV2 with only a private endpoint configured routes its *outbound* traffic (to backends) over the public internet. The AI Services backend has public access disabled, so APIM cannot reach it. The `snet-apim` subnet existed and had an NSG associated, but was never connected to the APIM resource for outbound VNet integration. Additionally the subnet had the wrong delegation (`Microsoft.ApiManagement/service` instead of `Microsoft.Web/serverFarms`, which StandardV2 outbound integration requires).

**Resolution:** Fixed in two places:
- `environments/dev/private_networking.tf` — corrected `snet-apim` delegation to `Microsoft.Web/serverFarms`
- `modules/core/main.tf` — added outbound VNet integration to the APIM resource:
```hcl
virtual_network_type = var.enable_private_networking ? "External" : "None"

dynamic "virtual_network_configuration" {
  for_each = var.enable_private_networking ? [1] : []
  content {
    subnet_id = var.private_networking.apim_subnet_id
  }
}
```

---

### 6.3 Agents page blocked in Microsoft Edge

**Symptom:** Navigating to the Agents page in the AI Foundry portal shows _"Error loading your agents. Your request for data was not sent."_ The Edge DevTools Issues pane reports requests as `blocked` with a message about local network access restrictions.

**Cause:** Edge (Chromium-based) implements the [Private Network Access](https://wicg.github.io/private-network-access/) spec, which blocks requests from public origins (`ai.azure.com`) to private IP addresses (the `10.0.0.x` private endpoints). The Azure AI Services private endpoints do not respond with the `Access-Control-Allow-Private-Network: true` CORS header that Edge requires. Disabling the feature via `--disable-features` flags or `HKLM` registry policies does not reliably override this in newer Edge versions.

**Workaround:** Use **Google Chrome** or **Mozilla Firefox** instead of Edge on the jump VM. Chrome surfaces the actual API error (see 6.2 below) rather than silently blocking, and Firefox does not implement the Private Network Access restriction.

---

### 6.4 Agents page returns 403 Forbidden on first load

**Symptom:** After switching to Chrome, the Agents page shows a 403 error containing:
```
principal [...] does not have required RBAC permissions to perform action
[Microsoft.DocumentDB/databaseAccounts/readMetadata] on resource
[dbs/enterprise_memory/colls/{project-id}-agent-definitions-v1]
```

**Cause:** The agent service creates the `agent-definitions-v1` CosmosDB collection lazily on first access (list or create). The project managed identity needs `Built-in Data Contributor` access on this collection before it exists. Collection-scoped CosmosDB role assignments cannot be created against a non-existent collection, so the role must be scoped at the **database level** (`/dbs/enterprise_memory`) rather than per-collection.

**Resolution:** This is already fixed in the Terraform — the `postcaphost_cosmos` role assignments in both `modules/core` and `modules/spoke-multi` are scoped to the `enterprise_memory` database rather than individual collections. If you encounter this error after a fresh deployment, confirm the role assignment scope is correct:

```bash
az cosmosdb sql role assignment list \
  --account-name cosmos-core-contoso-e84b7b \
  --resource-group rg-contoso-core-e84b7b \
  --query "[].{principal:principalId, scope:scope}" \
  --output table
```

**Expected:** The scope column shows `.../dbs/enterprise_memory` (not `.../colls/...`).

### 6.5 Agent invocation returns generic error; diagnostic logs show 403 on `Agents_Wildcard_Get`

**Symptom:** Opening an agent in the Build pane / playground works, but submitting any prompt returns a generic *"The server had an error processing your request"* error. The Foundry account's Log Analytics workspace shows entries like:

```
OperationName  : Agents_Wildcard_Get   (or Projects_Wildcard_Get)
ResultSignature: 403
DurationMs     : ~50
apiName        : Azure AI Projects API
objectId       : <your user object id>
```

**Cause:** Subscription-level `Azure AI User` does not satisfy nextgen Foundry's project-scoped data-plane authorisation. The portal user needs a role assignment at the **project resource** scope.

**Resolution:** Add the user (or a security group containing them) to `var.project_admin_principals` (admin project) or `var.team_admin_principals` (team projects), then `terraform apply`. See [`core-account-admin-project-setup.md` §12 — Operator (User) RBAC](./core-account-admin-project-setup.md#12-operator-user-rbac) for the full rationale, variable schema, and migration from imperative assignments.

For an immediate one-off fix without re-applying:

```bash
az role assignment create \
  --assignee-object-id <user-or-group-object-id> \
  --assignee-principal-type User \
  --role "Azure AI Project Manager" \
  --scope "/subscriptions/.../accounts/aif-core-<customer>-<suffix>/projects/project-admin-<suffix>"
```

But back-port to Terraform afterwards to avoid drift.

---

## 7. Jump VM Hygiene

The jump VM has an **auto-shutdown schedule** configured at **23:00 UTC** daily to avoid unnecessary cost. This is visible in the Azure Portal:

Portal → **Virtual machines** → `vm-jump` → **Auto-shutdown** (left menu under Operations).

**Best practices:**
- Close the Bastion session when done (close the browser tab)
- The VM will shut down automatically at 23:00 UTC if you forget
- To restart a stopped VM: Portal → `vm-jump` → **Start**, or:

```bash
az vm start --name vm-jump --resource-group rg-contoso-core-e84b7b
```

- The VM does **not** have a public IP — it is only accessible through Bastion. There is no SSH or RDP exposure to the internet.

---

## 8. Set Up VS Code Remote Tunnel (for Notebook Development)

Running Jupyter notebooks against the private Foundry endpoints requires executing code from inside the VNet. The recommended approach is a **VS Code Remote Tunnel**: a lightweight service installed on the jump VM that lets you connect from your local VS Code without staying inside a Bastion RDP session.

> **Prerequisites:** Complete section 4 first to open a Bastion RDP session. All commands below are run in a PowerShell window on the jump VM.

---

### 8.1 Install developer tools on the jump VM

Windows Server 2022 does not ship with `winget`. Install Git, VS Code, and `uv` using direct downloads instead.

> **Note:** The NAT gateway on `snet-jump` provides outbound internet access for the jump VM, so all downloads work without any proxy configuration.

**Install Git:**

```powershell
Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/v2.49.0.windows.1/Git-2.49.0-64-bit.exe" `
  -OutFile "$env:TEMP\git.exe"
Start-Process "$env:TEMP\git.exe" -ArgumentList "/VERYSILENT /NORESTART /COMPONENTS=icons,ext,ext\shellhere,assoc,assoc_sh" -Wait

$env:Path = "C:\Program Files\Git\cmd;$env:Path"
git --version
```

**Install VS Code:**

```powershell
Invoke-WebRequest -Uri "https://update.code.visualstudio.com/latest/win32-x64/stable" `
  -OutFile "$env:TEMP\vscode.exe"
Start-Process "$env:TEMP\vscode.exe" -ArgumentList "/VERYSILENT /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath" -Wait
```

**Install uv:**

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
$env:Path = "C:\Users\azureadmin\.local\bin;$env:Path"
uv --version
```

Reload the full machine PATH so all tools are available in the current session:

```powershell
$env:Path = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + $env:Path
```

---

### 8.2 Clone the repo and install dependencies

```powershell
git clone https://github.com/corticalstack/geberit-foundry-nextgen C:\dev\geberit-foundry-nextgen
cd C:\dev\geberit-foundry-nextgen
uv sync
```

**Populate `.env`** — copy `.env.example` to `.env` and fill in the values for the team project you want to use. The key values are:

| Variable | Value |
|----------|-------|
| `BETA_FOUNDRY_PROJECT_ENDPOINT` | `https://aif-spk-contoso-e84b7b.services.ai.azure.com/api/projects/project-beta-e84b7b` |
| `BETA_FOUNDRY_HUB_CONNECTION` | `core-beta` |
| `CHAT_MODEL` | `gpt-4.1-mini` |

> **Connection name format:** The APIM connection in each Foundry project is named `core-{team}` (e.g. `core-beta`, `core-delta`, `core-gamma`). This is different from the `hub-{team}` naming used in older single-spoke deployments. The model reference passed to the agent SDK is `{connection}/{model}`, e.g. `core-beta/gpt-4.1-mini`.

---

### 8.3 Install and start the tunnel service

```powershell
code tunnel service install --accept-server-license-terms
code tunnel service start
```

On first run this prints a GitHub device authentication URL and a one-time code:

```
To grant access to the server, please log into https://github.com/login/device and use code XXXX-XXXX
```

Open that URL in the browser **inside the Bastion session**, enter the code, and authorise with your GitHub account. Once authenticated the tunnel is registered and starts running as a Windows service — it will survive reboots and you do not need to keep the Bastion session open.

Check the tunnel is running:

```powershell
code tunnel service log
```

---

### 8.4 Install VS Code extensions on the remote

The Python and Jupyter extensions must be installed on the remote (jump VM) side, not just locally. The VS Code Extensions panel search may not work reliably on Windows Server — install by ID from the jump VM terminal instead:

```powershell
code --install-extension ms-python.python
code --install-extension ms-toolsai.jupyter
```

Restart VS Code after installation.

---

### 8.5 Connect from your local VS Code

1. In your **local VS Code**, install the **Remote - Tunnels** extension (`ms-vscode.remote-server`) if not already present.
2. Press `Ctrl+Shift+P` → **Remote Tunnels: Connect to Tunnel**.
3. Sign in with the same GitHub account used in step 8.3.
4. Select the tunnel (named after the jump VM, e.g. `vm-jump`).

A new VS Code window opens with the filesystem and terminal running on the jump VM, inside the VNet. Open `C:\dev\geberit-foundry-nextgen`, select the `.venv` kernel (`C:\dev\geberit-foundry-nextgen\.venv\Scripts\python.exe`), and run any notebook — all traffic to `*.services.ai.azure.com` resolves via private DNS and routes through the private endpoints.
