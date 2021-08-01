#!/usr/bin/env bash
# set -euo pipefail
#
# Requires:
#   wget
#   realpath, tr, dirname, wc (coreutils)
#   grep
#   find (findutils)
#   awk (gawk)

__error_exit() {
    echo -e "$1" > /dev/stderr
    exit "${2:-99}"
}

__empty_test() {
    [[ "${1}" == "" ]] && exit "${2:-99}" || :
}

# test $1 call __error_exit with $2 $3
__empty_exit() {
    [[ "${1}" == "" ]] && __error_exit "${2:-}" "${3:-99}" || :
}

# i: $1=$?, $2=error message
__exit_status_check() {
    if (($1 != 0)); then
        __error_exit "$2" "$1"
    fi
}

# get 'latest' version
# API_URL needed, like: https://api.github.com/repos/user_name/user_name/releases/latest
# i: optional $1, if set do not delete prefix 'v'
# o: latest tag, without prefix 'v'
__query_github_latest() {
    [[ -v "${API_URL}" ]] && __error_exit "REPO API_URL needed!" 2
    if [[ "${API_URL}" =~ .*\/tags$ ]]; then
        __query_github_latest_tag
    else
        local latest
        latest="$(wget "${API_URL}" -qO - | jq '.tag_name' | tr -d '"')"
        __exit_status_check "$?" "${FUNCNAME[0]}: error with latest (version) query"
        [[ -v 1 ]] && echo "${latest}" || echo "${latest#v}"
    fi
}

