#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR"||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

# Deepak
source "$CONFIG_DIR/openstack"

exec_logfile

indicate_current_auto
# tacker is to be started manually after setup is up. Tacker start in automation do not exit from script. 
#run_process "$1" "$2" >$SERVICE_DIR/$SCREEN_NAME/$1.pid

sudo python /usr/local/bin/tacker-server \
    --config-file /usr/local/etc/tacker/tacker.conf \
    --log-file /var/log/tacker/tacker.log > "$HOME/tacker-server-console.log" &

source admin-openrc.sh
tacker vim-register --is-default --config-file /etc/tacker/config.yaml --description Aricent_Gurugram_network VIM.Aricent.Gurugram
#tacker vim-register --is-default --config-file $HOME/tacker/config.yaml --description Aricent_Gurugram_network VIM.Aricent.Gurugram

tacker vnfd-create --vnfd-file "$HOME/img/$VNF_DHCP_NAME"".yaml" "VNFD_""$VNF_DHCP_NAME"
tacker vnfd-create --vnfd-file "$HOME/img/$VNF_FIREWALL_NAME"".yaml" "VNFD_""$VNF_FIREWALL_NAME"
tacker vnfd-create --vnfd-file "$HOME/img/$VNF_VROUTER_NAME"".yaml" "VNFD_""$VNF_VROUTER_NAME"

tacker vnffgd-create --vnffgd-file "$HOME/img/$VNFFGD_NAME"".yaml" "VNFFGD_""$VNFFGD_NAME"
