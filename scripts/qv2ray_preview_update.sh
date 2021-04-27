#!/usr/bin/env bash
#
set -euo pipefail

# - update base
# - check update
# - up file or just trigger service run

## needed outer parameters
## OBS_DIR, REPO_DIR
OBS_PRJ='home:zzndb001:test/Qv2ray-preview'
UP_REPO='zzndb/Qv2ray'
PRJ_DIR="${OBS_DIR}/${OBS_PRJ}"
API_URL="https://api.github.com/repos/${UP_REPO}/releases/latest"

up_message='trigger update'

VERSION='makespec/VERSION'
BUILDVERSION='makespec/BUILDVERSION'

## 0xFF
## checkout obs prj source
pushd "${OBS_DIR}" || exit
osc checkout ${OBS_PRJ}
popd || exit

## 0x00
pushd "${PRJ_DIR}" || exit
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

source "${REPO_DIR}"/scripts/obs-utils.sh
__old_version="$(__query_old_base_version "versionformat")"
# query old revision from _service
CURRENT="$(__query_service_param 'revision')"

# seems just need record last commit short rev
## seems osc do not check upstream if source exist?
[[ ! -d Qv2ray ]] && {
    if ! git clone -b dev https://github.com/${UP_REPO}.git; then
        exit 
    fi
}
pushd Qv2ray || exit
# check change
git fetch --all
git reset --hard origin/dev
git pull
LATEST="$(git rev-parse --short HEAD)"
git submodule update --init --recursive
git submodule update --recursive --force
[[ "${CURRENT}" == "${LATEST}" && "${CURRENT}" != "" ]] && exit 0
# filter some change
CHANGE_COUNT=$(git diff --name-only "${CURRENT}" "${LATEST}" \
    | grep -cv '^.github\|^.copr\|^debian\|^snap')
[[ ${CHANGE_COUNT} -le 0 ]] && exit 0
popd || exit

up_message="${up_message} ${CURRENT} -> ${LATEST}"
### 'version' and 'revision' (for remote specified source pull) in _service file
source "${REPO_DIR}"/scripts/update_service_version.sh
update_version
### get new version from above source
source "${REPO_DIR}"/scripts/update_interface_version.sh
update_interface 'spec'

set -x
## 0x02
__try_renew_obsfile "Qv2ray"

# base version update (with old_main)
# compare __version from update_parent_version.sh
#         __old_version from __query_old_base_version
if (("$(__check_version_update "${__old_version}" "${__version}")")); then
    up_message="${up_message}"" & bump base version to ${__version}"
fi
# interface version update
if [[ "$(osc diff 'Qv2ray-preview.spec' | wc --chars)" != "0" ]]; then
    up_message="${up_message}"" & bump interface version to ${latest}"
fi

osc ar
osc ci -m "${up_message}"
set +x
popd || exit
