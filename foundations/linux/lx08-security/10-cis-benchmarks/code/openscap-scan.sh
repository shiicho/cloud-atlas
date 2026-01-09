#!/bin/bash
# =============================================================================
# OpenSCAP CIS Benchmark Scan Script
# =============================================================================
#
# Description:
#   Automated CIS Level 1 compliance scan using OpenSCAP.
#   Detects OS type and selects appropriate SCAP content.
#
# Usage:
#   sudo bash openscap-scan.sh [profile]
#
# Profiles (optional):
#   l1 or cis_server_l1  - CIS Level 1 Server (default)
#   l2 or cis_server_l2  - CIS Level 2 Server
#   stig                 - DISA STIG
#
# Output:
#   /var/log/openscap/cis-report-YYYYMMDD-HHMMSS.html
#   /var/log/openscap/cis-results-YYYYMMDD-HHMMSS.xml
#
# Author: cloud-atlas
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

REPORT_DIR="/var/log/openscap"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_HTML="${REPORT_DIR}/cis-report-${TIMESTAMP}.html"
RESULTS_XML="${REPORT_DIR}/cis-results-${TIMESTAMP}.xml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID="${ID}"
        OS_VERSION="${VERSION_ID%%.*}"
        log_info "Detected OS: ${NAME} ${VERSION_ID}"
    else
        log_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
}

find_scap_content() {
    local content_dir="/usr/share/xml/scap/ssg/content"

    case "${OS_ID}" in
        rhel|centos|rocky|almalinux|ol)
            SCAP_CONTENT="${content_dir}/ssg-rhel${OS_VERSION}-ds.xml"
            ;;
        fedora)
            SCAP_CONTENT="${content_dir}/ssg-fedora-ds.xml"
            ;;
        debian)
            SCAP_CONTENT="${content_dir}/ssg-debian${OS_VERSION}-ds.xml"
            ;;
        ubuntu)
            # Ubuntu uses YYMM format (e.g., 2204 for 22.04)
            local ubuntu_version="${VERSION_ID//./}"
            SCAP_CONTENT="${content_dir}/ssg-ubuntu${ubuntu_version}-ds.xml"
            ;;
        *)
            log_error "Unsupported OS: ${OS_ID}"
            exit 1
            ;;
    esac

    if [[ ! -f "${SCAP_CONTENT}" ]]; then
        log_error "SCAP content not found: ${SCAP_CONTENT}"
        log_info "Please install scap-security-guide:"
        log_info "  RHEL/Rocky: sudo dnf install scap-security-guide"
        log_info "  Ubuntu:     sudo apt install ssg-debderived ssg-base"
        exit 1
    fi

    log_info "Using SCAP content: ${SCAP_CONTENT}"
}

select_profile() {
    local profile_arg="${1:-l1}"

    case "${profile_arg}" in
        l1|cis_server_l1)
            PROFILE="xccdf_org.ssgproject.content_profile_cis_server_l1"
            PROFILE_NAME="CIS Level 1 Server"
            ;;
        l2|cis_server_l2)
            PROFILE="xccdf_org.ssgproject.content_profile_cis_server_l2"
            PROFILE_NAME="CIS Level 2 Server"
            ;;
        stig)
            PROFILE="xccdf_org.ssgproject.content_profile_stig"
            PROFILE_NAME="DISA STIG"
            ;;
        *)
            # Try to use as-is (full profile ID)
            PROFILE="${profile_arg}"
            PROFILE_NAME="${profile_arg}"
            ;;
    esac

    log_info "Selected profile: ${PROFILE_NAME}"
}

check_dependencies() {
    if ! command -v oscap &> /dev/null; then
        log_error "OpenSCAP not installed."
        log_info "Please install OpenSCAP:"
        log_info "  RHEL/Rocky: sudo dnf install openscap-scanner"
        log_info "  Ubuntu:     sudo apt install libopenscap8"
        exit 1
    fi

    log_info "OpenSCAP version: $(oscap --version | head -1)"
}

