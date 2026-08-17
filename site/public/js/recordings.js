var _AUTO_REFRESH_INTERVAL = null;
var _RECORDINGS = [];

// Markers closer together than this (in seconds) are merged into one range
var MARKER_MERGE_GAP = 15;

$(function () {
    setupClearButton();
    loadRecordings();

    $('#auto_refresh_switch').on('change', function () {
        if (this.checked) {
            _AUTO_REFRESH_INTERVAL = setInterval(loadRecordings, 15000);
        } else {
            clearInterval(_AUTO_REFRESH_INTERVAL);
            _AUTO_REFRESH_INTERVAL = null;
        }
    });

    $('#recordings_list').on('click', '.play-toggle-btn', function () {
        togglePlayer($(this).closest('.recording-item'));
    });

    $('#recordings_list').on('click', '.delete-recording-btn', function (e) {
        e.stopPropagation();
        var name = $(this).closest('.recording-item').data('name');
        confirmDeleteRecording(name);
    });

    $('#recordings_list').on('click', '.marker-chip, .marker-range', function (e) {
        e.stopPropagation();
        var $item = $(this).closest('.recording-item');
        var time = parseFloat($(this).data('time'));
        seekPlayer($item, time);
    });

    $('#recordings_list').on('click', '.marker-bar', function (e) {
        var $item = $(this).closest('.recording-item');
        var duration = parseFloat($item.data('duration'));
        var fraction = (e.pageX - $(this).offset().left) / $(this).width();
        seekPlayer($item, fraction * duration);
    });
});

function setupClearButton() {
    var _clear_trigger = {};
    connectModalToObject(
        _clear_trigger,
        {
            icon: 'trash',
            confirm: LANG['ok'],
            dismiss: LANG['cancel'],
            confirmOnclick: function () {
                $.post('clear_recordings.php', function () {
                    loadRecordings();
                });
            }
        },
        { text: LANG_SURE_CLEAR, showText: function () { return true; } }
    );
    $('#clear_btn').on('click', function () {
        _clear_trigger.triggerModal();
    });
}

function confirmDeleteRecording(name) {
    var _delete_trigger = {};
    connectModalToObject(
        _delete_trigger,
        {
            icon: 'trash',
            confirm: LANG['ok'],
            dismiss: LANG['cancel'],
            confirmOnclick: function () {
                $.post('delete_recording.php', { name: name }, function () {
                    loadRecordings();
                });
            }
        },
        { text: LANG_SURE_DELETE, showText: function () { return true; } }
    );
    _delete_trigger.triggerModal();
}

function loadRecordings() {
    $.getJSON('get_recordings.php', function (recordings) {
        _RECORDINGS = recordings || [];
        renderRecordings(_RECORDINGS);
    });
}

function renderRecordings(recordings) {
    var $list = $('#recordings_list');
    var playing = rememberPlayback($list);
    $list.empty();

    if (!recordings || recordings.length === 0) {
        $('#storage_info').text('');
        $list.html('<p class="text-center text-bm py-5">' + LANG_RECORDINGS_EMPTY + '</p>');
        return;
    }

    var totalSize = 0;
    recordings.forEach(function (r) { totalSize += r.size; });
    $('#storage_info').text(LANG_TOTAL_STORAGE + ': ' + formatSize(totalSize) + ' (' + recordings.length + ')');

    var todayStr    = formatDateKey(new Date());
    var yesterdayMs = new Date() - 86400000;
    var yestStr     = formatDateKey(new Date(yesterdayMs));

    var currentDay = null;

    recordings.forEach(function (rec) {
        var dt     = new Date(rec.start_time * 1000);
        var dayKey = formatDateKey(dt);

        if (dayKey !== currentDay) {
            currentDay = dayKey;
            var dayLabel;
            if (dayKey === todayStr)     dayLabel = LANG_TODAY;
            else if (dayKey === yestStr) dayLabel = LANG_YESTERDAY;
            else                         dayLabel = formatDay(dt);
            $list.append('<div class="day-header text-bm">' + escapeHtml(dayLabel) + '</div>');
        }

        $list.append(buildRecordingItem(rec, dt));
    });

    restorePlayback($list, playing);
}

function buildRecordingItem(rec, dt) {
    return rec.kind === 'video' ? buildVideoItem(rec, dt) : buildAudioItem(rec, dt);
}

function buildAudioItem(rec, dt) {
    var cryMarkers = rec.markers.filter(function (m) { return m.type === 'bad'; });
    var hasCry = cryMarkers.length > 0;
    var ranges = mergeMarkers(rec.markers);

    var mediaUrl = 'get_recording_media.php?name=' + encodeURIComponent(rec.name);
    var markerSummary = hasCry
        ? LANG_CRY_MARKERS.replace('{}', cryMarkers.length)
        : LANG_NO_CRY_MARKERS;

    return buildItemShell(rec, dt,
        {
            icon: hasCry ? 'emoji-frown-fill' : 'mic-fill',
            iconClass: hasCry ? ' has-cry' : '',
            metaExtra: ' · ' + escapeHtml(markerSummary)
        },
        '<audio controls preload="none">' +
            '<source src="' + mediaUrl + '" type="audio/wav">' +
        '</audio>' +
        buildMarkerBar(ranges, rec.duration) +
        buildMarkerChips(ranges));
}

