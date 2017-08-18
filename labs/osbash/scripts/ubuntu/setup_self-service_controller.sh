#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR"||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"
source "$CONFIG_DIR/openstack"

# Deepak
source "$CONFIG_DIR/config.controller"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Networking Option 2: Self-service networks
# http://docs.openstack.org/ocata/install-guide-ubuntu/neutron-controller-install-option2.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install the components
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Deepak
echo "Installing additional packages for self-service networks."
sudo apt install -y \
    neutron-server neutron-plugin-ml2 \
    neutron-openvswitch-agent neutron-l3-agent neutron-dhcp-agent \
    neutron-metadata-agent

echo "Configuring neutron for controller node."
function get_database_url {
    local db_user=$NEUTRON_DB_USER
    local database_host=controller

    echo "mysql+pymysql://$db_user:$NEUTRON_DBPASS@$database_host/neutron"
}

database_url=$(get_database_url)

neutron_admin_user=neutron

nova_admin_user=nova

echo "Setting database connection: $database_url."
conf=/etc/neutron/neutron.conf

# Configure [database] section.
iniset_sudo $conf database connection "$database_url"

# Configure [DEFAULT] section.
iniset_sudo $conf DEFAULT core_plugin ml2
iniset_sudo $conf DEFAULT service_plugins router
iniset_sudo $conf DEFAULT allow_overlapping_ips true

echo "Configuring RabbitMQ message queue access."
iniset_sudo $conf DEFAULT transport_url "rabbit://openstack:$RABBIT_PASS@controller"

# Configuring [DEFAULT] section.
iniset_sudo $conf DEFAULT auth_strategy keystone

# Configuring [keystone_authtoken] section.
iniset_sudo $conf keystone_authtoken auth_uri http://controller:5000
iniset_sudo $conf keystone_authtoken auth_url http://controller:35357
iniset_sudo $conf keystone_authtoken memcached_servers controller:11211
iniset_sudo $conf keystone_authtoken auth_type password
iniset_sudo $conf keystone_authtoken project_domain_name default
iniset_sudo $conf keystone_authtoken user_domain_name default
iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf keystone_authtoken username "$neutron_admin_user"
iniset_sudo $conf keystone_authtoken password "$NEUTRON_PASS"

# Configure nova related parameters
iniset_sudo $conf DEFAULT notify_nova_on_port_status_changes true
iniset_sudo $conf DEFAULT notify_nova_on_port_data_changes true

# Configure [nova] section.
iniset_sudo $conf nova auth_url http://controller:35357
iniset_sudo $conf nova auth_type password
iniset_sudo $conf nova project_domain_name default
iniset_sudo $conf nova user_domain_name default
iniset_sudo $conf nova region_name "$REGION"
iniset_sudo $conf nova project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf nova username "$nova_admin_user"
iniset_sudo $conf nova password "$NOVA_PASS"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the Modular Layer 2 (ML2) plug-in
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Configuring the Modular Layer 2 (ML2) plug-in."
conf=/etc/neutron/plugins/ml2/ml2_conf.ini

# Edit the [ml2] section.
iniset_sudo $conf ml2 type_drivers flat,vlan,vxlan
iniset_sudo $conf ml2 tenant_network_types vxlan

# Deepak
#iniset_sudo $conf ml2 mechanism_drivers linuxbridge,l2population
iniset_sudo $conf ml2 mechanism_drivers openvswitch,l2population
iniset_sudo $conf ml2 extension_drivers port_security

if [ $EXT_NW_MULTIPLE = "true" ]; then
  # Edit the [ml2_type_flat] section.
  PROVIDER_NETWORKS="provider,provider1,provider_odl"
  iniset_sudo $conf ml2_type_flat flat_networks $PROVIDER_NETWORKS
  
  # Edit the [ml2_type_vlan] section.
  iniset_sudo $conf ml2_type_vlan network_vlan_ranges $PROVIDER_NETWORKS
else
  # Edit the [ml2_type_flat] section.
  iniset_sudo $conf ml2_type_flat flat_networks provider

  # Edit the [ml2_type_vlan] section.  
  iniset_sudo $conf ml2_type_vlan network_vlan_ranges provider
