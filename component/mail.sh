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
  local EMAIL_TEMPLATE_FILE="$SYNC_TOOL_PATH/template/email-report.html"
  
  # Check if template file exists
  if [[ ! -f "$EMAIL_TEMPLATE_FILE" ]]; then
    op_prompt_error "Email template file not found: $EMAIL_TEMPLATE_FILE"
    return 1
  fi
  
  if [[ ${REPORT_TOTAL} -gt 0 ]]; then
    SUCCESS_RATE=$((REPORT_SUCCESS * 100 / REPORT_TOTAL))%
  fi
  
  # Build detailed report section
  local DETAILED_REPORT=""
  if [[ -f "$REPORT_FILE" && -s "$REPORT_FILE" ]]; then
    DETAILED_REPORT+="      <div class=\"section\">\n"
    DETAILED_REPORT+="        <div class=\"section-title\">Detailed Report</div>\n"
    while IFS= read -r line; do
      # Escape HTML special characters
      line="${line//&/&amp;}"
      line="${line//</&lt;}"
      line="${line//>/&gt;}"
      
      # Determine status class based on PASS/FAIL
      if [[ "$line" == *"PASS"* ]]; then
        DETAILED_REPORT+="        <div class=\"report-item status-pass\">${line}</div>\n"
      elif [[ "$line" == *"FAIL"* ]]; then
        DETAILED_REPORT+="        <div class=\"report-item status-fail\">${line}</div>\n"
      else
        DETAILED_REPORT+="        <div class=\"report-item\">${line}</div>\n"
      fi
    done < "$REPORT_FILE"
    DETAILED_REPORT+="      </div>\n"
  fi
  
  # Build status note section
  local STATUS_NOTE=""
  if [[ ${REPORT_FAILED} -eq 0 ]]; then
    STATUS_NOTE+="          <div style=\"display: flex; align-items: center;\">\n"
    STATUS_NOTE+="            <span class=\"icon\">✓</span>\n"
    STATUS_NOTE+="            <span style=\"color: #28a745; font-weight: 500;\">All syncs completed successfully!</span>\n"
    STATUS_NOTE+="          </div>\n"
  else
    STATUS_NOTE+="          <div style=\"display: flex; align-items: center;\">\n"
    STATUS_NOTE+="            <span class=\"icon\">⚠</span>\n"
    STATUS_NOTE+="            <span style=\"color: #dc3545; font-weight: 500;\">Some syncs failed. Please review the detailed report.</span>\n"
    STATUS_NOTE+="          </div>\n"
  fi
  
  # Load template and replace placeholders
  local EMAIL_BODY
  EMAIL_BODY=$(cat "$EMAIL_TEMPLATE_FILE")
  EMAIL_BODY="${EMAIL_BODY//\{\{TIMESTAMP\}\}/$TIMESTAMP}"
  EMAIL_BODY="${EMAIL_BODY//\{\{HOSTNAME\}\}/$HOSTNAME}"
  EMAIL_BODY="${EMAIL_BODY//\{\{EXECUTION_MODE\}\}/$EXECUTION_MODE}"
  EMAIL_BODY="${EMAIL_BODY//\{\{REPORT_TOTAL\}\}/$REPORT_TOTAL}"
  EMAIL_BODY="${EMAIL_BODY//\{\{REPORT_SUCCESS\}\}/$REPORT_SUCCESS}"
  EMAIL_BODY="${EMAIL_BODY//\{\{REPORT_FAILED\}\}/$REPORT_FAILED}"
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
    
    echo -e "$EMAIL_CONTENT" | sendmail -t
    if [[ $? -eq 0 ]]; then
      op_prompt_checkpoint "Email sent from: ${GREEN}${SENDER}${NC} to: ${GREEN}${RECIPIENT}${NC}"
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
op_send_email_notification() {
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
