<?php
require_once(dirname(__DIR__) . '/config/path_config.php');
require_once(SRC_DIR . '/session.php');
require_once(SRC_DIR . '/control.php');

if (!isLoggedIn()) {
  http_response_code(403);
  exit();
}

header('Content-Type: application/json');

if (!isset($_POST['disable'])) {
  http_response_code(400);
  echo json_encode(array('success' => false));
  exit();
}

$disable = ($_POST['disable'] === '1' || $_POST['disable'] === 1) ? '1' : '0';
$success = executeServerControlAction('set_status_leds', $disable);

echo json_encode(array('success' => $success, 'disabled' => $disable === '1'));
