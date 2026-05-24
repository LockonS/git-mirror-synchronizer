#!/usr/bin/env zsh

# function and variables in this file is gitlab exclusive
export GITLAB_ACCESS_TOKEN_FILE="$DATA_PATH/gitlab/gitlab-access-token"
export GITLAB_ACCESS_TOKEN

op_load_gitlab_access_token() {
  op_load_access_token "$GITLAB_ACCESS_TOKEN_FILE" GITLAB_ACCESS_TOKEN "GitLab"
}

# extract repo identifier from repo url
op_gitlab_extract_repo_identifier() {
  local REPO_URL REPO_AUTHOR REPO_NAME REPO_IDENTIFIER
  REPO_URL="${1}"

  # extract repo creator and name from url
  REPO_AUTHOR=$(echo "$REPO_URL" | awk -F/ '{print $(NF-1)}')
  REPO_NAME=$(basename "$REPO_URL" | sed 's/\.git$//')
  REPO_IDENTIFIER="${REPO_AUTHOR}/${REPO_NAME}"
  echo "$REPO_IDENTIFIER"
}

# check GitLab API response for errors
# Parameters: JSON_DATA, ARTIFACT_TYPE ("release" or "tags")
# Returns: 0 if no error, 1 for errors, 2 for "Not Found" (caller should exit gracefully)
op_gitlab_check_api_response() {
  local JSON_DATA ARTIFACT_TYPE RESPONSE_MESSAGE
  JSON_DATA="${1}"
  ARTIFACT_TYPE="${2}"

  RESPONSE_MESSAGE=$(jq -r 'select(type=="object" and has("message")) | .message' <<<"$JSON_DATA")
  if [[ -n "$RESPONSE_MESSAGE" && "$RESPONSE_MESSAGE" != "null" ]]; then
    case "$RESPONSE_MESSAGE" in
      *"Not Found"* | *"404"*)
        op_prompt_info "No ${ARTIFACT_TYPE} artifact found"
        return 2
        ;;
      *)
        op_prompt_warn "GitLab API response: ${BOLD}${RESPONSE_MESSAGE}${NC}"
        return 1
        ;;
    esac
  fi
  return 0
}

# validate GitLab API response and handle status codes
# Parameters: JSON_DATA, ARTIFACT_TYPE ("release" or "tags")
# Returns: 0 for success (continue), 200 for "Not Found" (parent should return 0), other codes for errors
op_gitlab_validate_response() {
  local JSON_DATA ARTIFACT_TYPE
  JSON_DATA="${1}"
  ARTIFACT_TYPE="${2}"

  op_gitlab_check_api_response "$JSON_DATA" "$ARTIFACT_TYPE"
  local API_STATUS=$?

  if [[ $API_STATUS -eq 2 ]]; then
    return 200
  elif [[ $API_STATUS -ne 0 ]]; then
    return $API_STATUS
  fi

  return 0
}

op_gitlab_download_release() {
  local REPO_URL REPO_IDENTIFIER REPO_RELEASE_STORAGE EXCLUDE_KEYWORDS CUSTOM_IDENTIFIER KEPT_VERSION_NUM REPO_CATALOG AUTH_REQUEST_HEADER KEPT_VERSIONS
  REPO_URL="${1}"
  REPO_RELEASE_STORAGE="${2}"
  EXCLUDE_KEYWORDS="${3}"
  CUSTOM_IDENTIFIER="${4}"
  KEPT_VERSION_NUM="${5}"
  REPO_CATALOG="${6}"
  KEPT_VERSIONS="${7}"

  # use custom identifier if provided, otherwise extract from URL
  if [[ -n "$CUSTOM_IDENTIFIER" ]] && [[ "$CUSTOM_IDENTIFIER" != "null" ]]; then
    REPO_IDENTIFIER="$CUSTOM_IDENTIFIER"
  else
    REPO_IDENTIFIER=$(op_gitlab_extract_repo_identifier "$REPO_URL")
  fi

  op_prompt_checkpoint -n "Downloading release assets for ${BOLD}${GREEN}${REPO_IDENTIFIER}${NC}"

  # TODO: implement GitLab release download
  op_prompt_warn "GitLab release download is not implemented yet."
}

op_gitlab_download_release_asset() {
  local RELEASE_STORAGE_PATH ASSET_DATA EXCLUDE_KEYWORDS
  RELEASE_STORAGE_PATH="${1}"
  ASSET_DATA="${2}"
  EXCLUDE_KEYWORDS="${3}"

  # TODO: implement GitLab release asset download
  op_prompt_warn "GitLab release asset download is not implemented yet."
}

op_gitlab_download_tag() {
  local REPO_URL REPO_RELEASE_STORAGE REPO_IDENTIFIER CUSTOM_IDENTIFIER KEPT_VERSION_NUM REPO_CATALOG AUTH_REQUEST_HEADER KEPT_VERSIONS
  REPO_URL="${1}"
  REPO_RELEASE_STORAGE="${2}"
  CUSTOM_IDENTIFIER="${3}"
  KEPT_VERSION_NUM="${4}"
  REPO_CATALOG="${5}"
  KEPT_VERSIONS="${6}"

  # use custom identifier if provided, otherwise extract from URL
  if [[ -n "$CUSTOM_IDENTIFIER" ]] && [[ "$CUSTOM_IDENTIFIER" != "null" ]]; then
    REPO_IDENTIFIER="$CUSTOM_IDENTIFIER"
  else
    REPO_IDENTIFIER=$(op_gitlab_extract_repo_identifier "$REPO_URL")
  fi

  op_prompt_checkpoint -n "Downloading tag assets for ${BOLD}${GREEN}${REPO_IDENTIFIER}${NC}"

  # TODO: implement GitLab tag download
  op_prompt_warn "GitLab tag download is not implemented yet."
}

# handle GitLab repository operations (sync, release, tag downloads)
op_handle_gitlab_repo() {
  op_handle_repo "$@" op_gitlab_download_release op_gitlab_download_tag
}

#op_load_gitlab_access_token
