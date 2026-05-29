---
name: hermes-a2a-cron-agent-maintainer
description: Complete guide to setting up and maintaining a Hermes cron-driven A2A agent team system. Covers architecture, spawning, state management, root permission workarounds, model policies, and all gotchas discovered in production.
trigger: /hermes-a2a-setup
---

# Hermes A2A Cron Agent Maintainer

This skill documents the end-to-end setup and maintenance of a **Hermes cron → A2A bus → agent team** hardening system. It was built and refined on **rbm4** (Proxmox VM, root user) and covers every pitfall discovered in production.

## Architecture Overview

```
┌──────────────┐
│  Hermes Cron │  every 30min → LLM agent reads a2a-cheatsheet skill
│  Gateway     │  systemd service, auto-fires ticks
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────┐
│  Cron LLM Agent (orchestrator)   │  plans, spawns, monitors, cleans up
│  Reads state, picks project,     │
│  writes kit prompts, spawns team │
└──────────────┬───────────────────┘
       │
       ▼
┌──────────────────────────────────┐
│  a2a-spawn (2 agents)            │
│  ┌──────────┐  ┌──────────────┐ │
│  │ builder  │  │ reviewer     │ │
│  │ (sonnet) │  │ (haiku)     │ │
│  └────┬─────┘  └──────┬───────┘ │
│       │               │         │
│       ▼               ▼         │
│  ┌──────────────────────────┐   │
│  │  A2A SQLite Bus          │   │
│  │  ~/.a2a/{project}/db.db  │   │
│  │  recv → claim → work →   │   │
│  │  commit → broadcast      │   │
│  └──────────────────────────┘   │
└──────────────────────────────────┘
       │
       ▼
  git commit → git push → rotate project
```

## Prerequisites

