#!/bin/bash
# =============================================================
#  INFRASTRUCTURE HEALTH SCORE  --  PERSON A
#  Categories: Security (25 pts) + Reliability (25 pts)
#  Writes: partial_a.json
#
#  Run it like this:   sudo ./health_checks_a.sh
#  (sudo is needed because some security files are root-only)
# =============================================================


# -------------------------------------------------------------
# SETTINGS - you can change these, or override them when running
# -------------------------------------------------------------

# Which service must be running for the "Reliability" check.
# While building alone, test with:  sudo HEALTH_SERVICE=sshd ./health_checks_a.sh
SERVICE_NAME="${HEALTH_SERVICE:-demoweb}"

# Folder where we expect to find recent backups.
BACKUP_DIR="${HEALTH_BACKUP_DIR:-/var/backups/health-demo}"

# Name of the file we write our results into.
OUT_FILE="${HEALTH_OUT_A:-partial_a.json}"

# How far back to look for failed logins.
LOGIN_WINDOW="${HEALTH_LOGIN_WINDOW:-1 hour ago}"


# -------------------------------------------------------------
# HELPER: add_check
# Every check calls this once. It saves the result as a little
# JSON object and prints a human-readable line to the screen.
#
# Usage: add_check <category> <check name> <points> <max> <reason>
# -------------------------------------------------------------

RESULTS=""          # this string collects all the JSON objects

add_check() {
  CATEGORY="$1"
  NAME="$2"
  POINTS="$3"
  MAX="$4"
  # Strip characters that would break JSON (quotes, backslashes, newlines)
  REASON=$(printf "%s" "$5" | tr -d '"\\' | tr '\n' ' ')

  ONE="    {\"category\": \"$CATEGORY\", \"check\": \"$NAME\", \"points\": $POINTS, \"max_points\": $MAX, \"reason\": \"$REASON\"}"

  if [ -z "$RESULTS" ]; then
    RESULTS="$ONE"
  else
    RESULTS="$RESULTS,
$ONE"
  fi

  printf "  %-14s %-34s %2s/%-2s  %s\n" "[$CATEGORY]" "$NAME" "$POINTS" "$MAX" "$REASON"
}


# =============================================================
#  SECURITY CHECKS  (25 points total)
# =============================================================

