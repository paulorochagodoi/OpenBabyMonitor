<?php
require_once(dirname(__DIR__) . '/config/site_config.php');
redirectIfLoggedOut('index.php');

require_once(SRC_DIR . '/events.php');

header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
  http_response_code(405);
  echo json_encode(['error' => 'Method not allowed']);
  exit;
}

try {
  createEventsTableIfMissing($_DATABASE);
  clearEvents($_DATABASE);
  echo json_encode(['success' => true]);
} catch (Exception $e) {
  error_log("Error clearing events: " . $e->getMessage());
  echo json_encode(['error' => 'Failed to clear events']);
}
