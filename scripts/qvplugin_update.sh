#!/usr/bin/env bash

# get log!
# __log_tdir=.
__log_mail_path="/home/zzndb/scripts/mail_notify.sh"
__log_keep_latest=
source /home/zzndb/scripts/get_log.sh

# needed: plugins project placed in the directory below
bdir='/home/zzndb/obs/home:zzndb'
pushd $bdir || exit 1

# osc service remoterun home:zzndb Qv2ray-preview
# osc service remoterun home:zzndb:Qv2ray Qv2ray-preview

renew_obsfile() {
    # delete old obs{cpio, info}
    find . -maxdepth 1 -type f \( -name "*.obscpio" -exec rm {} \; \) \
        -o \( -name "*.obsinfo" -exec rm {} \; \)
    # get source if needed / new obs{cpio, info}
    osc service disabledrun
}

unset dir_list
declare -a dir_list
while read -r item; do
    dir_list+=("$item")
done <<< "$(find "${bdir}" -maxdepth 1 -type d -name "QvPlugin-*")"

for p in "${dir_list[@]}"; do
    up_message='trigger update'

    pushd "$p" || exit 2
    set -x
    # update
    osc up

    GIT_DIR="$(find . -maxdepth 2 -type d -name '.git' | grep 'QvPlugin-')"
    CURRENT="$(git --git-dir="${GIT_DIR}" rev-parse --short HEAD)"
    # try 'osc service disablerun' once before re-clone source
    if ! renew_obsfile; then
        # remove old source dir to escape potential pull merge error
        find . -maxdepth 1 -type d -name "QvPlugin-*" -exec rm -rf {} \;
        # renew
        renew_obsfile
    fi
    LATEST="$(git --git-dir="${GIT_DIR}" rev-parse --short HEAD)"
    up_message="${up_message} ${CURRENT} -> ${LATEST}"

    # change interface version if needed
    ## source update_interface_version
    . /home/zzndb/scripts/update_interface_version.sh
    update_interface 'service'
    [[ "$?" != 0 ]] && exit 3
    if [[ "$(osc diff _service | wc --chars)" != "0" ]]; then
        up_message="${up_message}"" & bump interface version to ${latest}"

        # get_log!
        package_name="$(pwd)"
        package_name="${package_name##*/}"
        declare -F __log_add_to_message > /dev/null \
            && __log_add_to_message "bump ${package_name} interface to ${latest}"

        # renew obscpio/obsinfo
        renew_obsfile
    fi

    # update
    osc ar
    osc ci -m "${up_message}"
    set +x
    popd || exit 2
done
popd || exit 1
