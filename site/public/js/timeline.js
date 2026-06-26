const ICON_MAP = {
    sound:        { icon: 'volume-up-fill',       cls: 'icon-sound' },
    bad:          { icon: 'emoji-frown-fill',      cls: 'icon-bad'   },
    good:         { icon: 'emoji-smile-fill',      cls: 'icon-good'  },
    bad_and_good: { icon: 'emoji-neutral-fill',    cls: 'icon-mixed' },
    bad_or_good:  { icon: 'question-circle-fill',  cls: 'icon-mixed' }
};

var _CURRENT_FILTER = 'all';
var _AUTO_REFRESH_INTERVAL = null;

$(function () {
    setupClearButton();
    setupFilters();
    loadEvents();

    $('#auto_refresh_switch').on('change', function () {
        if (this.checked) {
            _AUTO_REFRESH_INTERVAL = setInterval(loadEvents, 10000);
        } else {
            clearInterval(_AUTO_REFRESH_INTERVAL);
            _AUTO_REFRESH_INTERVAL = null;
        }
    });
});

function setupFilters() {
    $('#filter_bar').on('click', '.filter-btn', function () {
        $('#filter_bar .filter-btn').removeClass('active');
        $(this).addClass('active');
        _CURRENT_FILTER = $(this).data('type');
        loadEvents();
    });
}

function setupClearButton() {
    var _clear_trigger = {};
    connectModalToObject(
        _clear_trigger,
        {
            icon: 'trash',
            confirm: LANG['ok'],
            dismiss: LANG['cancel'],
            confirmOnclick: function () {
                $.post('clear_events.php', function () {
                    loadEvents();
                });
            }
        },
        { text: LANG_SURE_CLEAR, showText: function () { return true; } }
    );
    $('#clear_btn').on('click', function () {
        _clear_trigger.triggerModal();
    });
}

function loadEvents() {
    var apiType = _CURRENT_FILTER;
    if (apiType === 'mixed') {
        apiType = 'all';
    }
    $.getJSON('get_events.php', { type: apiType }, function (events) {
        if (_CURRENT_FILTER === 'mixed') {
            events = events.filter(function (e) {
                return e.type === 'bad_and_good' || e.type === 'bad_or_good';
            });
        }
        renderEvents(events);
    });
}

function renderEvents(events) {
    var $list = $('#timeline_list');
    $list.empty();

    if (!events || events.length === 0) {
        $list.html('<p class="text-center text-bm py-5">' + LANG_TIMELINE_EMPTY + '</p>');
        return;
    }

    var todayStr    = formatDateKey(new Date());
    var yesterdayMs = new Date() - 86400000;
    var yestStr     = formatDateKey(new Date(yesterdayMs));

    var currentDay = null;

    events.forEach(function (ev) {
        var dt      = new Date(ev.recorded_at.replace(' ', 'T'));
        var dayKey  = formatDateKey(dt);

        if (dayKey !== currentDay) {
            currentDay = dayKey;
            var dayLabel;
            if (dayKey === todayStr)    dayLabel = LANG_TODAY;
            else if (dayKey === yestStr) dayLabel = LANG_YESTERDAY;
            else                         dayLabel = formatDay(dt);
            $list.append('<div class="day-header text-bm">' + escapeHtml(dayLabel) + '</div>');
        }

        var info    = ICON_MAP[ev.type] || { icon: 'bell-fill', cls: 'icon-sound' };
        var label   = EVENT_LABELS[ev.type] || ev.type;
        var timeStr = formatTime(dt);

        var html =
            '<div class="timeline-item">' +
                '<div class="timeline-icon ' + info.cls + '">' +
                    '<svg fill="currentColor" class="bi"><use href="media/bootstrap-icons.svg#' + info.icon + '"/></svg>' +
                '</div>' +
                '<div class="flex-grow-1">' +
                    '<div class="timeline-label text-bm">' + escapeHtml(label) + '</div>' +
                    '<div class="timeline-time">' + escapeHtml(timeStr) + '</div>' +
                '</div>' +
            '</div>';
        $list.append(html);
    });
}

function formatDateKey(d) {
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
}

function formatDay(d) {
    return d.toLocaleDateString(undefined, { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
}

function formatTime(d) {
    return pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds());
}

function pad(n) {
    return n < 10 ? '0' + n : '' + n;
}

function escapeHtml(s) {
    return String(s)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}
