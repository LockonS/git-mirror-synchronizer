#!/usr/bin/env zsh

SCRIPT_DIR=`dirname $0`
OFFSET=" --"
DEBUG=
LOG_FILE=/var/log/mirror-sync.log
EXECUTE_TIME=$(date '+%Y-%m-%d %H:%M:%S')

repo-sync(){
	local REPO_NAME=${1}
	local REPO_LOCAL_PATH=${2}
	local TRACK_REMOTE_REPO_NAME=${3}
	local MIRROR_REMOTE_REPO_NAME=${4}
	local DRY_RUN=${5}

	# support sync with no mirror
	PROMPT_MSG="Sync project ==> \033[0;32m$REPO_NAME\033[0m"
	SYNC_CMD="cd $REPO_LOCAL_PATH && git pull $TRACK_REMOTE_REPO_NAME"
	if [[ -n $MIRROR_REMOTE_REPO_NAME ]]; then
		PROMPT_MSG+=" to \033[0;34m$MIRROR_REMOTE_REPO_NAME\033[0m"
		SYNC_CMD+=" && git push $MIRROR_REMOTE_REPO_NAME"
	fi

	echo $PROMPT_MSG
	if [[ ! -n $DRY_RUN ]]; then
		sh -c $SYNC_CMD
	else
		echo $SYNC_CMD
	fi
	echo ""
}

repo-init(){
	local REPO_NAME=${1}
	local REPO_LOCAL_PATH=${2}
	local TRACK_REMOTE_REPO_NAME=${3}
	local TRACK_REMOTE_REPO_URL=${4}
	local DRY_RUN=${5}
	echo "Initialize project ==> \033[0;32m$REPO_NAME\033[0m	\033[0;34m$REPO_LOCAL_PATH\033[0m" 
	mkdir -p $(dirname $REPO_LOCAL_PATH)
	if [[ -d $REPO_LOCAL_PATH/.git ]]; then
		[[ $DEBUG ]] && echo "$OFFSET \033[0;33mProject repository is initialized, abort clone process\033[0m" 
		return 0
	fi
	if [[ ! -n $DRY_RUN ]]; then
		git clone $TRACK_REMOTE_REPO_URL $REPO_LOCAL_PATH 
	else
		echo "git clone $TRACK_REMOTE_REPO_URL $REPO_LOCAL_PATH"
	fi
	echo ""
}

repo-set-remote-repo(){
	local REPO_NAME=${1}
	local REPO_LOCAL_PATH=${2}
	local MIRROR_REMOTE_REPO_NAME=${3}
	local MIRROR_REMOTE_REPO_URL=${4}
	local DRY_RUN=${5}
	cd $REPO_LOCAL_PATH
	# check if remote repo has been configured already
	echo "$OFFSET Add remote repository ==> \033[0;32m$MIRROR_REMOTE_REPO_NAME\033[0m	\033[0;34m$MIRROR_REMOTE_REPO_URL\033[0m" 
	if [[ ! -n $(git remote | grep "^$MIRROR_REMOTE_REPO_NAME$") ]]; then
		if [[ ! -n $DRY_RUN ]]; then
			git remote add $MIRROR_REMOTE_REPO_NAME $MIRROR_REMOTE_REPO_URL 
		else
			echo "git remote add $MIRROR_REMOTE_REPO_NAME $MIRROR_REMOTE_REPO_URL"
		fi
	fi
}