function buildVideoItem(rec, dt) {
    var mediaUrl = 'get_recording_media.php?name=' + encodeURIComponent(rec.name);
    return buildItemShell(rec, dt,
        {
            icon: 'camera-video-fill',
            iconClass: ' is-video',
            metaExtra: ''
        },
        '<video controls preload="none" playsinline>' +
            '<source src="' + mediaUrl + '" type="video/mp2t">' +
        '</video>' +
        '<div class="mt-2">' +
            '<a class="btn btn-sm btn-outline-secondary" href="' + mediaUrl + '" download="' +
                escapeHtml(rec.name) + '.ts">' +
                '<svg class="bi me-1" style="width:1em;height:1em;" fill="currentColor">' +
                    '<use href="media/bootstrap-icons.svg#download"/></svg>' +
                LANG_DOWNLOAD +
            '</a>' +
            '<span class="recording-meta ms-2">' + escapeHtml(LANG_VIDEO_HINT) + '</span>' +
        '</div>');
}

function buildItemShell(rec, dt, opts, playerInner) {
    var startStr = formatTime(dt);
    var endStr   = formatTime(new Date((rec.start_time + rec.duration) * 1000));

    return (
        '<div class="recording-item" data-name="' + escapeHtml(rec.name) + '" data-duration="' + rec.duration + '">' +
            '<div class="recording-header">' +
                '<div class="recording-icon' + opts.iconClass + '">' +
                    '<svg fill="currentColor" class="bi"><use href="media/bootstrap-icons.svg#' + opts.icon + '"/></svg>' +
                '</div>' +
                '<div class="flex-grow-1">' +
                    '<div class="recording-label text-bm">' + escapeHtml(startStr) + ' – ' + escapeHtml(endStr) + '</div>' +
                    '<div class="recording-meta">' + escapeHtml(formatDuration(rec.duration)) + ' · ' +
                        escapeHtml(formatSize(rec.size)) + opts.metaExtra + '</div>' +
                '</div>' +
                '<button class="btn btn-sm btn-outline-primary play-toggle-btn">' +
                    '<svg class="bi" style="width:1em;height:1em;" fill="currentColor">' +
                        '<use href="media/bootstrap-icons.svg#play-fill"/></svg>' +
                '</button>' +
                '<button class="btn btn-sm btn-outline-danger delete-recording-btn">' +
                    '<svg class="bi" style="width:1em;height:1em;" fill="currentColor">' +
                        '<use href="media/bootstrap-icons.svg#trash"/></svg>' +
                '</button>' +
            '</div>' +
            '<div class="recording-player" style="display: none;">' + playerInner + '</div>' +
        '</div>');
}

function mergeMarkers(markers) {
    var ranges = [];
    markers.forEach(function (m) {
        var last = ranges[ranges.length - 1];
        if (last && last.type === m.type && m.time - last.end <= MARKER_MERGE_GAP) {
            last.end = m.time;
        } else {
            ranges.push({ start: m.time, end: m.time, type: m.type });
        }
    });
    return ranges;
}

function buildMarkerBar(ranges, duration) {
    if (duration <= 0) {
        return '';
    }
    var html = '<div class="marker-bar">';
    ranges.forEach(function (r) {
        var left  = Math.min(100, 100 * r.start / duration);
        var width = Math.max(0.5, 100 * (r.end - r.start) / duration);
        html += '<div class="marker-range' + (r.type === 'sound' ? ' marker-sound' : '') +
            '" style="left:' + left.toFixed(2) + '%;width:' + width.toFixed(2) + '%;" data-time="' +
            r.start + '"></div>';
    });
    html += '</div>';
    return html;
}

function buildMarkerChips(ranges) {
    if (ranges.length === 0) {
        return '';
    }
    var html = '<div class="marker-chips">';
    ranges.forEach(function (r) {
        var label = formatOffset(r.start);
        if (r.end - r.start >= 1) {
            label += '–' + formatOffset(r.end);
        }
        html += '<span class="marker-chip' + (r.type === 'sound' ? ' marker-sound' : '') +
            '" data-time="' + r.start + '">' + escapeHtml(label) + '</span>';
    });
    html += '</div>';
    return html;
}

function togglePlayer($item) {
    var $player = $item.find('.recording-player');
    if ($player.is(':visible')) {
        $player.hide();
        $player.find('audio, video')[0].pause();
    } else {
        $player.show();
        $player.find('audio, video')[0].play();
    }
}

function seekPlayer($item, time) {
    var $player = $item.find('.recording-player');
    $player.show();
    var audio = $player.find('audio, video')[0];
    var doSeek = function () {
        audio.currentTime = Math.max(0, time - 2);
        audio.play();
    };
    if (audio.readyState > 0) {
        doSeek();
    } else {
        $(audio).one('loadedmetadata', doSeek);
        audio.load();
    }
}

function rememberPlayback($list) {
    var playing = null;
    $list.find('audio, video').each(function () {
        if (!this.paused) {
            playing = {
                name: $(this).closest('.recording-item').data('name'),
                time: this.currentTime
            };
        }
    });
    return playing;
}

function restorePlayback($list, playing) {
    if (!playing) {
        return;
    }
    $list.find('.recording-item').each(function () {
        if ($(this).data('name') === playing.name) {
            seekPlayer($(this), playing.time + 2);
        }
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

function formatOffset(seconds) {
    var m = Math.floor(seconds / 60);
    var s = Math.floor(seconds % 60);
    return m + ':' + pad(s);
}

function formatDuration(seconds) {
    var m = Math.floor(seconds / 60);
    var s = Math.round(seconds % 60);
    return m > 0 ? (m + ' min ' + s + ' s') : (s + ' s');
}

function formatSize(bytes) {
    if (bytes >= 1e9) {
        return (bytes / 1e9).toFixed(2) + ' GB';
    } else if (bytes >= 1e6) {
        return (bytes / 1e6).toFixed(1) + ' MB';
    } else {
        return Math.round(bytes / 1e3) + ' kB';
    }
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
