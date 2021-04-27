#!/usr/bin/env bash
#
set -euo pipefail

# get log!
# __log_tdir=.
__log_mail_path="/home/zzndb/scripts/mail_notify.sh"
__log_keep_latest=
source /home/zzndb/scripts/get_log.sh

# - update base
# - check update
# - up file or just trigger service run

P_DIR='/home/zzndb/obs/home:zzndb/Qv2ray-preview'
API_URL='https://api.github.com/repos/Qv2ray/Qv2ray/releases/latest'
up_message='trigger update'

VERSION='makespec/VERSION'
BUILDVERSION='makespec/BUILDVERSION'

## 0x00
pushd "${P_DIR}" || exit
if ! osc up; then
    exit
fi

## 0x01
### update version if needed
### get from github release & sed replace all version
# ~/scripts/update_parent_version.sh
# [[ "$?" != 0 ]] && exit
#
## 0x01-1 
## get all version from source
set -x
# need maintain source directory
[[ ! -d Qv2ray ]] && {
    if ! git clone -b dev https://github.com/Qv2ray/Qv2ray.git; then
        exit 
    fi
}
pushd Qv2ray || exit
# check change
CURRENT="$(git rev-parse --short HEAD)"
git fetch --all
git reset --hard origin/dev
git pull
LATEST="$(git rev-parse --short HEAD)"
git submodule update --init --recursive
git submodule update --recursive --force
[[ "${CURRENT}" == "${LATEST}" && "${CURRENT}" != "" ]] && exit 0
# filter some change
[[ $(git diff --name-only "${CURRENT}" "${LATEST}" \
    | grep -cv '^.github\|^.copr\|^debian\|^snap') -le 0 ]] && exit 0
popd || exit

##
source /home/zzndb/scripts/obs-utils.sh 
__old_version="$(__query_old_base_version "versionformat")"

# query old revision
up_message="${up_message} $(__query_service_param 'revision') -> ${LATEST}"
### 'version' and 'revision' (for remote specified source pull) in _service file
source /home/zzndb/scripts/update_service_version.sh
update_version
### get new version from above source
source /home/zzndb/scripts/update_interface_version.sh
update_interface 'spec'

set -x
## 0x02
__try_renew_obsfile "Qv2ray"

# base version update (with old_main)
# compare __version from update_parent_version.sh
#         __old_version from __query_old_base_version
if (("$(__check_version_update "${__old_version}" "${__version}")")); then
    up_message="${up_message}"" & bump base version to ${__version}"

    # get_log!
    package_name="$(pwd)"
    package_name="${package_name##*/}"
    declare -F __log_add_to_message > /dev/null \
        && __log_add_to_message "bump ${package_name} base version to ${old}"

fi
# interface version update
if [[ "$(osc diff 'Qv2ray-preview.spec' | wc --chars)" != "0" ]]; then
    up_message="${up_message}"" & bump interface version to ${latest}"

    # get_log!
    package_name="$(pwd)"
    package_name="${package_name##*/}"
    declare -F __log_add_to_message > /dev/null \
        && __log_add_to_message "bump ${package_name} interface version to ${latest}"
fi

osc ar
osc ci -m "${up_message}"
set +x
popd || exit
