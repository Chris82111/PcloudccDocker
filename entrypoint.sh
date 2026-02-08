#!/bin/bash

cleanup() {
    log "[info] Cleanup"
    printf "f\n" | script -q -c "pcloudcc -k" /dev/null
    sleep 1
    exit 143
}

log() {
  echo "$*" | tee -a "${LOG}"
}

if [ "$(id -u)" -eq 0 ]; then
    mkdir -p "/root/.pcloud"
    LOG="/root/.pcloud/log.log"
    log "[info] Log"
    log "[info] User: root"
else
    DEFAULT_USER="ubuntu"
    mkdir -p "/home/${DEFAULT_USER}/.pcloud"
    LOG="/home/${DEFAULT_USER}/.pcloud/log.log"
    log "[info] Log"
    log "[info] User: ${DEFAULT_USER}"
fi

trap cleanup SIGTERM SIGINT

log "[info] Check if mail is not empty, ${EMAIL}"
    
if [ -n "${EMAIL}" ] ; then

    log "[info] Starting pcloudcc for user: ${EMAIL}"
    if (
        umask 000
        PCLOUD_REGION_EU=true pcloudcc -u "${EMAIL}" -d
    ) ; then
    
        log "[info] pcloud started"
                 
        # Wait an additional 2 seconds before starting checks
        log "[info] Wait 2 seconds."
        sleep 2
                
        HAS_PROBLEMS=true

        for ((i=1; i<=4; i++)); do
        
            ERR1=false
            ERR2=false
            
            log "[info] ${i} Execute check."
        
            OUTPUT=$(printf "s ls\nq\n" | script -q -c "pcloudcc -k" /dev/null)
                    
            if echo "$OUTPUT" | grep -q "List Sync Folders failed: Unable to connect to UNIX socket"; then
                ERR1=true
                log "[errs] ${i} No user is logged in"
            fi

            if echo "$OUTPUT" | grep -q "No synchronized folders found."; then
                ERR2=true
                log "[errs] ${i} No folders are set up for synchronization."
            fi

            # Additional action if one of them matched
            if [ "${ERR1}" = "true" ] || [ "${ERR2}" = "true" ] ; then
                log "[errs] ${i} Attempt failed, retrying..."
                HAS_PROBLEMS=false
                sleep 2
            else
                log "[info] ${i} Attempt succeeded."
                HAS_PROBLEMS=true
                break
            fi
        
        done

        # If all 4 attempts failed
        if [ "${HAS_PROBLEMS}" = "false" ] ; then
            log "[info] The background process will be disabled."
            printf "f\n" | script -q -c "pcloudcc -k" /dev/null
        fi
    else
        log "[errs] Failed to start pcloud."
    fi
else
    log "[errs] EMAIL variable is empty."
fi

# Keep container running and wait so signals can be caught
log "[info] Keep script running."
sleep infinity &
wait $!

