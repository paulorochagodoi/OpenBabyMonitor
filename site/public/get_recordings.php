<?php
require_once(dirname(__DIR__) . '/config/site_config.php');
redirectIfLoggedOut('index.php');

require_once(SRC_DIR . '/recordings.php');

try {
  ensureRecordingSettingsColumns($_DATABASE);
} catch (Exception $e) {
  error_log("Warning: Could not ensure recording settings columns: " . $e->getMessage());
}

header('Content-Type: application/json');

try {
  echo json_encode(listRecordings());
} catch (Exception $e) {
  error_log("Error listing recordings: " . $e->getMessage());
  echo json_encode([]);
}
