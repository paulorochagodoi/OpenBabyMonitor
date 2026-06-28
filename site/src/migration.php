<?php
require_once(dirname(__DIR__) . '/config/config.php');
require_once(__DIR__ . '/database.php');

// Idempotently ensure a settings table defined in config.json exists and holds
// its single default row. This lets settings tables added after a device was
// first set up (e.g. whitenoise_settings) appear automatically on upgrade,
// without re-running the full database initialisation (which would drop the
// database and lose existing settings).
function ensureSettingsTableInitialized($database, $table_name) {
  createTableIfMissing($database, $table_name, readTableColumnsFromConfig($table_name));
  if (!tableHasEntries($database, $table_name)) {
    insertValuesIntoTable($database, $table_name, readTableInitialValuesFromConfig($table_name));
  }
}
