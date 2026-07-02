<?php
require_once(dirname(__DIR__) . '/config/site_config.php');
redirectIfLoggedOut('index.php');

require_once(SRC_DIR . '/recordings.php');
try {
  ensureRecordingSettingsColumns($_DATABASE);
} catch (Exception $e) {
  error_log("Warning: Could not ensure recording settings columns: " . $e->getMessage());
}
?>

<!DOCTYPE html>
<html>

<head>
  <?php require_once(TEMPLATES_DIR . '/head_common.php'); ?>
  <style>
    .recordings-container {
      max-width: 680px;
      margin: 0 auto;
    }
    .recording-item {
      padding: 0.75rem 0;
      border-bottom: 1px solid rgba(128,128,128,0.15);
    }
    .recording-item:last-child {
      border-bottom: none;
    }
    .recording-header {
      display: flex;
      align-items: center;
      gap: 1rem;
    }
    .recording-icon {
      flex-shrink: 0;
      width: 2.2rem;
      height: 2.2rem;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      background-color: #0d6efd22;
      color: #0d6efd;
    }
    .recording-icon.has-cry {
      background-color: #dc354522;
      color: #dc3545;
    }
    .recording-icon.is-video {
      background-color: #6f42c122;
      color: #6f42c1;
    }
    .recording-icon svg {
      width: 1.1rem;
      height: 1.1rem;
    }
    .recording-player video {
      width: 100%;
      max-height: 60vh;
      border-radius: 0.3rem;
      background: #000;
    }
    .recording-meta {
      font-size: 0.78rem;
      opacity: 0.6;
      white-space: nowrap;
    }
    .recording-label {
      font-weight: 500;
    }
    .recording-player {
      margin-top: 0.6rem;
    }
    .recording-player audio {
      width: 100%;
      height: 2.4rem;
    }
    .marker-bar {
      position: relative;
      height: 0.55rem;
      border-radius: 0.3rem;
      background-color: rgba(128,128,128,0.18);
      margin: 0.45rem 0.2rem 0.2rem;
      cursor: pointer;
    }
    .marker-range {
      position: absolute;
      top: 0;
      height: 100%;
      min-width: 4px;
      border-radius: 0.3rem;
      background-color: #dc3545;
      opacity: 0.85;
    }
    .marker-range.marker-sound {
      background-color: #6c757d;
    }
    .marker-chips {
      margin-top: 0.4rem;
      display: flex;
      flex-wrap: wrap;
      gap: 0.3rem;
    }
    .marker-chip {
      font-size: 0.72rem;
      padding: 0.1rem 0.5rem;
      border-radius: 1rem;
      background-color: #dc354522;
      color: #dc3545;
      cursor: pointer;
      white-space: nowrap;
    }
    .marker-chip.marker-sound {
      background-color: #6c757d22;
      color: #6c757d;
    }
    .day-header {
      font-size: 0.8rem;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.07em;
      opacity: 0.55;
      padding: 1rem 0 0.3rem;
    }
    .storage-info {
      font-size: 0.8rem;
      opacity: 0.65;
    }
  </style>
</head>

<body>
  <div class="d-flex flex-column min-vh-100">
    <header>
      <?php
      require_once(TEMPLATES_DIR . '/navbar.php');
      require_once(TEMPLATES_DIR . '/confirmation_modal.php');
      ?>
    </header>

    <main class="flex-grow-1 py-4 px-3">
      <div class="recordings-container">

        <div class="d-flex align-items-center justify-content-between mb-1 flex-wrap gap-2">
          <h5 class="mb-0 text-bm fw-bold"><?php echo LANG['recordings']; ?></h5>
          <div class="d-flex align-items-center gap-2 flex-wrap">
            <div class="form-check form-switch mb-0 d-flex align-items-center gap-2">
              <input class="form-check-input" type="checkbox" id="auto_refresh_switch" role="button">
              <label class="form-check-label text-bm" for="auto_refresh_switch"><?php echo LANG['auto_refresh']; ?></label>
            </div>
            <button id="clear_btn" class="btn btn-sm btn-outline-danger">
              <svg class="bi me-1" style="width:1em;height:1em;" fill="currentColor">
                <use href="media/bootstrap-icons.svg#trash" />
              </svg>
              <?php echo LANG['recordings_clear']; ?>
            </button>
          </div>
        </div>

        <div id="storage_info" class="storage-info text-bm mb-3"></div>

        <div id="recordings_list">
          <div class="text-center py-5 text-bm" id="recordings_spinner">
            <span class="spinner-border"></span>
          </div>
        </div>

      </div>
    </main>
  </div>

  <?php
  require_once(TEMPLATES_DIR . '/bootstrap_js.php');
  require_once(TEMPLATES_DIR . '/jquery_js.php');
  require_once(TEMPLATES_DIR . '/js-cookie_js.php');
  ?>

  <script src="js/confirmation_modal.js"></script>

  <?php
  require_once(TEMPLATES_DIR . '/notifications_js.php');
  require_once(TEMPLATES_DIR . '/monitoring_js.php');
  ?>

  <script>
    const LANG_RECORDINGS_EMPTY = <?php echo json_encode(LANG['recordings_empty']); ?>;
    const LANG_SURE_CLEAR       = <?php echo json_encode(LANG['sure_want_to_clear_recordings']); ?>;
    const LANG_SURE_DELETE      = <?php echo json_encode(LANG['sure_want_to_delete_recording']); ?>;
    const LANG_TODAY            = <?php echo json_encode(LANG['today']); ?>;
    const LANG_YESTERDAY        = <?php echo json_encode(LANG['yesterday']); ?>;
    const LANG_CRY_MARKERS      = <?php echo json_encode(LANG['cry_markers']); ?>;
    const LANG_NO_CRY_MARKERS   = <?php echo json_encode(LANG['no_cry_markers']); ?>;
    const LANG_TOTAL_STORAGE    = <?php echo json_encode(LANG['total_storage']); ?>;
    const LANG_DOWNLOAD         = <?php echo json_encode(LANG['download']); ?>;
    const LANG_VIDEO_HINT       = <?php echo json_encode(LANG['video_playback_hint']); ?>;
    const ACCESS_POINT_ACTIVE = <?php echo ACCESS_POINT_ACTIVE ? 'true' : 'false'; ?>;
  </script>

  <script src="js/style.js"></script>
  <script src="js/navbar.js"></script>
  <script src="js/recordings.js"></script>
</body>

</html>
