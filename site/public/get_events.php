<?php
require_once(dirname(__DIR__) . '/config/site_config.php');
redirectIfLoggedOut('index.php');

require_once(SRC_DIR . '/events.php');
createEventsTableIfMissing($_DATABASE);

header('Content-Type: application/json');

$type_filter = isset($_GET['type']) ? $_GET['type'] : 'all';
$valid_types = ['all', 'sound', 'bad', 'good', 'bad_and_good', 'bad_or_good'];
if (!in_array($type_filter, $valid_types)) {
  $type_filter = 'all';
}

$limit = isset($_GET['limit']) ? intval($_GET['limit']) : 200;
$events = queryEvents($_DATABASE, $type_filter, $limit);
echo json_encode($events);
