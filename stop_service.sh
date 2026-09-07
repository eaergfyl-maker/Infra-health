#!/bin/bash
# =============================================================
#  SABOTAGE 2 of 3  --  stop a service
#
#  This manages "demoweb", a tiny web server made from Python's
#  built-in http.server. Person A's reliability check looks for
#  exactly this service, so stopping it costs 15 points.
#
#  Usage:
#    sudo ./stop_service.sh setup   <- run ONCE, creates the service
#    sudo ./stop_service.sh stop    <- break it  (-15 points)
#    sudo ./stop_service.sh start   <- fix it
#    sudo ./stop_service.sh status  <- is it running?
#    sudo ./stop_service.sh remove  <- delete the service entirely
# =============================================================

SERVICE="demoweb"
WEBROOT="/var/tmp/demoweb"
PORT=8088
UNIT="/etc/systemd/system/${SERVICE}.service"

ACTION="$1"

case "$ACTION" in

  setup)
    echo "Creating the $SERVICE service ..."

    # A folder with one page in it, for the web server to serve
    mkdir -p "$WEBROOT"
    echo "<h1>Demo service is alive</h1>" > "$WEBROOT/index.html"
    chmod -R 755 "$WEBROOT"

    # Write a systemd unit file. This is what turns our little
    # Python web server into a real managed service.
    cat > "$UNIT" <<EOF
[Unit]
Description=Demo web service for the Infrastructure Health Score

[Service]
Type=simple
ExecStart=/usr/bin/python3 -m http.server $PORT --directory $WEBROOT
Restart=no

[Install]
WantedBy=multi-user.target
EOF

    # Tell systemd to re-read its config, then start the service
    systemctl daemon-reload
    systemctl enable --now "$SERVICE"

    echo ""
    systemctl is-active "$SERVICE"
    echo "Try it: curl http://localhost:$PORT"
    ;;

  stop)
    echo "Stopping $SERVICE ..."
    systemctl stop "$SERVICE"
    systemctl is-active "$SERVICE"
    echo "Done. Re-run the health checks to see the score drop."
    ;;

  start)
    echo "Starting $SERVICE ..."
    systemctl start "$SERVICE"
    systemctl is-active "$SERVICE"
    echo "Done. Re-run the checks to recover the points."
    ;;

  status)
    systemctl status "$SERVICE" --no-pager
    ;;

  remove)
    systemctl disable --now "$SERVICE" 2>/dev/null
    rm -f "$UNIT"
    rm -rf "$WEBROOT"
    systemctl daemon-reload
    echo "Removed the $SERVICE service."
    ;;

  *)
    echo "Usage: sudo $0 setup|stop|start|status|remove"
    exit 1
    ;;
esac
