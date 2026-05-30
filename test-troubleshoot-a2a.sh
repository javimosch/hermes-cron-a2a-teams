#!/bin/bash

# Test script for troubleshoot-a2a.sh
# Validates the troubleshooting functionality

echo "🧪 Testing A2A Troubleshooting Tool"
echo "==================================="

TESTS_PASSED=0
TESTS_TOTAL=0

run_test() {
    local test_name="$1"
    local test_cmd="$2"
    ((TESTS_TOTAL++))

    echo -n "Testing $test_name... "

    if eval "$test_cmd" >/dev/null 2>&1; then
        echo "✓"
        ((TESTS_PASSED++))
    else
        echo "✗"
        echo "  Failed: $test_cmd"
    fi
}

# Test script structure and functions
run_test "script is executable" "[ -x './troubleshoot-a2a.sh' ]"
run_test "script has valid bash syntax" "bash -n troubleshoot-a2a.sh"
run_test "script has shebang" "head -n 1 troubleshoot-a2a.sh | grep -q '#!/bin/bash'"

# Test for required functions and patterns
run_test "contains check_and_fix function" "grep -q 'check_and_fix()' troubleshoot-a2a.sh"
run_test "has colored output" "grep -q 'RED=' troubleshoot-a2a.sh && grep -q 'GREEN=' troubleshoot-a2a.sh && grep -q 'YELLOW=' troubleshoot-a2a.sh"
run_test "tracks issues and fixes" "grep -q 'ISSUES_FOUND=' troubleshoot-a2a.sh && grep -q 'FIXES_APPLIED=' troubleshoot-a2a.sh"

# Test for specific checks mentioned in SKILL.md
run_test "checks Hermes gateway" "grep -q 'systemctl is-active hermes-gateway' troubleshoot-a2a.sh"
run_test "checks database ownership" "grep -q 'stat -c %U.*agent' troubleshoot-a2a.sh"
run_test "checks agent user" "grep -q 'id agent' troubleshoot-a2a.sh"
run_test "checks Claude auth" "grep -q 'claude.*credentials' troubleshoot-a2a.sh"
run_test "checks A2A tools" "grep -q 'command -v a2a' troubleshoot-a2a.sh"
run_test "checks state file" "grep -q 'a2a-hardening-state.json' troubleshoot-a2a.sh"

# Test for common fixes
run_test "can fix gateway" "grep -q 'systemctl start hermes-gateway' troubleshoot-a2a.sh"
run_test "can fix ownership" "grep -q 'chown -R agent:agent' troubleshoot-a2a.sh"
run_test "can reset state file" "grep -q 'current_idx.*session.*use_claude' troubleshoot-a2a.sh"

# Test for network checks
run_test "has network connectivity check" "grep -q 'curl.*google.com' troubleshoot-a2a.sh"
run_test "has GitHub access check" "grep -q 'github.com.*a2a-skill' troubleshoot-a2a.sh"

# Test for environment variable handling
run_test "checks CLAUDE_CODE env var" "grep -q 'CLAUDE_CODE_DANGEROUSLY_SKIP_PERMISSIONS' troubleshoot-a2a.sh"

# Test for proper exit codes and summary
run_test "has exit code handling" "grep -q 'exit.*ISSUES_FOUND' troubleshoot-a2a.sh"
run_test "has summary section" "grep -q 'Troubleshooting Summary' troubleshoot-a2a.sh"

# Test for references to documentation
run_test "references SKILL.md" "grep -q 'SKILL.md' troubleshoot-a2a.sh"
run_test "references validate-setup.sh" "grep -q 'validate-setup.sh' troubleshoot-a2a.sh"

# Test specific error scenarios mentioned in SKILL.md
run_test "handles PID checking" "grep -q 'kill -0' troubleshoot-a2a.sh"
run_test "handles JSON validation" "grep -q 'jq empty' troubleshoot-a2a.sh"
run_test "checks for stale processes" "grep -q 'ps.*grep.*a2a-kit' troubleshoot-a2a.sh"

# Test that timeouts are reasonable
run_test "uses reasonable timeouts" "grep -q 'connect-timeout 5' troubleshoot-a2a.sh"

echo ""
echo "==================================="
echo "Test Results: $TESTS_PASSED/$TESTS_TOTAL passed"

if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
    echo "✓ All troubleshooting tool tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi