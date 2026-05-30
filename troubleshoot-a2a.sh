#!/bin/bash

# A2A Team Troubleshooting Tool
# Diagnoses common issues mentioned in SKILL.md and provides fixes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 A2A Team Troubleshooting Tool${NC}"
echo "================================="
echo "Diagnosing common A2A system issues..."

# Track issues found
ISSUES_FOUND=0
FIXES_APPLIED=0

check_and_fix() {
    local check_name="$1"
    local check_cmd="$2"
    local fix_name="$3"
    local fix_cmd="$4"
    local description="$5"

    echo ""
    echo "Checking: $check_name"
    echo "Description: $description"

    if eval "$check_cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $check_name: OK"
    else
        echo -e "${RED}✗${NC} $check_name: ISSUE DETECTED"
        ((ISSUES_FOUND++))

        if [ -n "$fix_cmd" ]; then
            echo -e "${YELLOW}🔧${NC} Attempting fix: $fix_name"
            if eval "$fix_cmd"; then
                echo -e "${GREEN}✓${NC} Fix applied successfully"
                ((FIXES_APPLIED++))
            else
                echo -e "${RED}✗${NC} Fix failed - manual intervention required"
            fi
        else
            echo -e "${YELLOW}⚠${NC} Manual fix required: $fix_name"
        fi
    fi
}

echo ""
echo "1. Checking Hermes Gateway Status (most common failure)"

check_and_fix \
    "Hermes Gateway Running" \
    "systemctl is-active hermes-gateway" \
    "Start Hermes gateway" \
    "sudo systemctl start hermes-gateway" \
    "Gateway must be running for cron jobs to execute"

echo ""
echo "2. Checking A2A Database Ownership (common spawn failure)"

