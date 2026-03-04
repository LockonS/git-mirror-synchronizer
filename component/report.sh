#!/usr/bin/env zsh

# write the report file header
op_report_write_header() {
  local EXECUTION_MODE="${1:-all}"
  local START_INDEX="${2:-0}"
  local END_INDEX="${3:-}"
  local FILTER_REPO_URL="${4:-}"
  echo -e "\n${BOLD}${WHITE}=== Sync Report ===${NC}"
  echo -e "Date:    ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
  echo -e "Mode:    ${CYAN}${EXECUTION_MODE}${NC}"
  [[ -z "$FILTER_REPO_URL" ]] && echo -e "Range:   ${CYAN}${START_INDEX} - ${END_INDEX}${NC}"
  [[ -n "$FILTER_REPO_URL" ]] && echo -e "Repo:    ${CYAN}${FILTER_REPO_URL}${NC}"
  [[ -z "$REPORT_FILE" ]] && return 0
  {
    echo -e "${BOLD}${WHITE}=== Sync Report ===${NC}"
    echo -e "Date:    ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "Mode:    ${CYAN}${EXECUTION_MODE}${NC}"
    [[ -z "$FILTER_REPO_URL" ]] && echo -e "Range:   ${CYAN}${START_INDEX} - ${END_INDEX}${NC}"
    [[ -n "$FILTER_REPO_URL" ]] && echo -e "Repo:    ${CYAN}${FILTER_REPO_URL}${NC}"
    echo ""
  } > "$REPORT_FILE"
}

# append a single repo result line to the report file
op_report_append_repo_result() {
  local INDEX="${1}"
  local TOTAL="${2}"
  local REPO_URL="${3}"
  local STATUS="${4}"
  
  echo -e ""
  if [[ "$STATUS" == "PASS" ]]; then
    echo -e "[${INDEX}/${TOTAL}] ${GREEN}${BOLD}${STATUS}${NC}   ${REPO_URL}"
  else
    echo -e "[${INDEX}/${TOTAL}] ${RED}${BOLD}${STATUS}${NC}   ${REPO_URL}"
  fi
  [[ -z "$REPORT_FILE" ]] && return 0
  if [[ "$STATUS" == "PASS" ]]; then
    printf "[%d/%d] ${GREEN}${BOLD}%-6s${NC} %s\n" "$INDEX" "$TOTAL" "$STATUS" "$REPO_URL" >> "$REPORT_FILE"
  else
    printf "[%d/%d] ${RED}${BOLD}%-6s${NC} %s\n" "$INDEX" "$TOTAL" "$STATUS" "$REPO_URL" >> "$REPORT_FILE"
  fi
}

# append summary block to the report file and echo it to stdout
op_report_write_summary() {
  local TOTAL="${1}"
  local SUCCESS="${2}"
  local FAILED="${3}"

  local FAILED_COLOR
  if [[ "$FAILED" -eq 0 ]]; then
    FAILED_COLOR="${WHITE}"
  else
    FAILED_COLOR="${RED}"
  fi

  # print summary on console with colored formatting
  op_prompt_checkpoint -n "Report task summary"
  REPORT_CONTENT="Total:    ${BLUE}${TOTAL}${NC}"
  REPORT_CONTENT+="\nSuccess:  ${GREEN}${SUCCESS}${NC}"
  REPORT_CONTENT+="\nFailed:   ${FAILED_COLOR}${FAILED}${NC}"
  op_prompt_info "$REPORT_CONTENT"

  if [[ -n "$REPORT_FILE" ]]; then
    {
      op_prompt_info "\n${BOLD}${WHITE}=== Task Summary ===${NC}\n"
      op_prompt_info "$REPORT_CONTENT"
    } >> "$REPORT_FILE"

    op_prompt_checkpoint -n "Save task summary report"
    op_prompt_info "Export: ${BOLD}${REPORT_FILE}${NC}"
  fi
}

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
        # Strip ANSI/tput color codes (CSI, ESC(B from tput sgr0, and SI control char)
        line=$(printf '%s' "$line" | sed $'s/\033\\[[0-9;]*[A-Za-z]//g; s/\033(B//g; s/\017//g')
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

  # Inject detail section to produce brief and full HTML reports
  local HTML_BRIEF_REPORT HTML_FULL_REPORT
  HTML_BRIEF_REPORT="${BASE_TEMPLATE//\{\{DETAILED_REPORT\}\}/$DETAILED_REPORT_BRIEF}"
  HTML_FULL_REPORT="${BASE_TEMPLATE//\{\{DETAILED_REPORT\}\}/$DETAILED_REPORT_FULL}"

  # Apply status note to brief report only; full report omits it
  HTML_BRIEF_REPORT="${HTML_BRIEF_REPORT//\{\{STATUS_NOTE\}\}/$STATUS_NOTE}"
  HTML_FULL_REPORT="${HTML_FULL_REPORT//\{\{STATUS_NOTE\}\}/}"

  # Inject full report URL link into brief report only
  local FULL_REPORT_URL_SECTION=""
  if [[ -n "$HTML_REPORT_PUBLIC_URL" ]]; then
    local URL_SECTION_TEMPLATE
    URL_SECTION_TEMPLATE=$(<"$HTML_DIR/section-full-report-url.html")
    FULL_REPORT_URL_SECTION="${URL_SECTION_TEMPLATE//\{\{HTML_REPORT_PUBLIC_URL\}\}/$HTML_REPORT_PUBLIC_URL}"
  fi
  HTML_BRIEF_REPORT="${HTML_BRIEF_REPORT//\{\{FULL_REPORT_URL_SECTION\}\}/$FULL_REPORT_URL_SECTION}"
  # HTML_FULL_REPORT="${HTML_FULL_REPORT//\{\{FULL_REPORT_URL_SECTION\}\}/}"

  # Write both report files alongside the text report
  echo -e "$HTML_BRIEF_REPORT" > "$HTML_BRIEF_REPORT_FILE"
  echo -e "$HTML_FULL_REPORT" > "$HTML_FULL_REPORT_FILE"
}

