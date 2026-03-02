#!/usr/bin/env zsh

# Email notification functions for git-mirror-synchronizer

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
    op_prompt_warn "${BOLD}sendmail${NC} command not found, email notification skipped"
    return 1
  fi
}

# send email notification with formatted report
op_process_email_notification() {
  local RUNTIME_CONFIG_FILE="${1:-}"
  local REPORT_TOTAL="${2:-0}"
  local REPORT_SUCCESS="${3:-0}"
  local REPORT_FAILED="${4:-0}"
  local REPORT_FILE="${5:-}"

  local NOTIFICATION_SENDER=""
  local NOTIFICATION_RECEIVER=""
  local NOTIFICATION_ENABLE=""
  
  if [[ -f "$RUNTIME_CONFIG_FILE" ]]; then
    NOTIFICATION_ENABLE=$(jq -r '.notification.email.enable // ""' "$RUNTIME_CONFIG_FILE")
    NOTIFICATION_SENDER=$(jq -r '.notification.email.sender // ""' "$RUNTIME_CONFIG_FILE")
    NOTIFICATION_RECEIVER=$(jq -r '.notification.email.receiver // ""' "$RUNTIME_CONFIG_FILE")
  fi

  if [[ "$NOTIFICATION_ENABLE" != "true" ]]; then
    op_prompt_debug "Email notification skipped: not enabled"
    return 0
  fi
  
  if [[ -n "$NOTIFICATION_RECEIVER" ]]; then
    local EMAIL_SUBJECT EMAIL_REPORT_CONTENT
    EMAIL_SUBJECT="Git Mirror Sync Report"

    EMAIL_REPORT_CONTENT=$(<"$HTML_BRIEF_REPORT_FILE")
    
    op_send_email "$NOTIFICATION_SENDER" "$NOTIFICATION_RECEIVER" "$EMAIL_SUBJECT" "$EMAIL_REPORT_CONTENT"
  fi
}
