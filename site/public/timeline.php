<?php
require_once(dirname(__DIR__) . '/config/site_config.php');
redirectIfLoggedOut('index.php');
?>

<!DOCTYPE html>
<html>

<head>
  <?php require_once(TEMPLATES_DIR . '/head_common.php'); ?>
  <style>
    .timeline-container {
      max-width: 680px;
      margin: 0 auto;
    }
    .timeline-item {
      display: flex;
      align-items: flex-start;
      gap: 1rem;
      padding: 0.75rem 0;
      border-bottom: 1px solid rgba(128,128,128,0.15);
    }
    .timeline-item:last-child {
      border-bottom: none;
    }
    .timeline-icon {
      flex-shrink: 0;
      width: 2.2rem;
      height: 2.2rem;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .timeline-icon svg {
      width: 1.1rem;
      height: 1.1rem;
    }
    .icon-sound  { background-color: #6c757d22; color: #6c757d; }
    .icon-bad    { background-color: #dc354522; color: #dc3545; }
    .icon-good   { background-color: #19875422; color: #198754; }
    .icon-mixed  { background-color: #fd7e1422; color: #fd7e14; }
    .timeline-time {
      font-size: 0.78rem;
      opacity: 0.6;
      white-space: nowrap;
    }
    .timeline-label {
      font-weight: 500;
    }
    .day-header {
      font-size: 0.8rem;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.07em;
      opacity: 0.55;
      padding: 1rem 0 0.3rem;
    }
    .filter-btn.active {
      font-weight: 600;
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
      <div class="timeline-container">

        <div class="d-flex align-items-center justify-content-between mb-3 flex-wrap gap-2">
          <h5 class="mb-0 text-bm fw-bold"><?php echo LANG['timeline']; ?></h5>
          <div class="d-flex align-items-center gap-2 flex-wrap">
            <div class="form-check form-switch mb-0 d-flex align-items-center gap-2">
              <input class="form-check-input" type="checkbox" id="auto_refresh_switch" role="button">
              <label class="form-check-label text-bm" for="auto_refresh_switch"><?php echo LANG['auto_refresh']; ?></label>
            </div>
            <button id="clear_btn" class="btn btn-sm btn-outline-danger">
              <svg class="bi me-1" style="width:1em;height:1em;" fill="currentColor">
                <use href="media/bootstrap-icons.svg#trash" />
              </svg>
              <?php echo LANG['timeline_clear']; ?>
            </button>
          </div>
        </div>

        <div class="d-flex gap-2 flex-wrap mb-3" id="filter_bar">
          <button class="btn btn-sm btn-outline-secondary filter-btn active" data-type="all"><?php echo LANG['filter_all']; ?></button>
          <button class="btn btn-sm btn-outline-secondary filter-btn" data-type="sound"><?php echo LANG['filter_sound']; ?></button>
          <button class="btn btn-sm btn-outline-secondary filter-btn" data-type="bad"><?php echo LANG['filter_crying']; ?></button>
          <button class="btn btn-sm btn-outline-secondary filter-btn" data-type="good"><?php echo LANG['filter_babbling']; ?></button>
          <button class="btn btn-sm btn-outline-secondary filter-btn" data-type="mixed"><?php echo LANG['filter_mixed']; ?></button>
        </div>

        <div id="timeline_list">
          <div class="text-center py-5 text-bm" id="timeline_spinner">
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
    const LANG_TIMELINE_EMPTY  = <?php echo json_encode(LANG['timeline_empty']); ?>;
    const LANG_SURE_CLEAR      = <?php echo json_encode(LANG['sure_want_to_clear']); ?>;
    const LANG_TODAY           = <?php echo json_encode(LANG['today']); ?>;
    const LANG_YESTERDAY       = <?php echo json_encode(LANG['yesterday']); ?>;
    const EVENT_LABELS = {
      sound:           <?php echo json_encode(LANG['event_sound']); ?>,
      bad:             <?php echo json_encode(LANG['event_crying']); ?>,
      good:            <?php echo json_encode(LANG['event_babbling']); ?>,
      bad_and_good:    <?php echo json_encode(LANG['event_crying_and_babbling']); ?>,
      bad_or_good:     <?php echo json_encode(LANG['event_crying_or_babbling']); ?>
    };
    const ACCESS_POINT_ACTIVE = <?php echo ACCESS_POINT_ACTIVE ? 'true' : 'false'; ?>;
  </script>

  <script src="js/style.js"></script>
  <script src="js/navbar.js"></script>
  <script src="js/timeline.js"></script>
</body>

</html>
