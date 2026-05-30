#!/bin/bash

# Documentation Consistency Checker
# Validates consistency between README.md and SKILL.md

echo "📝 Documentation Consistency Check"
echo "=================================="

ERRORS=0
WARNINGS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo "1. Checking command consistency..."

# Check if README and SKILL use same command syntax
readme_cronjob=$(grep -c "cronjob action=create" README.md || true)
skill_cronjob=$(grep -c "cronjob action=create" .agents/skills/hermes-a2a-cron-agent-maintainer/SKILL.md || true)

if [ "$readme_cronjob" -gt 0 ] && [ "$skill_cronjob" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} cronjob command syntax consistent"
else
    echo -e "${RED}✗${NC} Inconsistent cronjob command syntax between README and SKILL"
    ((ERRORS++))
fi

echo ""
echo "2. Checking URL consistency..."

# Extract URLs from both files and compare
readme_urls=$(grep -o 'https://github.com/[^)]*' README.md | sort -u)
skill_urls=$(grep -o 'https://github.com/[^)]*' .agents/skills/hermes-a2a-cron-agent-maintainer/SKILL.md | sort -u)

# Check if main repository URLs are consistent
main_repo_readme=$(echo "$readme_urls" | grep "hermes-cron-a2a-teams" | head -1)
main_repo_skill=$(echo "$skill_urls" | grep "hermes-cron-a2a-teams" | head -1)

if [ "$main_repo_readme" = "$main_repo_skill" ] && [ -n "$main_repo_readme" ]; then
    echo -e "${GREEN}✓${NC} Main repository URL consistent"
else
    echo -e "${YELLOW}⚠${NC} Main repository URL may be inconsistent"
    ((WARNINGS++))
fi

# Check a2a-skill URL consistency
a2a_repo_readme=$(echo "$readme_urls" | grep "a2a-skill" | head -1)
a2a_repo_skill=$(echo "$skill_urls" | grep "a2a-skill" | head -1)

if [ "$a2a_repo_readme" = "$a2a_repo_skill" ] && [ -n "$a2a_repo_readme" ]; then
    echo -e "${GREEN}✓${NC} A2A skill repository URL consistent"
else
    echo -e "${YELLOW}⚠${NC} A2A skill repository URL may be inconsistent"
    ((WARNINGS++))
fi

echo ""
echo "3. Checking version references..."

# Check for version-specific references that might become outdated
version_refs=$(grep -n "claude-.*4\|sonnet.*4\|haiku.*4" README.md .agents/skills/hermes-a2a-cron-agent-maintainer/SKILL.md | wc -l)

if [ "$version_refs" -gt 0 ]; then
    echo -e "${YELLOW}⚠${NC} Found $version_refs model version references - verify these are current"
    ((WARNINGS++))
else
    echo -e "${GREEN}✓${NC} No specific model version references found"
fi

echo ""
echo "4. Checking file path references..."

# Check for hard-coded paths that might be environment-specific
hardcoded_paths=$(grep -n "/root/" README.md | wc -l)

if [ "$hardcoded_paths" -gt 0 ]; then
    echo -e "${YELLOW}⚠${NC} Found $hardcoded_paths hard-coded /root/ paths in README"
    echo "    Consider using \$HOME or relative paths where possible"
    ((WARNINGS++))
else
    echo -e "${GREEN}✓${NC} No hard-coded /root/ paths in README"
fi

echo ""
echo "5. Checking for broken internal references..."

# Check for references to sections that might not exist
broken_refs=0

# Check if README references to SKILL.md sections exist
if grep -q "from .agents/skills/SKILL.md" README.md; then
    if [ -f ".agents/skills/hermes-a2a-cron-agent-maintainer/SKILL.md" ]; then
        echo -e "${GREEN}✓${NC} SKILL.md reference is valid"
    else
        echo -e "${RED}✗${NC} Referenced SKILL.md file not found"
        ((ERRORS++))
    fi
fi

echo ""
echo "6. Checking for outdated information..."

# Look for date-specific information that might be outdated
current_year=$(date +%Y)
old_dates=$(grep -o "202[0-9]" README.md .agents/skills/hermes-a2a-cron-agent-maintainer/SKILL.md | cut -d: -f2 | sort -u | grep -E "^[0-9]{4}$")

for date in $old_dates; do
    if [ -n "$date" ] && [ "$date" -lt $((current_year - 1)) ]; then
        echo -e "${YELLOW}⚠${NC} Found potentially outdated date: $date"
        ((WARNINGS++))
        break
    fi
done

if [ -z "$old_dates" ]; then
    echo -e "${GREEN}✓${NC} No specific year references found"
fi

echo ""
echo "=================================="
echo "Documentation Check Summary:"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ Documentation appears consistent!${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ $WARNINGS warnings found${NC}"
    echo "Consider reviewing warnings above for potential improvements."
    exit 1
else
    echo -e "${RED}✗ $ERRORS errors and $WARNINGS warnings found${NC}"
    echo "Please address the errors above to ensure documentation consistency."
    exit 2
fi