# get 'latest' tag name
# API_URL needed, like: https://api.github.com/repos/user_name/repo_name/tags
# o: latest tag, without prefix 'v'
__query_github_latest_tag() {
    [[ ! -v API_URL ]] && __error_exit "${FUNCNAME[0]}: REPO API_URL needed!" 2
    local latest
    latest="$(wget "${API_URL}" -qO - | jq '.[0].name' | tr -d '"')"
    __exit_status_check "$?" "${FUNCNAME[0]}: error with latest tag query"
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

# switch to called script / specify ($1) directory, set PRJ_DIR if needed
__switch_to_prj_dir() {
    local prj_dir
    if [[ "${1:-}" != '' && -d "$1" ]]; then
        pushd "$1" || __error_exit "${FUNCNAME[0]}: for some reason can not pushd in ${1}"
        prj_dir="$1"
    else
        local FILE_PATH PRJ_PATH
        FILE_PATH="$(realpath "$0")"
        PRJ_PATH="$(dirname "$FILE_PATH")"
        [[ -d "$PRJ_PATH" ]] && pushd "$PRJ_PATH" ||
                __error_exit "${FUNCNAME[0]}: for some reason can not pushd in ${PRJ_PATH}"
        prj_dir="$PRJ_PATH"
    fi
    if [[ ! -v PRJ_DIR ]]; then
        export PRJ_DIR="${prj_dir}"
    fi
}

# query param from spec, only the first one will be got if the param used more than once
# in: $1 param name like: Name, Version
__query_spec_param() {
    local real_path spec_file value
    [[ "${1:-}" == "" ]] && __error_exit "${FUNCNAME[0]}: param k needed!" 3
    [[ ! -v PRJ_DIR ]] && PRJ_DIR="$(realpath .)"
    real_path="$(realpath "$PRJ_DIR")"
    pushd "${real_path}" >/dev/null || exit 2
    spec_file="$(find . -maxdepth 1 -type f -name "*.spec")"
    [[ ${spec_file} == "" ]] && __error_exit "${FUNCNAME[0]}: no .spec file found!" 1
    [[ $(wc -l <<<"${spec_file}") -gt 1 ]] &&
        __error_exit "${FUNCNAME[0]}: more than one .spec file found!" 1
    [[ ! -f "${spec_file}" ]] && exit 3
    spec_file="$(realpath "${spec_file}")"

    value="$(awk -F':' "BEGIN{c=0} /${1}:/ {if (c==0) {print \$2}; c=1}" "${spec_file}")"
    # only work for space more than one between k/v
    value="${value##*  }"
    [[ ${value} == "" ]] && __error_exit "${FUNCNAME[0]}: empty value got!" 4 || echo "${value}"
    popd >/dev/null || exit 2
}

# set spec param value, only the first one will be set if the param used more than once
# in: $1 param name like: Name, Version
#     $2 param value
__set_spec_param() {
    local real_path spec_file value
    [[ "${1:-}" == "" || "${2:-}" == "" ]] && __error_exit "${FUNCNAME[0]}: param k/v needed!" 3
    [[ ! -v PRJ_DIR ]] && PRJ_DIR="$(realpath .)"
    real_path="$(realpath "$PRJ_DIR")"
    pushd "${real_path}" >/dev/null || exit 2
    spec_file="$(find . -maxdepth 1 -type f -name "*.spec")"
    [[ ${spec_file} == "" ]] && __error_exit "${FUNCNAME[0]}: no .spec file found!" 1
    [[ $(wc -l <<<"${spec_file}") -gt 1 ]] &&
        __error_exit "${FUNCNAME[0]}: more than one .spec file found!" 1
    [[ ! -f "${spec_file}" ]] && exit 3
    spec_file="$(realpath "${spec_file}")"

    space="$(awk -F':' "BEGIN{c=0} /${1}:/ {if (c==0) {print \$2}; c=1}" "${spec_file}")"
    # only work for space more than one between k/v
    space="${space%${space##*  }}"
    if ! sed -i "s/^${1}:${space}.*$/${1}:${space}${2}/" "${spec_file}"; then
        osc revert "${spec_file}"
        __error_exit "${FUNCNAME[0]}: sed replace ${1} with error" 5
    fi
    popd >/dev/null || exit 2
}

# replace .changes user info
# in: $1 optional dir contain .changes file
__hide_changes_userinfo() {
    local obs_user obs_mail
    obs_user='opensuse-packaging'
    obs_mail='opensuse-packaging@opensuse.org'

    __switch_to_prj_dir "${1:-}"
    local file_path
    file_path=$(find . -maxdepth 1 -type f -name "*.changes")
    [[ ${file_path} == "" ]] && __error_exit "${FUNCNAME[0]}: no .changes file found!" 1
    [[ $(wc -l <<<"${file_path}") -gt 1 ]] &&
        __error_exit "${FUNCNAME[0]}: more than one .changes file found!" 1
    file_path=$(realpath "$file_path")

    # Wed Jun 24 06:17:14 UTC 2020 - opensuse-packaging <opensuse-packaging@opensuse.org>
    sed -i "s/ - .* <.*@.*>$/ - ${obs_user} <${obs_mail}>/" "${file_path}"
    # Wed Jun 24 06:17:14 UTC 2020 - opensuse-packaging@opensuse.org
    # TODO correct it
    # sed -i "s/ - .*@[0-9A-Za-z.]*$/ - ${obs_mail}/" "${file_path}"
}

# renew golang vendor
# $1: name of source dir
__renew_golang_vendor() {
    [[ "${1:-}" == '' ]] && __error_exit "${FUNCNAME[0]}: no source dir name set!"
    pushd "$1" || __error_exit "${FUNCNAME[0]}: source dir name ${1} not right?"
    # TODO check vendor ext
    go mod vendor && tar cJf ../vendor.tar.xz vendor && rm -r vendor
    popd || __error_exit "${FUNCNAME[0]}: can not popd with ${PWD} -> $(dirs | cut -d' ' -f2) ???"
}

# renew cargo vendor
# $1: name of source dir
__renew_cargo_vendor() {
    [[ "${1:-}" == '' ]] && __error_exit "${FUNCNAME[0]}: no source dir name set!"
    pushd "$1" || __error_exit "${FUNCNAME[0]}: source dir name ${1} not right?"
    # TODO check vendor ext
    cargo vendor && tar cJf ../vendor.tar.xz vendor && rm -r vendor
    # TODO check cargo-home set instruct
    popd || __error_exit "${FUNCNAME[0]}: can not popd with ${PWD} -> $(dirs | cut -d' ' -f2) ???"
}
