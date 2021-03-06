#!/usr/bin/env bashio
WAIT_PIDS=()
TOKEN_VALID="$(python3 -c "import time; print((time.time() + 60 * 60 * 24 * 365 * 5) * 1000)")"

ha_config=$(\
    bashio::var.json \
        host "$(hostname)" \
        port "3001" \
)

almond_config=$(\
    bashio::var.json \
        kind "io.home-assistant" \
        hassUrl "http://hassio/homeassistant" \
        accessToken "${HASSIO_TOKEN}" \
        refreshToken "" \
        accessTokenExpires "^${TOKEN_VALID}" \
        isHassio "^true" \
)

# HA Discovery
if bashio::discovery "almond" "${ha_config}" > /dev/null; then
    bashio::log.info "Successfully send discovery information to Home Assistant."
else
    bashio::log.error "Discovery message to Home Assistant failed!"
fi

# Ingress handling
# shellcheck disable=SC2155
export THINGENGINE_BASE_URL=$(bashio::addon.ingress_entry)

# Setup nginx
nginx -c /etc/nginx/nginx.conf &
WAIT_PIDS+=($!)

# Skip Auth handling
if ! bashio::fs.file_exists "${THINGENGINE_HOME}/prefs.db"; then
    mkdir -p "${THINGENGINE_HOME}"
    echo '{"server-login":{"password":"x","salt":"x","sqliteKeySalt":"x"}}' > "${THINGENGINE_HOME}/prefs.db"
fi

# Start Almond
yarn start &
WAIT_PIDS+=($!)

# Insert HA connection settings
bashio::net.wait_for 3000
if curl -f -s -X POST -H "Content-Type: application/json" -d "${almond_config}" http://127.0.0.1:3000/api/devices/create; then
    bashio::log.info "Successfully register local Home Assistant on Almond"
else
    bashio::log.error "Almond registration of local Home Assistant fails!"
fi

# Register stop
function stop_addon() {
    echo "Kill Processes..."
    kill -15 "${WAIT_PIDS[@]}"
    wait "${WAIT_PIDS[@]}"
    echo "Done."
}
trap "stop_addon" SIGTERM SIGHUP

# Wait until all is done
wait "${WAIT_PIDS[@]}"
