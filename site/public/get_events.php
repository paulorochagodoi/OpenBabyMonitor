<?php
require_once(dirname(__DIR__) . '/config/site_config.php');
redirectIfLoggedOut('index.php');

require_once(SRC_DIR . '/events.php');

// Don't fail entirely if table creation has issues - just log and continue
try {
  createEventsTableIfMissing($_DATABASE);
} catch (Exception $e) {
  error_log("Warning: Could not create events table: " . $e->getMessage());
}

header('Content-Type: application/json');

$type_filter = isset($_GET['type']) ? $_GET['type'] : 'all';
$valid_types = ['all', 'sound', 'bad', 'good', 'bad_and_good', 'bad_or_good'];
if (!in_array($type_filter, $valid_types)) {
  $type_filter = 'all';
}

$limit = isset($_GET['limit']) ? intval($_GET['limit']) : 200;

try {
  $events = queryEvents($_DATABASE, $type_filter, $limit);
  echo json_encode($events);
} catch (Exception $e) {
  error_log("Error querying events: " . $e->getMessage());
  echo json_encode([]);
}
