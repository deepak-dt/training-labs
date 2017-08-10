#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR"||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

# Deepak
source "$CONFIG_DIR/config.compute1"
source "$CONFIG_DIR/config.controller"

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

if [ $EXT_NW_ON_COMPUTE = "true" ]; then
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Create the provider bridge in OVS
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  sudo ovs-vsctl add-br $EXT_BRIDGE_NAME_1
  sudo ovs-vsctl add-port $EXT_BRIDGE_NAME_1 $PROVIDER_INTERFACE_1

  # Deepak
  echo "EXT_BRIDGE_NAME_1=$EXT_BRIDGE_NAME_1"
  echo "EXT_BRIDGE_NAME_2=$EXT_BRIDGE_NAME_2"

  if [ $EXT_NW_MULTIPLE = "true" ]; then
    sudo ovs-vsctl add-br $EXT_BRIDGE_NAME_2
    sudo ovs-vsctl add-port $EXT_BRIDGE_NAME_2 $PROVIDER_INTERFACE_2
	
	EXT_BRIDGE_MAPPING="provider:$EXT_BRIDGE_NAME_1,provider1:$EXT_BRIDGE_NAME_2"
    iniset_sudo $conf ovs bridge_mappings $EXT_BRIDGE_MAPPING
  else
    iniset_sudo $conf ovs bridge_mappings provider:$EXT_BRIDGE_NAME_1
  fi
fi

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

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the Modular Layer 2 (ML2) plug-in
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
echo "Installing ml2 plugin."
sudo apt-get install neutron-plugin-ml2

echo "Configuring ml2_conf.ini."
conf=/etc/neutron/plugins/ml2/ml2_conf.ini

# Edit the [ml2] section.
iniset_sudo $conf ml2 type_drivers flat,vlan,vxlan
iniset_sudo $conf ml2 tenant_network_types vxlan
iniset_sudo $conf ml2 mechanism_drivers openvswitch,l2population
iniset_sudo $conf ml2 extension_drivers port_security

# Deepak
if [ $EXT_NW_ON_COMPUTE = "true" ]; then
  if [ $EXT_NW_MULTIPLE = "true" ]; then
    PROVIDER_NETWORKS="provider,provider1"
	
	# Edit the [ml2_type_flat] section.
    iniset_sudo $conf ml2_type_flat flat_networks $PROVIDER_NETWORKS
    
	# Edit the [ml2_type_vlan] section.
	iniset_sudo $conf ml2_type_vlan network_vlan_ranges $PROVIDER_NETWORKS
  else
    # Edit the [ml2_type_flat] section.
    iniset_sudo $conf ml2_type_flat flat_networks provider
	
	# Edit the [ml2_type_vlan] section.
    iniset_sudo $conf ml2_type_vlan network_vlan_ranges provider
  fi
fi

# Deepak
# Edit the [ml2_type_vxlan] section.
iniset_sudo $conf ml2_type_vxlan vni_ranges 1:1000

# Edit the [securitygroup] section.
iniset_sudo $conf securitygroup enable_ipset true

