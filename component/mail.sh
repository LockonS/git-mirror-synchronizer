#!/usr/bin/env zsh

# Email notification functions for git-mirror-synchronizer

# format email body with report content (HTML rich text from template)
op_format_email_body() {
  local EXECUTION_MODE="${1:-}"
  local REPORT_TOTAL="${2:-0}"
  local REPORT_SUCCESS="${3:-0}"
  local REPORT_FAILED="${4:-0}"
  local REPORT_FILE="${5:-}"
  
  local TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  local HOSTNAME=$(hostname)
  local SUCCESS_RATE="N/A"
  local EMAIL_TEMPLATE_FILE="$SYNC_TOOL_PATH/template/html/mail-report.html"
  
  # Check if template file exists
  if [[ ! -f "$EMAIL_TEMPLATE_FILE" ]]; then
    op_prompt_error "Email template file not found: $EMAIL_TEMPLATE_FILE"
    return 1
  fi
  
  if [[ ${REPORT_TOTAL} -gt 0 ]]; then
    SUCCESS_RATE=$((REPORT_SUCCESS * 100 / REPORT_TOTAL))%
  fi
  
  # Build detailed report section (only first 10 failed items)
  local HTML_DIR="$SYNC_TOOL_PATH/template/html/mail-report"
  local DETAILED_REPORT=""
  if [[ -f "$REPORT_FILE" && -s "$REPORT_FILE" ]]; then
    local ITEM_TEMPLATE SECTION_TEMPLATE FAIL_COUNT=0 ITEMS=""
    ITEM_TEMPLATE=$(<"$HTML_DIR/section-detail-item.html")
    while IFS= read -r line; do
      if [[ "$line" == *"FAIL"* && $FAIL_COUNT -lt 10 ]]; then
        # Escape HTML special characters
        line="${line//&/&amp;}"
        line="${line//</&lt;}"
        line="${line//>/&gt;}"
        ITEMS+="${ITEM_TEMPLATE//\{\{LINE\}\}/$line}"$'\n'
        (( FAIL_COUNT++ ))
      fi
    done < "$REPORT_FILE"

    if [[ ${REPORT_FAILED} -gt 10 ]]; then
      local OVERFLOW_TEMPLATE
      OVERFLOW_TEMPLATE=$(<"$HTML_DIR/section-detail-overflow.html")
      ITEMS+="${OVERFLOW_TEMPLATE//\{\{COUNT\}\}/$((REPORT_FAILED - 10))}"$'\n'
    fi

    SECTION_TEMPLATE=$(<"$HTML_DIR/section-detail-report.html")
    DETAILED_REPORT="${SECTION_TEMPLATE//\{\{ITEMS\}\}/$ITEMS}"
  fi

  # Build status note section
  local STATUS_NOTE=""
  if [[ ${REPORT_FAILED} -eq 0 ]]; then
    STATUS_NOTE=$(<"$HTML_DIR/section-status-success.html")
  else
    STATUS_NOTE=$(<"$HTML_DIR/section-status-failed.html")
  fi
  
  # Load template and replace placeholders
  local EMAIL_BODY REPORT_FAILED_CLASS
  if [[ ${REPORT_FAILED} -eq 0 ]]; then
    REPORT_FAILED_CLASS="stat-failed-zero"
  else
    REPORT_FAILED_CLASS="stat-failed"
  fi
  EMAIL_BODY=$(cat "$EMAIL_TEMPLATE_FILE")
  EMAIL_BODY="${EMAIL_BODY//\{\{TIMESTAMP\}\}/$TIMESTAMP}"
  EMAIL_BODY="${EMAIL_BODY//\{\{HOSTNAME\}\}/$HOSTNAME}"
  EMAIL_BODY="${EMAIL_BODY//\{\{EXECUTION_MODE\}\}/$EXECUTION_MODE}"
  EMAIL_BODY="${EMAIL_BODY//\{\{REPORT_TOTAL\}\}/$REPORT_TOTAL}"
  EMAIL_BODY="${EMAIL_BODY//\{\{REPORT_SUCCESS\}\}/$REPORT_SUCCESS}"
  EMAIL_BODY="${EMAIL_BODY//\{\{REPORT_FAILED\}\}/$REPORT_FAILED}"
  EMAIL_BODY="${EMAIL_BODY//\{\{REPORT_FAILED_CLASS\}\}/$REPORT_FAILED_CLASS}"
  EMAIL_BODY="${EMAIL_BODY//\{\{SUCCESS_RATE\}\}/$SUCCESS_RATE}"
  EMAIL_BODY="${EMAIL_BODY//\{\{DETAILED_REPORT\}\}/$DETAILED_REPORT}"
  EMAIL_BODY="${EMAIL_BODY//\{\{STATUS_NOTE\}\}/$STATUS_NOTE}"
  
  echo -e "$EMAIL_BODY"
}

