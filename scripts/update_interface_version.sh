#!/usr/bin/env bash
# set -euo pipefail

# do what?
#   check github page / updated local for interface version
#   auto update interface version prefix if needed
# how?
#   get interface version from interface/InterfaceVersion file
#   change interface in _service file or spec file
#
# call from QvPlugin update script
# at OBS project directory 

# get version
get_interface_version() {
    file="$(find . -type f -name InterfaceVersion)"
    # check whether find the file 
    [[ "$(wc -l <<< "$file")" != "1" || "$(wc -c <<< "$file")" -le 1 ]] && exit 1
    file="$(readlink -f "$file")"
    latest="$(cat "$file")"
}

# update version
get_old_version() {
    old_file='_service'
    [[ ! -f "${old_file}" ]] && exit 2
    old="$(grep 'versionprefix' "${old_file}")"
    [[ $? != 0 ]] && exit 4
    old="${old#*>}"
    old="${old%<*}"
}

get_old_version_spec() {
    old_file="$(find . -maxdepth 1 -name "*.spec")"
    [[ "$(wc -l <<< "${old_file}")" != 1 ]] && exit 5
    # [[ ! -f "${old_file}" ]] && exit 2
    old="$(grep '%define interface_version' "${old_file}")"
    [[ $? != 0 ]] && exit 4
    # %define interface_version 2
    old="${old##*' '}"
    # check whether a number
    [[ ! ( ${old} =~ ^[0-9]+$ ) ]] && exit 6
    # the do nothing hidden else ':' escape the error exit
    :
}

update_service_version() {
    # check target parameter 'spec'
    if [[ "$1" == 'spec' ]]; then
        sed -i "s/%define interface_version .*/%define interface_version ${latest}/" "${old_file}"
    else
        sed -i "s/<param name=\"versionprefix\">${old}/<param name=\"versionprefix\">${latest}/" "${old_file}"
    fi
}

update_interface() {
    set -x
    target="${1:-service}"
    get_interface_version
    # check target parameter 'spec'
    if [[ "${target}" == 'spec' ]]; then
        get_old_version_spec
    else
        get_old_version
    fi
    # just return as a func instead of exit
    [[ "${old}" -eq "${latest}" ]] && return
    [[ "${old}" -gt "${latest}" ]] && exit 3
    update_service_version "${target}"
    set +x
}

# just '$@' for function test
# "$@"