create_report_dir() {
    if [[ ! -d "${REPORT_DIR}" ]]; then
        mkdir -p "${REPORT_DIR}"
        chmod 750 "${REPORT_DIR}"
        log_info "Created report directory: ${REPORT_DIR}"
    fi
}

run_scan() {
    log_info "Starting compliance scan..."
    log_info "This may take several minutes..."
    echo ""

    local start_time=$(date +%s)

    # Run the scan
    oscap xccdf eval \
        --profile "${PROFILE}" \
        --results "${RESULTS_XML}" \
        --report "${REPORT_HTML}" \
        "${SCAP_CONTENT}" 2>&1 || true  # Don't fail on non-zero exit (expected when there are failures)

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    log_success "Scan completed in ${duration} seconds"
}

show_summary() {
    echo ""
    echo "=========================================="
    echo "         SCAN RESULTS SUMMARY"
    echo "=========================================="
    echo ""

    # Extract counts from XML results
    local pass_count=$(grep -c 'result="pass"' "${RESULTS_XML}" 2>/dev/null || echo "0")
    local fail_count=$(grep -c 'result="fail"' "${RESULTS_XML}" 2>/dev/null || echo "0")
    local notapplicable_count=$(grep -c 'result="notapplicable"' "${RESULTS_XML}" 2>/dev/null || echo "0")
    local notchecked_count=$(grep -c 'result="notchecked"' "${RESULTS_XML}" 2>/dev/null || echo "0")
    local error_count=$(grep -c 'result="error"' "${RESULTS_XML}" 2>/dev/null || echo "0")

    local total=$((pass_count + fail_count))
    local pass_rate=0
    if [[ ${total} -gt 0 ]]; then
        pass_rate=$(echo "scale=1; ${pass_count} * 100 / ${total}" | bc)
    fi

    echo -e "${GREEN}Pass:${NC}            ${pass_count}"
    echo -e "${RED}Fail:${NC}            ${fail_count}"
    echo -e "${YELLOW}Not Applicable:${NC}  ${notapplicable_count}"
    echo -e "${BLUE}Not Checked:${NC}     ${notchecked_count}"
    if [[ ${error_count} -gt 0 ]]; then
        echo -e "${RED}Error:${NC}           ${error_count}"
    fi
    echo "----------------------------------------"
    echo -e "Pass Rate:       ${GREEN}${pass_rate}%${NC}"
    echo ""
    echo "Reports generated:"
    echo "  HTML: ${REPORT_HTML}"
    echo "  XML:  ${RESULTS_XML}"
    echo ""

    # Show top 10 fail items
    if [[ ${fail_count} -gt 0 ]]; then
        echo "Top Fail Items (showing first 10):"
        echo "----------------------------------------"
        grep -B 2 'result="fail"' "${RESULTS_XML}" | \
            grep 'rule id' | \
            sed 's/.*rule id="\([^"]*\)".*/\1/' | \
            sed 's/xccdf_org.ssgproject.content_rule_//' | \
            head -10
        echo ""
    fi
}

show_usage() {
    echo "Usage: sudo $0 [profile]"
    echo ""
    echo "Profiles:"
    echo "  l1, cis_server_l1  - CIS Level 1 Server (default)"
    echo "  l2, cis_server_l2  - CIS Level 2 Server"
    echo "  stig               - DISA STIG"
    echo ""
    echo "Examples:"
    echo "  sudo $0              # Run CIS Level 1 scan"
    echo "  sudo $0 l2           # Run CIS Level 2 scan"
    echo "  sudo $0 stig         # Run STIG scan"
    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    # Handle help option
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        show_usage
        exit 0
    fi

    echo ""
    echo "=========================================="
    echo "   OpenSCAP CIS Compliance Scanner"
    echo "=========================================="
    echo ""

    check_root
    check_dependencies
    detect_os
    find_scap_content
    select_profile "${1:-l1}"
    create_report_dir
    run_scan
    show_summary

    echo "Next steps:"
    echo "  1. Review the HTML report in your browser"
    echo "  2. Analyze each Fail item"
    echo "  3. Decide: Remediate or Document Exception"
    echo "  4. For exceptions, use: code/exception-template.md"
    echo ""
}

main "$@"
