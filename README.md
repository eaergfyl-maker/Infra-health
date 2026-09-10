# Infrastructure Health Score Dashboard

A Linux server health checker that scores your machine out of 100 and gives it a
video-game-style rank — S, A, B, C, or D, based on real checks across security,
reliability, resource usage, and maintenance hygiene.


Built in a 3-hour hackathon by 3 beginners, on Rocky Linux, with nothing but
bash, Python, and static HTML. No database, no Docker, no frameworks. 

**Team ICEMAN** : Abdul Rahman Bin Rahmatullah, Jayden Tan Jin Wei, Eashwar Singh Sidhu -
Built at the APU Red Hat Academy Hackathon

![Rank S example](https://img.shields.io/badge/rank-S-brightgreen)
![Bash](https://img.shields.io/badge/bash-checks-blue)
![Python](https://img.shields.io/badge/python-aggregator-blue)

---

## What it does

Most server health tooling means running ten different commands and knowing
what each one means. This project runs those checks automatically and turns
the result into one number and one letter, with a plain-English reason
attached to every point lost.

It checks 11 things across 4 categories:

| Category | Points | Checks |
|---|---|---|
| **Security** | 25 | SSH root login disabled, firewall active, recent failed logins |
| **Reliability** | 25 | Key service running, recent backup exists |
| **Resource Health** | 25 | Disk usage, memory usage, CPU load |
| **Maintenance** | 25 | Outdated packages, stale log files, zombie processes |

Score 90+ is rank **S**. Below 60 is rank **D**.

The project also ships three safe "sabotage" scripts that intentionally break
things. Fill a disk, stop a service, fake some failed logins, so you can
watch the score drop and recover live.

---

## Screenshot

Open `dashboard.html` in any browser (works straight from the file system, no
server required) to see a health bar, a category breakdown, and a list of
every reason points were lost.

---

## Quick start

```bash
git clone https://github.com/eaergfyl-maker/Infra-health.git
cd Infra-health
chmod +x *.sh

# Run the security + reliability checks
sudo ./health_checks_a.sh

# Run the resource + maintenance checks
sudo ./health_checks_b.sh

# Combine both into a final score
python3 aggregator.py

# View it
firefox dashboard.html &
```

Or run everything in one command:

```bash
sudo ./run_all.sh
```

### Requirements

Standard on any Rocky Linux install. If you're on a minimal image:

```bash
sudo dnf install -y openssh-server openssh-clients firewalld util-linux \
                     procps-ng findutils dnf-utils python3
```

---

## How it works

There's no backend server, no database, and no shared state. Three
independent scripts pass data through plain JSON files:

```
health_checks_a.sh  ──writes──>  partial_a.json  ──┐
                                                     ├──> aggregator.py ──> total_health.json
health_checks_b.sh  ──writes──>  partial_b.json  ──┘                            │
                                                                                 ▼
                                                                          dashboard.html
```

- **`health_checks_a.sh`** / **`health_checks_b.sh`** — bash scripts, each
  containing a handful of check functions. Every check runs a real Linux
  command, decides pass/fail, and awards points with a short reason. Each
  script writes its own JSON file.
- **`aggregator.py`** — reads both partial files, adds up the points, works
  out the rank, groups results by category, and writes the final report.
- **`dashboard.html`** — one static HTML file with plain JavaScript. Reads
  the final report and draws the health bar, category rows, and the "where
  the points went" list. No build step, no dependencies.

This was a deliberate constraint, not a limitation: three people could build
their piece independently, on separate machines, and everything joins on file
names alone. See [`INTEGRATION.md`](INTEGRATION.md) for the exact contract
between the parts.

---

## The sabotage scripts

Three scripts break things safely for a live demo, each with a way back:

| Script | What it breaks | Points lost | How to undo |
|---|---|---|---|
| `fill_disk.sh on` | Fills a 64 MB RAM disk to ~97% (your real disk is never touched) | 10 | `fill_disk.sh off` |
| `stop_service.sh stop` | Stops a small demo web service | 15 | `stop_service.sh start` |
| `fake_failed_logins.sh 8` | Triggers real, harmless rejected SSH logins | up to 5 | Ages out after 1 hour, same as a real log would |

```bash
sudo ./fill_disk.sh on
sudo ./stop_service.sh stop
./fake_failed_logins.sh 8
sudo ./run_all.sh          # watch the score fall

sudo ./fill_disk.sh off
sudo ./stop_service.sh start
sudo ./run_all.sh          # watch it recover
```

---

## Project structure

```
.
├── health_checks_a.sh       # Security + Reliability checks
├── health_checks_b.sh       # Resource Health + Maintenance checks
├── aggregator.py            # Combines both into a final score
├── dashboard.html           # Static dashboard, no server required
├── fill_disk.sh             # Sabotage: disk usage
├── stop_service.sh          # Sabotage: service uptime
├── fake_failed_logins.sh    # Sabotage: failed logins
├── run_all.sh                # Runs the whole pipeline in one command
├── INTEGRATION.md           # The shared contract + demo script
├── OVERVIEW.md               # Plain-English project walkthrough
└── README_A.md / README_B.md / README_C.md   # Per-person build notes
```

---

## Why no database, no Docker, no framework

This was built to a specific constraint: 3 beginners, 3 laptops, 3 hours. Every
dependency is something that can fail to install, need configuring, or cause a
merge conflict between teammates working at the same time. Bash, Python's
standard library, and one HTML file need none of that, anyone can clone this
repo and see it working with two commands and a browser.

---

## License

Built for a hackathon. Use it, fork it, adapt it.

## Team 

Built by team ICEMAN at
