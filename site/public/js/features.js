// Toggles an independent feature (white noise, night light, ...) on or off by
// starting/stopping its systemd service via toggle_feature.php. These features
// run alongside any monitoring mode, so they are controlled separately from the
// mode radio buttons.
function toggleFeature(feature, enabled) {
    var data = new URLSearchParams();
    data.append('feature', feature);
    data.append('enabled', enabled ? '1' : '0');

    return fetch('toggle_feature.php', {
        method: 'post',
        body: data
    })
        .then(response => response.text())
        .then(function (responseText) {
            if (typeof logoutIfSessionExpired === 'function') {
                logoutIfSessionExpired(responseText);
            }
        })
        .catch(function (error) {
            if (typeof triggerErrorEvent === 'function') {
                triggerErrorEvent(error);
            }
        });
}

$(function () {
    $('#whitenoise_feature_switch').on('change', function () {
        toggleFeature('whitenoise', this.checked);
    });
    $('#nightlight_feature_switch').on('change', function () {
        toggleFeature('nightlight', this.checked);
    });
    $('#features_container').show();
});
