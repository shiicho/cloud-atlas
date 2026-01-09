#!/bin/bash
# ==============================================================================
# log-analyzer.sh - Web Server Log Analysis Tool
# ==============================================================================
#
# Description:
#   Comprehensive log analysis tool for Apache/Nginx Combined Log Format.
#   Generates traffic summaries, status code breakdowns, top IPs, performance
#   metrics, and security alerts.
#
# Usage:
#   ./log-analyzer.sh [OPTIONS] <access.log>
#
# Options:
#   --format <text|csv|json>  Output format (default: text)
#   --from <HH:MM>            Start time filter
#   --to <HH:MM>              End time filter
#   --threshold <N>           High-frequency IP threshold (default: 50)
#   --error-log <file>        Error log for correlation analysis
#   --top <N>                 Number of top IPs to show (default: 10)
#   -h, --help                Show this help message
#
# Examples:
#   ./log-analyzer.sh access.log
#   ./log-analyzer.sh --format csv access.log > report.csv
#   ./log-analyzer.sh --format json access.log | jq .
#   ./log-analyzer.sh --from "09:00" --to "12:00" access.log
#   ./log-analyzer.sh --error-log error.log access.log
#
# Author: cloud-atlas project (https://github.com/shiicho/cloud-atlas)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

OUTPUT_FORMAT="text"
FROM_TIME=""
TO_TIME=""
THRESHOLD=50
ERROR_LOG=""
TOP_N=10
ACCESS_LOG=""

# ==============================================================================
# Helper Functions
# ==============================================================================

show_help() {
    cat << 'EOF'
Usage: log-analyzer.sh [OPTIONS] <access.log>

Web Server Log Analysis Tool - Analyze Apache/Nginx Combined Log Format

OPTIONS:
  --format <text|csv|json>  Output format (default: text)
  --from <HH:MM>            Start time filter (e.g., "09:00")
  --to <HH:MM>              End time filter (e.g., "18:00")
  --threshold <N>           High-frequency IP threshold (default: 50)
  --error-log <file>        Error log for correlation analysis
  --top <N>                 Number of top IPs to show (default: 10)
  -h, --help                Show this help message

EXAMPLES:
  # Basic analysis
  ./log-analyzer.sh access.log

  # CSV output for Excel
  ./log-analyzer.sh --format csv access.log > report.csv

  # JSON output for automation
  ./log-analyzer.sh --format json access.log | jq .

  # Time-filtered analysis
  ./log-analyzer.sh --from "09:00" --to "12:00" access.log

  # Multi-file correlation
  ./log-analyzer.sh --error-log error.log access.log

OUTPUT FORMATS:
  text  - Human-readable report (default)
  csv   - Comma-separated values for spreadsheets
  json  - JSON for automation and APIs
EOF
}

error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# ==============================================================================
# Argument Parsing
# ==============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format)
                OUTPUT_FORMAT="${2:-}"
                if [[ ! "$OUTPUT_FORMAT" =~ ^(text|csv|json)$ ]]; then
                    error_exit "Invalid format: $OUTPUT_FORMAT (use text, csv, or json)"
                fi
                shift 2
                ;;
            --from)
                FROM_TIME="${2:-}"
                shift 2
                ;;
            --to)
                TO_TIME="${2:-}"
                shift 2
                ;;
            --threshold)
                THRESHOLD="${2:-50}"
                shift 2
                ;;
            --error-log)
                ERROR_LOG="${2:-}"
                if [[ -n "$ERROR_LOG" && ! -f "$ERROR_LOG" ]]; then
                    error_exit "Error log file not found: $ERROR_LOG"
                fi
                shift 2
                ;;
            --top)
                TOP_N="${2:-10}"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                error_exit "Unknown option: $1"
                ;;
            *)
                ACCESS_LOG="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$ACCESS_LOG" ]]; then
        error_exit "Access log file is required. Use --help for usage."
    fi

    if [[ ! -f "$ACCESS_LOG" ]]; then
        error_exit "Access log file not found: $ACCESS_LOG"
    fi
}

