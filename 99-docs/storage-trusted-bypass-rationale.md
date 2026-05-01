# Storage Trusted-Bypass Rationale

This document explains why the BYO storage accounts (`core_storage` in `modules/core` and `agent_storage` in `modules/spoke-multi`) declare both a private endpoint **and** a `networkAcls.resourceAccessRules` entry for the Foundry account and project resource IDs. Either alone is insufficient for a private-networked Foundry agent service. This is not redundancy — it is two complementary network-allow paths for two different traffic origins.

---

## TL;DR

A private endpoint authorises traffic that originates **inside your VNet**. The Foundry agent service has multiple components, some of which run in **Microsoft-managed shared infrastructure outside your VNet**. Those components reach your storage account from Microsoft-owned IPs. With `publicNetworkAccess = "Disabled"`, that traffic is rejected by the storage firewall *before* RBAC is ever evaluated. `networkAcls.resourceAccessRules` is the explicit "this Microsoft service is allowed in" handshake that lets those service-to-service calls land — narrow to the named resource IDs, not a blanket public opening.

---

## 1. Why a private endpoint alone is not enough

Each network-allow mechanism on a storage account covers a different traffic origin:

| Mechanism | Lets traffic in *from* | Authentication boundary |
|---|---|---|
| **Private endpoint** | Anything inside *your* VNet (or peered/DNS-linked VNets) that resolves the storage hostname to the PE's private IP | Customer-controlled network |
| **`bypass = "AzureServices"`** | A small fixed set of first-party Azure services that Microsoft has hard-coded as trusted (e.g. Backup, Site Recovery, Azure Monitor) | Microsoft-managed network, hard-coded list |
| **`resourceAccessRules`** | A *specific* Microsoft Azure service identified by ARM resource ID, when its managed identity presents a token whose source resource ID matches one of the listed entries | Microsoft-managed network, customer-curated list |

`publicNetworkAccess = "Disabled"` blocks any traffic that does not satisfy at least one of these three rules. RBAC is **only checked once the network ACL has passed**, so missing network authorisation is invisible to data-plane logs — the request is rejected before it is logged as a request.

The Foundry "service" is not one component. It is a constellation of runtimes that span the customer VNet *and* Microsoft-managed shared infrastructure:

```
Customer VNet (snet-agents / snet-agents-spoke)     Microsoft-managed shared infra
─────────────────────────────────────────────       ──────────────────────────────────────────
                                                       ┌──────────────────────────────────┐
   Agent runtime (the sandbox running                  │ managementfrontend               │
   your Code Interpreter session,                      │ (Foundry control plane,          │
   VNet-injected via the account-level                 │  Projects API)                   │
   capability host's customerSubnet)                   ├──────────────────────────────────┤
        │                                              │ Files API backend                │
        │  data-plane reads via PE  → 🟢 works         ├──────────────────────────────────┤
        ▼                                              │ Agent orchestrator               │
   stcorecontosoe84b7b /                               │ (capability-host compute)        │
   stcontoso<team>-...                                 └──────────────────────────────────┘
   (PE-only storage)                                                  │
        ▲                                                             │
        │  control-plane reads, file metadata, blob lifecycle ops     │
        │  from MS-owned IPs (NOT inside your VNet) ◀─────────────────┘
        │  → 🔴 PE doesn't apply, blocked unless trusted-bypass
```

The runtime in your subnet *can* use the PE for its own data reads. But many of the operations that happen during a code-interpreter-with-file invocation do not originate from the runtime — they originate from Foundry's control-plane services running in shared Microsoft infrastructure. That traffic does not enter your VNet, so the PE does not apply. It hits the storage account from a Microsoft-owned IP, gets evaluated against `networkAcls`, and `defaultAction = "Deny"` rejects it unless the calling resource's ARM ID appears in `resourceAccessRules`.

---

## 2. What traffic does the trusted-bypass enable?

The Foundry agent service touches your BYO storage account on behalf of the project for several distinct operations. The `resourceAccessRules` entry permits these specific service-to-service calls:

| Foundry operation | Why it touches your storage |
|---|---|
| **File upload via the Files API** when a user attaches a file to an agent's Code Interpreter tool | The project capability host is configured with `storageConnections = ["storage-…"]`, so Foundry persists the uploaded file as a blob in your account rather than its own internal store |
| **File metadata / list / delete** via the Files API | Same blob lifecycle, on the same connection target |
| **Code Interpreter sandbox fetching the bound file** before execution | The sandbox in `snet-agents` *can* go via the PE, but the orchestration layer that hands the file reference to the sandbox runs in MS shared infrastructure and reads/streams the blob from there |
| **Agent service writing intermediate artifacts** (logs, sandbox outputs, run state) | Same connection target |
| **Thread/agent definitions metadata that has blob pointers** | Cosmos holds the row, but blob-typed columns dereference to your storage |

