#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

# Deepak
source "$CONFIG_DIR/config.compute1"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Networking Option 2: Self-service networks
# http://docs.openstack.org/mitaka/install-guide-ubuntu/neutron-compute-install-option2.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the Linux bridge agent
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Configuring the Linux bridge agent."
conf=/etc/neutron/plugins/ml2/linuxbridge_agent.ini

# Edit the [linux_bridge] section.
# TODO Better method of getting interface name
PUBLIC_INTERFACE_NAME=eth2
#Deepak
if [ $EXT_NW_MULTIPLE = "true" ]; then
PUBLIC_INTERFACE_NAME_1=eth3
iniset_sudo $conf linux_bridge physical_interface_mappings provider:$PUBLIC_INTERFACE_NAME,provider1:$PUBLIC_INTERFACE_NAME_1
else
iniset_sudo $conf linux_bridge physical_interface_mappings provider:$PUBLIC_INTERFACE_NAME
fi

# Edit the [vxlan] section.
OVERLAY_INTERFACE_IP_ADDRESS=$(get_node_ip_in_network "$(hostname)" "mgmt")
iniset_sudo $conf vxlan enable_vxlan True
iniset_sudo $conf vxlan local_ip $OVERLAY_INTERFACE_IP_ADDRESS
iniset_sudo $conf vxlan l2_population True

# Edit the [agent] section.
iniset_sudo $conf agent prevent_arp_spoofing True

# Edit the [securitygroup] section.
iniset_sudo $conf securitygroup enable_security_group True
iniset_sudo $conf securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
