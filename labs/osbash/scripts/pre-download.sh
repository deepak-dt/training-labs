#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR"||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/openstack"
source "$CONFIG_DIR/localrc"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto

if [ -n "${VM_PROXY:-""}" ]; then
    echo "Using VM_PROXY as http_proxy: $VM_PROXY"
    export http_proxy=$VM_PROXY
    export https_proxy=$VM_PROXY
fi

# Deepak - generalize the function
# Download OS image
function get_os_image() {
    local OS_IMG_URL=$1
    local file_name=$(basename $OS_IMG_URL)
    local remote_dir=$(dirname $OS_IMG_URL)
    local md5_f=$file_name.md5sum

    mkdir -p "$IMG_DIR"

    # Download to IMG_DIR to cache the data if the directory is shared
    # with the host computer.
    if [ ! -f "$IMG_DIR/$md5_f" ]; then
        wget -O - "$remote_dir/MD5SUMS"|grep "$file_name" > "$IMG_DIR/$md5_f"
    fi

    if [ ! -f "$IMG_DIR/$file_name" ]; then
        wget --directory-prefix="$IMG_DIR" "$OS_IMG_URL"
    fi

    # Make sure we have image and MD5SUM on the basedisk.
    if [ "$IMG_DIR" != "$HOME/img" ]; then
        mkdir -p "$HOME/img"
        cp -a "$IMG_DIR/$file_name" "$IMG_DIR/$md5_f" "$HOME/img"
    fi

    cd "$HOME/img"
    md5sum -c "$HOME/img/$md5_f"
    cd -
}

function pre-download_remote_file {
    local file=$1
    local url=$2
    local dir=${3:-$HOME}

    if [ ! -f "$dir/$file" ]; then
        wget --directory-prefix "$dir" -O "$file" "$url"
    fi
}

# Deepak
# Get cirros, ubuntu images.
get_os_image $CIRROS_URL
get_os_image $UBUNTU_16_04_URL

# Swift controller
pre-download_remote_file "swift-proxy-server.conf" \
        "https://git.openstack.org/cgit/openstack/swift/plain/etc/proxy-server.conf-sample?h=stable/newton"

# Swift storage
pre-download_remote_file "swift-account-server.conf" \
        "https://git.openstack.org/cgit/openstack/swift/plain/etc/account-server.conf-sample?h=stable/newton"

pre-download_remote_file "swift-container-server.conf" \
        "https://git.openstack.org/cgit/openstack/swift/plain/etc/container-server.conf-sample?h=stable/newton"

pre-download_remote_file "swift-object-server.conf" \
        "https://git.openstack.org/cgit/openstack/swift/plain/etc/object-server.conf-sample?h=stable/newton"

# Swift finalize
pre-download_remote_file "swift-swift.conf" \
        "https://git.openstack.org/cgit/openstack/swift/plain/etc/swift.conf-sample?h=stable/newton"
