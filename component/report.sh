#!/usr/bin/env zsh

# HTML report generation functions for git-mirror-synchronizer

# format and write HTML report files (brief: first 10 failures, full: all failures)
op_generate_html_report() {
  local EXECUTION_MODE="${1:-}"
  local REPORT_TOTAL="${2:-0}"
  local REPORT_SUCCESS="${3:-0}"
  local REPORT_FAILED="${4:-0}"
  local REPORT_FILE="${5:-}"

  local TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  local HOSTNAME=$(hostname)
  local SUCCESS_RATE="N/A"
  local REPORT_TEMPLATE_FILE="$SYNC_TOOL_PATH/template/html/report.html"

  if [[ ! -f "$REPORT_TEMPLATE_FILE" ]]; then
    op_prompt_error "Report template file not found: $REPORT_TEMPLATE_FILE"
    return 1
  fi

  if [[ ${REPORT_TOTAL} -gt 0 ]]; then
    SUCCESS_RATE=$((REPORT_SUCCESS * 100 / REPORT_TOTAL))%
  fi

  # Build brief (first 10 failed) and full (all failed) detail sections in one pass
  local HTML_DIR="$SYNC_TOOL_PATH/template/html/report"
  local DETAILED_REPORT_BRIEF="" DETAILED_REPORT_FULL=""
  if [[ -f "$REPORT_FILE" && -s "$REPORT_FILE" ]]; then
    local ITEM_TEMPLATE SECTION_TEMPLATE FAIL_COUNT=0 ITEMS_BRIEF="" ITEMS_FULL="" rendered=""
    ITEM_TEMPLATE=$(<"$HTML_DIR/section-detail-item.html")
    while IFS= read -r line; do
      if [[ "$line" == *"FAIL"* ]]; then
        # Strip ANSI color codes
        line=$(printf '%s' "$line" | sed $'s/\033\\[[0-9;]*m//g')
        # Escape HTML special characters
        line="${line//&/&amp;}"
        line="${line//</&lt;}"
        line="${line//>/&gt;}"
        rendered="${ITEM_TEMPLATE//\{\{LINE\}\}/$line}"
        ITEMS_FULL+="$rendered"$'\n'
        if [[ $FAIL_COUNT -lt 10 ]]; then
          ITEMS_BRIEF+="$rendered"$'\n'
          (( FAIL_COUNT++ ))
        fi
      fi
    done < "$REPORT_FILE"

    if [[ ${REPORT_FAILED} -gt 10 ]]; then
      local OVERFLOW_TEMPLATE
      OVERFLOW_TEMPLATE=$(<"$HTML_DIR/section-detail-overflow.html")
      ITEMS_BRIEF+="${OVERFLOW_TEMPLATE//\{\{COUNT\}\}/$((REPORT_FAILED - 10))}"$'\n'
    fi

    SECTION_TEMPLATE=$(<"$HTML_DIR/section-detail-report.html")
    DETAILED_REPORT_BRIEF="${SECTION_TEMPLATE//\{\{ITEMS\}\}/$ITEMS_BRIEF}"
    DETAILED_REPORT_FULL="${SECTION_TEMPLATE//\{\{ITEMS\}\}/$ITEMS_FULL}"
  fi

  # Build status note section
  local STATUS_NOTE=""
  if [[ ${REPORT_FAILED} -eq 0 ]]; then
    STATUS_NOTE=$(<"$HTML_DIR/section-status-success.html")
  else
    STATUS_NOTE=$(<"$HTML_DIR/section-status-failed.html")
  fi

  # Apply shared placeholders once to a base template
  local REPORT_FAILED_CLASS
  if [[ ${REPORT_FAILED} -eq 0 ]]; then
    REPORT_FAILED_CLASS="stat-failed-zero"
  else
    REPORT_FAILED_CLASS="stat-failed"
  fi
  local BASE_TEMPLATE
  BASE_TEMPLATE=$(cat "$REPORT_TEMPLATE_FILE")
  BASE_TEMPLATE="${BASE_TEMPLATE//\{\{TIMESTAMP\}\}/$TIMESTAMP}"
  BASE_TEMPLATE="${BASE_TEMPLATE//\{\{HOSTNAME\}\}/$HOSTNAME}"
  BASE_TEMPLATE="${BASE_TEMPLATE//\{\{EXECUTION_MODE\}\}/$EXECUTION_MODE}"
  BASE_TEMPLATE="${BASE_TEMPLATE//\{\{REPORT_TOTAL\}\}/$REPORT_TOTAL}"
  BASE_TEMPLATE="${BASE_TEMPLATE//\{\{REPORT_SUCCESS\}\}/$REPORT_SUCCESS}"
  BASE_TEMPLATE="${BASE_TEMPLATE//\{\{REPORT_FAILED\}\}/$REPORT_FAILED}"
  BASE_TEMPLATE="${BASE_TEMPLATE//\{\{REPORT_FAILED_CLASS\}\}/$REPORT_FAILED_CLASS}"
  BASE_TEMPLATE="${BASE_TEMPLATE//\{\{SUCCESS_RATE\}\}/$SUCCESS_RATE}"
  BASE_TEMPLATE="${BASE_TEMPLATE//\{\{STATUS_NOTE\}\}/$STATUS_NOTE}"

  # Inject detail section to produce brief and full HTML reports
  local HTML_BRIEF_REPORT HTML_FULL_REPORT
  HTML_BRIEF_REPORT="${BASE_TEMPLATE//\{\{DETAILED_REPORT\}\}/$DETAILED_REPORT_BRIEF}"
  HTML_FULL_REPORT="${BASE_TEMPLATE//\{\{DETAILED_REPORT\}\}/$DETAILED_REPORT_FULL}"

  # Write both report files alongside the text report
  echo -e "$HTML_BRIEF_REPORT" > "$HTML_BRIEF_REPORT_FILE"
  echo -e "$HTML_FULL_REPORT" > "$HTML_FULL_REPORT_FILE"
}