# send email notification using sendmail
op_send_email() {
  local SENDER="${1:-}"
  local RECIPIENT="${2:-}"
  local SUBJECT="${3:-}"
  local BODY="${4:-}"

  # Skip if email is empty or not configured
  if [[ -z "$RECIPIENT" ]]; then
    op_prompt_debug "Email notification skipped: no recipient configured"
    return 0
  fi

  # Use default sender if not provided
  if [[ -z "$SENDER" && -n "$RECIPIENT" ]]; then
    SENDER="noreply@git-mirror-synchronizer"
  fi

  # Send email using sendmail command
  if command -v sendmail &> /dev/null; then
    # Construct email with proper headers for HTML rich text
    local EMAIL_CONTENT="From: ${SENDER}\n"
    EMAIL_CONTENT+="To: ${RECIPIENT}\n"
    EMAIL_CONTENT+="Subject: ${SUBJECT}\n"
    EMAIL_CONTENT+="MIME-Version: 1.0\n"
    EMAIL_CONTENT+="Content-Type: text/html; charset=UTF-8\n"
    EMAIL_CONTENT+="Content-Transfer-Encoding: 8bit\n"
    EMAIL_CONTENT+="\n"
    EMAIL_CONTENT+="${BODY}"

    # print empty line before email content for better readability in logs
    echo -e ""
    
    echo -e "$EMAIL_CONTENT" | sendmail -t
    if [[ $? -eq 0 ]]; then
      op_prompt_checkpoint "Email sent from: ${BOLD}${GREEN}${SENDER}${NC} to: ${BOLD}${GREEN}${RECIPIENT}${NC}"
    else
      op_prompt_error "Failed to send email from: ${BOLD}${SENDER}${NC} to: ${BOLD}${RECIPIENT}${NC}"
      return 1
    fi
  else
    op_prompt_warn "sendmail command not found, email notification skipped"
    return 1
  fi
}

# send email notification with formatted report
op_process_email_notification() {
  local RUNTIME_CONFIG_FILE="${1:-}"
  local EXECUTION_MODE="${2:-}"
  local REPORT_TOTAL="${3:-0}"
  local REPORT_SUCCESS="${4:-0}"
  local REPORT_FAILED="${5:-0}"
  local REPORT_FILE="${6:-}"

  local NOTIFICATION_SENDER=""
  local NOTIFICATION_RECEIVER=""
  
  if [[ -f "$RUNTIME_CONFIG_FILE" ]]; then
    NOTIFICATION_SENDER=$(jq -r '.notification.email.sender // ""' "$RUNTIME_CONFIG_FILE")
    NOTIFICATION_RECEIVER=$(jq -r '.notification.email.receiver // ""' "$RUNTIME_CONFIG_FILE")
  fi
  
  if [[ -n "$NOTIFICATION_RECEIVER" ]]; then
    local EMAIL_SUBJECT="Git Mirror Sync Report"
    local EMAIL_BODY=$(op_format_email_body "$EXECUTION_MODE" "$REPORT_TOTAL" "$REPORT_SUCCESS" "$REPORT_FAILED" "$REPORT_FILE")
    
    op_send_email "$NOTIFICATION_SENDER" "$NOTIFICATION_RECEIVER" "$EMAIL_SUBJECT" "$EMAIL_BODY"
  fi
}
