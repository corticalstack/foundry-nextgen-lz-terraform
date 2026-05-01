# =============================================================================
# OBSERVABILITY — shared Log Analytics workspace + diagnostic settings
# Always created (independent of enable_private_networking).
# Storage diag setting is gated because core_storage only exists in private
# networking mode.
# =============================================================================

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-core-${var.customer}-${local.subscription_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  # Match the LZ-wide posture of disabling shared-key/local auth.
  local_authentication_disabled = true

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Foundry account diagnostics — captures RequestResponse, Audit,
# AzureOpenAIRequestUsage, Trace under the "allLogs" category group.
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "core_account" {
  name                       = "diag-${local.core_account_name}"
  target_resource_id         = azapi_resource.core_account.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "research_account" {
  name                       = "diag-${local.research_account_name}"
  target_resource_id         = azurerm_cognitive_account.research.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ---------------------------------------------------------------------------
# Storage blob diagnostics — only in private-networking mode (core_storage
# is gated on that flag). Captures StorageRead/Write/Delete and Transaction
# metrics. Critical for diagnosing agent-runtime → storage failures.
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "core_storage_blob" {
  count = var.enable_private_networking ? 1 : 0

  name                       = "diag-${local.core_storage_name}-blob"
  target_resource_id         = "${azapi_resource.core_storage[0].id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }

  metric {
    category = "Transaction"
    enabled  = true
  }
}
