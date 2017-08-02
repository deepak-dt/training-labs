#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR"||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto
# tacker is to be started manually after setup is up. Tacker start in automation do not exit from script. 
sudo python /usr/local/bin/tacker-server \
    --config-file /usr/local/etc/tacker/tacker.conf \
    --log-file /var/log/tacker/tacker.log &

#source admin-openrc.sh
#tacker vim-register --is-default --config-file /etc/tacker/config.yaml \
#       --description Aricent_Gurugram_network VIM.Aricent.Gurugram

