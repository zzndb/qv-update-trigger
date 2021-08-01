#!/usr/bin/env bash
# set -euo pipefail
#
# Requires:
#   find (findutils)
#   wc, realpath, cat (coreutils)
#   grep

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
    [[ "$(wc -l <<<"$file")" != "1" || "$(wc -c <<<"$file")" -le 1 ]] && exit 1
    file="$(realpath "$file")"
    __interface_latest="$(cat "$file")"
}

# update version
get_old_version() {
    old_file='_service'
    [[ ! -f "${old_file}" ]] && exit 2
    __interface_old="$(grep 'versionprefix' "${old_file}")"
    [[ $? != 0 ]] && exit 4
    __interface_old="${__interface_old#*>}"
    __interface_old="${__interface_old%<*}"
}

get_old_version_spec() {
    old_file="$(find . -maxdepth 1 -name "*.spec")"
    [[ "$(wc -l <<<"${old_file}")" != 1 ]] && exit 5
    # [[ ! -f "${old_file}" ]] && exit 2
    __interface_old="$(grep '%define interface_version' "${old_file}")"
    [[ $? != 0 ]] && exit 4
    # %define interface_version 2
    __interface_old="${__interface_old##*' '}"
    # check whether a number
    [[ ! (${__interface_old} =~ ^[0-9]+$) ]] && exit 6
    # the do nothing hidden else ':' escape the error exit
    :
}

update_service_version() {
    # check target parameter 'spec'
    if [[ "$1" == 'spec' ]]; then
        sed -i "s/%define interface_version .*/%define interface_version ${__interface_latest}/" "${old_file}"
    else
        sed -i "s/<param name=\"versionprefix\">${__interface_old}/<param name=\"versionprefix\">${__interface_latest}/" "${old_file}"
    fi
}

update_interface() {
    [[ ! -o xtrace ]] && set -x && without_xtrace=
    target="${1:-service}"
    get_interface_version
    # check target parameter 'spec'
    if [[ "${target}" == 'spec' ]]; then
        get_old_version_spec
    else
        get_old_version
    fi
    # just return as a func instead of exit
    [[ "${__interface_old}" -eq "${__interface_latest}" ]] && return
    [[ "${__interface_old}" -gt "${__interface_latest}" ]] && exit 3
    update_service_version "${target}"
    [[ -v without_xtrace ]] && set +x && unset without_xtrace || :
}

# just '$@' for function test
# "$@"