Without the trusted-bypass entries, the same auth posture that makes Foundry's MSI valid (RBAC) is moot — the network layer rejects the request before RBAC is ever evaluated. The visible symptom is a fast HTTP 500 with an empty response body returned to the user, *no transactions logged on the storage account during the failure window*, and no actionable error in Foundry's `RequestResponse` diagnostic logs other than the bare 500.

---

## 3. Will it expose anything you don't want?

This is the legitimate concern that follows from any "let traffic in" rule. The honest answer:

`resourceAccessRules` is **narrower than `bypass = "AzureServices"`** and much narrower than `publicNetworkAccess = "Enabled"`. It is not a public-internet opening. The storage account's evaluation order on each request is:

1. Did the request arrive via a private endpoint that this account owns? If yes → allow. If no → continue.
2. Does the request match a `bypass` category that the calling service belongs to? If yes → allow. If no → continue.
3. Does the request present a managed-identity token whose resource ID exactly matches an entry in `resourceAccessRules` (with the correct `tenantId`)? If yes → allow. If no → continue.
4. `defaultAction = "Deny"` rejects the request.

So the entry permits only this combination:

- Traffic from Microsoft-managed network, AND
- Authenticating with a managed-identity token, AND
- Where the token's source resource ID is exactly the listed Foundry account or project ARM ID, AND
- Where the token's tenant ID matches the listed `tenantId`.

A token from another tenant, from an unrelated Azure resource, or from anywhere on the public internet without a matching MSI still falls through to `defaultAction = "Deny"`. RBAC is then evaluated on the (now allowed-network) request — meaning the calling resource also has to have an explicit Storage role assignment to do anything useful. Network authorisation alone does not grant data access.

What you are *not* opening:

- The storage account is not reachable from public internet IPs.
- Other Azure subscriptions or tenants cannot use this rule.
- Other Microsoft services (e.g. someone else's Cognitive Services account in another tenant) cannot piggy-back on it.
- Even the Foundry account itself, if it loses its system-assigned identity, cannot reach storage via this rule — the rule is bound to the resource's identity, not the resource's name.

The narrower alternative would be to embed the runtime fully inside the customer VNet so that the PE handles all traffic. Foundry's nextgen agent service does VNet-inject the *runtime* via the account-level capability host's `customerSubnet` — but the *control-plane* services (Files API, agent orchestrator, managementfrontend) remain in Microsoft-managed network and require the trusted-bypass to interact with PE-only customer storage. That is a Foundry architecture choice, not a customer-side choice.

---

## 4. Where this is configured in the Terraform

The rules are declared inline on the storage account resources, so they exist from the moment the account is created (no window where the storage account is reachable but the rules are absent):

- **Core**: `modules/core/main.tf` — `azapi_resource.core_storage.body.properties.networkAcls.resourceAccessRules`. Lists the core Foundry account ARM ID and the admin project ARM ID.
- **Spoke (per-team)**: `modules/spoke-multi/main.tf` — `azapi_resource.agent_storage.body.properties.networkAcls.resourceAccessRules`. Lists the spoke Foundry account ARM ID plus every per-team project ARM ID, built dynamically from `var.teams`.

Both blocks coexist with the existing `bypass = "AzureServices"` setting. Microsoft services that already rely on the broader bypass (e.g. Defender for Cloud's StorageDataScanner) continue to work; the new entries simply add Foundry to the list of resources the storage account will accept service-to-service traffic from.

---

## 5. How to verify the rules are in place

After `terraform apply`:

```bash
az storage account show \
  -g <rg-name> -n <storage-name> \
  --query "networkRuleSet.resourceAccessRules" -o json
```

Expect to see one entry per Foundry account/project ARM ID listed in the Terraform, plus any entries Microsoft services have added themselves (e.g. Defender). Each entry has the correct `tenantId` matching `data.azurerm_client_config.current.tenant_id`.

If a Code Interpreter agent invocation fails with a fast HTTP 500 and zero transactions on the storage account during the failure window (`Transactions` metric, split by `ResponseType`, all zero), the most common cause is a missing or stale entry in `resourceAccessRules`. Re-running `terraform apply` reconciles drift; a manual entry can be added for triage with:

```bash
az storage account network-rule add \
  -g <rg-name> --account-name <storage-name> \
  --resource-id <foundry-account-or-project-arm-id> \
  --tenant-id <tenant-id>
```

…but anything added imperatively should be back-ported to Terraform to avoid drift on the next apply.
