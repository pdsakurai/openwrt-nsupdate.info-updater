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

function is_under_CGN() {
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

function is_update_needed() {
    local ip_version="${1:?Missing: IP version}"
    local my_ip_address="${2:-NXDOMAIN}"

    local dns_record_type="$( [ "$ip_version" == "IPv4" ] \
        && printf "a" \
        || printf "aaaa" )"

    if [ $( nslookup -type=$dns_record_type $HOST_NAME | grep -c "$my_ip_address" ) -ge 1 ]; then
        log_info "$ip_version address of $HOST_NAME is still $my_ipaddress."
        return 1
    fi

    return 0
}

function delete_hostname() {
    local ip_version="${1:?Missing: IP version}"

    local result="$( uclient-fetch -qO- "https://$HOST_NAME:$SECRET_KEY@$ip_version.nsupdate.info/nic/delete" )"
    local result_successful="deleted *"
    case "$result" in
        $result_successful)
            log_info "$ip_version address deleted for $HOST_NAME."
            return 0
        *)
            log_error "Failed to delete $ip_version address for $HOST_NAME. Error: $result"
            return 1
    esac
}

function change_hostname() {
    local ip_version="${1:?Missing: IP version}"

    local result=$( uclient-fetch -qO- "https://$HOST_NAME:$SECRET_KEY@$ip_version.nsupdate.info/nic/update" )
    local updated_ip_address=$( printf "$result" | cut -d ' ' -f 2 )
    local result_successful_changed="good"
    local result_successful_unchanged="nochg"
    case $( printf "$result" | cut -d ' ' -f 1 ) in
        $result_successful_changed)
            log_info "$HOST_NAME has been updated successfully with $ip_version address: $updated_ip_address"
            ;;
        $result_successful_unchanged)
            log_warning "$HOST_NAME still has the same $ip_version address: $updated_ip_address."
            ;;
        *)
            log_error "Failed to update $HOST_NAME with $ip_version address. Error: $result"
            return 1
    esac

    return 0
}

function update_hostname() {
    local ip_version="${1:?Missing: IP version}"
    local my_ip_address="$2"

    if [ -z "$my_ip_address" ]; then
        delete_hostname "$1"
    else
        change_hostname "$1"
    fi

    return $?
}

function get_my_ip_address() {
    uclient-fetch -qO- "https://${1:?Missing: IP version}.nsupdate.info/myip" 2> /dev/null
}

function process() {
    local ip_version="${1:?Missing: IP version}"

    local my_ip_address=$( get_my_ip_address "$ip_version" )
    if [ "$ip_version" == "IPv4" ] && [ -n "$my_ip_address" ] && is_under_CGN "$my_ip_address"; then
        my_ip_address=""
    fi

    if is_update_needed "$ip_version" "$my_ip_address"; then
        update_hostname "$ip_version" "$my_ip_address"
    fi
}

while true; do
    process "IPv4"
    process "IPv6"

    log_info "Next update will be done after 1 day."
    sleep 86400
done

exit 0