fi

# Deepak
# Edit the [ml2_type_vxlan] section.
iniset_sudo $conf ml2_type_vxlan vni_ranges 1:1000

# Edit the [securitygroup] section.
iniset_sudo $conf securitygroup enable_ipset true

# Deepak
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the Open vSwitch agent
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Configuring Open vSwitch agent."
conf=/etc/neutron/plugins/ml2/openvswitch_agent.ini

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Create the provider bridge in OVS
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#Suhail tempory change to varify functionality before ODL configuration.
sudo ovs-vsctl add-br $EXT_BRIDGE_NAME_1
sudo ovs-vsctl add-port $EXT_BRIDGE_NAME_1 $PROVIDER_INTERFACE_1

if [ $EXT_NW_MULTIPLE = "true" ]; then
# Suhail
  sudo ovs-vsctl add-br $EXT_BRIDGE_NAME_2
  sudo ovs-vsctl add-port $EXT_BRIDGE_NAME_2 $PROVIDER_INTERFACE_2

  sudo ovs-vsctl add-br $EXT_BRIDGE_NAME_ODL
  sudo ovs-vsctl add-port $EXT_BRIDGE_NAME_ODL $PROVIDER_ODL_INTERFACE
fi

# Deepak
# Edit the [ovs] section.
echo "EXT_BRIDGE_NAME_1=$EXT_BRIDGE_NAME_1"
echo "EXT_BRIDGE_NAME_2=$EXT_BRIDGE_NAME_2"
echo "EXT_BRIDGE_NAME_ODL=$EXT_BRIDGE_NAME_ODL"

if [ $EXT_NW_MULTIPLE = "true" ]; then
  EXT_BRIDGE_MAPPING="provider:$EXT_BRIDGE_NAME_1,provider1:$EXT_BRIDGE_NAME_2,provider_odl:$EXT_BRIDGE_NAME_ODL"
  iniset_sudo $conf ovs bridge_mappings $EXT_BRIDGE_MAPPING
else
  iniset_sudo $conf ovs bridge_mappings provider:$EXT_BRIDGE_NAME_1
fi

OVERLAY_INTERFACE_IP_ADDRESS=$(get_node_ip_in_network "$(hostname)" "overlay")
#OVERLAY_INTERFACE_IP_ADDRESS=$(echo "$NET_IF_3" |awk '{print $2}')
iniset_sudo $conf ovs local_ip $OVERLAY_INTERFACE_IP_ADDRESS

# Deepak
# Edit the [agent] section.
iniset_sudo $conf agent tunnel_types vxlan
iniset_sudo $conf agent l2_population true

# Edit the [securitygroup] section.
iniset_sudo $conf securitygroup enable_security_group true
# Deepak
iniset_sudo $conf securitygroup firewall_driver iptables_hybrid
#iniset_sudo $conf securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the layer-3 agent
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Configuring the layer-3 agent."
conf=/etc/neutron/l3_agent.ini
# Deepak
iniset_sudo $conf DEFAULT interface_driver openvswitch

# The external_network_bridge option intentionally lacks a value to enable
# multiple external networks on a single agent.
iniset_sudo $conf DEFAULT external_network_bridge ""

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the DHCP agent
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Configuring the DHCP agent."
conf=/etc/neutron/dhcp_agent.ini
# Deepak
iniset_sudo $conf DEFAULT interface_driver openvswitch
iniset_sudo $conf DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
iniset_sudo $conf DEFAULT enable_isolated_metadata true
# Deepak
iniset_sudo $conf DEFAULT force_metadata true

# Not in install-guide:
iniset_sudo $conf DEFAULT dnsmasq_config_file /etc/neutron/dnsmasq-neutron.conf

cat << DNSMASQ | sudo tee /etc/neutron/dnsmasq-neutron.conf
# Override --no-hosts dnsmasq option supplied by neutron
addn-hosts=/etc/hosts

# Log dnsmasq queries to syslog
log-queries

# Verbose logging for DHCP
log-dhcp
DNSMASQ
