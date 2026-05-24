#!/usr/bin/env zsh

op_prompt_checkpoint() {
  local MSG NEWLINE_BEFORE ARROW_COLOR
  ARROW_COLOR="$BLUE"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n) NEWLINE_BEFORE="true"; shift ;;
      -c) ARROW_COLOR="$2"; shift 2 ;;
      *) MSG="$1"; shift ;;
    esac
  done

  [[ -n "$NEWLINE_BEFORE" ]] && echo -e ""
  echo -e "${ARROW_COLOR}==>${NC} ${WHITE}${MSG}${NC}"
}

op_prompt_debug() {
  if [[ "$LOG_LEVEL" != "debug" ]]; then
    return 0
  fi
  echo -e "${GREY}${1}${NC}"
}

op_prompt_info() {
  echo -e "${WHITE}${1}${NC}"
}

op_prompt_warn() {
  echo -e "${BOLD}${YELLOW}${1}${NC}"
}

op_prompt_error() {
  echo -e "${BOLD}${RED}${1}${NC}"
}

op_run_cmd() {
  local CMD_STR="${*}"

  if [[ "$DRY_RUN" != true ]]; then
    if ! zsh -c "$CMD_STR"; then
      op_prompt_error "Error: command execute failure"
      return 1
    fi
  else
    # print command on console
    echo -e "\n${GREY}${CMD_STR}${NC}\n"
  fi
}

# run a command and track its failure into the global REPO_PROCESS_STATUS
op_run_tracked_cmd() {
  if ! op_run_cmd "$@"; then
    REPO_PROCESS_STATUS="failed"
  fi
}

op_run_cmd_with_result() {
  local CMD_STR="${*}"

  if [[ "$DRY_RUN" != true ]]; then
    CMD_EXEC_STDOUT=$(zsh -c "$CMD_STR")
  else
    # print command on console
    echo -e "\n${GREY}${CMD_STR}${NC}\n"
  fi
}

op_get_os_type() {
  local OSNAME
  OSNAME=$(uname -s | tr "[:lower:]" "[:upper:]")
  if [[ $OSNAME == DARWIN* ]]; then
    export OS_TYPE="MACOS"
  elif [[ $OSNAME == LINUX* ]]; then
    export OS_TYPE="LINUX"
  else
    echo "Unsupported OS, exiting"
    exit 1
  fi
}

op_remove_trailing_slash() {
  local INPUT="${1:-}"
  if [[ "$INPUT" == */ ]]; then
    echo "${INPUT%/}"
  else
    echo "$INPUT"
  fi
}
