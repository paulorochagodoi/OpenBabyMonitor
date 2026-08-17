<?php
require_once(dirname(__DIR__) . '/config/site_config.php');
redirectIfLoggedOut('index.php');

require_once(SRC_DIR . '/recordings.php');

header('Content-Type: application/json');

try {
  clearRecordings();
  echo json_encode(array('success' => true));
} catch (Exception $e) {
  error_log("Error clearing recordings: " . $e->getMessage());
  echo json_encode(array('success' => false));
}
