#!/usr/bin/env zsh

# write the report file header
op_report_write_header() {
  local EXECUTION_MODE="${1:-all}"
  local START_INDEX="${2:-0}"
  local END_INDEX="${3:-}"
  local FILTER_REPO_URL="${4:-}"

  local SCOPE_LINE
  if [[ -n "$FILTER_REPO_URL" ]]; then
    SCOPE_LINE="Repo:    ${CYAN}${FILTER_REPO_URL}${NC}"
  else
    SCOPE_LINE="Range:   ${CYAN}${START_INDEX} - ${END_INDEX}${NC}"
  fi

  local SUMMARY_HEADER=""

  SUMMARY_HEADER+="\n${BOLD}${WHITE}=== Sync Report ===${NC}"
  SUMMARY_HEADER+="\nDate:    ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
  SUMMARY_HEADER+="\nMode:    ${CYAN}${EXECUTION_MODE}${NC}"
  SUMMARY_HEADER+="\n$SCOPE_LINE\n"

  echo -e "$SUMMARY_HEADER"

  [[ -z "$REPORT_FILE" ]] && return 0
  {
    SUMMARY_HEADER+="\n${BOLD}${WHITE}=== Task Detail ===${NC}\n"
    echo -e "${SUMMARY_HEADER}"
  } > "$REPORT_FILE"
}

# append a single repo result line to the report file
op_report_append_repo_result() {
  local INDEX="${1}"
  local TOTAL="${2}"
  local REPO_URL="${3}"
  local STATUS="${4}"
  
  local STATUS_COLOR
  [[ "$STATUS" == "PASS" ]] && STATUS_COLOR="$GREEN" || STATUS_COLOR="$RED"

  echo -e ""
  echo -e "[${INDEX}/${TOTAL}] ${STATUS_COLOR}${BOLD}${STATUS}${NC}   ${REPO_URL}"
  [[ -z "$REPORT_FILE" ]] && return 0
  printf "[%d/%d] ${STATUS_COLOR}${BOLD}%-6s${NC} %s\n" "$INDEX" "$TOTAL" "$STATUS" "$REPO_URL" >> "$REPORT_FILE"
}

# append per-repo detail line to report file (used by full HTML report)
op_report_append_repo_detail() {
  local REPO_URL="${1}"
  local REPO_UPDATED="${2:-false}"
  local RELEASE_DL_COUNT="${3:-0}"

  [[ -z "$REPORT_FILE" ]] && return 0

  local DETAIL_PREFIX="[DETAIL]"
  if [[ "$REPO_UPDATED" == "true" ]]; then
    # TODO remove duplicated state
    DETAIL_PREFIX="[DETAIL][UPDATED]"
  fi

  local DETAIL_LINE="${DETAIL_PREFIX} ${REPO_URL}"
  if [[ "$RELEASE_DL_COUNT" -gt 0 ]]; then
    DETAIL_LINE+=" | Release Artifacts Downloaded: ${RELEASE_DL_COUNT}"
  fi

  printf "%s\n" "$DETAIL_LINE" >> "$REPORT_FILE"
}

