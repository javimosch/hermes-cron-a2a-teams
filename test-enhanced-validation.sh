#!/bin/bash

# Test script for enhanced validation functionality
# This tests the new features added to validate-setup.sh

echo "🧪 Testing Enhanced Validation Features"
echo "======================================="

# Test that new functions exist
echo "Checking for new functions..."

if grep -q "check_network" validate-setup.sh; then
    echo "✓ check_network function exists"
else
    echo "✗ Missing check_network function"
    exit 1
fi

if grep -q "check_permissions" validate-setup.sh; then
    echo "✓ check_permissions function exists"
else
    echo "✗ Missing check_permissions function"
    exit 1
fi

# Test that timeout parameters are present in URL checks
if grep -q "\--connect-timeout" validate-setup.sh && grep -q "\--max-time" validate-setup.sh; then
    echo "✓ URL checks include timeout parameters"
else
    echo "✗ Missing timeout parameters in URL checks"
    exit 1
fi

# Test that network check is called
if grep -q "check_network.*Basic internet access" validate-setup.sh; then
    echo "✓ Network connectivity check is called"
else
    echo "✗ Missing network connectivity check call"
    exit 1
fi

# Test that permission checks are performed
if grep -q "check_permissions.*Agent home" validate-setup.sh; then
    echo "✓ Agent home permissions check exists"
else
    echo "✗ Missing agent home permissions check"
    exit 1
fi

# Test that script permissions are checked
if grep -q "check_permissions.*validation script" validate-setup.sh; then
    echo "✓ Script permissions check exists"
else
    echo "✗ Missing script permissions check"
    exit 1
fi

# Test that database directory checks are present
if grep -q "database.*directory.*permissions" validate-setup.sh; then
    echo "✓ Database directory checks exist"
else
    echo "✗ Missing database directory checks"
    exit 1
fi

# Test the script still has proper structure
echo ""
echo "Testing script structure..."

# Count validation sections
sections=$(grep -c "echo.*[0-9]\+\." validate-setup.sh)
if [ "$sections" -ge 8 ]; then
    echo "✓ Script has adequate validation sections ($sections)"
else
    echo "✗ Script may be missing validation sections ($sections found)"
    exit 1
fi

# Test that error counting is maintained
if grep -q "ERRORS=" validate-setup.sh && grep -q "WARNINGS=" validate-setup.sh; then
    echo "✓ Error and warning tracking maintained"
else
    echo "✗ Missing error/warning tracking"
    exit 1
fi

# Test that colored output is preserved
if grep -q "GREEN=" validate-setup.sh && grep -q "RED=" validate-setup.sh && grep -q "YELLOW=" validate-setup.sh; then
    echo "✓ Colored output formatting preserved"
else
    echo "✗ Missing colored output formatting"
    exit 1
fi

echo ""
echo "Testing syntax and executability..."

# Test syntax
if bash -n validate-setup.sh; then
    echo "✓ Enhanced validation script has valid syntax"
else
    echo "✗ Enhanced validation script has syntax errors"
    exit 1
fi

# Test that script is executable
if [ -x "./validate-setup.sh" ]; then
    echo "✓ Enhanced validation script is executable"
else
    echo "✗ Enhanced validation script is not executable"
    exit 1
fi

echo ""
echo "======================================="
echo "✓ All enhanced validation tests passed!"
echo ""
echo "Enhanced features validated:"
echo "- Network connectivity checking"
echo "- Timeout parameters for URL validation"
echo "- File permission validation"
echo "- Database directory checks"
echo "- Agent user home directory validation"