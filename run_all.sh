#!/bin/bash
# =============================================================
#  Runs the whole pipeline in one go.
#  Usage:  sudo ./run_all.sh
# =============================================================

# Work in the folder this script lives in, so all the JSON files
# land next to dashboard.html.
cd "$(dirname "$0")" || exit 1

echo "Step 1 of 3: Person A's checks"
HEALTH_SERVICE=demoweb ./health_checks_a.sh

echo "Step 2 of 3: Person B's checks"
SKIP_UPDATES="${SKIP_UPDATES:-no}" ./health_checks_b.sh

echo "Step 3 of 3: combining the scores"
python3 aggregator.py
