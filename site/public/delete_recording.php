<?php
require_once(dirname(__DIR__) . '/config/site_config.php');
redirectIfLoggedOut('index.php');

require_once(SRC_DIR . '/recordings.php');

header('Content-Type: application/json');

if (!isset($_POST['name']) || !isValidRecordingName($_POST['name'])) {
  http_response_code(400);
  echo json_encode(array('success' => false));
  exit();
}

echo json_encode(array('success' => deleteRecording($_POST['name'])));
