<?php
require_once(dirname(__DIR__) . '/config/error_config.php');
require_once(__DIR__ . '/database.php');

function createEventsTableIfMissing($database) {
  $result = $database->query(
    "CREATE TABLE IF NOT EXISTS `events` (
      `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      `type` VARCHAR(20) NOT NULL,
      `recorded_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    );"
  );
  if (!$result) {
    throw new Exception("Could not create events table: " . $database->error);
  }
}

function insertEvent($database, $type) {
  $escaped = $database->real_escape_string($type);
  $result = $database->query("INSERT INTO `events` (`type`) VALUES ('$escaped')");
  if (!$result) {
    bm_error("Could not insert event: " . $database->error);
  }
}

function queryEvents($database, $type_filter = 'all', $limit = 200) {
  $where = '';
  if ($type_filter !== 'all') {
    $escaped = $database->real_escape_string($type_filter);
    $where = "WHERE `type` = '$escaped'";
  }
  $limit = max(1, min(1000, intval($limit)));
  $result = $database->query(
    "SELECT `id`, `type`, `recorded_at` FROM `events` $where ORDER BY `recorded_at` DESC LIMIT $limit"
  );
  if (!$result) {
    throw new Exception("Could not query events: " . $database->error);
  }
  return $result->fetch_all(MYSQLI_ASSOC);
}

function clearEvents($database) {
  if (!$database->query("DELETE FROM `events`")) {
    throw new Exception("Could not clear events: " . $database->error);
  }
}
