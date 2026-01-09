#!/bin/bash
# =============================================================================
# build-install.sh - Build and Install Custom SELinux Policy Module
# =============================================================================
#
# This script compiles and installs the myapp SELinux policy module.
#
# Prerequisites:
#   - policycoreutils-devel package
#   - Root privileges
#
# Usage: sudo bash build-install.sh
#
# =============================================================================

set -e

MODULE_NAME="myapp"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "Build and Install SELinux Policy: ${MODULE_NAME}"
echo "============================================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script requires root privileges"
    echo "Usage: sudo bash $0"
    exit 1
fi

# Change to script directory
cd "$SCRIPT_DIR"

# Check for required tools
echo "[Step 1] Checking Prerequisites"
echo "------------------------------------------------------------"

MISSING=""

if ! command -v checkmodule &> /dev/null; then
    MISSING="$MISSING checkmodule"
fi

if ! command -v semodule_package &> /dev/null; then
    MISSING="$MISSING semodule_package"
fi

if ! command -v semodule &> /dev/null; then
    MISSING="$MISSING semodule"
fi

if [ -n "$MISSING" ]; then
    echo "Error: Missing required tools:$MISSING"
    echo ""
    echo "Install with:"
    echo "  RHEL/Rocky/Alma: dnf install policycoreutils-devel"
    echo "  Fedora: dnf install policycoreutils-devel"
    exit 1
fi

echo "All prerequisites met"
echo ""

# Check for source files
echo "[Step 2] Checking Source Files"
echo "------------------------------------------------------------"

if [ ! -f "${MODULE_NAME}.te" ]; then
    echo "Error: ${MODULE_NAME}.te not found"
    exit 1
fi

echo "Found: ${MODULE_NAME}.te"

if [ -f "${MODULE_NAME}.fc" ]; then
    echo "Found: ${MODULE_NAME}.fc"
    HAS_FC=1
else
    echo "No ${MODULE_NAME}.fc found (file contexts will not be set)"
    HAS_FC=0
fi

echo ""

# Confirm before proceeding
echo "[Step 3] Confirmation"
echo "------------------------------------------------------------"
echo ""
echo "This will:"
echo "  1. Compile ${MODULE_NAME}.te into a policy module"
echo "  2. Install the module into the running SELinux policy"
if [ "$HAS_FC" -eq 1 ]; then
    echo "  3. Apply file contexts from ${MODULE_NAME}.fc"
fi
echo ""

read -p "Proceed? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""

# Compile the policy
echo "[Step 4] Compiling Policy"
echo "------------------------------------------------------------"

echo "Running: checkmodule -M -m -o ${MODULE_NAME}.mod ${MODULE_NAME}.te"
checkmodule -M -m -o "${MODULE_NAME}.mod" "${MODULE_NAME}.te"
echo "Created: ${MODULE_NAME}.mod"

echo ""

# Package the policy
echo "[Step 5] Packaging Policy"
echo "------------------------------------------------------------"

if [ "$HAS_FC" -eq 1 ]; then
    echo "Running: semodule_package -o ${MODULE_NAME}.pp -m ${MODULE_NAME}.mod -f ${MODULE_NAME}.fc"
    semodule_package -o "${MODULE_NAME}.pp" -m "${MODULE_NAME}.mod" -f "${MODULE_NAME}.fc"
else
    echo "Running: semodule_package -o ${MODULE_NAME}.pp -m ${MODULE_NAME}.mod"
    semodule_package -o "${MODULE_NAME}.pp" -m "${MODULE_NAME}.mod"
fi
echo "Created: ${MODULE_NAME}.pp"

echo ""

# Check if module already exists
echo "[Step 6] Installing Policy Module"
echo "------------------------------------------------------------"

EXISTING=$(semodule -l | grep "^${MODULE_NAME}" || true)
if [ -n "$EXISTING" ]; then
    echo "Existing module found: $EXISTING"
    echo "Will be upgraded..."
fi

echo "Running: semodule -i ${MODULE_NAME}.pp"
semodule -i "${MODULE_NAME}.pp"

echo ""

# Verify installation
echo "[Step 7] Verification"
echo "------------------------------------------------------------"

INSTALLED=$(semodule -l | grep "^${MODULE_NAME}")
if [ -n "$INSTALLED" ]; then
    echo "Successfully installed: $INSTALLED"
else
    echo "Error: Module not found after installation"
    exit 1
fi

echo ""

# Apply file contexts if applicable
if [ "$HAS_FC" -eq 1 ]; then
    echo "[Step 8] Applying File Contexts"
    echo "------------------------------------------------------------"
    echo ""
    echo "To apply file contexts, run:"
    echo "  restorecon -Rv /opt/myapp /var/log/myapp"
    echo ""
    echo "Note: Create the directories first if they don't exist"
    echo ""
fi

# Register port if needed
echo "[Step 9] Port Registration"
echo "------------------------------------------------------------"
echo ""
echo "If myapp uses port 8888, register it:"
echo "  semanage port -a -t myapp_port_t -p tcp 8888"
echo ""
echo "Check existing ports:"
echo "  semanage port -l | grep myapp"
echo ""

# Cleanup
echo "[Step 10] Cleanup"
echo "------------------------------------------------------------"
rm -f "${MODULE_NAME}.mod"
echo "Removed intermediate file: ${MODULE_NAME}.mod"
echo "Kept: ${MODULE_NAME}.pp (for reuse/distribution)"

echo ""

# Summary
echo "============================================================"
echo "Installation Complete"
echo "============================================================"
echo ""
echo "Module: ${MODULE_NAME}"
echo "Status: Installed"
echo ""
echo "Next steps:"
echo "  1. Create application directories if needed"
echo "  2. Apply file contexts: restorecon -Rv /opt/myapp /var/log/myapp"
echo "  3. Register port: semanage port -a -t myapp_port_t -p tcp 8888"
echo "  4. Start your application and test"
echo ""
echo "To remove the module later:"
echo "  semodule -r ${MODULE_NAME}"
echo ""
