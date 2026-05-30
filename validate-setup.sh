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

    if curl -s --head "$url" | head -n 1 | grep -q "200 OK"; then
        echo -e "${GREEN}✓${NC} $description: $url accessible"
    else
        echo -e "${YELLOW}⚠${NC} $description: $url may not be accessible"
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
echo "7. Validating GitHub repositories..."

check_url "https://github.com/javimosch/hermes-cron-a2a-teams" "Main repository"
check_url "https://github.com/javimosch/a2a-skill" "A2A skill repository"
check_url "https://github.com/javimosch/supercli" "SuperCLI repository"

echo ""
echo "8. Checking permissions..."

if [ "$(whoami)" = "root" ]; then
    echo -e "${GREEN}✓${NC} Running as root (required for setup)"
else
    echo -e "${YELLOW}⚠${NC} Not running as root (some operations may require sudo)"
    ((WARNINGS++))
fi

if id agent >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Agent user exists"
else
    echo -e "${YELLOW}⚠${NC} Agent user not found (will be needed for secure spawning)"
    ((WARNINGS++))
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