repo-parse(){
	local REPO_DATA=${1}
	local EXECUTE_MODE=${2}
	local REPO_NAME=$(echo $REPO_DATA | jq '.repoName' | tr -d '"')
	local REPO_LOCAL_PATH=$(echo $REPO_DATA | jq '.repoLocalPath' | tr -d '"')
	local TRACK_REMOTE_REPO_NAME=$(echo $REPO_DATA | jq '.trackRemoteRepoName' | tr -d '"')
	local TRACK_REMOTE_REPO_URL=$(echo $REPO_DATA | jq '.trackRemoteRepoUrl' | tr -d '"')
	local MIRROR_LENGTH=$(echo $REPO_DATA | jq '.mirror | length')
	if [[ ! -n $REPO_LOCAL_PATH ]] || [[ ! -n $TRACK_REMOTE_REPO_NAME ]] || [[ ! -n $TRACK_REMOTE_REPO_URL ]] ; then
		[[ $DEBUG ]] && echo "$OFFSET \033[0;33mTracking repository configuration is not complete, abort task\033[0m" 
		return 0
	fi
	# traverse miror list
	if [[ $EXECUTE_MODE == "init" ]]; then
		repo-init $REPO_NAME $REPO_LOCAL_PATH $TRACK_REMOTE_REPO_NAME $TRACK_REMOTE_REPO_URL 
	fi
	# if no mirror was set
	if [[ $MIRROR_LENGTH -eq 0 ]]; then
		repo-sync $REPO_NAME $REPO_LOCAL_PATH $TRACK_REMOTE_REPO_NAME
	else
		for (( MIRROR_INDEX = 0; MIRROR_INDEX < $MIRROR_LENGTH; MIRROR_INDEX++ )); do
			local MIRROR_REMOTE_REPO_NAME=$(echo $REPO_DATA | jq ".mirror[$MIRROR_INDEX].repoName" | tr -d '"')
			local MIRROR_REMOTE_REPO_URL=$(echo $REPO_DATA | jq ".mirror[$MIRROR_INDEX].repoUrl" | tr -d '"')
			if [[ ! -n $MIRROR_REMOTE_REPO_NAME ]] || [[ ! -n $MIRROR_REMOTE_REPO_URL ]]; then
				[[ $DEBUG ]] && echo "$OFFSET \033[0;33mMirror repository configuration is not complete, abort task\033[0m" 
				return 0
			fi
			if [[ $EXECUTE_MODE == "init" ]]; then
				repo-set-remote-repo $REPO_NAME $REPO_LOCAL_PATH $MIRROR_REMOTE_REPO_NAME $MIRROR_REMOTE_REPO_URL 
			else
				repo-sync $REPO_NAME $REPO_LOCAL_PATH $TRACK_REMOTE_REPO_NAME $MIRROR_REMOTE_REPO_NAME
			fi
		done
	fi
}

help-page(){
	echo "\nusage: ./mirror-sync.sh [-f config-file] [-m execute-mode] [-h]"
	echo "       -f file   Specify input config file, default to path-to-script/data/repo.json"
	echo "       -m mode   Specify execute mode [init | sync], default to sync mode"
	echo "       -h  	 Display help page"
}

running-check(){
	# drop log files to desktop for MacOS
	if [[ $OSTYPE == 'darwin'* ]]; then
		LOG_FILE=$HOME/Desktop/mirror-sync.log
	fi
	if [[ ! -f $LOG_FILE ]]; then
		touch $LOG_FILE
	fi
	echo "\n\n--------------- $EXECUTE_TIME ---------------\n" 
}

load-config(){
	OPT=$@
	EXECUTE_MODE="sync"
	CONFIG_FILE=""
	while getopts 'f:m:dh' OPT; do
		case $OPT in
			f)
				CONFIG_FILE=$OPTARG;;
			m)
				EXECUTE_MODE=$OPTARG;;
			d)
				DEBUG=true;;
			h)
				help-page && return 0;;
			?)
				echo "\033[1;31mUnknown argument.\033[0m" && exit 1;;
		esac
	done
	shift $(($OPTIND - 1))
	# validate input config file
	if [[ ! -n $CONFIG_FILE ]]; then
		# apply default config file
		CONFIG_FILE=$SCRIPT_DIR/data/repo.json
	fi
	[[ ! -f $CONFIG_FILE ]] && echo "Config file \033[0;33m$CONFIG_FILE\033[0m does not exist" && return 1
	# validate execute mode
	case $EXECUTE_MODE in
		(init | sync) echo "" ;;
		(*) echo "Execute mode \033[0;33m$EXECUTE_MODE\033[0m not exist" && return 1 ;;
	esac
	# get config file content
	local CONFIG=$(cat $CONFIG_FILE)
	# traverse repo list
	local REPO_LENGTH=$(echo $CONFIG | jq '. | length')
	for (( REPO_INDEX = 0; REPO_INDEX < $REPO_LENGTH; REPO_INDEX++ )); do
		local REPO_DATA=$(echo $CONFIG | jq ".[$REPO_INDEX]")
		local PROGRESS_INDEX=`expr $REPO_INDEX + 1`
		echo "--------------- Progress $PROGRESS_INDEX/$REPO_LENGTH ---------------\n" 
		repo-parse $REPO_DATA $EXECUTE_MODE
	done
}

running-check
load-config $@