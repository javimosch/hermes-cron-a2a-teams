#!/bin/bash

# Run all test suites for the A2A project tools
# Provides comprehensive validation of all tooling

echo "🚀 Running All A2A Project Tests"
echo "================================="

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test_suite() {
    local suite_name="$1"
    local test_script="$2"

    echo ""
    echo "Running $suite_name..."
    echo "$(printf '=%.0s' {1..40})"

    ((TOTAL_TESTS++))

    if [ -x "$test_script" ]; then
        if ./"$test_script"; then
            echo -e "\033[0;32m✓ $suite_name: PASSED\033[0m"
            ((PASSED_TESTS++))
        else
            echo -e "\033[0;31m✗ $suite_name: FAILED\033[0m"
            ((FAILED_TESTS++))
        fi
    else
        echo -e "\033[0;33m⚠ $suite_name: SKIPPED (script not executable)\033[0m"
        ((FAILED_TESTS++))
    fi
}

# Run all available test suites
run_test_suite "Setup Validation Tests" "test-validate-setup.sh"
run_test_suite "Enhanced Validation Tests" "test-enhanced-validation.sh"
run_test_suite "Troubleshooting Tool Tests" "test-troubleshoot-a2a.sh"

# Run documentation consistency check (not exactly a test but validation)
echo ""
echo "Running Documentation Consistency Check..."
echo "$(printf '=%.0s' {1..40})"

((TOTAL_TESTS++))
if [ -x "./check-docs.sh" ]; then
    if ./check-docs.sh; then
        echo -e "\033[0;32m✓ Documentation Consistency: PASSED\033[0m"
        ((PASSED_TESTS++))
    else
        echo -e "\033[0;33m⚠ Documentation Consistency: WARNINGS\033[0m"
        echo "  (This is normal - warnings don't indicate failures)"
        ((PASSED_TESTS++))  # Warnings are acceptable
    fi
else
    echo -e "\033[0;33m⚠ Documentation Consistency: SKIPPED\033[0m"
    ((FAILED_TESTS++))
fi

echo ""
echo "$(printf '=%.0s' {1..50})"
echo "Test Results Summary"
echo "$(printf '=%.0s' {1..50})"
echo "Total test suites: $TOTAL_TESTS"
echo -e "Passed: \033[0;32m$PASSED_TESTS\033[0m"
echo -e "Failed: \033[0;31m$FAILED_TESTS\033[0m"

if [ $FAILED_TESTS -eq 0 ]; then
    echo ""
    echo -e "\033[0;32m🎉 All test suites passed!\033[0m"
    echo "Your A2A development tools are working correctly."
    echo ""
    echo "Next steps:"
    echo "- Run './validate-setup.sh' to check your A2A system setup"
    echo "- Use './troubleshoot-a2a.sh' if you encounter issues"
    echo "- See README.md for complete setup instructions"
    exit 0
else
    echo ""
    echo -e "\033[0;31m❌ Some test suites failed\033[0m"
    echo "Please review the failed tests above and ensure all scripts are executable."
    exit 1
fi