#!/bin/sh

readonly HOST_NAME="${1:?Missing: Hostname}"
readonly SECRET_KEY="${2:?Missing: Secret key}"

function log_info() {
    local level="${1:-info}"
    local tag="nsupdate.info-updater[$$]"
    logger -t "$tag" -pdaemon.$level "$@"
}

function log_warning() {
    log_info "warning"
}

function log_error() {
    log_info "err"
}

is_under_CGN() {
    local my_ip_address="${1:?Missing:IP address}"

    local result=$( traceroute "$my_ip_address" -n --max-hops=3 | tail -1 )
    local hops=$( printf "${result## }" | cut -d ' ' -f 1 )
    local ip_address=$( printf "${result## }" | cut -d ' ' -f 2 )

    if [ "$hops" == "1" ] && [ "$my_ip_address" == "$ip_address" ]; then
        return 1
    fi

    log_warning "IPv4 network is under CGN."
    return 0
}

is_update_needed() {
    local my_ip_address="${1:?Missing: Current public IP address}"

    if [ $( nslookup $HOST_NAME | grep -c "$my_ip_address" ) -ge 1 ]; then
        log_info "$HOST_NAME is already updated with the same address: $my_ip_address."
        return 1
    fi

    return 0
}

delete_hostname() {
    local ip_version="${1:?Missing: IP version}"

    local result="$( uclient-fetch -qO- "https://$HOST_NAME:$SECRET_KEY@$ip_version.nsupdate.info/nic/delete" )"
    local result_successful="deleted *"
    case "$result" in
        $result_successful)
            log_info "$ip_version address deleted for $HOST_NAME."
            ;;
        *)
            log_error "Failed to delete $ip_version address for $HOST_NAME. Error: $result"
            exit 1
            ;;
    esac
}

change_hostname() {
    local ip_version="${1:?Missing: IP version}"

    get_result_code() {
        printf "$1" | cut -d ' ' -f 1
    }
    get_result_ip_address() {
        printf "$1" | cut -d ' ' -f 2
    }

    local result=$( uclient-fetch -qO- "https://$HOST_NAME:$SECRET_KEY@$ip_version.nsupdate.info/nic/update" )
    local updated_ip_address=$( get_result_ip_address "$result" )
    local result_successful_changed="good"
    local result_successful_unchanged="nochg"
    case $( get_result_code "$result" ) in
        $result_successful_changed)
            log_info "$HOST_NAME has been updated successfully with $ip_version address: $updated_ip_address"
            ;;
        $result_successful_unchanged)
            log_info "$HOST_NAME still has the same $ip_version address: $updated_ip_address."
            ;;
        *)
            log_error "Failed to update $HOST_NAME with $ip_version address. Error: $result"
            exit 1
            ;;
    esac
}

update_hostname() {
    local ip_version="${1:?Missing: IP version}"
    local my_ip_address="$2"

    if [[ -z "$my_ip_address" ]]; then
        delete_hostname "$1"
    else
        change_hostname "$1"
    fi
}

get_my_ip_address() {
    local ip_version="${1:?Missing: IP version}"
    uclient-fetch -qO- "https://$ip_version.nsupdate.info/myip"
}

process() {
    local ip_version=$( printf "${1:?Missing: IP version}" | awk '{print tolower($0)}' ) 

    local my_ip_address=$( get_my_ip_address "$ip_version" )
    if [[ "$ip_version" == "ipv4" ]] && is_under_CGN "$my_ip_address"; then
        my_ip_address=""
    fi

    if is_update_needed "$my_ip_address"; then
        update_hostname "$ip_version" "$my_ip_address"
    fi
}

process "IPv4"
process "IPv6"

exit 0