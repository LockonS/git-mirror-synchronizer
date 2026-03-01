#!/usr/bin/env zsh

op_handle_general_repo() {
  local REPO_RUNTIME_CONFIG
  REPO_RUNTIME_CONFIG="${1}"

  # general repos have no known release/tag API — disable downloads
  REPO_RUNTIME_CONFIG=$(echo "$REPO_RUNTIME_CONFIG" | jq '.release.download = "false" | .tag.download = "false"')

  op_handle_repo "$REPO_RUNTIME_CONFIG"
}