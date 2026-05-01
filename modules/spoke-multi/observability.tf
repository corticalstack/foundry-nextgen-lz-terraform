# =============================================================================
# OBSERVABILITY — diagnostic settings for spoke account and agent storage
# Both target the shared Log Analytics workspace passed in from the env via
# var.log_analytics_workspace_id (sourced from module.core).
# =============================================================================

resource "azurerm_monitor_diagnostic_setting" "spoke_account" {
  name                       = "diag-${local.spoke_account_name}"
  target_resource_id         = azapi_resource.spoke_account.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ---------------------------------------------------------------------------
# Storage blob diagnostics — only in private-networking mode (agent_storage
# is gated on that flag). Captures StorageRead/Write/Delete and Transaction
# metrics. Critical for diagnosing agent-runtime → storage failures.
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "agent_storage_blob" {
  count = var.enable_private_networking ? 1 : 0

  name                       = "diag-${local.agent_storage_name}-blob"
  target_resource_id         = "${azapi_resource.agent_storage[0].id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

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
