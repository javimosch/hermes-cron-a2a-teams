<p align="center">
  <img src="https://img.shields.io/badge/status-production-green" alt="Status">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="License">
  <img src="https://img.shields.io/github/stars/javimosch/hermes-cron-a2a-teams?style=social" alt="Stars">
</p>

<h1 align="center">Hermes Cron → A2A Teams</h1>

<p align="center">
  <b>Recurring agent teams that harden your codebases.</b><br>
  Hermes cron fires every 30min → spawns 2 agents (builder + reviewer) on an A2A bus<br>
  → they coordinate, fix bugs, write tests, commit, push → next project.<br>
  Works for humans. Works for AI agents.
</p>

<p align="center">
  <a href="#-quick-start"><b>Quick Start →</b></a>
  &nbsp;&nbsp;|&nbsp;&nbsp;
  <a href="#-how-it-works"><b>How It Works →</b></a>
  &nbsp;&nbsp;|&nbsp;&nbsp;
  <a href="#-for-ai-agents"><b>For AI Agents →</b></a>
  &nbsp;&nbsp;|&nbsp;&nbsp;
  <a href="#-key-files"><b>Key Files →</b></a>
</p>

<br>

---

**The problem:** Codebases accumulate bugs and missing tests. Manual hardening is tedious and doesn't scale. AI agents can do the work but need coordination — otherwise they step on each other or duplicate effort.

**Hermes Cron → A2A Teams fixes this.** Every 30 minutes, an orchestrator spawns a pair of agents on a shared A2A message bus. They claim tasks, review each other's work, and commit fixes. No orchestrator needed after spawn — the bus handles coordination.

---

## ⚡ Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/javimosch/hermes-cron-a2a-teams.git
cd hermes-cron-a2a-teams

# 2. Install a2a
git clone https://github.com/javimosch/a2a-skill.git
ln -s a2a-skill/a2a /usr/local/bin/a2a
ln -s a2a-skill/a2a-spawn /usr/local/bin/a2a-spawn

# 3. Symlink the skill so Hermes can load it
ln -s $(pwd)/.agents/skills/hermes-a2a-cron-agent-maintainer ~/.agents/skills/hermes-a2a-cron-agent-maintainer

# 4. Start the Hermes gateway (for cron scheduling)
sudo hermes gateway install --system --run-as-user root

# 5. Register the cron job (use the prompt from .agents/skills/SKILL.md)
cronjob action=create \
  name=a2a-hardening \
  schedule="once in 30m" \
  skills='["a2a-cheatsheet"]' \
  repeat=0 \
  deliver=local \
  enabled_toolsets='["terminal","file"]' \
  prompt="..."

# 6. Validate setup
./validate-setup.sh
# → Comprehensive validation of all prerequisites

# 7. Verify cron configuration
hermes cron status
cronjob action=list
# → ✓ Gateway is running — cron jobs will fire automatically
```

> **Need a2a cheatsheet?** Create it with `hermes skills create a2a-cheatsheet` using the template from the [a2a-skill repo](https://github.com/javimosch/a2a-skill).

---

## 🧠 How It Works

```
┌──────────────┐
│  Hermes Cron │  every 30min
│  Gateway     │  systemd service
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────┐
│  Cron LLM Agent (orchestrator)   │
│  Reads state → picks project →   │
│  writes kit prompts → spawns     │
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

### Project Rotation

7 repos in rotation, sorted alphabetically. Each gets 5 new hardening commits per pass, then wraps around:

```
automaintainer → boilerplate-cli-ui-go → javika-analysis-tool →
superbackend → supercli → supergato → superlandings → repeat
```

### Model Policy

| Role | Claude mode | Fallback (opencode) |
|---|---|---|
| **Builder** | `claude-sonnet-4-6` (max 1 per team) | `opencode-go/deepseek-v4-flash` |
| **Reviewer** | `claude-haiku-4-5-20251001` | `opencode-go/deepseek-v4-flash` |

No opus. If claude auth fails, automatically falls back to opencode for both agents.

---

## 📊 Production Metrics (rbm4)

| Metric | Value |
|---|---|
| Commits per session | 2–5 (avg ~3) |
| Projects per day | 4–8 |
| Claude auth expiry | ~4–6 hours |
| Time to first commit | ~2–5 min after spawn |
| Session duration | 5–20 min |
| Gateway uptime | Indefinite (systemd) |

