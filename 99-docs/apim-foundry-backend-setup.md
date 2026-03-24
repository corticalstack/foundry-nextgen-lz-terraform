# APIM Configuration for the Core Foundry Account Backend

This guide covers everything required to wire an existing APIM instance to a deployed core Foundry account (`aif-core`), exposing it as an OpenAI-compatible API to consumers inside the VNet.

---

## Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [How the Request Flow Works](#how-the-request-flow-works)
- [Step 1 — RBAC: Grant APIM Access to the Foundry Account](#step-1--rbac-grant-apim-access-to-the-foundry-account)
- [Step 2 — Backend](#step-2--backend)
- [Step 3 — API Definition](#step-3--api-definition)
- [Step 4 — Operations](#step-4--operations)
- [Step 5 — API-Level Policy](#step-5--api-level-policy)
- [Step 6 — Subscriptions](#step-6--subscriptions)
- [Terraform Reference](#terraform-reference)
- [Validation](#validation)

---

## Overview

APIM acts as the single entry point for all model inference traffic. It authenticates to the Foundry account using its own **system-assigned managed identity** (no API keys in transit), enforces a consistent `api-version`, applies rate limiting, and routes requests to the correct backend. Consumers authenticate to APIM using a subscription key (`api-key` header).

```
Consumer (api-key)
    │
    ▼
APIM  ──[MSI Bearer token]──▶  aif-core private endpoint  ──▶  Foundry account
```

---

## Prerequisites

| Requirement | Detail |
|---|---|
| APIM instance | Existing, with system-assigned managed identity enabled |
| APIM VNet integration | Outbound VNet integration (StandardV2 External mode) or Internal VNet injection (Premium) into `snet-apim` — required to reach the Foundry account's private endpoint |
| Core Foundry account | Deployed and in `Succeeded` state |
| Private DNS resolution | `privatelink.cognitiveservices.azure.com`, `privatelink.openai.azure.com`, and `privatelink.services.ai.azure.com` zones linked to the VNet — so APIM resolves the Foundry FQDN to a private IP |

---

## How the Request Flow Works

1. Consumer sends a POST to APIM with an `api-key` subscription key header
2. APIM validates the subscription key
3. The API-level policy runs in the inbound pipeline:
   - Sets the backend to the Foundry account
   - Enforces `api-version=2024-10-21` (overrides or adds the query parameter)
   - Acquires an AAD Bearer token using the APIM managed identity for the `https://cognitiveservices.azure.com` resource
   - Replaces the incoming `Authorization` header with the Bearer token
   - Applies rate limiting (100 calls per 60 seconds)
4. APIM forwards the request to the Foundry account's private endpoint over the VNet
5. The Foundry account validates the Bearer token against its RBAC — the APIM MI must have `Cognitive Services User` on the account

---

## Step 1 — RBAC: Grant APIM Access to the Foundry Account

The APIM managed identity must have **Cognitive Services User** on the core Foundry account. This is the minimum role required to call inference endpoints. Without it the Foundry account returns HTTP 403 when APIM presents its Bearer token.

**Terraform:** [`modules/core/main.tf#L333`](../modules/core/main.tf#L333)

```hcl
resource "azurerm_role_assignment" "apim_core" {
  scope                = azapi_resource.core_account.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_api_management.main.identity[0].principal_id
}
```

**Azure CLI equivalent (for an existing APIM):**
```bash
# Get the APIM managed identity principal ID
APIM_PRINCIPAL=$(az apim show \
  --name {apim-name} \
  --resource-group {apim-rg} \
  --query "identity.principalId" -o tsv)

# Get the Foundry account resource ID
FOUNDRY_ID=$(az cognitiveservices account show \
  --name aif-core-{customer}-{suffix} \
  --resource-group rg-{customer}-core-{suffix} \
  --query id -o tsv)

# Assign Cognitive Services User
az role assignment create \
  --assignee $APIM_PRINCIPAL \
  --role "Cognitive Services User" \
  --scope $FOUNDRY_ID
```

> RBAC propagation takes up to 60 seconds. Do not proceed to test until propagation is complete.

---

## Step 2 — Backend

The backend tells APIM where to forward requests. The URL is the Foundry account's endpoint with `/openai` appended — this is the path prefix for all OpenAI-compatible operations.

**Terraform:** [`modules/core/main.tf#L189`](../modules/core/main.tf#L189)

```hcl
resource "azurerm_api_management_backend" "hub" {
  name                = "openai"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  protocol            = "http"
  url                 = "${azapi_resource.core_account.output.properties.endpoint}openai"
}
```

The Foundry account endpoint follows the pattern:
```
https://aif-core-{customer}-{suffix}.cognitiveservices.azure.com/
```

So the backend URL becomes:
```
https://aif-core-{customer}-{suffix}.cognitiveservices.azure.com/openai
```

**Azure portal:** APIM → Backends → Add backend
- Name: `openai`
- Type: Custom URL
- Runtime URL: `https://aif-core-{customer}-{suffix}.cognitiveservices.azure.com/openai`

> The backend name `openai` must match the `backend-id` referenced in the API-level policy (Step 5).

---

## Step 3 — API Definition

Create an API that maps to the `/openai` path. Subscription is required — consumers must present an `api-key` header or query parameter.

**Terraform:** [`modules/core/main.tf#L210`](../modules/core/main.tf#L210)

```hcl
resource "azurerm_api_management_api" "main" {
  name                  = "openai"
  display_name          = "OpenAI"
  revision              = "1"
  path                  = "openai"
  protocols             = ["https"]
  subscription_required = true

  subscription_key_parameter_names {
    header = "api-key"    # consumers send: api-key: {subscription-key}
    query  = "api-key"    # or: ?api-key={subscription-key}
  }
}
```

| Setting | Value | Reason |
|---|---|---|
| `path` | `openai` | APIM gateway URL becomes `{gateway-url}/openai/...` — matching the OpenAI SDK base URL convention |
| `subscription_required` | `true` | All callers must present a valid APIM subscription key |
| `header` / `query` name | `api-key` | OpenAI SDK sends `api-key` by default — no SDK reconfiguration needed |

---

## Step 4 — Operations

Four operations cover the full set of inference endpoints exposed by the Foundry account.

**Terraform:** [`modules/core/main.tf#L230`](../modules/core/main.tf#L230)

### Chat Completions

```hcl
resource "azurerm_api_management_api_operation" "chat" {
  operation_id = "chat"
  display_name = "Chat Completions"
  method       = "POST"
  url_template = "/deployments/{deployment-id}/chat/completions"

  template_parameter {
    name     = "deployment-id"
    required = true
    type     = "string"
  }
}
```

### Embeddings

```hcl
resource "azurerm_api_management_api_operation" "embeddings" {
  operation_id = "embeddings"
  display_name = "Embeddings"
  method       = "POST"
  url_template = "/deployments/{deployment-id}/embeddings"

  template_parameter {
    name     = "deployment-id"
    required = true
    type     = "string"
  }
}
```

### Responses (OpenAI Responses API)

```hcl
resource "azurerm_api_management_api_operation" "responses" {
  operation_id = "responses"
  display_name = "Responses"
  method       = "POST"
  url_template = "/responses"
}
```

The `{deployment-id}` template parameter in chat and embeddings is passed through in the URL to the backend — APIM does not inspect or validate the value, so any deployed model name is valid.

---

## Step 5 — API-Level Policy

The policy runs on every operation under this API. It handles authentication, backend routing, API version enforcement, and rate limiting in a single inbound pipeline.

**Terraform:** [`modules/core/main.tf#L302`](../modules/core/main.tf#L302)
**Template:** [`modules/core/templates/api_policy.xml.tftpl`](../modules/core/templates/api_policy.xml.tftpl)

```xml
<policies>
  <inbound>
    <base />

    <!-- Route all requests to the core Foundry account backend -->
    <set-backend-service backend-id="openai" />

    <!-- Enforce api-version=2024-10-21 regardless of what the client sends.
         "skip" means: only set it if the client did not include it.
         This prevents consumers from accidentally calling unsupported versions. -->
    <set-query-parameter name="api-version" exists-action="skip">
      <value>2024-10-21</value>
    </set-query-parameter>

    <!-- Acquire a Bearer token for the APIM managed identity scoped to
         the Cognitive Services resource. Stored in a context variable.
         The Foundry account validates this token against its RBAC. -->
    <authentication-managed-identity
      resource="https://cognitiveservices.azure.com"
      output-token-variable-name="msi-access-token"
      ignore-error="false" />

    <!-- Replace any incoming Authorization header (e.g. the consumer's own
         api-key or Bearer token) with the APIM MSI token. The Foundry account
         only accepts AAD tokens — subscription keys are not forwarded. -->
    <set-header name="Authorization" exists-action="override">
      <value>@("Bearer " + (string)context.Variables["msi-access-token"])</value>
    </set-header>

    <!-- Rate limit: 100 calls per 60-second window per subscription key.
         Returns HTTP 429 when exceeded. Adjust per consumer SLA. -->
    <rate-limit calls="100" renewal-period="60" />

  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
</policies>
```

### Key policy decisions

| Policy statement | Why |
|---|---|
| `set-backend-service` | Decouples the API route from the backend URL — the backend can be swapped without changing the API definition |
| `set-query-parameter exists-action="skip"` | Clients that omit `api-version` get the pinned version; clients that send their own value keep it — avoids breaking SDK defaults |
| `authentication-managed-identity` | APIM exchanges its identity for an AAD token at request time — no stored credentials, token is always fresh |
| `set-header Authorization override` | Replaces the subscription key (which the Foundry account would reject) with a valid AAD Bearer token |
| `rate-limit` | Applied per subscription key — protects the Foundry account from a single consumer exhausting quota |

---

## Step 6 — Subscriptions

One APIM subscription per team or consumer. The subscription key is what consumers use as the `api-key` — APIM validates it, then swaps it for the MSI Bearer token before forwarding to Foundry.

**Terraform:** [`modules/core/main.tf#L318`](../modules/core/main.tf#L318)

```hcl
resource "azurerm_api_management_subscription" "team" {
  for_each = toset(var.teams)

  display_name    = "Foundry Gateway Access (${title(each.key)})"
  subscription_id = "foundry-gateway-${each.key}"
  api_id          = azurerm_api_management_api.main.id
  state           = "active"
}
```

Each subscription is scoped to the `openai` API (not product or global scope) so consumers can only call Foundry endpoints — not other APIs on the same APIM instance.

**Azure CLI — create a subscription for a new team:**
```bash
az apim subscription create \
  --resource-group {apim-rg} \
  --service-name {apim-name} \
  --subscription-id "foundry-gateway-{team}" \
  --display-name "Foundry Gateway Access ({Team})" \
  --api-id "/apis/openai" \
  --state active
```

**Retrieve the subscription key:**
```bash
az apim subscription show \
  --resource-group {apim-rg} \
  --service-name {apim-name} \
  --subscription-id "foundry-gateway-{team}" \
  --query "{primary:primaryKey, secondary:secondaryKey}"
```

---

## Terraform Reference

| Resource | File | Line |
|---|---|---|
| APIM backend (`openai`) | [`modules/core/main.tf`](../modules/core/main.tf#L189) | L189 |
| API definition | [`modules/core/main.tf`](../modules/core/main.tf#L210) | L210 |
| Chat Completions operation | [`modules/core/main.tf`](../modules/core/main.tf#L230) | L230 |
| Embeddings operation | [`modules/core/main.tf`](../modules/core/main.tf#L256) | L256 |
| Responses operation | [`modules/core/main.tf`](../modules/core/main.tf#L272) | L272 |
| API-level policy | [`modules/core/main.tf`](../modules/core/main.tf#L302) | L302 |
| Policy template | [`modules/core/templates/api_policy.xml.tftpl`](../modules/core/templates/api_policy.xml.tftpl) | — |
| Subscriptions | [`modules/core/main.tf`](../modules/core/main.tf#L318) | L318 |
| APIM → Foundry RBAC | [`modules/core/main.tf`](../modules/core/main.tf#L333) | L333 |

---

## Validation

Run these from inside the VNet (jump VM via Bastion) after all configuration is applied.

**1. Confirm RBAC is in place**
```bash
az role assignment list \
  --scope $(az cognitiveservices account show \
    --name aif-core-{customer}-{suffix} \
    --resource-group rg-{customer}-core-{suffix} \
    --query id -o tsv) \
  --query "[?principalId=='{apim-mi-principal-id}'].roleDefinitionName"
```
Expected: `["Cognitive Services User"]`

**2. Confirm the backend resolves to a private IP**

From the jump VM, verify APIM's outbound VNet integration can reach the Foundry endpoint:
```powershell
Resolve-DnsName aif-core-{customer}-{suffix}.cognitiveservices.azure.com
Test-NetConnection aif-core-{customer}-{suffix}.cognitiveservices.azure.com -Port 443
```
Expected: private IP (10.x.x.x), `TcpTestSucceeded: True`

**3. Call the API through APIM with a subscription key**
```powershell
$key = "{apim-subscription-key}"

Invoke-RestMethod `
  -Uri "{apim-gateway-url}/openai/deployments/{model-name}/chat/completions?api-version=2024-10-21" `
  -Method POST `
  -Headers @{ "api-key" = $key; "Content-Type" = "application/json" } `
  -Body '{"messages":[{"role":"user","content":"ping"}],"max_tokens":5}'
```
Expected: HTTP 200 with a completion response.

| Error | Likely cause |
|---|---|
| HTTP 401 | RBAC not propagated — wait 60s and retry |
| HTTP 403 | APIM MI not assigned `Cognitive Services User`, or MSI token acquisition failed |
| HTTP 404 | Backend URL incorrect, or deployment name does not exist on the account |
| HTTP 429 | Rate limit hit — subscription exceeded 100 calls in 60s |
| Connection refused / timeout | APIM not integrated into VNet, or private DNS not resolving to PE IP |
