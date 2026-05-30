#!/bin/bash

# Hermes Cron A2A Teams - Setup Validation Script
# This script validates the setup instructions from README.md

set -e

echo "🔍 Hermes Cron A2A Teams Setup Validation"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track validation results
ERRORS=0
WARNINGS=0

check_command() {
    local cmd="$1"
    local description="$2"

    if command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $description: $cmd found"
    else
        echo -e "${RED}✗${NC} $description: $cmd not found"
        ((ERRORS++))
    fi
}

check_file() {
    local file="$1"
    local description="$2"

    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $description: $file exists"
    else
        echo -e "${RED}✗${NC} $description: $file not found"
        ((ERRORS++))
    fi
}

check_directory() {
    local dir="$1"
    local description="$2"

    if [ -d "$dir" ]; then
        echo -e "${GREEN}✓${NC} $description: $dir exists"
    else
        echo -e "${YELLOW}⚠${NC} $description: $dir not found"
        ((WARNINGS++))
    fi
}

check_url() {
    local url="$1"
    local description="$2"

    if curl -s --connect-timeout 5 --max-time 8 --head "$url" 2>/dev/null | head -n 1 | grep -q "200 OK"; then
        echo -e "${GREEN}✓${NC} $description: $url accessible"
    else
        echo -e "${YELLOW}⚠${NC} $description: $url may not be accessible (or network timeout)"
        ((WARNINGS++))
    fi
}

check_network() {
    local description="$1"

    if curl -s --connect-timeout 5 --max-time 10 google.com > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $description: Network connectivity available"
    else
        echo -e "${YELLOW}⚠${NC} $description: Network connectivity issues detected"
        ((WARNINGS++))
    fi
}

check_permissions() {
    local path="$1"
    local description="$2"
    local expected_perm="$3"

    if [ -e "$path" ]; then
        actual_perm=$(stat -c "%a" "$path" 2>/dev/null)
        if [ "$actual_perm" = "$expected_perm" ]; then
            echo -e "${GREEN}✓${NC} $description: permissions correct ($expected_perm)"
        else
            echo -e "${YELLOW}⚠${NC} $description: permissions $actual_perm (expected $expected_perm)"
            ((WARNINGS++))
        fi
    else
        echo -e "${YELLOW}⚠${NC} $description: file not found for permission check"
        ((WARNINGS++))
    fi
}

echo ""
echo "1. Checking prerequisites..."

check_command "hermes" "Hermes CLI"
check_command "git" "Git"
check_command "systemctl" "systemd (for gateway)"

echo ""
echo "2. Checking A2A installation..."

check_command "a2a" "A2A CLI"
check_command "a2a-spawn" "A2A spawn utility"
check_directory "/root/projects/a2a-skill" "A2A skill repository"

echo ""
echo "3. Checking agent CLIs..."

check_command "claude" "Claude CLI"
check_command "opencode" "OpenCode CLI (fallback)"

echo ""
echo "4. Checking Hermes gateway status..."

if systemctl is-active hermes-gateway >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Hermes gateway is running"
else
    echo -e "${YELLOW}⚠${NC} Hermes gateway is not running"
    ((WARNINGS++))
fi

echo ""
echo "5. Checking project directories..."

check_directory "/root/projects" "Projects root directory"
check_directory "/root/.hermes" "Hermes configuration directory"

echo ""
echo "6. Checking critical files..."

check_file "/root/.hermes/skills/a2a-cheatsheet/SKILL.md" "A2A cheatsheet skill"
check_file "/root/.hermes/scripts/a2a-hardening-state.json" "State file (created on first run)"

echo ""
echo "7. Checking network connectivity..."

check_network "Basic internet access"

echo ""
echo "8. Validating GitHub repositories..."

check_url "https://github.com/javimosch/hermes-cron-a2a-teams" "Main repository"
check_url "https://github.com/javimosch/a2a-skill" "A2A skill repository"
check_url "https://github.com/javimosch/supercli" "SuperCLI repository"

echo ""
echo "9. Checking permissions and ownership..."

if [ "$(whoami)" = "root" ]; then
    echo -e "${GREEN}✓${NC} Running as root (required for setup)"
else
    echo -e "${YELLOW}⚠${NC} Not running as root (some operations may require sudo)"
    ((WARNINGS++))
fi

if id agent >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Agent user exists"

    # Check if agent user has proper home directory permissions
    agent_home=$(eval echo "~agent")
    if [ -d "$agent_home" ]; then
        check_permissions "$agent_home" "Agent home directory" "755"
    fi
else
    echo -e "${YELLOW}⚠${NC} Agent user not found (will be needed for secure spawning)"
    ((WARNINGS++))
fi

# Check permissions of validation scripts
check_permissions "./validate-setup.sh" "Setup validation script" "755"
if [ -f "./test-validate-setup.sh" ]; then
    check_permissions "./test-validate-setup.sh" "Test validation script" "755"
fi

# Check for A2A binary permissions if it exists
if command -v a2a >/dev/null 2>&1; then
    a2a_path=$(command -v a2a)
    check_permissions "$a2a_path" "A2A binary" "755"
fi

echo ""
echo "10. Checking database and state directory permissions..."

# Check for potential A2A database directories
if [ -d "/root/.a2a" ]; then
    echo -e "${GREEN}✓${NC} A2A root database directory exists"
    # Check if any project databases have correct ownership
    for db_dir in /root/.a2a/*/; do
        if [ -d "$db_dir" ]; then
            db_name=$(basename "$db_dir")
            echo -e "${GREEN}✓${NC} Found A2A project database: $db_name"
        fi
    done
fi

# Check for agent A2A database directory
agent_home=$(eval echo "~agent" 2>/dev/null || echo "/home/agent")
if [ -d "$agent_home/.a2a" ]; then
    echo -e "${GREEN}✓${NC} Agent A2A database directory exists"
else
    echo -e "${YELLOW}⚠${NC} Agent A2A database directory not found (created on first use)"
    ((WARNINGS++))
fi

# Check Hermes state directory
if [ -d "/root/.hermes" ]; then
    echo -e "${GREEN}✓${NC} Hermes configuration directory exists"
    if [ -d "/root/.hermes/scripts" ]; then
        echo -e "${GREEN}✓${NC} Hermes scripts directory exists"
    fi
fi

echo ""
echo "=========================================="
echo "Validation Summary:"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ $WARNINGS warnings found${NC}"
    exit 1
else
    echo -e "${RED}✗ $ERRORS errors and $WARNINGS warnings found${NC}"
    echo ""
    echo "Please address the errors above before proceeding with setup."
    exit 2
fi