| Component | Required | Notes |
|---|---|---|
| Hermes CLI | Yes | Must support `cronjob` tool and gateway |
| a2a-skill | Yes | Clone from `github.com/javimosch/a2a-skill` ([repo](https://github.com/javimosch/a2a-skill)) |
| Agent CLIs | 1+ | claude code, opencode, or pi |
| Git | Yes | For repos to harden |
| systemd | Yes (or equivalent) | For Hermes gateway daemon |

**Recommended:** [supercli](https://github.com/javimosch/supercli) (`sc`)
— a plugin system that brings superpowers for A2A teams. It provides:
- Plugin discovery, install, and lifecycle management
- Agent skill management (`sc skills teach`, `sc skills search`)
- CLI integration with a2a workflows
- See [AGENTS.md](https://github.com/javimosch/supercli/blob/master/AGENTS.md) for agent usage instructions

## Setup Steps

### 1. Install Hermes Gateway (for cron scheduling)

```bash
# Check status first
hermes cron status

# If gateway not running:
sudo hermes gateway install --system --run-as-user root
# Answer Y to start immediately and enable on boot

# Verify
hermes cron status
# → "✓ Gateway is running — cron jobs will fire automatically"
```

**Critical:** Without the gateway, cron jobs are created but NEVER execute. The `cronjob` tool modifies a JSON file but the gateway's scheduler loop actually runs ticks.

### 2. Install A2A

```bash
git clone https://github.com/javimosch/a2a-skill.git /root/projects/a2a-skill
# Or SSH: git clone git@github.com:javimosch/a2a-skill.git /root/projects/a2a-skill
ln -s /root/projects/a2a-skill/a2a /usr/local/bin/a2a
ln -s /root/projects/a2a-skill/a2a-spawn /usr/local/bin/a2a-spawn
```

**Repo:** https://github.com/javimosch/a2a-skill — also contains:
- Multi-language client libraries (Python, Go, Node.js, Rust)
- REST API server (`a2a_server.py`)
- 800+ tests across all clients
- Detailed AGENTS.md and canonical SKILL.md in `.agents/skills/a2a/`

Ensure `a2a` is on PATH for ALL users that spawn agents (root AND any sudo target users).

### 3. Create the A2A cheatsheet skill

This is loaded by the cron job so the orchestrator knows how to use a2a:

```bash
hermes skills create a2a-cheatsheet
```

Content must include: CLI commands, a2a-spawn usage, kit prompt template, root caveats, spawn protocol, and common pitfalls.

### 4. Register the cron job

```bash
# Create the job with skills reference
cronjob action=create \
  name=a2a-hardening \
  schedule="once in 30m" \
  skills='["a2a-cheatsheet"]' \
  repeat=0 \
  deliver=local \
  enabled_toolsets='["terminal","file"]' \
  prompt="..."
```

The prompt is the heart of the system — see "Cron Prompt Design" below.

### 5. Prepare projects

List `/root/projects/` — any directory with `.git` is a candidate. Exclude the a2a-skill repo itself and any non-Paseo repos.

State file at `/root/.hermes/scripts/a2a-hardening-state.json` (auto-created on first tick).

## Cron Prompt Design

The prompt is a detailed instruction set for the LLM orchestrator. It must cover:

### State management
- State file path and JSON format
- `current_idx`, `projects` list, `use_claude` boolean, `session` object
- Read at start of every tick, write after any change

### Project discovery
- `ls /root/projects/` → filter `.git` dirs → sort → skip exclusions
- Store in state on first run, reuse on subsequent ticks

### Model policy (STRICT)
```
Builder: claude-sonnet-4-6     (max 1 sonnet per team)
Reviewer: claude-haiku-4-5-20251001  (never opus)
Fallback: opencode-go/deepseek-v4-flash  (all agents)
```

### CLI fallback logic
1. Try claude first
2. If claude fails (401, root block, exit code 1) → set `use_claude: false` in state
3. On subsequent ticks with `use_claude: false`, skip claude entirely
4. Every ~10 ticks, test claude again

### Tick decision tree
```
Read state
│
├─ Session active?
│  ├─ Check agent PIDs alive (kill -0)
│  ├─ Count git commits since baseline
│  ├─ >= 5? → git push → cleanup → advance idx
│  ├─ Both dead, partial progress? → git push → cleanup → restart same project
│  ├─ Both dead, 0 commits? → advance idx (skip)
│  └─ Still running? → report progress → exit
│
└─ No session?
   ├─ Pick project: projects[current_idx % len]
   ├─ git checkout . && pull
   ├─ a2a init && register agents
   ├─ Write kit prompts to /tmp/
   ├─ Spawn via a2a-spawn
   ├─ chown db for agent user
   ├─ Register PIDs
   └─ Save state
```

### Kit prompt template
Must include for EACH agent:
1. Agent ID and role
2. Peer list
3. Project path and test command
4. a2a locator snippet (resolves from PATH, then standard paths)
5. Communication protocol (recv → send → broadcast → status done)
6. Coordination rules (CLAIM before work, broadcast commits)
7. Hard cap (14 iterations max)
8. Task-specific instructions (builder: fix bugs + write tests; reviewer: review + verify)

## A2A Team Spawning (exact mechanism)

The cron agent spawns teams using `a2a-spawn`, not by directly invoking CLIs.
This is critical — `a2a-spawn` handles per-CLI flag differences, resolves
binary paths, and sets the right env vars.

### The spawn sequence (in order)

```
1. a2a init                          # create ~agent/.a2a/{project}/database.db
2. a2a register builder-{proj} ...   # register builder on bus
3. a2a register reviewer-{proj} ...  # register reviewer on bus
4. Write kit prompt to /tmp/a2a-kit-{ts}-builder-{proj}.kit
5. Write kit prompt to /tmp/a2a-kit-{ts}-reviewer-{proj}.kit
6. PID1=$(a2a-spawn --cli claude --id builder-{proj} --kit-file ... --model MODEL)
7. PID2=$(a2a-spawn --cli claude --id reviewer-{proj} --kit-file ... --model MODEL)
8. a2a register builder-{proj} --pid $PID1 --upsert
9. a2a register reviewer-{proj} --pid $PID2 --upsert
10. chown -R agent:agent ~agent/.a2a/{project}/   # fix db ownership
```

### Why kit files, not inline prompts

Kit prompts are always written to `/tmp/` files, then passed to `a2a-spawn`
via `--kit-file`. Reasons:

- **Shell escaping is brittle** — multi-line prompts with special chars
  (`$`, `"`, backticks) break inline arguments
- **a2a-spawn expects a file** — it reads `KIT="$(cat "$KIT_FILE")"` and
  passes it via `--append-system-prompt` (claude) or embeds in message body
  (opencode)
- **Debugging** — the kit file is a record of exactly what each agent received

### PID lifecycle

- PIDs are captured from `a2a-spawn` stdout and saved to state
- Registered on the a2a bus via `--upsert` so peers can see each other
- Checked on every tick via `kill -0 $PID`
- Killed on session completion/cleanup via `kill $PID; kill -9 $PID`
- Bulk kill: `a2a list --json | grep -o '"pid": [0-9]*' | awk '{print $2}' | xargs -r kill`

### Chown criticality

Step 10 is easy to forget. Without it, agents spawned as `sudo -u agent`
can't write to the database and silently fail with "readonly database".
The a2a bus remains empty, agents never coordinate, and the cron reports
0 commits on the next tick.

## A2A System Learnings (from production)

These are observations from running A2A teams across 5+ projects over many
cycles. They go beyond the official docs.

### Coordination works best with role separation

Teams of 2 with distinct roles (builder + reviewer) outperform same-role teams.
The builder claims work, the reviewer reviews. Role separation reduces
contention and produces better commits:

- Builder: finds bugs, writes tests, commits
- Reviewer: audits code, checks test coverage, suggests edge cases
- Both use CLAIM/Role-Cross protocol to avoid stepping on each other

### Kit prompt design matters enormously

The difference between a productive team and a silent one is in the kit prompt.

**Must have:**
- A2A locator snippet (agents must find the binary themselves)
- Explicit `A2A_PROJECT` (agents land on the same bus)
- Peer list (`a2a list --json` output)
- Hard iteration cap (14 max — without it, agents loop forever)
- Empty-recv threshold ("3 empty recvs = done")
- Clear commit announcement format ("COMMIT: <message>")

**Nice to have:**
- CLAIM/ACK protocol for task division
- ROLE-CROSS signal for crossing role boundaries
- Project-specific test commands (prevent "running full suite" mistake)
- File ownership declarations (avoid simultaneous writes)

### Agents discover the a2a binary dynamically

The kit prompt's locator snippet probes in order:
1. `command -v a2a` (PATH)
2. `~/.agents/skills/a2a/a2a` (cross-CLI global)
3. `~/.claude/skills/a2a/a2a` (claude skills dir)

This works across CLIs and users. For `sudo -u agent`, ensure a2a is on
the target user's PATH or at one of the standard locations.

### Agent communication patterns observed

```
Introduction → Task claim → Work → Commit broadcast → Review request
  → Sign-off → Next claim → ... → Summary → Done
```

Most productive teams follow this sequence naturally. Key observations:

- **First message is always an intro** — agents introduce themselves and
  ask what to do. The orchestrator doesn't need to seed conversations.
- **Commit broadcasts are reliable** — agents consistently announce commits
  with COMMIT: prefix. This lets the orchestrator track progress via the bus.
- **Reviewer rarely writes code** — true to their role, reviewers mostly
  audit and suggest. When the builder asks for help, the reviewer assists.
- **Agents stop when peers are done** — if one agent finishes early, the
  other continues alone. The hard cap prevents infinite loops.

### Messages on the bus are the source of truth

Never trust agent claims without bus verification. If an agent says
"committed fix X", check with `a2a peek` or `git log` before recording it.

### The 5-commit target works well

Teams consistently produce 2-5 commits per session. The 5-commit target
is achievable in a single 30-min window with sonnet + haiku. Push happens
at session end (or on restart with partial progress).

### Empty a2a peek means coordination failure

If `a2a peek --project {name}` returns empty after agents have been running
for >60 seconds, something is wrong. Common causes in order of likelihood:

1. **DB ownership** — agents can't write (fix: chown)
2. **Wrong A2A_PROJECT** — agents on different buses (fix: export + verify)
3. **a2a not on PATH** — agents can't find the binary (fix: install system-wide)
4. **Kit prompt missing locator** — agents don't know how to find a2a

### Never reuse a2a project names across sessions

Each session gets its own project name (`a2a-hardening-{project}`).
Reusing names causes message cross-contamination between sessions.
Use `a2a clear --yes --project {name}` or `rm -rf ~/.a2a/{name}/` to
clean up between sessions.

### a2a-spawn known limitations

- **a2a-spawn for claude uses `--dangerously-skip-permissions` internally**
  which is blocked on root. The script was patched on rbm4 with
  `CLAUDE_CODE_DANGEROUSLY_SKIP_PERMISSIONS=1` env var instead.
  If cloning a fresh a2a-skill, this patch must be re-applied for root.
- **a2a-spawn for opencode resolves the binary to `~/.opencode/bin/opencode`**
  (not the tmux-wrapped `opencode` alias). Works correctly when the target
  binary exists at that path.
- **a2a-spawn --max-turns defaults to 16 for claude** which limits each
  agent to ~8 recv/send cycles. For hardening work, this is usually
  enough for 2-3 commits. The cron handles the rest by respawning.

## Monitoring the System (Supervisor Hat)

This section is for the **Hermes agent** (supervisor) overseeing the cron
and A2A teams — not for the cron agent itself. It covers what to check,
how often, and what patterns signal problems vs normal operation.

### Tick cadence and what to expect

The cron fires every 30 min. Each tick goes through phases:

```
T+0s    LLM agent boots, reads state, loads a2a-cheatsheet skill
T+5-15s Agent decides action (spawn new team / check progress / cleanup)
T+15s   If spawning: git pull, a2a init, write kits, spawn agents
T+20s   Agents starting, kit prompt being processed
T+30s+  Agents on the bus, intro messages appearing
T+2-5m  First commits appearing (fix + test cycle)
T+10m+  More commits as agents coordinate
T+30m   Next cron tick checks progress, reports
```

A healthy system produces output on most ticks. If ticks are silent
(no delivery), check `hermes cron status` and `journalctl`.

### Supervision checklist (every few ticks)

```bash
# 1. Is the gateway alive?
hermes cron status

# 2. Did the last tick succeed?
cronjob action=list  # check last_status

# 3. State advancing?
cat /root/.hermes/scripts/a2a-hardening-state.json

# 4. Agents alive?
ps -ef | grep "a2a-kit\|builder-\|reviewer-" | grep -v grep

# 5. Bus active?
sudo -u agent a2a peek --project a2a-hardening-{project} --limit 5

# 6. Commits accumulating?
git -C /root/projects/{name} log --oneline -5

# 7. Pushed to remote?
git -C /root/projects/{name} rev-list --count @{u}..HEAD
```

### Pattern recognition

#### Normal operation
- State alternates between `session: {...}` (active) and `session: null` (between projects)
- `current_idx` increments slowly (1 per 5-commits, ~30-90 min each)
- Bus shows intro → claim → commit → commit → ... pattern
- 2-5 commits per session
- `use_claude` stays `true` (claude auth working)

#### Warning signs
| Signal | What it means | Action |
|---|---|---|
| `current_idx` stuck for 3+ ticks | Session stuck or timed out | Check agents, check bus, check logs |
| `last_status: error` | API failure | `journalctl -u hermes-gateway` for details |
| `session: null` for 2+ ticks with no idx advance | Cron failing to start sessions | Check claude auth, check opencode API |
| `use_claude: true` but agents using opencode | Inconsistent state | Fix state or investigate race |
| State file missing entirely | State was deleted or first run | Should auto-create on next tick |
| `baseline_commits` unchanged for 2+ sessions on same project | Agents failing to produce | Check kit prompts, check agent logs |
| Builder PID alive but reviewer PID dead | Asymmetric failure | Reviewer likely hit a claude error |
| Both PIDs dead with 0 commits since baseline | Immediate spawn failure | Check daemon log for claude/opencode errors |

#### Healthy metrics (from rbm4 production data)
- **Commits per session**: 2-5 (average ~3)
- **Session duration**: agents live 5-20 min usually
- **Projects per day**: 4-8 (at 30-min ticks)
- **Push cadence**: after each session (5 commits or partial restart)
- **Claude auth expiry**: every ~4-6 hours (needs re-auth)
- **Gateway uptime**: indefinite (systemd service)

### What to do when things go silent

If the cron stops producing output:

```bash
# Step 1: Check gateway
hermes cron status
# → If not running: sudo hermes gateway start --system

# Step 2: Check last tick
journalctl -u hermes-gateway -n 30 --no-pager
# → Look for "Job failed" or "Connection error"

# Step 3: Check cron job state
cronjob action=list
# → If disabled: cronjob action=resume id={id}

# Step 4: Check state integrity
cat /root/.hermes/scripts/a2a-hardening-state.json
# → Missing/corrupt: reset to {"current_idx":0,"session":null,"use_claude":true}

# Step 5: Test agent CLIs
claude -p "echo test"
opencode --version
# → Fix auth if needed, re-sync credentials

# Step 6: Force a tick
hermes cron run {id}
hermes cron tick
# → Monitor next delivery
```

### When to intervene vs let it self-heal

**Let it self-heal:**
- Transient API errors (gateway retries 3x)
- Single agent failure (cron respawns on next tick)
- Slow project (agents running, just taking time)
- Network blips (resolved on retry)

**Intervene immediately:**
- Gateway down for 2+ ticks → restart it
- Claude auth expired (401) → re-auth + sync to agent user
- State file corrupt → reset to blank state
- Cron showing `enabled: false` → resume it
- All projects stuck at same idx for 6+ hours → investigate prompt/agents

### Delivery expectations

The cron job delivers output on every tick. The delivery is the cron agent's
final message — a brief sitrep of what happened. Don't expect walls of text;
the agent summarizes in a few lines.

If `deliver` is set to `local`, output is saved to the cron output directory
but not sent anywhere. Set `deliver=origin` to get reports in your
conversation channel.

### Historical tracking

The state file only tracks the current session. For historical data:
- **Git log per project**: `git log --oneline --since="1 week ago"`
- **A2A bus history**: lost when db is cleaned up (but commits are in git)
- **Cron delivery history**: `journalctl -u hermes-gateway` for last N runs
- **Gateway log**: `journalctl -u hermes-gateway --since "24 hours ago"`

## The No-Root Approach (rbm4-specific)

This is the single most important architectural decision on rbm4. The cron
orchestrator runs as **root**, but spawned agents run as a separate **agent**
user via `sudo -u agent`. This avoids nearly all root-related permission
blocks, at the cost of one extra step (db chown).

```
┌──────────────────────────────┐
│  Orchestrator (root)         │
│  - owns state file           │
│  - owns kit files in /tmp/   │
│  - runs a2a init             │
│  - spawns agents via sudo    │
└──────────────┬───────────────┘
               │ sudo -u agent
               ▼
┌──────────────────────────────┐
│  Builder/Reviewer (agent)    │
│  - claude/opencode process   │
│  - reads kit from /tmp/      │
│  - writes to a2a db          │
│  - runs git commands          │
└──────────────────────────────┘
```

### Why not just run everything as root?

- Claude's `--dangerously-skip-permissions` is **blocked on root**
- The env var workaround (`CLAUDE_CODE_DANGEROUSLY_SKIP_PERMISSIONS=1`)
  exists but is fragile (must be set in every shell)
- `sudo -u agent` cleanly sidesteps the entire problem
- No special env vars needed in agent shell configs

### The one cost: database ownership

Because `a2a init` runs as root but agents access the db as `agent`,
the database file is root-owned. Agents get:

```
a2a: list error: attempt to write a readonly database
```

**This MUST be fixed after every `a2a init`:**

```bash
# Run this immediately after registering agents:
chown -R agent:agent ~agent/.a2a/{project}/
```

This step is the #1 cause of "agents spawned but bus is empty" bugs.
It's easy to forget because:
- `a2a init` succeeds silently (root creates the file)
- `a2a register` succeeds silently (root writes to the db)
- `a2a-spawn` succeeds silently (agent process starts)
- Agent runs, tries `a2a recv`, gets "readonly database", fails silently
- Orchestrator sees agents alive but bus empty, assumes they're still booting
- Next tick: agents dead, 0 commits, no messages on bus

### The chown is also needed between sessions

When cleaning up between projects, don't just re-init — also remove the
old database to avoid stale permissions:

```bash
rm -rf ~agent/.a2a/{old_project}/
# Then init fresh for new project
sudo -u agent mkdir -p ~agent/.a2a/{new_project}
```

Or better: always init and chown as a pair:

```bash
a2a init --project {name}
chown -R agent:agent ~agent/.a2a/{name}/
```

This two-line sequence is the minimal correct spawn preamble. Never omit
the chown.

### The env var alternative (if not using sudo)

If you can't use `sudo -u agent`, the env var approach works but requires
consistency across all touch points:

```bash
# Every shell that spawns claude must have this
export CLAUDE_CODE_DANGEROUSLY_SKIP_PERMISSIONS=1

# .bashrc, .zshrc, and cron job env dict all need it
# a2a-spawn script already includes it (line 91)
```

The `sudo -u agent` approach is preferred because it's self-contained —
no env vars to propagate, no shell configs to maintain.

### OpenCode root behavior (contrast)

Unlike claude, `opencode run --dangerously-skip-permissions` **works fine**
on root. No special handling, no env var, no sudo needed. This makes
opencode a good fallback when claude auth is down — zero config changes.

### Sudo spawns lose environment

When spawning via `sudo -u user`, the child inherits a minimal environment. `A2A_PROJECT`, PATH additions, and shell configs are NOT inherited.

**Fix:** Either pass env explicitly (`sudo -u agent env A2A_PROJECT=...`), use absolute paths in kit locators, or install a2a system-wide.

### 5. Claude auth propagation

The claude credential file at `~/.claude/.credentials.json` is user-specific. If you re-auth as root but agents run as `agent` user, you must sync:
```bash
cp /root/.claude/.credentials.json /home/agent/.claude/.credentials.json
chown agent:agent /home/agent/.claude/.credentials.json
```

The OAuth token expires periodically (every few hours). If the cron starts failing with 401, re-auth claude and sync to agent user.

## State File Structure

```json
{
  "current_idx": 0,
  "projects": ["automaintainer", "boilerplate-cli-ui-go", ...],
  "use_claude": true,
  "session": {
    "project_name": "supergato",
    "project_path": "/root/projects/supergato",
    "test_cmd": "npm test",
    "baseline_commits": 212,
    "started_at": "2026-05-29T00:00:00Z",
    "builder_pid": 2270217,
    "reviewer_pid": 2273167,
    "a2a_project": "a2a-hardening-supergato",
    "active_cli": "claude"
  }
}
```

Location: `/root/.hermes/scripts/a2a-hardening-state.json`

## A2A-Skill Repo Documentation

The canonical a2a skill doc is at `.agents/skills/a2a/SKILL.md` in the a2a-skill repo. It has a "Common Pitfalls & Gotchas" section covering:
- **#12 Cross-user database ownership** (the chown fix)
- **#13 Sudo spawns lose PATH and env vars**
- **#14 `--dangerously-skip-permissions` blocked on root**

Always update this file when new gotchas are discovered. Commit and push to the repo.

## Monitoring & Debugging

### Check if cron is firing
```bash
hermes cron status
journalctl -u hermes-gateway -n 20 --no-pager
```

### Check agent processes
```bash
ps -ef | grep "a2a-kit\|builder-\|reviewer-" | grep -v grep
```

### Check A2A bus
```bash
sudo -u agent a2a peek --project a2a-hardening-{project} --limit 10
sudo -u agent a2a list --project a2a-hardening-{project}
```

### Check agent logs
```bash
cat /tmp/a2a-{id}.log
cat /tmp/a2a-kit-*-{project}.kit  # kit prompts delivered to agents
```

### Force a tick
```bash
hermes cron tick        # may not work if gateway has its own schedule
hermes cron run {id}    # schedules for next gateway tick, not immediate
```

### Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| Cron job never fires | Gateway not running | `sudo hermes gateway start --system` |
| `last_status: error`, "Connection error" | Transient network | Gateway retries; check `journalctl` |
| Agents spawn but a2a bus empty | DB ownership (root vs agent) | `chown -R agent:agent ~agent/.a2a/{proj}/` |
| Claude CLI fails 401 | Auth token expired | Re-auth claude + sync to agent user |
| `--dangerously-skip-permissions` blocked | Running as root | Use env var or `sudo -u agent` |
| opencode API "Connection error" | Network issue | Check `curl https://api.opencode.ai` |
| Cron `enabled: false` after run | Schedule completed | `cronjob action=resume` |

## Key Files Reference (rbm4)

| Path | Purpose |
|---|---|
| `/root/.hermes/scripts/a2a-hardening-state.json` | Session state |
| `/root/.hermes/skills/a2a-cheatsheet/SKILL.md` | A2A cheatsheet (loaded by cron) |
| `/root/.agents/skills/rbm4-a2a/SKILL.md` | rbm4-specific overview skill |
| `/root/.agents/skills/a2a-hardening/SKILL.md` | Workflow skill doc |
| `/root/projects/a2a-skill/.agents/skills/a2a/SKILL.md` | Canonical a2a skill (in repo) |
| `/root/.config/opencode/opencode.jsonc` | opencode config (has defaultModel) |
| `/root/.local/bin/a2a` | a2a binary symlink |
| `/root/.local/bin/a2a-spawn` | a2a-spawn symlink |

## Adapting to a Different Machine

To replicate this system elsewhere:

1. **Install Hermes** — ensure `cronjob` tool and gateway are available
2. **Clone a2a-skill** — ensure `a2a` and `a2a-spawn` are on PATH
3. **Install agent CLIs** — `claude` and/or `opencode`
4. **Create cheatsheet skill** — adapt paths to match new machine
5. **Register cron job** — update paths in prompt, set model names to local config
6. **Start gateway** — `hermes gateway install`
7. **Monitor first tick** — check `journalctl -u hermes-gateway` for errors
8. **Fix perms** — ensure a2a db ownership matches spawn user
9. **Iterate** — each failure reveals a new gotcha to document

Key differences to watch for:
- Non-root machines: no `--dangerously-skip-permissions` block needed
- Different agent users: adjust `chown` targets and credential sync paths
- Different model names: check `claude --version` and `opencode models` for exact names
- Different project paths: update the project discovery logic