# assemble bucket file path and public URL for the generated report file, export as env variable
op_generate_report_file_path() {
  local RUNTIME_CONFIG_FILE="${1:-}"
  local REPORT_FILE_PATH="${2:-}"

  if [[ -f "$RUNTIME_CONFIG_FILE" ]]; then
    S3_PATH_PREFIX=$(jq -r '.report.s3.pathPrefix // ""' "$RUNTIME_CONFIG_FILE")
    S3_URL_PREFIX=$(jq -r '.report.s3.urlPrefix // ""' "$RUNTIME_CONFIG_FILE")

    # remove trailing '/' if present
    S3_PATH_PREFIX=$(op_remove_trailing_slash "$S3_PATH_PREFIX")
    S3_URL_PREFIX=$(op_remove_trailing_slash "$S3_URL_PREFIX")
  fi

  # assemble and export public report URL as env variable
  HTML_REPORT_BUCKET_PATH="${S3_PATH_PREFIX}/report/${LOG_DATE}/report-${LOG_TIMESTAMP}.html"
  HTML_REPORT_PUBLIC_URL="${S3_URL_PREFIX}/${HTML_REPORT_BUCKET_PATH}"
  export HTML_REPORT_BUCKET_PATH HTML_REPORT_PUBLIC_URL
}

# Upload report file to S3 if enabled in config, and export public URL for email notification
op_upload_report_s3() {
  local RUNTIME_CONFIG_FILE="${1:-}"
  local REPORT_FILE_PATH="${2:-}"

  local S3_ENABLE="" 
  local S3_PROFILE="" 
  local S3_BUCKET="" 
  local S3_PATH_PREFIX="" 
  local S3_URL_PREFIX=""
  local CMD_UPLOAD_FILE=""

  if [[ -f "$RUNTIME_CONFIG_FILE" ]]; then
    S3_ENABLE=$(jq -r '.report.s3.enable // "false"' "$RUNTIME_CONFIG_FILE")
    S3_PROFILE=$(jq -r '.report.s3.profile // ""' "$RUNTIME_CONFIG_FILE")
    S3_BUCKET=$(jq -r '.report.s3.bucket // ""' "$RUNTIME_CONFIG_FILE")
    S3_PATH_PREFIX=$(jq -r '.report.s3.pathPrefix // ""' "$RUNTIME_CONFIG_FILE")
    S3_URL_PREFIX=$(jq -r '.report.s3.urlPrefix // ""' "$RUNTIME_CONFIG_FILE")
    
    # remove trailing '/' if present
    S3_PATH_PREFIX=$(op_remove_trailing_slash "$S3_PATH_PREFIX")
    S3_URL_PREFIX=$(op_remove_trailing_slash "$S3_URL_PREFIX")
  fi

  if [[ -z "$REPORT_FILE_PATH" || ! -f "$REPORT_FILE_PATH" ]]; then
    op_prompt_warn "Report file not exist: ${BOLD}${REPORT_FILE_PATH}${NC}"
  fi

  if [[ "$S3_ENABLE" != "true" ]]; then
    op_prompt_checkpoint -n -c "${YELLOW}" "S3 report upload not enabled, skipping uploading operation"
    return 0
  fi

  if [[ -z "$S3_BUCKET" ]]; then
    op_prompt_warn "S3 report upload skipped: no bucket configured"
    return 1
  fi

  if [[ -z "$S3_PROFILE" ]]; then
    op_prompt_warn "S3 report upload skipped: no profile configured"
    return 1
  fi

  if ! command -v rclone &>/dev/null; then
    op_prompt_warn "S3 report upload skipped: ${BOLD}rclone${NC} not found"
    return 1
  fi

  op_prompt_checkpoint -n "Upload HTML reports to S3"
  HTML_REPORT_BUCKET_FULL_PATH="${S3_PROFILE}:${S3_BUCKET}/${HTML_REPORT_BUCKET_PATH}"
  CMD_UPLOAD_FILE="rclone copyto $REPORT_FILE_PATH ${HTML_REPORT_BUCKET_FULL_PATH}"

  op_run_cmd "$CMD_UPLOAD_FILE"
  op_prompt_info "Report: ${BOLD}${REPORT_FILE_PATH}${NC}"
  op_prompt_info "Upload: ${BOLD}${HTML_REPORT_BUCKET_FULL_PATH}${NC}"
}