# append summary block to the report file and echo it to stdout
op_report_write_summary() {
  local TOTAL="${1}"
  local SUCCESS="${2}"
  local FAILED="${3}"
  local UPDATED_REPOS="${4:-0}"
  local RELEASE_DL_COUNT="${5:-0}"
  local REPORT_CONTENT=""

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
  REPORT_CONTENT+="\nUpdated:  ${CYAN}${UPDATED_REPOS}${NC}"
  REPORT_CONTENT+="\nRelease Downloaded:  ${CYAN}${RELEASE_DL_COUNT}${NC}"
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

# Parse report file; render each line into an HTML item and assemble brief/full detail sections.
# Brief contains the first 10 failures only; full contains all entries ordered fail→updated→pass.
# Usage: _op_html_build_detail_sections <HTML_DIR> <REPORT_FILE> <REPORT_FAILED> <out_brief_var> <out_full_var>
_op_html_build_detail_sections() {
  local HTML_DIR="${1}"
  local REPORT_FILE="${2}"
  local REPORT_FAILED="${3}"
  local _out_brief_var="${4}"
  local _out_full_var="${5}"

  local _detail_brief=""
  local _detail_full=""
  [[ ! -f "$REPORT_FILE" || ! -s "$REPORT_FILE" ]] && return 0

  local ITEM_TEMPLATE_FAIL ITEM_TEMPLATE_PASS ITEM_TEMPLATE_UPDATED SECTION_TEMPLATE
  local FAIL_COUNT=0 ITEMS_FAIL_ALL="" ITEMS_FAIL_BRIEF="" ITEMS_UPDATED="" ITEMS_PASS="" RENDERED_LINE=""

  ITEM_TEMPLATE_FAIL=$(<"$HTML_DIR/section-detail-item.html")
  ITEM_TEMPLATE_PASS="${ITEM_TEMPLATE_FAIL/status-fail/status-pass}"
  ITEM_TEMPLATE_UPDATED="${ITEM_TEMPLATE_FAIL/status-fail/status-updated}"

  while IFS= read -r line; do
    if [[ "$line" == *"FAIL"* ]]; then
      # Strip ANSI/tput color codes (CSI, ESC(B from tput sgr0, and SI control char)
      line=$(printf '%s' "$line" | sed $'s/\033\\[[0-9;]*[A-Za-z]//g; s/\033(B//g; s/\017//g')
      line="${line//&/&amp;}"
      line="${line//</&lt;}"
      line="${line//>/&gt;}"
      RENDERED_LINE="${ITEM_TEMPLATE_FAIL//\{\{LINE\}\}/$line}"
      RENDERED_LINE="${RENDERED_LINE//\{\{RELEASE_DL_COUNT\}\}/}"
      ITEMS_FAIL_ALL+="$RENDERED_LINE"$'\n'
      [[ $FAIL_COUNT -lt 10 ]] && ITEMS_FAIL_BRIEF+="$RENDERED_LINE"$'\n'
      (( FAIL_COUNT++ ))
    elif [[ "$line" == "[DETAIL]"* ]]; then
      local DETAIL_TEMPLATE="$ITEM_TEMPLATE_PASS"
      local DETAIL_RELEASE_DL_COUNT="0"
      local IS_UPDATED=false
      if [[ "$line" == "[DETAIL][UPDATED]"* ]]; then
        line=$(printf '%s' "$line" | sed 's/^\[DETAIL\]\[UPDATED\][[:space:]]*//')
        DETAIL_TEMPLATE="$ITEM_TEMPLATE_UPDATED"
        IS_UPDATED=true
      else
        line=$(printf '%s' "$line" | sed 's/^\[DETAIL\][[:space:]]*//')
      fi
      if [[ "$line" == *" | Release Artifacts Downloaded: "* ]]; then
        DETAIL_RELEASE_DL_COUNT="${line##* | Release Artifacts Downloaded: }"
        line="${line% | Release Artifacts Downloaded: *}"
      fi
      line="${line//&/&amp;}"
      line="${line//</&lt;}"
      line="${line//>/&gt;}"
      RENDERED_LINE="${DETAIL_TEMPLATE//\{\{LINE\}\}/$line}"
      local BADGE_RELEASE_DL_COUNT="$DETAIL_RELEASE_DL_COUNT"
      if [[ "$DETAIL_RELEASE_DL_COUNT" =~ ^[0-9]+$ ]] && [[ "$DETAIL_RELEASE_DL_COUNT" -eq 0 ]]; then
        BADGE_RELEASE_DL_COUNT=""
      fi
      RENDERED_LINE="${RENDERED_LINE//\{\{RELEASE_DL_COUNT\}\}/$BADGE_RELEASE_DL_COUNT}"
      if [[ "$IS_UPDATED" == true ]]; then
        ITEMS_UPDATED+="$RENDERED_LINE"$'\n'
      else
        ITEMS_PASS+="$RENDERED_LINE"$'\n'
      fi
    fi
  done < "$REPORT_FILE"

  if [[ ${REPORT_FAILED} -gt 10 ]]; then
    local OVERFLOW_TEMPLATE
    OVERFLOW_TEMPLATE=$(<"$HTML_DIR/section-detail-overflow.html")
    ITEMS_FAIL_BRIEF+="${OVERFLOW_TEMPLATE//\{\{COUNT\}\}/$((REPORT_FAILED - 10))}"$'\n'
  fi

  # Order: failed → updated → success (not updated)
  SECTION_TEMPLATE=$(<"$HTML_DIR/section-detail-report.html")
  _detail_brief="${SECTION_TEMPLATE//\{\{ITEMS\}\}/$ITEMS_FAIL_BRIEF}"
  _detail_full="${SECTION_TEMPLATE//\{\{ITEMS\}\}/${ITEMS_FAIL_ALL}${ITEMS_UPDATED}${ITEMS_PASS}}"

  eval "${_out_brief_var}=\${_detail_brief}"
  eval "${_out_full_var}=\${_detail_full}"
}

# Fill all {{PLACEHOLDER}} variables in the base HTML template with report stats.
# Usage: _op_html_populate_base_template <template_file> <execution_mode> <timestamp> <hostname>
#        <total> <success> <failed> <updated> <release_dl> <success_rate> <failed_class> <out_var>
_op_html_populate_base_template() {
  local TEMPLATE_FILE="${1}"
  local EXECUTION_MODE="${2}"
  local TIMESTAMP="${3}"
  local HOSTNAME="${4}"
  local REPORT_TOTAL="${5}"
  local REPORT_SUCCESS="${6}"
  local REPORT_FAILED="${7}"
  local UPDATED_REPOS="${8}"
  local RELEASE_DL_COUNT="${9}"
  local SUCCESS_RATE="${10}"
  local REPORT_FAILED_CLASS="${11}"
  local _out_tmpl_var="${12}"

  local _tmpl_out
  _tmpl_out=$(<"$TEMPLATE_FILE")
  _tmpl_out="${_tmpl_out//\{\{TIMESTAMP\}\}/$TIMESTAMP}"
  _tmpl_out="${_tmpl_out//\{\{HOSTNAME\}\}/$HOSTNAME}"
  _tmpl_out="${_tmpl_out//\{\{EXECUTION_MODE\}\}/$EXECUTION_MODE}"
  _tmpl_out="${_tmpl_out//\{\{REPORT_TOTAL\}\}/$REPORT_TOTAL}"
  _tmpl_out="${_tmpl_out//\{\{REPORT_SUCCESS\}\}/$REPORT_SUCCESS}"
  _tmpl_out="${_tmpl_out//\{\{REPORT_FAILED\}\}/$REPORT_FAILED}"
  _tmpl_out="${_tmpl_out//\{\{REPORT_UPDATED\}\}/$UPDATED_REPOS}"
  _tmpl_out="${_tmpl_out//\{\{REPORT_REL_DOWNLOADED\}\}/$RELEASE_DL_COUNT}"
  _tmpl_out="${_tmpl_out//\{\{REPORT_FAILED_CLASS\}\}/$REPORT_FAILED_CLASS}"
  _tmpl_out="${_tmpl_out//\{\{SUCCESS_RATE\}\}/$SUCCESS_RATE}"

  eval "${_out_tmpl_var}=\${_tmpl_out}"
}

# Inject detail sections, status note, and full-report URL into brief and full HTML reports.
# Status note and URL appear in brief only; full report shows status note on success only.
# Usage: _op_html_assemble_reports <base_template> <detail_brief> <detail_full>
#        <report_failed> <html_dir> <out_brief_var> <out_full_var>
_op_html_assemble_reports() {
  local BASE_TEMPLATE="${1}"
  local DETAIL_BRIEF="${2}"
  local DETAIL_FULL="${3}"
  local REPORT_FAILED="${4}"
  local HTML_DIR="${5}"
  local _out_brief_var="${6}"
  local _out_full_var="${7}"

  local _brief_out=""
  local _full_out=""

  # Inject detail sections
  _brief_out="${BASE_TEMPLATE//\{\{DETAILED_REPORT\}\}/$DETAIL_BRIEF}"
  _full_out="${BASE_TEMPLATE//\{\{DETAILED_REPORT\}\}/$DETAIL_FULL}"

  # Build and inject status note section
  local STATUS_NOTE STATUS_NOTE_SECTION=""
  if [[ ${REPORT_FAILED} -eq 0 ]]; then
    STATUS_NOTE=$(<"$HTML_DIR/section-status-success.html")
  else
    STATUS_NOTE=$(<"$HTML_DIR/section-status-failed.html")
  fi
  if [[ -n "$STATUS_NOTE" ]]; then
    STATUS_NOTE_SECTION=$(<"$HTML_DIR/section-status-note.html")
    STATUS_NOTE_SECTION="${STATUS_NOTE_SECTION//\{\{STATUS_NOTE\}\}/$STATUS_NOTE}"
  fi
  _brief_out="${_brief_out//\{\{STATUS_NOTE_SECTION\}\}/$STATUS_NOTE_SECTION}"
  if [[ ${REPORT_FAILED} -eq 0 ]]; then
    _full_out="${_full_out//\{\{STATUS_NOTE_SECTION\}\}/$STATUS_NOTE_SECTION}"
  else
    _full_out="${_full_out//\{\{STATUS_NOTE_SECTION\}\}/}"
  fi

  # Build and inject full report URL section (brief only; omit from full)
  local FULL_REPORT_URL_SECTION=""
  if [[ -n "$HTML_REPORT_PUBLIC_URL" ]]; then
    local URL_SECTION_TEMPLATE
    URL_SECTION_TEMPLATE=$(<"$HTML_DIR/section-full-report-url.html")
    FULL_REPORT_URL_SECTION="${URL_SECTION_TEMPLATE//\{\{HTML_REPORT_PUBLIC_URL\}\}/$HTML_REPORT_PUBLIC_URL}"
  fi
  _brief_out="${_brief_out//\{\{FULL_REPORT_URL_SECTION\}\}/$FULL_REPORT_URL_SECTION}"
  _full_out="${_full_out//\{\{FULL_REPORT_URL_SECTION\}\}/}"

  eval "${_out_brief_var}=\${_brief_out}"
  eval "${_out_full_var}=\${_full_out}"
}

# format and write HTML report files (brief: first 10 failures, full: all failures)
op_generate_html_report() {
  local EXECUTION_MODE="${1:-}"
  local REPORT_TOTAL="${2:-0}"
  local REPORT_SUCCESS="${3:-0}"
  local REPORT_FAILED="${4:-0}"
  local REPORT_FILE="${5:-}"
  local UPDATED_REPOS="${6:-0}"
  local RELEASE_DL_COUNT="${7:-0}"

  local TIMESTAMP HOSTNAME SUCCESS_RATE="N/A"
  local REPORT_TEMPLATE_FILE="$SYNC_TOOL_PATH/template/html/report.html"
  local HTML_DIR="$SYNC_TOOL_PATH/template/html/report"

  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  HOSTNAME=$(hostname)

  if [[ ! -f "$REPORT_TEMPLATE_FILE" ]]; then
    op_prompt_error "Report template file not found: $REPORT_TEMPLATE_FILE"
    return 1
  fi

  [[ ${REPORT_TOTAL} -gt 0 ]] && SUCCESS_RATE=$((REPORT_SUCCESS * 100 / REPORT_TOTAL))%
  local REPORT_FAILED_CLASS="stat-failed-zero"
  [[ ${REPORT_FAILED} -gt 0 ]] && REPORT_FAILED_CLASS="stat-failed"

  # Phase 1: parse report file and render brief/full detail section HTML
  local DETAIL_BRIEF="" DETAIL_FULL=""
  _op_html_build_detail_sections "$HTML_DIR" "$REPORT_FILE" "$REPORT_FAILED" DETAIL_BRIEF DETAIL_FULL

  # Phase 2: populate the base HTML template with stats placeholders
  local BASE_TEMPLATE=""
  _op_html_populate_base_template \
    "$REPORT_TEMPLATE_FILE" "$EXECUTION_MODE" "$TIMESTAMP" "$HOSTNAME" \
    "$REPORT_TOTAL" "$REPORT_SUCCESS" "$REPORT_FAILED" \
    "$UPDATED_REPOS" "$RELEASE_DL_COUNT" "$SUCCESS_RATE" "$REPORT_FAILED_CLASS" \
    BASE_TEMPLATE

  # Phase 3: inject detail sections, status note, and URL into brief and full reports
  local HTML_BRIEF_REPORT="" HTML_FULL_REPORT=""
  _op_html_assemble_reports \
    "$BASE_TEMPLATE" "$DETAIL_BRIEF" "$DETAIL_FULL" \
    "$REPORT_FAILED" "$HTML_DIR" \
    HTML_BRIEF_REPORT HTML_FULL_REPORT

  # Phase 4: write output files
  echo -e "$HTML_BRIEF_REPORT" > "$HTML_BRIEF_REPORT_FILE"
  echo -e "$HTML_FULL_REPORT" > "$HTML_FULL_REPORT_FILE"
}

# assemble bucket file path and public URL for the generated report file, export as env variable
op_generate_report_file_path() {
  local RUNTIME_CONFIG_FILE="${1:-}"
  local REPORT_FILE_PATH="${2:-}"
  local S3_PATH_PREFIX=""
  local S3_URL_PREFIX=""

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

  local S3_ENABLE S3_PROFILE S3_BUCKET S3_PATH_PREFIX S3_URL_PREFIX
  local CMD_UPLOAD_FILE HTML_REPORT_BUCKET_FULL_PATH

  if [[ -f "$RUNTIME_CONFIG_FILE" ]]; then
    S3_ENABLE=$(jq -r '.report.s3.enable // "false"' "$RUNTIME_CONFIG_FILE")
    S3_PROFILE=$(jq -r '.report.s3.profile // ""' "$RUNTIME_CONFIG_FILE")
    S3_BUCKET=$(jq -r '.report.s3.bucket // ""' "$RUNTIME_CONFIG_FILE")
    S3_PATH_PREFIX=$(jq -r '.report.s3.pathPrefix // ""' "$RUNTIME_CONFIG_FILE")
    S3_URL_PREFIX=$(jq -r '.report.s3.urlPrefix // ""' "$RUNTIME_CONFIG_FILE")
    
    # remove trailing '/' if present
    S3_PATH_PREFIX=$(op_remove_trailing_slash "$S3_PATH_PREFIX")
    S3_URL_PREFIX=$(op_remove_trailing_slash "$S3_URL_PREFIX")
  else
    S3_ENABLE="false"
    S3_PROFILE=""
    S3_BUCKET=""
    S3_PATH_PREFIX=""
    S3_URL_PREFIX=""
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

# write failed repo URLs to temp-files/failed-repo.txt, or remove the file if none failed
# Parameters: FAILED_REPO_URLS (array elements passed as individual arguments)
op_export_failed_repos() {
  if [[ $# -gt 0 ]]; then
    printf '%s\n' "$@" > "$FAILED_REPO_FILE"
    op_prompt_info "Failed repos exported to: ${BOLD}${FAILED_REPO_FILE}${NC}"
  else
    [[ -f "$FAILED_REPO_FILE" ]] && rm -f "$FAILED_REPO_FILE"
  fi
}