# ==============================================================================
# Data Collection Functions
# ==============================================================================

# Apply time filter if specified
get_filtered_log() {
    if [[ -n "$FROM_TIME" || -n "$TO_TIME" ]]; then
        local from="${FROM_TIME:-00:00}"
        local to="${TO_TIME:-23:59}"
        awk -v from="$from" -v to="$to" '
        {
            # Extract time from [04/Jan/2026:09:15:30 +0900]
            # Format: [DD/Mon/YYYY:HH:MM:SS +TZ]
            # We want HH:MM (characters 14-18 from $4, 0-indexed after removing [)
            ts = $4
            gsub(/\[/, "", ts)
            # ts is now: 04/Jan/2026:09:15:30
            # Time starts at position 13 (0-indexed): "09:15:30"
            if (length(ts) >= 17) {
                time = substr(ts, 13, 5)  # Extract HH:MM
                if (time >= from && time <= to) {
                    print $0
                }
            }
        }
        ' "$ACCESS_LOG"
    else
        cat "$ACCESS_LOG"
    fi
}

# Collect all metrics in one awk pass for efficiency
collect_metrics() {
    get_filtered_log | awk '
    BEGIN {
        s2xx = 0; s3xx = 0; s4xx = 0; s5xx = 0
        total = 0
        sum_rt = 0
        max_rt = 0
        max_rt_method = ""
        max_rt_path = ""
        first_time = ""
        last_time = ""
        rt_count = 0
    }
    {
        total++

        # IP address
        ip = $1
        ip_count[ip]++

        # Timestamp
        ts = $4
        gsub(/\[/, "", ts)
        if (first_time == "") first_time = ts
        last_time = ts

        # Status code
        status = $9
        if (status ~ /^2/) s2xx++
        else if (status ~ /^3/) s3xx++
        else if (status ~ /^4/) s4xx++
        else if (status ~ /^5/) s5xx++

        # Response time (last field, if numeric)
        rt = $NF
        if (rt ~ /^[0-9]+$/) {
            sum_rt += rt
            rt_count++
            if (rt > max_rt) {
                max_rt = rt
                gsub(/"/, "", $6)
                max_rt_method = $6
                max_rt_path = $7
            }
        }
    }
    END {
        # Basic stats
        printf "total_requests=%d\n", total

        # Count unique IPs
        unique_ips = 0
        for (ip in ip_count) unique_ips++
        printf "unique_ips=%d\n", unique_ips

        # Time range
        printf "time_start=%s\n", first_time
        printf "time_end=%s\n", last_time

        # Status codes
        printf "s2xx=%d\n", s2xx
        printf "s3xx=%d\n", s3xx
        printf "s4xx=%d\n", s4xx
        printf "s5xx=%d\n", s5xx

        # Percentages
        if (total > 0) {
            printf "p2xx=%.1f\n", s2xx * 100 / total
            printf "p3xx=%.1f\n", s3xx * 100 / total
            printf "p4xx=%.1f\n", s4xx * 100 / total
            printf "p5xx=%.1f\n", s5xx * 100 / total
        }

        # Response time metrics (avg and max only, P95 calculated separately)
        if (rt_count > 0) {
            printf "avg_rt=%d\n", sum_rt / rt_count
            printf "rt_count=%d\n", rt_count
            printf "max_rt=%d\n", max_rt
            printf "max_rt_method=%s\n", max_rt_method
            printf "max_rt_path=%s\n", max_rt_path
        }

        # Top IPs (output as ip:count pairs)
        printf "TOP_IPS_START\n"
        for (ip in ip_count) {
            printf "%d %s\n", ip_count[ip], ip
        }
        printf "TOP_IPS_END\n"

        # High frequency IPs (for security alerts)
        printf "HIGH_FREQ_IPS_START\n"
        for (ip in ip_count) {
            printf "%d %s\n", ip_count[ip], ip
        }
        printf "HIGH_FREQ_IPS_END\n"
    }
    '
}

# Calculate P95 response time using sort (portable method)
calculate_p95() {
    get_filtered_log | awk '{rt = $NF; if (rt ~ /^[0-9]+$/) print rt}' | sort -n | awk '
    {
        values[NR] = $1
    }
    END {
        if (NR > 0) {
            p95_idx = int(NR * 0.95)
            if (p95_idx < 1) p95_idx = 1
            print values[p95_idx]
        } else {
            print "0"
        }
    }'
}

# Get top N IPs sorted
get_top_ips() {
    local metrics="$1"
    local n="$2"
    echo "$metrics" | sed -n '/TOP_IPS_START/,/TOP_IPS_END/p' | grep -v '_START\|_END' | sort -rn | head -n "$n"
}

# Get high frequency IPs above threshold
get_high_freq_ips() {
    local metrics="$1"
    local threshold="$2"
    echo "$metrics" | sed -n '/HIGH_FREQ_IPS_START/,/HIGH_FREQ_IPS_END/p' | grep -v '_START\|_END' | awk -v t="$threshold" '$1 >= t'
}

# Get metric value by key
get_metric() {
    local metrics="$1"
    local key="$2"
    echo "$metrics" | grep "^${key}=" | cut -d= -f2
}

# ==============================================================================
# Error Log Correlation
# ==============================================================================

correlate_error_log() {
    local metrics="$1"
    local error_log="$2"

    if [[ -z "$error_log" || ! -f "$error_log" ]]; then
        return
    fi

    # Get high frequency IPs (threshold 10 for correlation)
    local high_freq_ips
    high_freq_ips=$(get_high_freq_ips "$metrics" 10)

    echo "$high_freq_ips" | while read -r count ip; do
        if [[ -n "$ip" ]]; then
            local errors
            errors=$(grep -c "$ip" "$error_log" 2>/dev/null || echo "0")
            if [[ "$errors" -gt 0 ]]; then
                echo "$ip:$errors"
            fi
        fi
    done
}

# ==============================================================================
# Output Formatters
# ==============================================================================

output_text() {
    local metrics="$1"
    local p95_rt="$2"

    local total=$(get_metric "$metrics" "total_requests")
    local unique_ips=$(get_metric "$metrics" "unique_ips")
    local time_start=$(get_metric "$metrics" "time_start")
    local time_end=$(get_metric "$metrics" "time_end")

    local s2xx=$(get_metric "$metrics" "s2xx")
    local s3xx=$(get_metric "$metrics" "s3xx")
    local s4xx=$(get_metric "$metrics" "s4xx")
    local s5xx=$(get_metric "$metrics" "s5xx")

    local p2xx=$(get_metric "$metrics" "p2xx")
    local p3xx=$(get_metric "$metrics" "p3xx")
    local p4xx=$(get_metric "$metrics" "p4xx")
    local p5xx=$(get_metric "$metrics" "p5xx")

    local avg_rt=$(get_metric "$metrics" "avg_rt")
    local max_rt=$(get_metric "$metrics" "max_rt")
    local max_rt_method=$(get_metric "$metrics" "max_rt_method")
    local max_rt_path=$(get_metric "$metrics" "max_rt_path")

    cat << EOF
======================================
Web Server Log Analysis Report
Generated: $(date '+%Y-%m-%d %H:%M:%S')
Log File: $ACCESS_LOG
======================================

TRAFFIC SUMMARY
---------------
Total Requests: ${total:-0}
Unique IPs: ${unique_ips:-0}
Time Range: ${time_start:-N/A} - ${time_end:-N/A}

STATUS CODE BREAKDOWN
---------------------
2xx: ${s2xx:-0} (${p2xx:-0}%)
3xx: ${s3xx:-0} (${p3xx:-0}%)
4xx: ${s4xx:-0} (${p4xx:-0}%)
5xx: ${s5xx:-0} (${p5xx:-0}%)

TOP $TOP_N IPs
----------
EOF

    get_top_ips "$metrics" "$TOP_N" | awk '{printf "%3d. %-15s %5d requests\n", NR, $2, $1}'

    echo ""
    echo "PERFORMANCE"
    echo "-----------"

    if [[ -n "$avg_rt" ]]; then
        echo "Average Response Time: ${avg_rt}ms"
        echo "P95 Response Time: ${p95_rt:-N/A}ms"
        echo "Slowest Request: ${max_rt}ms ${max_rt_method} ${max_rt_path}"
    else
        echo "No response time data available"
    fi

    echo ""
    echo "SECURITY ALERTS (threshold: $THRESHOLD requests)"
    echo "---------------"

    local high_freq
    high_freq=$(get_high_freq_ips "$metrics" "$THRESHOLD")

    if [[ -n "$high_freq" ]]; then
        echo "$high_freq" | while read -r count ip; do
            echo "[!] Potential attack: $ip - $count requests"
        done
    else
        echo "No suspicious activity detected"
    fi

    # Error log correlation
    if [[ -n "$ERROR_LOG" && -f "$ERROR_LOG" ]]; then
        echo ""
        echo "ERROR LOG CORRELATION"
        echo "---------------------"
        echo "Error Log: $ERROR_LOG"
        echo ""

        local correlations
        correlations=$(correlate_error_log "$metrics" "$ERROR_LOG")

        if [[ -n "$correlations" ]]; then
            echo "$correlations" | while IFS=: read -r ip errors; do
                echo "IP $ip: $errors errors in error.log"
                grep "$ip" "$ERROR_LOG" | head -2 | sed 's/^/  /'
            done
        else
            echo "No correlation found"
        fi
    fi

    echo ""
    echo "======================================"
}

output_csv() {
    local metrics="$1"
    local p95_rt="$2"

    echo "metric,value"
    echo "report_time,$(date '+%Y-%m-%d %H:%M:%S')"
    echo "log_file,$ACCESS_LOG"
    echo "total_requests,$(get_metric "$metrics" "total_requests")"
    echo "unique_ips,$(get_metric "$metrics" "unique_ips")"
    echo "time_start,$(get_metric "$metrics" "time_start")"
    echo "time_end,$(get_metric "$metrics" "time_end")"
    echo "status_2xx,$(get_metric "$metrics" "s2xx")"
    echo "status_2xx_pct,$(get_metric "$metrics" "p2xx")"
    echo "status_3xx,$(get_metric "$metrics" "s3xx")"
    echo "status_3xx_pct,$(get_metric "$metrics" "p3xx")"
    echo "status_4xx,$(get_metric "$metrics" "s4xx")"
    echo "status_4xx_pct,$(get_metric "$metrics" "p4xx")"
    echo "status_5xx,$(get_metric "$metrics" "s5xx")"
    echo "status_5xx_pct,$(get_metric "$metrics" "p5xx")"
    echo "avg_response_ms,$(get_metric "$metrics" "avg_rt")"
    echo "p95_response_ms,$p95_rt"
    echo "slowest_request_ms,$(get_metric "$metrics" "max_rt")"
    echo "slowest_request_path,$(get_metric "$metrics" "max_rt_path")"

    local high_freq_count
    high_freq_count=$(get_high_freq_ips "$metrics" "$THRESHOLD" | wc -l | tr -d ' ')
    echo "alert_high_freq_ips,$high_freq_count"

    # Top IPs as separate CSV section
    echo ""
    echo "# Top IPs"
    echo "rank,ip,requests"
    get_top_ips "$metrics" "$TOP_N" | awk '{print NR "," $2 "," $1}'
}

output_json() {
    local metrics="$1"
    local p95_rt="$2"

    local total=$(get_metric "$metrics" "total_requests")
    local unique_ips=$(get_metric "$metrics" "unique_ips")
    local time_start=$(get_metric "$metrics" "time_start")
    local time_end=$(get_metric "$metrics" "time_end")

    local s2xx=$(get_metric "$metrics" "s2xx")
    local s3xx=$(get_metric "$metrics" "s3xx")
    local s4xx=$(get_metric "$metrics" "s4xx")
    local s5xx=$(get_metric "$metrics" "s5xx")

    local p2xx=$(get_metric "$metrics" "p2xx")
    local p3xx=$(get_metric "$metrics" "p3xx")
    local p4xx=$(get_metric "$metrics" "p4xx")
    local p5xx=$(get_metric "$metrics" "p5xx")

    local avg_rt=$(get_metric "$metrics" "avg_rt")
    local max_rt=$(get_metric "$metrics" "max_rt")
    local max_rt_method=$(get_metric "$metrics" "max_rt_method")
    local max_rt_path=$(get_metric "$metrics" "max_rt_path")

    # Build top IPs JSON array
    local top_ips_json="["
    local first=1
    while read -r count ip; do
        if [[ -n "$ip" ]]; then
            if [[ $first -eq 0 ]]; then
                top_ips_json+=","
            fi
            top_ips_json+="{\"ip\":\"$ip\",\"count\":$count}"
            first=0
        fi
    done < <(get_top_ips "$metrics" "$TOP_N")
    top_ips_json+="]"

    # Build security alerts JSON array
    local alerts_json="["
    first=1
    while read -r count ip; do
        if [[ -n "$ip" ]]; then
            if [[ $first -eq 0 ]]; then
                alerts_json+=","
            fi
            alerts_json+="{\"type\":\"high_request_rate\",\"ip\":\"$ip\",\"count\":$count,\"threshold\":$THRESHOLD}"
            first=0
        fi
    done < <(get_high_freq_ips "$metrics" "$THRESHOLD")
    alerts_json+="]"

    cat << EOF
{
  "report_time": "$(date '+%Y-%m-%d %H:%M:%S')",
  "log_file": "$ACCESS_LOG",
  "traffic_summary": {
    "total_requests": ${total:-0},
    "unique_ips": ${unique_ips:-0},
    "time_range": {
      "start": "${time_start:-null}",
      "end": "${time_end:-null}"
    }
  },
  "status_breakdown": {
    "2xx": {"count": ${s2xx:-0}, "percentage": ${p2xx:-0}},
    "3xx": {"count": ${s3xx:-0}, "percentage": ${p3xx:-0}},
    "4xx": {"count": ${s4xx:-0}, "percentage": ${p4xx:-0}},
    "5xx": {"count": ${s5xx:-0}, "percentage": ${p5xx:-0}}
  },
  "top_ips": $top_ips_json,
  "performance": {
    "avg_response_ms": ${avg_rt:-null},
    "p95_response_ms": ${p95_rt:-null},
    "slowest": {
      "response_ms": ${max_rt:-null},
      "method": "${max_rt_method:-null}",
      "path": "${max_rt_path:-null}"
    }
  },
  "security_alerts": $alerts_json
}
EOF
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    parse_args "$@"

    # Check for empty file
    if [[ ! -s "$ACCESS_LOG" ]]; then
        error_exit "Log file is empty: $ACCESS_LOG"
    fi

    # Collect metrics
    local metrics
    metrics=$(collect_metrics)

    # Calculate P95 separately (portable method)
    local p95_rt
    p95_rt=$(calculate_p95)

    # Output based on format
    case "$OUTPUT_FORMAT" in
        text)
            output_text "$metrics" "$p95_rt"
            ;;
        csv)
            output_csv "$metrics" "$p95_rt"
            ;;
        json)
            output_json "$metrics" "$p95_rt"
            ;;
    esac
}

main "$@"
