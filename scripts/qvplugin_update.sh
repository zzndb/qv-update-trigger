#!/usr/bin/env bash
#
set -euo pipefail

## needed outer parameters
## OBS_DIR, REPO_DIR
OBS_PRJ='home:zzndb001:test'

# needed: plugins project placed in the directory below
PLUGIN_DIR="${OBS_DIR}/${OBS_PRJ}"
pushd "$PLUGIN_DIR" || exit 1

# osc service remoterun home:zzndb Qv2ray-preview
# osc service remoterun home:zzndb:Qv2ray Qv2ray-preview

source "${REPO_DIR}"/scripts/obs-utils.sh

unset dir_list
declare -a dir_list
while read -r item; do
    dir_list+=("$item")
done <<<"$(osc api /source/${OBS_PRJ} | awk -F'"' '/QvPlugin/ {print $2}')"

for p in "${dir_list[@]}"; do
    up_message='trigger update'

    # checkout obs prj source
    osc checkout "${p}"

    pushd "$p" || exit 2
    set -x
    # update
    osc up

    GIT_DIR="$(find . -maxdepth 2 -type d -name '.git' | grep 'QvPlugin-')"
    CURRENT="$(__query_service_param 'revision')"
    # try 'osc service disablerun' once before re-clone source
    __try_renew_obsfile "QvPlugin-*"
    LATEST="$(git --git-dir="${GIT_DIR}" rev-parse --short HEAD)"
    up_message="${up_message} ${CURRENT} -> ${LATEST}"

    # change interface version if needed
    source "${REPO_DIR}"/scripts/update_interface_version.sh
    update_interface 'service'
    source "${REPO_DIR}"/scripts/update_service_version.sh
    update_rev
    if [[ "$(osc diff _service | wc --chars)" != "0" ]]; then
        up_message="${up_message}"" & bump interface version to ${latest}"
        # renew obscpio/obsinfo
        __try_renew_obsfile
    fi

    # update
    osc ar
    osc ci -m "${up_message}"
    set +x
    popd || exit 2
done
popd || exit 1
