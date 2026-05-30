#!/bin/bash

# Test script for validate-setup.sh
# This tests the validation functionality

echo "🧪 Testing validate-setup.sh"
echo "============================"

# Test that the script is executable
if [ -x "./validate-setup.sh" ]; then
    echo "✓ validate-setup.sh is executable"
else
    echo "✗ validate-setup.sh is not executable"
    exit 1
fi

# Test that the script has proper shebang
if head -n 1 validate-setup.sh | grep -q "#!/bin/bash"; then
    echo "✓ Script has proper shebang"
else
    echo "✗ Script missing or invalid shebang"
    exit 1
fi

# Test that the script doesn't have syntax errors
if bash -n validate-setup.sh; then
    echo "✓ Script has valid bash syntax"
else
    echo "✗ Script has syntax errors"
    exit 1
fi

# Test that script contains required functions
if grep -q "check_command" validate-setup.sh; then
    echo "✓ Contains check_command function"
else
    echo "✗ Missing check_command function"
    exit 1
fi

if grep -q "check_file" validate-setup.sh; then
    echo "✓ Contains check_file function"
else
    echo "✗ Missing check_file function"
    exit 1
fi

if grep -q "check_directory" validate-setup.sh; then
    echo "✓ Contains check_directory function"
else
    echo "✗ Missing check_directory function"
    exit 1
fi

if grep -q "check_url" validate-setup.sh; then
    echo "✓ Contains check_url function"
else
    echo "✗ Missing check_url function"
    exit 1
fi

# Test that script checks for key components mentioned in README
required_checks=(
    "hermes"
    "git"
    "a2a"
    "a2a-spawn"
    "claude"
    "systemctl"
)

for check in "${required_checks[@]}"; do
    if grep -q "$check" validate-setup.sh; then
        echo "✓ Checks for $check"
    else
        echo "✗ Missing check for $check"
        exit 1
    fi
done

# Test that script validates GitHub URLs from README
if grep -q "github.com/javimosch/hermes-cron-a2a-teams" validate-setup.sh; then
    echo "✓ Validates main repository URL"
else
    echo "✗ Missing main repository URL validation"
    exit 1
fi

if grep -q "github.com/javimosch/a2a-skill" validate-setup.sh; then
    echo "✓ Validates a2a-skill repository URL"
else
    echo "✗ Missing a2a-skill repository URL validation"
    exit 1
fi

# Test that script has proper exit codes
if grep -q "exit 0" validate-setup.sh && grep -q "exit 1" validate-setup.sh && grep -q "exit 2" validate-setup.sh; then
    echo "✓ Has proper exit codes"
else
    echo "✗ Missing proper exit codes"
    exit 1
fi

# Test output formatting
if grep -q "GREEN" validate-setup.sh && grep -q "RED" validate-setup.sh && grep -q "YELLOW" validate-setup.sh; then
    echo "✓ Has colored output"
else
    echo "✗ Missing colored output formatting"
    exit 1
fi

echo ""
echo "============================"
echo "✓ All tests passed!"

# Run a dry test (comment out actual validation to avoid side effects in test)
echo ""
echo "Running syntax validation test..."
bash -n validate-setup.sh
echo "✓ Script syntax is valid"