---

## 🤖 For AI Agents

This repo carries a skill at `.agents/skills/hermes-a2a-cron-agent-maintainer/SKILL.md` designed to be loaded by any Hermes agent that needs to understand or work on this system.

```bash
# Load the skill
skill_view(name='hermes-a2a-cron-agent-maintainer')

# Or reference the file directly
cat .agents/skills/hermes-a2a-cron-agent-maintainer/SKILL.md
```

The skill covers:
- Full architecture and setup steps
- Exact spawn sequence (10 steps, incl. critical chown)
- A2A system learnings from production (coordination patterns, bus diagnostics, gotchas)
- Root permission caveats (the no-root approach, database ownership)
- Supervision checklist (what to check, how often, pattern recognition)
- Troubleshooting guide (failure modes, fixes)
- Adaptation guide for new machines

### Companion Projects

- [**a2a-skill**](https://github.com/javimosch/a2a-skill) — The A2A peer messaging system (SQLite bus, multi-language clients, 800+ tests)
- [**supercli**](https://github.com/javimosch/supercli) — 3,300+ CLI tools, one command. Plugin system with agent skills and a2a workflow integration.

---

## 🛠 Development Tools

This repository includes comprehensive tooling for setup validation, troubleshooting, and maintenance:

### Setup Validation
```bash
# Validate complete system setup
./validate-setup.sh
```

**Features:**
- ✅ Prerequisite checking (Hermes, A2A, agent CLIs)
- ✅ Network connectivity and GitHub repository validation
- ✅ File permissions and ownership verification
- ✅ Database directory structure validation
- ✅ Colored output with error/warning categorization

### Documentation Consistency
```bash
# Check documentation consistency between files
./check-docs.sh
```

**Features:**
- ✅ Command syntax validation between README and SKILL.md
- ✅ URL consistency checking
- ✅ Version reference validation
- ✅ Hard-coded path detection

### Troubleshooting & Diagnosis
```bash
# Diagnose and fix common A2A system issues
./troubleshoot-a2a.sh
```

**Features:**
- 🔧 Automated diagnosis of 10+ common failure modes
- 🔧 Automatic fixes for resolvable issues (gateway, ownership, auth)
- 🔧 Process state validation and PID cleanup
- 🔧 Network connectivity and repository access testing
- 🔧 State file integrity validation with JSON parsing

### Test Coverage
```bash
# Run all test suites
./test-validate-setup.sh      # Test setup validation functionality
./test-enhanced-validation.sh # Test enhanced validation features  
./test-troubleshoot-a2a.sh    # Test troubleshooting tool (26 checks)
```

All tools include comprehensive test suites with 100% pass rates and proper error handling.

---

## 🗂 Key Files

| Path | Purpose |
|---|---|
| `.agents/skills/hermes-a2a-cron-agent-maintainer/SKILL.md` | Canonical skill (loadable by Hermes) |
| `README.md` | This file |
| `validate-setup.sh` | Comprehensive setup validation tool |
| `troubleshoot-a2a.sh` | Automated troubleshooting and repair tool |
| `check-docs.sh` | Documentation consistency checker |
| `test-*.sh` | Test suites for all tools |
| `docs/` | (optional) Extended docs |

---

## 📦 Production State File

```json
{
  "current_idx": 5,
  "projects": ["automaintainer", "boilerplate-cli-ui-go", "javika-analysis-tool", "superbackend", "supercli", "supergato", "superlandings"],
  "use_claude": true,
  "session": {
    "project_name": "supergato",
    "project_path": "/root/projects/supergato",
    "baseline_commits": 212,
    "builder_pid": 2270217,
    "reviewer_pid": 2273167,
    "active_cli": "claude"
  }
}
```

State auto-created on first tick, persisted between runs. Session advances on 5-commit target.

---

<p align="center">
  <b>Built with</b><br>
  <a href="https://github.com/javimosch/a2a-skill">a2a-skill</a> ·
  <a href="https://github.com/javimosch/supercli">supercli</a> ·
  Hermes CLI
</p>

<p align="center">
  <b>Author</b><br>
  <a href="https://www.linkedin.com/in/arancibiajav/">Javier Leandro Arancibia</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/javimosch">@javimosch</a>
</p>