# Check if any A2A databases exist and have wrong ownership
if [ -d "/root/.a2a" ]; then
    for proj_dir in /root/.a2a/*/; do
        if [ -d "$proj_dir" ]; then
            proj_name=$(basename "$proj_dir")

            check_and_fix \
                "A2A database ownership for $proj_name" \
                "[ \"\$(stat -c %U \"$proj_dir\")\" = \"agent\" ]" \
                "Fix database ownership" \
                "chown -R agent:agent \"$proj_dir\"" \
                "Agent processes must own their database files"
        fi
    done
else
    echo "No A2A databases found in /root/.a2a"
fi

echo ""
echo "3. Checking Agent User Permissions"

check_and_fix \
    "Agent user exists" \
    "id agent" \
    "Create agent user" \
    "" \
    "Agent user required for secure spawning (manual: useradd -m agent)"

agent_home=$(eval echo "~agent" 2>/dev/null || echo "/home/agent")
if id agent >/dev/null 2>&1; then
    check_and_fix \
        "Agent home directory accessible" \
        "[ -d \"$agent_home\" ]" \
        "Create agent home directory" \
        "mkdir -p \"$agent_home\" && chown agent:agent \"$agent_home\"" \
        "Agent needs accessible home directory"
fi

echo ""
echo "4. Checking Claude Authentication"

check_and_fix \
    "Claude credentials exist" \
    "[ -f \"/root/.claude/.credentials.json\" ]" \
    "Re-authenticate Claude" \
    "" \
    "Manual: run 'claude auth' and then sync to agent user"

if [ -f "/root/.claude/.credentials.json" ] && id agent >/dev/null 2>&1; then
    check_and_fix \
        "Claude credentials synced to agent user" \
        "[ -f \"$agent_home/.claude/.credentials.json\" ]" \
        "Sync credentials to agent" \
        "mkdir -p \"$agent_home/.claude\" && cp /root/.claude/.credentials.json \"$agent_home/.claude/\" && chown -R agent:agent \"$agent_home/.claude\"" \
        "Agent processes need Claude credentials"
fi

echo ""
echo "5. Checking A2A Tool Installation"

check_and_fix \
    "A2A binary in PATH" \
    "command -v a2a" \
    "Install A2A symlink" \
    "" \
    "Manual: ln -s /path/to/a2a-skill/a2a /usr/local/bin/a2a"

check_and_fix \
    "A2A-spawn binary in PATH" \
    "command -v a2a-spawn" \
    "Install A2A-spawn symlink" \
    "" \
    "Manual: ln -s /path/to/a2a-skill/a2a-spawn /usr/local/bin/a2a-spawn"

echo ""
echo "6. Checking State File Integrity"

state_file="/root/.hermes/scripts/a2a-hardening-state.json"
check_and_fix \
    "State file exists and is valid JSON" \
    "[ -f \"$state_file\" ] && jq empty \"$state_file\"" \
    "Reset state file" \
    "mkdir -p /root/.hermes/scripts && echo '{\"current_idx\":0,\"session\":null,\"use_claude\":true}' > \"$state_file\"" \
    "Cron agent needs valid state file"

echo ""
echo "7. Checking Process State (if agents are running)"

# Look for running A2A agents
running_agents=$(ps -ef | grep -E "(a2a-kit|builder-|reviewer-)" | grep -v grep | wc -l)
if [ "$running_agents" -gt 0 ]; then
    echo "Found $running_agents running A2A agents"

    # Check if PIDs in state file match running processes
    if [ -f "$state_file" ] && jq -e '.session.builder_pid' "$state_file" >/dev/null 2>&1; then
        builder_pid=$(jq -r '.session.builder_pid // empty' "$state_file")
        reviewer_pid=$(jq -r '.session.reviewer_pid // empty' "$state_file")

        if [ -n "$builder_pid" ]; then
            check_and_fix \
                "Builder PID $builder_pid alive" \
                "kill -0 \"$builder_pid\"" \
                "Clear stale PID from state" \
                "jq '.session.builder_pid = null' \"$state_file\" > /tmp/state.tmp && mv /tmp/state.tmp \"$state_file\"" \
                "State file should not reference dead processes"
        fi

        if [ -n "$reviewer_pid" ]; then
            check_and_fix \
                "Reviewer PID $reviewer_pid alive" \
                "kill -0 \"$reviewer_pid\"" \
                "Clear stale PID from state" \
                "jq '.session.reviewer_pid = null' \"$state_file\" > /tmp/state.tmp && mv /tmp/state.tmp \"$state_file\"" \
                "State file should not reference dead processes"
        fi
    fi
else
    echo "No A2A agents currently running"
fi

echo ""
echo "8. Checking Cron Job Configuration"

# Check if cron job exists and is enabled
if command -v cronjob >/dev/null 2>&1; then
    cron_status=$(cronjob action=list 2>/dev/null | grep -E "(a2a-hardening|enabled.*true)" || echo "")
    if [ -n "$cron_status" ]; then
        echo -e "${GREEN}✓${NC} A2A hardening cron job found and appears enabled"
    else
        echo -e "${RED}✗${NC} A2A hardening cron job not found or disabled"
        echo -e "${YELLOW}⚠${NC} Manual fix: Register cron job using instructions in README.md"
        ((ISSUES_FOUND++))
    fi
else
    echo -e "${YELLOW}⚠${NC} cronjob command not available"
fi

echo ""
echo "9. Environment Variable Check"

# Check for common env var issues
check_and_fix \
    "CLAUDE_CODE_DANGEROUSLY_SKIP_PERMISSIONS set" \
    "[ \"\$CLAUDE_CODE_DANGEROUSLY_SKIP_PERMISSIONS\" = \"1\" ] || [ \"\$(whoami)\" != \"root\" ]" \
    "Set environment variable" \
    "export CLAUDE_CODE_DANGEROUSLY_SKIP_PERMISSIONS=1" \
    "Required for Claude to work as root (alternative: use sudo -u agent)"

echo ""
echo "10. Network and Repository Access"

# Quick network check
check_and_fix \
    "Network connectivity" \
    "curl -s --connect-timeout 5 google.com >/dev/null" \
    "Check network configuration" \
    "" \
    "Manual: Check firewall, DNS, and network settings"

# Check GitHub access
check_and_fix \
    "GitHub access" \
    "curl -s --connect-timeout 5 https://api.github.com/repos/javimosch/a2a-skill >/dev/null" \
    "Check GitHub connectivity" \
    "" \
    "Manual: Verify GitHub is accessible and not blocked"

echo ""
echo "================================="
echo "Troubleshooting Summary"
echo "================================="

if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ No issues detected!${NC}"
    echo "Your A2A system appears to be healthy."
else
    echo -e "${YELLOW}⚠ Found $ISSUES_FOUND issue(s)${NC}"
    echo -e "${GREEN}✓ Applied $FIXES_APPLIED automatic fix(es)${NC}"

    remaining=$((ISSUES_FOUND - FIXES_APPLIED))
    if [ $remaining -gt 0 ]; then
        echo -e "${RED}⚠ $remaining issue(s) require manual intervention${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Review the manual fixes mentioned above"
        echo "2. Check the full SKILL.md for detailed troubleshooting"
        echo "3. Run this script again after applying fixes"
        echo "4. Check 'hermes cron status' and 'journalctl -u hermes-gateway'"
    else
        echo -e "${GREEN}✓ All issues were automatically resolved!${NC}"
    fi
fi

echo ""
echo "For detailed troubleshooting, see:"
echo "- .agents/skills/hermes-a2a-cron-agent-maintainer/SKILL.md (Monitoring & Debugging section)"
echo "- Run './validate-setup.sh' for comprehensive system validation"

exit $ISSUES_FOUND