# --- CHECK 1: is root allowed to log in over SSH? (10 points) ---
# Letting root log in over SSH directly is a classic security risk.
# We look for the "PermitRootLogin" line in the SSH server config.
check_ssh_root_login() {
  NAME="SSH root login disabled"

  if [ ! -r /etc/ssh/sshd_config ]; then
    add_check "Security" "$NAME" 0 10 "Cannot read sshd_config - run this script with sudo"
    return
  fi

  # Rocky Linux 9 can also keep settings in /etc/ssh/sshd_config.d/*.conf
  FILES="/etc/ssh/sshd_config"
  for EXTRA in /etc/ssh/sshd_config.d/*.conf; do
    if [ -r "$EXTRA" ]; then
      FILES="$FILES $EXTRA"
    fi
  done

  # Grab the last PermitRootLogin line, take the second word, lowercase it
  SETTING=$(grep -h -i "^[[:space:]]*PermitRootLogin" $FILES 2>/dev/null \
            | tail -n 1 | awk '{print $2}' | tr 'A-Z' 'a-z')

  if [ "$SETTING" = "no" ]; then
    add_check "Security" "$NAME" 10 10 "PermitRootLogin is set to no"
  elif [ "$SETTING" = "prohibit-password" ] || [ "$SETTING" = "without-password" ]; then
    add_check "Security" "$NAME" 5 10 "Root can still log in with an SSH key (PermitRootLogin $SETTING)"
  elif [ -z "$SETTING" ]; then
    add_check "Security" "$NAME" 0 10 "PermitRootLogin is not set, so the insecure default applies"
  else
    add_check "Security" "$NAME" 0 10 "PermitRootLogin is set to $SETTING"
  fi
}


# --- CHECK 2: is a firewall running? (10 points) ---
# systemctl is-active returns success (0) if the service is running.
check_firewall_active() {
  NAME="Firewall active"

  if systemctl is-active --quiet firewalld 2>/dev/null; then
    add_check "Security" "$NAME" 10 10 "firewalld is running"
  elif systemctl is-active --quiet nftables 2>/dev/null; then
    add_check "Security" "$NAME" 8 10 "nftables is running but firewalld is off"
  else
    add_check "Security" "$NAME" 0 10 "No firewall service is running"
  fi
}


# --- CHECK 3: recent failed login attempts (5 points) ---
# Lots of failed logins can mean someone is trying to guess a password.
check_failed_logins() {
  NAME="No recent failed logins"
  COUNT=0

  # First try the systemd journal (this is the normal place on Rocky Linux)
  if command -v journalctl >/dev/null 2>&1; then
    COUNT=$(journalctl -u sshd --since "$LOGIN_WINDOW" --no-pager 2>/dev/null \
            | grep -E -c "Failed password|nvalid user|authentication failure")
  fi

  # If the journal gave us nothing, fall back to the classic log file
  if [ -z "$COUNT" ] || [ "$COUNT" = "0" ]; then
    if [ -r /var/log/secure ]; then
      COUNT=$(tail -n 500 /var/log/secure 2>/dev/null \
              | grep -E -c "Failed password|nvalid user|authentication failure")
    fi
  fi

  [ -z "$COUNT" ] && COUNT=0

  if [ "$COUNT" -eq 0 ]; then
    add_check "Security" "$NAME" 5 5 "No failed login attempts found"
  elif [ "$COUNT" -le 5 ]; then
    add_check "Security" "$NAME" 3 5 "$COUNT failed login attempts found"
  else
    add_check "Security" "$NAME" 0 5 "$COUNT failed login attempts found - possible brute force"
  fi
}


# =============================================================
#  RELIABILITY CHECKS  (25 points total)
# =============================================================

# --- CHECK 4: is the important service running? (15 points) ---
check_service_running() {
  NAME="Service $SERVICE_NAME is running"

  # "systemctl cat" fails if the service does not exist at all
  if ! systemctl cat "$SERVICE_NAME" >/dev/null 2>&1; then
    add_check "Reliability" "$NAME" 0 15 "Service $SERVICE_NAME is not installed on this machine"
  elif systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    add_check "Reliability" "$NAME" 15 15 "$SERVICE_NAME is active"
  else
    add_check "Reliability" "$NAME" 0 15 "$SERVICE_NAME is installed but STOPPED"
  fi
}


# --- CHECK 5: do we have a recent backup? (10 points) ---
# "find -mtime -1" means "changed less than 1 day ago".
check_backup_recency() {
  NAME="Recent backup exists"

  if [ ! -d "$BACKUP_DIR" ]; then
    add_check "Reliability" "$NAME" 0 10 "Backup folder $BACKUP_DIR does not exist"
    return
  fi

  RECENT=$(find "$BACKUP_DIR" -type f -mtime -1 2>/dev/null | wc -l)
  ANY=$(find "$BACKUP_DIR" -type f 2>/dev/null | wc -l)

  if [ "$RECENT" -gt 0 ]; then
    add_check "Reliability" "$NAME" 10 10 "$RECENT backup file(s) from the last 24 hours"
  elif [ "$ANY" -gt 0 ]; then
    add_check "Reliability" "$NAME" 4 10 "Backups exist but the newest is older than 24 hours"
  else
    add_check "Reliability" "$NAME" 0 10 "Backup folder is empty"
  fi
}


# =============================================================
#  MAIN - run every check, then write the JSON file
# =============================================================

echo ""
echo "Person A: Security + Reliability checks"
echo "---------------------------------------------------------------"

check_ssh_root_login
check_firewall_active
check_failed_logins
check_service_running
check_backup_recency

echo "---------------------------------------------------------------"

HOST=$(hostname)
NOW=$(date -Iseconds)

# Write everything into partial_a.json
cat > "$OUT_FILE" <<EOF
{
  "person": "A",
  "hostname": "$HOST",
  "generated_at": "$NOW",
  "checks": [
$RESULTS
  ]
}
EOF

echo "Wrote $OUT_FILE"
echo ""
