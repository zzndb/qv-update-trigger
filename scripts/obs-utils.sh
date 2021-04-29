#!/usr/bin/env bash
# set -euo pipefail

__error_exit() {
    echo -e "$1"
    exit "${2:-99}"
}

__empty_test() {
    [[ "${1}" == "" ]] && exit "${2:-99}"
    :
}

# get 'latest' version
# API_URL needed, like: https://api.github.com/repos/user_name/user_name/releases/latest
# o: latest tag, without prefix 'v'
__query_github_latest() {
    [[ -v "${API_URL}" ]] && __error_exit "REPO API_URL needed!" 2
    if [[ "${API_URL}" =~ .*\/tags$ ]]; then
        __query_github_latest_tag
    else
        local latest
        latest="$(wget "${API_URL}" -qO - | jq '.tag_name' | tr -d '"')"
        [[ "$?" != 0 ]] && exit 1
        echo "${latest#v}"
    fi
}

# get 'latest' tag name
# API_URL needed, like: https://api.github.com/repos/user_name/repo_name/tags
# o: latest tag, without prefix 'v'
__query_github_latest_tag() {
    [[ ! -v API_URL ]] && __error_exit "${FUNCNAME[0]}: REPO API_URL needed!" 2
    local latest
    latest="$(wget "${API_URL}" -qO - | jq '.[0].name' | tr -d '"')"
    [[ "$?" != 0 ]] && __error_exit "${FUNCNAME[0]}: error with latest tag query" 1
    echo "${latest#v}"
}

# i: $1 xml tag keyword, like 'version'
# o: version string
# PRJ_DIR needed
__query_service_param() {
    local real_path
    [[ ! -v PRJ_DIR ]] && __error_exit "${FUNCNAME[0]}: Project directory 'PRJ_DIR' needed!" 2
    real_path="$(realpath "$PRJ_DIR")"
    pushd "${real_path}" >/dev/null || exit 2
    _service="${real_path}/_service"
    [[ ! -f "${_service}" ]] && exit 3
    old="$(grep "name=\"${1}\">" "${_service}")"
    # TODO potential issue: more than one param with same key, like 'exclude'
    [[ "${old}" == "" ]] && exit 4
    old="${old#*>}"
    old="${old%<*}"
    popd >/dev/null || exit 2
    echo "${old}"
}

# i: $1 xml tag key, $2 new value
# PRJ_DIR needed
__set_service_param() {
    local real_path
    [[ "${1:-}" == "" || "${2:-}" == "" ]] && __error_exit "${FUNCNAME[0]}: param k/v needed!" 3
    [[ ! -v PRJ_DIR ]] && __error_exit "${FUNCNAME[0]}: Project directory 'PRJ_DIR' needed!" 2
    real_path="$(realpath "$PRJ_DIR")"
    pushd "${real_path}" >/dev/null || exit 2
    _service="${real_path}/_service"
    [[ ! -f "${_service}" ]] && exit 3
    local old_param
    old_param="$(__query_service_param "${1}")"
    if ! sed -i "s/${old_param}/${2}/" "${_service}"; then
        osc revert "${_service}"
        exit 5
    fi
    popd >/dev/null || exit 2
}

# get '_service' path, 'old' version
# PRJ_DIR needed
# i: [optional] keyword
# like: <param name="version">2.7.0.6000~git.94d701ce</param>
# o: 2.7.0
__query_old_base_version() {
    [[ ! -v PRJ_DIR ]] && __error_exit "${FUNCNAME[0]}: Project directory 'PRJ_DIR' needed!" 2
    local real_path
    real_path="$(realpath "$PRJ_DIR")"
    pushd "${real_path}" >/dev/null || exit 2
    _service="${real_path}/_service"
    [[ ! -f "${_service}" ]] && exit 3
    local keyword
    keyword="${1:-version}"
    old="$(grep "name=\"$keyword\">" "${_service}")"
    [[ "${old}" == "" ]] && exit 4
    old="${old#*>}"
    old="${old%<*}"
    old="${old%~*}" # delete ~git.xxx
    old="${old%.*}" # delete .xxxx
    popd >/dev/null || exit 2
    echo "${old}"
}

# i: out and new
# o: 1: true or 0: false
__check_version_update() {
    __empty_test "${1}"
    __empty_test "${2}"
    # latest='2.6.1'
    # old='2.6.0'
    [[ "${1}" == "${2}" ]] && echo 0 && return
    local t_old
    local t_latest
    t_old="$(tr -d '.' <<<"${1}")"
    t_latest="$(tr -d '.' <<<"${2}")"
    [[ "${t_old}" > "${t_latest}" ]] && exit 3
    echo 1 && return
}

# renew obsfile for disabled mode package
__renew_obsfile() {
    # delete old obs{cpio, info}
    find . -maxdepth 1 -type f \( -name "*.obscpio" -exec rm {} \; \) \
        -o \( -name "*.obsinfo" -exec rm {} \; \)
    # get source if needed / new obs{cpio, info}
    osc service disabledrun
}

# try 'osc service disablerun' once before re-clone source
# in: $1 -> name of source dir, because of find, can use without specify name
__try_renew_obsfile() {
    [[ "${1:-}" == '' ]] && __error_exit "${FUNCNAME[0]}: no source dir name set!"
    if ! __renew_obsfile; then
        # remove old source dir to escape otential pull merge error
        find . -maxdepth 1 -type d -name "$1" -exec rm -rf {} \;
        # renew
        __renew_obsfile
    fi
}

# switch to called script / specify ($1) directory
__switch_to_prj_dir() {
    if [[ "${1:-}" != '' && -d "$1" ]]; then
        pushd "$1" || __error_exit "${FUNCNAME[0]}: for some reason can not pushd in ${1}"
    else
        local FILE_PATH
        local PRJ_PATH
        FILE_PATH="$(realpath "$0")"
        PRJ_PATH="$(dirname "$FILE_PATH")"
        [[ -d "$PRJ_PATH" ]] && pushd "$PRJ_PATH" ||
            __error_exit "${FUNCNAME[0]}: for some reason can not pushd in ${PRJ_PATH}"
    fi

}

# TODO query version from spec
