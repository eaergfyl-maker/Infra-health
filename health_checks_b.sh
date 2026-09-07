#!/bin/bash
# =============================================================
#  INFRASTRUCTURE HEALTH SCORE  --  PERSON B
#  Categories: Resource Health (25 pts) + Maintenance (25 pts)
#  Writes: partial_b.json
#
#  Run it like this:   sudo ./health_checks_b.sh
#  Skip the slow package check:  sudo SKIP_UPDATES=yes ./health_checks_b.sh
# =============================================================


# -------------------------------------------------------------
# SETTINGS
# -------------------------------------------------------------

OUT_FILE="${HEALTH_OUT_B:-partial_b.json}"

# The demo disk that Person C's fill_disk.sh mounts. If it exists,
# we include it in the disk check so the sabotage demo works.
DEMO_DISK="/mnt/health-demo-disk"

# Set SKIP_UPDATES=yes to skip the "dnf check-update" check (it needs
# the internet and can take 10-30 seconds).
SKIP_UPDATES="${SKIP_UPDATES:-no}"


# -------------------------------------------------------------
# HELPER: add_check  (identical to Person A's - same JSON format)
# -------------------------------------------------------------

RESULTS=""

add_check() {
  CATEGORY="$1"
  NAME="$2"
  POINTS="$3"
  MAX="$4"
  REASON=$(printf "%s" "$5" | tr -d '"\\' | tr '\n' ' ')

  ONE="    {\"category\": \"$CATEGORY\", \"check\": \"$NAME\", \"points\": $POINTS, \"max_points\": $MAX, \"reason\": \"$REASON\"}"

  if [ -z "$RESULTS" ]; then
    RESULTS="$ONE"
  else
    RESULTS="$RESULTS,
$ONE"
  fi

  printf "  %-18s %-32s %2s/%-2s  %s\n" "[$CATEGORY]" "$NAME" "$POINTS" "$MAX" "$REASON"
}


# =============================================================
#  RESOURCE HEALTH CHECKS  (25 points total)
# =============================================================

# --- CHECK 1: disk usage (10 points) ---
# "df -P /" prints usage for the main filesystem. Column 5 is the
# percentage, e.g. "42%", so we strip the % sign to get a number.
check_disk_usage() {
  NAME="Disk usage under control"

  WORST=$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')
  WHERE="/"

  # If the demo disk is mounted, use whichever filesystem is fuller
  if mountpoint -q "$DEMO_DISK" 2>/dev/null; then
    DEMO_PCT=$(df -P "$DEMO_DISK" | awk 'NR==2 {gsub("%","",$5); print $5}')
    if [ "$DEMO_PCT" -gt "$WORST" ]; then
      WORST="$DEMO_PCT"
      WHERE="$DEMO_DISK"
    fi
  fi

  if [ "$WORST" -lt 80 ]; then
    add_check "Resource Health" "$NAME" 10 10 "$WHERE is $WORST% full"
  elif [ "$WORST" -lt 90 ]; then
    add_check "Resource Health" "$NAME" 5 10 "$WHERE is $WORST% full - getting tight"
  else
    add_check "Resource Health" "$NAME" 0 10 "$WHERE is $WORST% full - almost out of space"
  fi
}


# --- CHECK 2: memory usage (8 points) ---
# In "free", column 2 is total and column 7 is available memory.
# used% = (total - available) / total * 100
check_memory_usage() {
  NAME="Memory usage under control"

  MEM_PCT=$(free | awk '/^Mem:/ {printf "%d", ($2-$7)/$2*100}')

  if [ "$MEM_PCT" -lt 75 ]; then
    add_check "Resource Health" "$NAME" 8 8 "$MEM_PCT% of memory in use"
  elif [ "$MEM_PCT" -lt 90 ]; then
    add_check "Resource Health" "$NAME" 4 8 "$MEM_PCT% of memory in use"
  else
    add_check "Resource Health" "$NAME" 0 8 "$MEM_PCT% of memory in use - server may start swapping"
  fi
}


