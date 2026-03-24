# Core Foundry Account and Admin Project Setup

This guide covers the minimum Terraform components required to provision a working Azure AI Foundry account with an admin project, enabling model testing in the Foundry playground. It assumes a VNet is already in place.

---

## Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [What the Core Module Deploys](#what-the-core-module-deploys)
  - [Required for Playground](#required-for-playground)
  - [Co-deployed by the Module](#co-deployed-by-the-module)
- [Component Reference](#component-reference)
  - [Resource Group](#1-resource-group)
  - [Core Foundry Account](#2-core-foundry-account-aif-core)
  - [Model Deployments](#3-model-deployments)
  - [Private Endpoint — Core Account](#4-private-endpoint--core-account)
  - [Admin Capability Host Backing Resources](#5-admin-capability-host-backing-resources)
  - [Admin Project](#6-admin-project)
  - [Pre-Caphost RBAC](#7-pre-caphost-rbac-admin-project-mi)
  - [Admin Project Connections](#8-admin-project-connections)
  - [Capability Host](#9-capability-host)
  - [Post-Caphost RBAC](#10-post-caphost-rbac)
  - [Deployer RBAC](#11-deployer-rbac)
- [Required VNet Inputs](#required-vnet-inputs)
- [Required DNS Zone Inputs](#required-dns-zone-inputs)
- [Configuration Variables](#configuration-variables)
- [Example `private.auto.tfvars`](#example-privateautotfvars)
- [Provisioning Order](#provisioning-order)
- [Deployment Steps](#deployment-steps)
- [Validation](#validation)

---

## Overview

The [`modules/core`](../modules/core/) module is the single Terraform module that needs to be applied. It provisions:

- A core Azure AI Foundry account (`aif-core`) with model deployments
- A private endpoint for the account (using your existing VNet)
- Backing resources for the admin capability host (Storage, CosmosDB, AI Search)
- An admin project and capability host, which **unlocks the Foundry playground and Agent Service**

The admin project and capability host are **only provisioned when `enable_private_networking = true`**, which is appropriate here since a VNet is already in place.

The module also creates an API Management instance and a research Foundry account — these are part of the full hub topology and are created unconditionally. They do not block playground access but will be provisioned as part of the same `terraform apply`.

---

## Prerequisites

Before applying:

| Requirement | Detail |
|---|---|
| Existing VNet | At minimum: two subnets (see [Required VNet Inputs](#required-vnet-inputs)) |
| Private DNS zones | Three zones for Foundry + three for backing resources (see [Required DNS Zone Inputs](#required-dns-zone-inputs)) |
| Azure role | `Owner` or `Contributor` + `User Access Administrator` on the target subscription |
| Terraform | `>= 1.5.0` |
| `azurerm` provider | `~> 3.0` |
| `azapi` provider | `~> 2.0` |

---

## What the Core Module Deploys

### Required for Playground

These resources form the critical path to a working admin project with playground access:

| Resource | Terraform identifier | Purpose |
|---|---|---|
| Resource group | [`azurerm_resource_group.main`](../modules/core/main.tf#L5) | Container for all core resources |
| Core Foundry account | [`azapi_resource.core_account`](../modules/core/main.tf#L16) | The AI Foundry hub account |
| Model deployments | [`azurerm_cognitive_deployment.core`](../modules/core/main.tf#L70) | Models available in the playground |
| Private endpoint | [`azurerm_private_endpoint.core_account`](../modules/core/main.tf#L383) | Connects account into your VNet |
| Storage account | [`azapi_resource.core_storage`](../modules/core/main.tf#L619) | Caphost backing: file/agent storage |
| CosmosDB account | [`azurerm_cosmosdb_account.core_cosmos`](../modules/core/main.tf#L677) | Caphost backing: thread storage |
| AI Search service | [`azapi_resource.core_search`](../modules/core/main.tf#L731) | Caphost backing: vector store |
| Admin project | [`azapi_resource.admin_project`](../modules/core/main.tf#L781) | Project that hosts the playground |
| Admin project connections | [`azapi_resource.admin_cosmos_connection`](../modules/core/main.tf#L881), [`admin_storage_connection`](../modules/core/main.tf#L906), [`admin_search_connection`](../modules/core/main.tf#L931) | Wire backing resources to the project |
| Capability host | [`azapi_resource.admin_capability_host`](../modules/core/main.tf#L961) | Enables Agents + playground |
| Deployer RBAC | [`azurerm_role_assignment.deployer_core`](../modules/core/main.tf#L345) | Allows the deployer to use the playground |

### Co-deployed by the Module

These resources are always created by the module but are not required to use the playground:

| Resource | Why it's created |
|---|---|
| Research Foundry account (`aif-research`) | Hub topology for reasoning models (e.g. o3); can be ignored initially |
| API Management (`apim-*`) | Hub gateway for team access; StandardV2 provisioning takes 15–20 min |

---

## Component Reference

### 1. Resource Group

**File:** [`modules/core/main.tf#L5`](../modules/core/main.tf#L5)

```hcl
resource "azurerm_resource_group" "main" {
  name     = "rg-{customer}-core-{suffix}"
  location = var.location
}
```

All core resources land in this resource group.

---

### 2. Core Foundry Account (`aif-core`)

**File:** [`modules/core/main.tf#L16`](../modules/core/main.tf#L16)

```hcl
resource "azapi_resource" "core_account" {
  type = "Microsoft.CognitiveServices/accounts@2025-06-01"
  # kind = "AIServices", sku = S0
  # publicNetworkAccess = "Disabled" when enable_private_networking = true
  # networkInjections configured for the agent subnet
}
```

The account is provisioned with:
- `allowProjectManagement = true` — required to create child projects
- `localAuthEnabled = false` — AAD-only authentication
- `publicNetworkAccess = "Disabled"` — traffic only via private endpoint
- Network injection into `var.private_networking.agent_subnet_id` — required for the Agent Service to run

**Naming:** `aif-core-{customer}-{suffix}` where suffix is the first 6 chars of `sha256(subscription_id)`.
See [`modules/core/locals.tf#L28`](../modules/core/locals.tf#L28).

---

### 3. Model Deployments

**File:** [`modules/core/main.tf#L70`](../modules/core/main.tf#L70)

```hcl
resource "azurerm_cognitive_deployment" "core" {
  for_each             = { for m in var.core_models : m.name => m }
  cognitive_account_id = azapi_resource.core_account.id
  version_upgrade_option = "NoAutoUpgrade"
}
```

One deployment per entry in `var.core_models`. Deployments are serialized (via `depends_on`) to avoid HTTP 409 conflicts from concurrent deployment requests on the same account.

`version_upgrade_option = "NoAutoUpgrade"` prevents Azure from silently changing model versions between Terraform runs.

---

### 4. Private Endpoint — Core Account

**File:** [`modules/core/main.tf#L366`](../modules/core/main.tf#L366) (sleep), [`#L383`](../modules/core/main.tf#L383) (endpoint)

```hcl
resource "time_sleep" "wait_core_account" {
  create_duration = "60s"   # waits for account provisioning state to settle
}

resource "azurerm_private_endpoint" "core_account" {
  subnet_id = var.private_networking.private_endpoint_subnet_id
  private_service_connection { subresource_names = ["account"] }
  private_dns_zone_group {
    private_dns_zone_ids = [
      var.dns_zone_ids.cognitive_services,
      var.dns_zone_ids.openai,
      var.dns_zone_ids.services_ai,
    ]
  }
}
```

The 60-second sleep before PE creation mitigates a known ARM race condition ([azurerm#31712](https://github.com/hashicorp/terraform-provider-azurerm/issues/31712)) where PE creation fails if the account is still finalising its provisioning state.

All three DNS zones are registered to the same PE — this covers the three FQDNs that the Foundry account responds on.

---

### 5. Admin Capability Host Backing Resources

All three are gated on `enable_private_networking = true` and each gets its own private endpoint.

#### Storage Account
**File:** [`modules/core/main.tf#L619`](../modules/core/main.tf#L619)

- Kind: StorageV2, SKU: Standard_ZRS
- Shared key access disabled; AAD-only
- Public access disabled
- Naming: `stcore{customer_no_hyphens}{suffix}` (max 24 chars, no hyphens)

#### CosmosDB Account
**File:** [`modules/core/main.tf#L677`](../modules/core/main.tf#L677)

- API: Core (SQL), consistency: Session
- Local auth disabled; AAD-only
- The Agent Service creates the `enterprise_memory` database and its collections lazily at runtime — the CosmosDB SQL role assignment (post-caphost) is scoped at database level to handle this

#### AI Search Service
**File:** [`modules/core/main.tf#L731`](../modules/core/main.tf#L731)

- SKU: Standard (required for semantic search features used by agents)
- Public network access disabled

---

### 6. Admin Project

**File:** [`modules/core/main.tf#L781`](../modules/core/main.tf#L781)

```hcl
resource "azapi_resource" "admin_project" {
  count     = var.enable_private_networking ? 1 : 0
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  parent_id = azapi_resource.core_account.id
  body = {
    properties = {
      description = "Admin project for model evaluation and playground access"
    }
  }
}
```

> **Note:** The admin project is only created when `enable_private_networking = true`. Since a VNet is in place, set this to `true`.

The project is a child of the core account. It receives a system-assigned managed identity whose principal ID is used for all downstream RBAC and connection resources.

Naming: `project-admin-{suffix}`.

---

### 7. Pre-Caphost RBAC (Admin Project MI)

**File:** [`modules/core/main.tf#L821`](../modules/core/main.tf#L821) – [`#L875`](../modules/core/main.tf#L875)

A 10-second sleep ([`time_sleep.wait_admin_project_identity`](../modules/core/main.tf#L810)) lets the project's managed identity propagate in AAD before role assignments are created.

| Role | Scope | Resource |
|---|---|---|
| Cosmos DB Operator | CosmosDB account | [`azurerm_role_assignment.admin_cosmos_operator`](../modules/core/main.tf#L821) |
| Storage Blob Data Contributor | Storage account | [`azurerm_role_assignment.admin_storage_blob_contributor`](../modules/core/main.tf#L831) |
| Search Index Data Contributor | AI Search | [`azurerm_role_assignment.admin_search_index_contributor`](../modules/core/main.tf#L841) |
| Search Service Contributor | AI Search | [`azurerm_role_assignment.admin_search_service_contributor`](../modules/core/main.tf#L851) |

A 60-second sleep ([`time_sleep.wait_admin_rbac`](../modules/core/main.tf#L865)) follows to allow RBAC to propagate before connections are created.

---

### 8. Admin Project Connections

**File:** [`modules/core/main.tf#L881`](../modules/core/main.tf#L881) – [`#L955`](../modules/core/main.tf#L955)

Three connections are registered under the admin project. All use AAD authentication.

| Connection name | Category | Target | Terraform resource |
|---|---|---|---|
| `cosmos-admin` | `CosmosDb` | CosmosDB endpoint | [`azapi_resource.admin_cosmos_connection`](../modules/core/main.tf#L881) |
| `storage-admin` | `AzureStorageAccount` | Storage blob endpoint | [`azapi_resource.admin_storage_connection`](../modules/core/main.tf#L906) |
| `search-admin` | `CognitiveSearch` | `https://{search}.search.windows.net` | [`azapi_resource.admin_search_connection`](../modules/core/main.tf#L931) |

These connection names are referenced directly in the capability host definition.

---

### 9. Capability Host

**File:** [`modules/core/main.tf#L961`](../modules/core/main.tf#L961)

```hcl
resource "azapi_resource" "admin_capability_host" {
  type      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name      = "caphost-admin"
  parent_id = azapi_resource.admin_project[0].id
  body = {
    properties = {
      capabilityHostKind       = "Agents"
      vectorStoreConnections   = ["search-admin"]
      storageConnections       = ["storage-admin"]
      threadStorageConnections = ["cosmos-admin"]
    }
  }
}
```

The capability host is what enables the **Agent Service** and the **Foundry playground** for this project. It wires the three backing resource connections into the project so the runtime can persist threads (CosmosDB), files (Storage), and embeddings (AI Search).

---

### 10. Post-Caphost RBAC

**File:** [`modules/core/main.tf#L996`](../modules/core/main.tf#L996) – [`#L1037`](../modules/core/main.tf#L1037)

After the capability host is created, two additional role assignments are applied:

**CosmosDB SQL role** — scoped to the `enterprise_memory` database (not collection-level, because the Agent Service creates collections lazily):
```
scope = "{cosmos_id}/dbs/enterprise_memory"
role  = "00000000-0000-0000-0000-000000000002"  # Built-in Data Contributor
```

**Storage ABAC** — `Storage Blob Data Owner` with an attribute condition that restricts access to containers whose name starts with the admin project's internal GUID:
```
{container} STARTSWITH "{admin_project_guid}-azureml-agent"
```

---

### 11. Deployer RBAC

**File:** [`modules/core/main.tf#L345`](../modules/core/main.tf#L345)

```hcl
resource "azurerm_role_assignment" "deployer_core" {
  scope                = azapi_resource.core_account.id
  role_definition_name = "Cognitive Services User"
  principal_id         = var.deployer_principal_id
}
```

Grants the identity running `terraform apply` the `Cognitive Services User` role on the core account. This is the minimum permission needed to open the Foundry Studio playground and call models.

---

## Required VNet Inputs

Pass your existing VNet details via `var.private_networking`:

```hcl
private_networking = {
  vnet_id                    = "/subscriptions/.../virtualNetworks/my-vnet"
  private_endpoint_subnet_id = "/subscriptions/.../subnets/snet-pe"
  agent_subnet_id            = "/subscriptions/.../subnets/snet-agents"

  # Required by the module variable schema but unused when deploying
  # only the core module (no spoke, no jump VM, no Bastion):
  apim_subnet_id    = "/subscriptions/.../subnets/snet-apim"
  jump_vm_subnet_id = ""
  bastion_subnet_id = ""
}
```

| Subnet | Purpose | Required delegation |
|---|---|---|
| `snet-pe` | NIC for all private endpoints | None |
| `snet-agents` | Network injection for the core account Agent Service | `Microsoft.App/environments` |
| `snet-apim` | Required by APIM (always created by module) | `Microsoft.Web/serverFarms` |

The `private_networking` variable is defined in [`modules/core/variables.tf#L118`](../modules/core/variables.tf#L118).

---

## Required DNS Zone Inputs

The core module needs resource IDs for private DNS zones. When private networking is enabled, zones must already be linked to your VNet before `terraform apply`.

```hcl
dns_zone_ids = {
  # Required for core account private endpoint:
  cognitive_services = "/subscriptions/.../privateDnsZones/privatelink.cognitiveservices.azure.com"
  openai             = "/subscriptions/.../privateDnsZones/privatelink.openai.azure.com"
  services_ai        = "/subscriptions/.../privateDnsZones/privatelink.services.ai.azure.com"

  # Required for admin backing resource private endpoints:
  search    = "/subscriptions/.../privateDnsZones/privatelink.search.windows.net"
  documents = "/subscriptions/.../privateDnsZones/privatelink.documents.azure.com"
  blob      = "/subscriptions/.../privateDnsZones/privatelink.blob.core.windows.net"

  # Required by the module schema (for APIM and research account):
  apim = "/subscriptions/.../privateDnsZones/privatelink.azure-api.net"
  file = "/subscriptions/.../privateDnsZones/privatelink.file.core.windows.net"
}
```

The `dns_zone_ids` variable is defined in [`modules/core/variables.tf#L131`](../modules/core/variables.tf#L131).

---

## Configuration Variables

Defined in [`modules/core/variables.tf`](../modules/core/variables.tf):

| Variable | Type | Required | Description |
|---|---|---|---|
| [`environment`](../modules/core/variables.tf#L1) | `string` | Yes | `dev`, `qa`, or `prod` |
| [`location`](../modules/core/variables.tf#L10) | `string` | Yes | Primary Azure region (e.g. `eastus2`) |
| [`customer`](../modules/core/variables.tf#L32) | `string` | Yes | Short slug in resource names (e.g. `contoso`) |
| [`deployer_principal_id`](../modules/core/variables.tf#L68) | `string` | Yes | Object ID of the identity running `terraform apply` |
| [`core_models`](../modules/core/variables.tf#L73) | `list(object)` | Yes | Model deployments for the core account |
| [`research_models`](../modules/core/variables.tf#L88) | `list(object)` | Yes | Models for the research account (required by module) |
| [`teams`](../modules/core/variables.tf#L103) | `list(string)` | Yes | Team identifiers (at least one; used for APIM subscriptions) |
| [`enable_private_networking`](../modules/core/variables.tf#L112) | `bool` | Yes | Must be `true` to create the admin project |
| [`private_networking`](../modules/core/variables.tf#L118) | `object` | Yes (when above is true) | BYO VNet subnet IDs |
| [`dns_zone_ids`](../modules/core/variables.tf#L131) | `object` | Yes (when above is true) | Private DNS zone resource IDs |
| [`publisher_email`](../modules/core/variables.tf#L58) | `string` | Yes | APIM publisher email (required by module) |
| [`publisher_name`](../modules/core/variables.tf#L63) | `string` | Yes | APIM publisher name (required by module) |

---

## Example `private.auto.tfvars`

Create this file at the environment root (e.g. `environments/dev/private.auto.tfvars`). It is git-ignored.

```hcl
customer              = "contoso"
publisher_email       = "admin@contoso.com"
publisher_name        = "Contoso IT"
enable_private_networking = true

core_models = [
  {
    name     = "gpt-4o"
    format   = "OpenAI"
    version  = "2024-11-20"
    sku      = "GlobalStandard"
    capacity = 30
  },
  {
    name     = "text-embedding-3-large"
    format   = "OpenAI"
    version  = "1"
    sku      = "Standard"
    capacity = 120
  }
]

research_models = [
  {
    name     = "o3"
    format   = "OpenAI"
    version  = "2025-04-16"
    sku      = "GlobalStandard"
    capacity = 10
  }
]

teams = ["admin"]

private_networking = {
  vnet_id                    = "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>"
  private_endpoint_subnet_id = "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/snet-pe"
  agent_subnet_id            = "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/snet-agents"
  apim_subnet_id             = "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/snet-apim"
  jump_vm_subnet_id          = ""
  bastion_subnet_id          = ""
}

dns_zone_ids = {
  cognitive_services = "/subscriptions/<sub-id>/resourceGroups/<dns-rg>/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
  openai             = "/subscriptions/<sub-id>/resourceGroups/<dns-rg>/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
  services_ai        = "/subscriptions/<sub-id>/resourceGroups/<dns-rg>/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
  search             = "/subscriptions/<sub-id>/resourceGroups/<dns-rg>/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
  documents          = "/subscriptions/<sub-id>/resourceGroups/<dns-rg>/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
  blob               = "/subscriptions/<sub-id>/resourceGroups/<dns-rg>/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  file               = "/subscriptions/<sub-id>/resourceGroups/<dns-rg>/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
  apim               = "/subscriptions/<sub-id>/resourceGroups/<dns-rg>/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
}
```

---

## Provisioning Order

The module enforces this dependency chain automatically. Understanding it helps diagnose failures:

```
azurerm_resource_group.main
  └─ azapi_resource.core_account
       ├─ azurerm_cognitive_deployment.core          (model deployments)
       └─ time_sleep.wait_core_account (60s)
            └─ azurerm_private_endpoint.core_account
       └─ azapi_resource.core_storage
            └─ azurerm_private_endpoint.core_storage
       └─ azurerm_cosmosdb_account.core_cosmos
            └─ azurerm_private_endpoint.core_cosmos
       └─ azapi_resource.core_search
            └─ azurerm_private_endpoint.core_search
       └─ azapi_resource.admin_project
            └─ time_sleep.wait_admin_project_identity (10s)
                 └─ azurerm_role_assignment.admin_*  (4 role assignments)
                      └─ time_sleep.wait_admin_rbac (60s)
                           └─ azapi_resource.admin_{cosmos,storage,search}_connection
                                └─ azapi_resource.admin_capability_host
                                     ├─ azurerm_cosmosdb_sql_role_assignment.admin_postcaphost_cosmos
                                     └─ azurerm_role_assignment.admin_storage_blob_data_owner
```

Total wall-clock time on first apply: **~35–45 minutes**, dominated by APIM StandardV2 provisioning (15–20 min) and the sequential sleep buffers.

---

## Deployment Steps

```bash
cd environments/dev

# Initialise providers and backend
terraform init

# Review the plan
terraform plan

# Apply — expect 35–45 minutes on first run
terraform apply
```

If applying only the core module without the full environment (no spoke, no VNet creation), you can call the module directly from a minimal root config:

```hcl
# main.tf (minimal root)
module "core" {
  source = "../../modules/core"

  environment               = "dev"
  location                  = "eastus2"
  customer                  = var.customer
  publisher_email           = var.publisher_email
  publisher_name            = var.publisher_name
  deployer_principal_id     = data.azurerm_client_config.current.object_id
  core_models               = var.core_models
  research_models           = var.research_models
  teams                     = var.teams
  enable_private_networking = true
  private_networking        = var.private_networking
  dns_zone_ids              = var.dns_zone_ids
}
```

---

## Validation

After `terraform apply` completes:

1. **Confirm the admin project exists:**
   - Navigate to [Azure AI Foundry Studio](https://ai.azure.com)
   - Select the core account (`aif-core-{customer}-{suffix}`)
   - The `project-admin-{suffix}` project should appear in the left nav

2. **Confirm models are deployed:**
   - Inside the admin project, go to **Deployments**
   - All entries from `var.core_models` should be listed with status `Succeeded`

3. **Open the playground:**
   - Go to **Playgrounds > Chat playground** within the admin project
   - Select a model deployment from the dropdown
   - Send a test message — a successful response confirms end-to-end connectivity

4. **Confirm the capability host (for agent playground):**
   - Go to **Management > Connected resources** inside the admin project
   - `cosmos-admin`, `storage-admin`, and `search-admin` connections should all show as connected

> If you are accessing Foundry Studio from outside the VNet, you will need to route through a jump VM or VPN. The core account's public network access is disabled when `enable_private_networking = true`.
