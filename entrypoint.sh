#!/bin/bash

cleanup() {
    log_info "Cleanup"
    printf "f\n" | script -q -c "pcloudcc -k" /dev/null
    sleep 1
    exit 143
}

red="\033[1;31m"
yellow="\033[1;33m"
cyan="\033[1;36m"
normal="\033[0m" 

log_info() {
  # Print colored to terminal
  echo -e "[info] $*"

  # Append plain text to log file
  # Strip ANSI codes before writing to file
  echo -e "$*" | sed 's/\x1b\[[0-9;]*m//g' >> "${LOG}"
}

log_warn() {
  # Print colored to terminal
  echo -e "[${yellow}warn${normal}] $*"

  # Append plain text to log file
  # Strip ANSI codes before writing to file
  echo -e "$*" | sed 's/\x1b\[[0-9;]*m//g' >> "${LOG}"
}

log_errs() {
  # Print colored to terminal
  echo -e "[${red}errs${normal}] $*"

  # Append plain text to log file
  # Strip ANSI codes before writing to file
  echo -e "$*" | sed 's/\x1b\[[0-9;]*m//g' >> "${LOG}"
}

if [ "$(id -u)" -eq 0 ] ; then
    mkdir -p "/root/.pcloud"
    LOG="/root/.pcloud/log.log"
else
	mkdir -p "${HOME}/.pcloud"
    LOG="${HOME}/.pcloud/log.log"
fi

log_info "Log"
log_info "USER    : ${USER}"
log_info "HOME    : ${HOME}"
log_info "HOST_UID: $(id -u)"
log_info "HOST_GID: $(id -g)"
log_info "whoami  : $(whoami)"

trap cleanup SIGTERM SIGINT

log_info "Check if mail is not empty, ${EMAIL}"
    
if [ -n "${EMAIL}" ] ; then

    log_info "Starting pcloudcc for user: ${cyan}${EMAIL}${normal}"
    if (
        umask 000
        PCLOUD_REGION_EU=true pcloudcc -u "${EMAIL}" -d
    ) ; then
    
        log_info "pcloud started"
                 
        # Wait an additional 2 seconds before starting checks
        log_info "Wait 2 seconds."
        sleep 2
                
        HAS_PROBLEMS=true

        for ((i=1; i<=4; i++)); do
        
            ERR1=false
            ERR2=false
            
            log_info "${i} Execute check."
        
            OUTPUT=$(printf "s ls\nq\n" | script -q -c "pcloudcc -k" /dev/null)
                    
            if echo "$OUTPUT" | grep -q "List Sync Folders failed: Unable to connect to UNIX socket"; then
                ERR1=true
                log_warn "${i} No user is logged in"
            fi

            if echo "$OUTPUT" | grep -q "No synchronized folders found."; then
                ERR2=true
                log_warn "${i} No folders are set up for synchronization."
            fi

            # Additional action if one of them matched
            if [ "${ERR1}" = "true" ] || [ "${ERR2}" = "true" ] ; then
                log_warn "${i} Attempt failed, retrying..."
                HAS_PROBLEMS=false
                sleep 2
            else
                log_info "${i} Attempt succeeded."
                HAS_PROBLEMS=true
                break
            fi
        
        done

        # If all 4 attempts failed
        if [ "${HAS_PROBLEMS}" = "false" ] ; then
            log_errs "The background process will be disabled."
            printf "f\n" | script -q -c "pcloudcc -k" /dev/null
        fi
    else
        log_errs "Failed to start pcloud."
    fi
else
    log_errs "EMAIL variable is empty."
fi

# Keep container running and wait so signals can be caught
log_info "Keep script running."
sleep infinity &
wait $!

