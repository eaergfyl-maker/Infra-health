#!/bin/bash
# =============================================================
#  SABOTAGE 3 of 3  --  failed login attempts
#
#  Makes a handful of failed SSH logins appear in the logs, so
#  Person A's "no recent failed logins" check drops points.
#
#  It is safe: it tries to log in as a user that does not exist,
#  with no password, from this machine to itself. Nothing is
#  changed, no account is locked, no password is guessed.
#
#  Usage:
#    ./fake_failed_logins.sh          <- 6 attempts (default)
#    ./fake_failed_logins.sh 12       <- 12 attempts
#    ./fake_failed_logins.sh check    <- just count what's in the log
# =============================================================

FAKE_USER="healthdemo_baduser"
ATTEMPTS="${1:-6}"

# --- "check" mode: just show the current count ---
if [ "$1" = "check" ]; then
  echo "Failed login records in the last hour:"
  journalctl -u sshd --since "1 hour ago" --no-pager 2>/dev/null \
    | grep -E -c "Failed password|nvalid user|authentication failure"
  exit 0
fi

echo "Generating $ATTEMPTS failed login attempts as user '$FAKE_USER' ..."

# Can we do this for real? We need an ssh client and a running sshd.
if command -v ssh >/dev/null 2>&1 && systemctl is-active --quiet sshd; then

  i=1
  while [ "$i" -le "$ATTEMPTS" ]; do
    # BatchMode=yes means "never ask me for a password, just fail".
    # The connection is refused and sshd writes an "Invalid user" line.
    ssh -o BatchMode=yes \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=3 \
        "$FAKE_USER@127.0.0.1" exit >/dev/null 2>&1

    echo "  attempt $i ... rejected (as expected)"
    i=$((i + 1))
  done

else
  # Fallback: sshd or the ssh client is missing, so write the log
  # lines directly with "logger". They land in /var/log/secure.
  echo "  (sshd or ssh client not available - writing log lines instead)"

  i=1
  while [ "$i" -le "$ATTEMPTS" ]; do
    logger -t sshd -p authpriv.info \
      "Failed password for invalid user $FAKE_USER from 127.0.0.1 port 22 ssh2"
    echo "  attempt $i ... logged"
    i=$((i + 1))
  done
fi

echo ""
echo "Done. Re-run the health checks to see the score drop."
echo "Note: this check only looks at the last hour, so the points"
echo "come back on their own once the attempts age out."
