#!/usr/bin/env bash
# set -euo pipefail

# process Qv2ray_preview _service file 'parent-tag' and 'versionprefix' part
# with the latest version which get query from github
# PRJ_DIR="$1"
# PRJ_DIR="$HOME/obs/home:zzndb/Qv2ray-preview/"
# API_URL='https://api.github.com/repos/Qv2ray/Qv2ray/releases/latest'

# VERSION='makespec/VERSION'
# BUILDVERSION='makespec/BUILDVERSION'

# sourced on main update script
# source /home/zzndb/scripts/obs-utils.sh

get_base_version() {
    pushd "${real_path}/Qv2ray" >/dev/null || exit 2
    __version="$(cat "${VERSION}")"
    value_check "${__version}"
    popd
}

get_buildversion() {
    pushd "${real_path}/Qv2ray" >/dev/null || exit 2
    __buildversion="$(cat "${BUILDVERSION}")"
    value_check "${__buildversion}"
    popd
}

# in: $1 prj name with .git
get_gitrev() {
    pushd "${real_path}/${1}" >/dev/null || exit 2
    __gitrev="$(git rev-parse --short HEAD)"
    value_check "${__gitrev}"
    popd
}

value_check() {
    [[ "$(wc -l <<<"$1")" != "1" || "$(wc -c <<<"$1")" -le 1 ]] && exit 1 || :
}

update_version() {
    [[ ! -o xtrace ]] && set -x && without_xtrace=
    prepare
    get_base_version
    get_buildversion
    get_gitrev 'Qv2ray'
    local old_version
    old_version="$(__query_service_param 'versionformat')"
    if ! sed -i "s/${old_version}/${__version}.${__buildversion}~git%cd.${__gitrev}/g" "${_service}"; then
        osc revert "${_service}"
        exit 5
    fi
    # change revision as well
    update_rev 'Qv2ray'
    [[ -v without_xtrace ]] && set +x && unset without_xtrace || :
}

# in: $1 prj name with .git
update_rev() {
    prepare
    local old_rev
    old_rev="$(__query_service_param 'revision')"
    get_gitrev "${1}"
    if ! sed -i "s/${old_rev}/${__gitrev}/g" "${_service}"; then
        osc revert "${_service}"
        exit 5
    fi
}

prepare() {
    real_path="$(realpath "$PRJ_DIR")"
    _service="${real_path}/_service"
}