# --- CHECK 3: CPU load (7 points) ---
# /proc/loadavg holds the 1-minute load average. A load equal to the
# number of CPU cores means the machine is exactly 100% busy, so we
# compare load against core count.
check_cpu_load() {
  NAME="CPU load under control"

  LOAD=$(awk '{print $1}' /proc/loadavg)
  CORES=$(nproc)
  # awk does the decimal maths for us and gives back a whole number
  LOAD_PCT=$(awk -v l="$LOAD" -v c="$CORES" 'BEGIN {printf "%d", (l/c)*100}')

  if [ "$LOAD_PCT" -lt 70 ]; then
    add_check "Resource Health" "$NAME" 7 7 "Load $LOAD across $CORES cores ($LOAD_PCT%)"
  elif [ "$LOAD_PCT" -lt 150 ]; then
    add_check "Resource Health" "$NAME" 4 7 "Load $LOAD across $CORES cores ($LOAD_PCT%) - busy"
  else
    add_check "Resource Health" "$NAME" 0 7 "Load $LOAD across $CORES cores ($LOAD_PCT%) - overloaded"
  fi
}


# =============================================================
#  MAINTENANCE / HYGIENE CHECKS  (25 points total)
# =============================================================

# --- CHECK 4: how many packages need updating? (10 points) ---
# "dnf check-update" lists packages that have a newer version.
check_outdated_packages() {
  NAME="Packages up to date"

  if [ "$SKIP_UPDATES" = "yes" ]; then
    add_check "Maintenance" "$NAME" 10 10 "Skipped by request (SKIP_UPDATES=yes)"
    return
  fi

  # Each updatable package is one line starting with a letter or number
  COUNT=$(dnf -q check-update 2>/dev/null | grep -E "^[a-zA-Z0-9]" | grep -v "^Obsoleting" | wc -l)
  [ -z "$COUNT" ] && COUNT=0

  if [ "$COUNT" -eq 0 ]; then
    add_check "Maintenance" "$NAME" 10 10 "No pending package updates"
  elif [ "$COUNT" -le 10 ]; then
    add_check "Maintenance" "$NAME" 6 10 "$COUNT packages can be updated"
  elif [ "$COUNT" -le 50 ]; then
    add_check "Maintenance" "$NAME" 3 10 "$COUNT packages can be updated"
  else
    add_check "Maintenance" "$NAME" 0 10 "$COUNT packages can be updated - system is well behind"
  fi
}


# --- CHECK 5: stale log files (8 points) ---
# "find -mtime +30" means "not touched in more than 30 days".
# Old logs piling up means log rotation is not doing its job.
check_stale_logs() {
  NAME="No stale log files"

  COUNT=$(find /var/log -type f -mtime +30 2>/dev/null | wc -l)

  if [ "$COUNT" -eq 0 ]; then
    add_check "Maintenance" "$NAME" 8 8 "No log files older than 30 days"
  elif [ "$COUNT" -le 10 ]; then
    add_check "Maintenance" "$NAME" 5 8 "$COUNT log files older than 30 days"
  else
    add_check "Maintenance" "$NAME" 0 8 "$COUNT log files older than 30 days - check logrotate"
  fi
}


# --- CHECK 6: zombie processes (7 points) ---
# A zombie process has finished but its parent never collected it.
# In "ps", the STAT column starts with Z for zombies.
check_zombie_processes() {
  NAME="No zombie processes"

  COUNT=$(ps -eo stat= 2>/dev/null | grep -c "^Z")
  [ -z "$COUNT" ] && COUNT=0

  if [ "$COUNT" -eq 0 ]; then
    add_check "Maintenance" "$NAME" 7 7 "No zombie processes"
  elif [ "$COUNT" -le 3 ]; then
    add_check "Maintenance" "$NAME" 4 7 "$COUNT zombie processes"
  else
    add_check "Maintenance" "$NAME" 0 7 "$COUNT zombie processes - a parent process is misbehaving"
  fi
}


# =============================================================
#  MAIN
# =============================================================

echo ""
echo "Person B: Resource Health + Maintenance checks"
echo "---------------------------------------------------------------"

check_disk_usage
check_memory_usage
check_cpu_load
check_outdated_packages
check_stale_logs
check_zombie_processes

echo "---------------------------------------------------------------"

HOST=$(hostname)
NOW=$(date -Iseconds)

cat > "$OUT_FILE" <<EOF
{
  "person": "B",
  "hostname": "$HOST",
  "generated_at": "$NOW",
  "checks": [
$RESULTS
  ]
}
EOF

echo "Wrote $OUT_FILE"
echo ""
