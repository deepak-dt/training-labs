#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR"||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

# Deepak
source "$CONFIG_DIR/config.compute1"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Networking Option 2: Self-service networks
# http://docs.openstack.org/ocata/install-guide-ubuntu/neutron-compute-install-option2.html
#------------------------------------------------------------------------------

# Deepak
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the Open vSwitch agent
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Configuring the Open vSwitch agent."
conf=/etc/neutron/plugins/ml2/openvswitch_agent.ini

# Deepak
# Edit the [ovs] section.
OVERLAY_INTERFACE_IP_ADDRESS=$(get_node_ip_in_network "$(hostname)" "overlay")
#OVERLAY_INTERFACE_IP_ADDRESS=$(echo "$NET_IF_3" |awk '{print $2}')
iniset_sudo $conf ovs local_ip $OVERLAY_INTERFACE_IP_ADDRESS

# Deepak
# Edit the [agent] section.
iniset_sudo $conf agent tunnel_types vxlan
iniset_sudo $conf agent l2_population true

# Deepak
# Edit the [securitygroup] section.
#iniset_sudo $conf securitygroup enable_security_group true
#iniset_sudo $conf securitygroup firewall_driver iptables_hybrid
