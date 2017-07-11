#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR"||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

# Deepak
source "$CONFIG_DIR/config.controller"

exec_logfile

indicate_current_auto

# Wait for keystone to come up
wait_for_keystone

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Clean instances, subnets, ports, routers, networks
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# ASSUMPTION: As it is a fresh installation therefore there are no context 
# (network, subnets, routers, public-IPs allocated yet.


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Remove neutron-plugin-openvswitch-agent, cleanup logs, conf.db etc and restart
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sudo service neutron-server stop

sudo apt-get -y purge neutron-openvswitch-agent
sudo service openvswitch-switch stop
sudo rm -rf /var/log/openvswitch/*
sudo rm -rf /etc/openvswitch/conf.db
sudo service openvswitch-switch start

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#  Connecting Open vSwitch with OpenDaylight
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
OVS_ID=`sudo ovs-vsctl show | head -n1 | awk '{print $1}'`
OVERLAY_INTERFACE_IP_ADDRESS=$(get_node_ip_in_network "$(hostname)" "overlay")

sudo ovs-vsctl set Open_vSwitch $OVS_ID other_config={'local_ip'='$OVERLAY_INTERFACE_IP_ADDRESS'}
sudo ovs-vsctl set-manager tcp:$OPENDAYLIGHT_MANAGEMENT_IP:6640

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Create the provider bridge in OVS
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sudo ovs-vsctl add-br $EXT_BRIDGE_NAME
sudo ovs-vsctl add-port $EXT_BRIDGE_NAME $PROVIDER_INTERFACE

echo "Sourcing the admin credentials."
source "$CONFIG_DIR/admin-openstackrc.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the Modular Layer 2 (ML2) plug-in
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
echo "Configuring ml2_conf.ini."
conf=/etc/neutron/plugins/ml2/ml2_conf.ini

# Configure [ml2] section.
iniset_sudo $conf ml2 mechanism_drivers opendaylight

# Configure [ml2_odl] section.
iniset_sudo $conf ml2_odl username admin
iniset_sudo $conf ml2_odl password admin
iniset_sudo $conf ml2_odl url http://$OPENDAYLIGHT_MANAGEMENT_IP:8080/controller/nb/v2/neutron

# Configure [ovs] section.
iniset_sudo $conf ovs bridge_mappings provider:$EXT_BRIDGE_NAME
iniset_sudo $conf ovs local_ip "$OVERLAY_INTERFACE_IP_ADDRESS"

# Configure [agent] section.
iniset_sudo $conf agent tunnel_types vxlan

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the neutron.conf
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#echo "Configuring the neutron.conf."
#conf=/etc/neutron/plugins/neutron.conf
#iniset_sudo $conf DEFAULT service_plugins odl-router

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the layer-3 agent
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#echo "Configuring the layer-3 agent."
#conf=/etc/neutron/l3_agent.ini
# iniset_sudo $conf DEFAULT interface_driver openvswitch
# The external_network_bridge option intentionally lacks a value to enable
# multiple external networks on a single agent.
# iniset_sudo $conf DEFAULT external_network_bridge "$EXT_BRIDGE_NAME"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the DHCP agent
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
echo "Configuring the DHCP agent."
conf=/etc/neutron/dhcp_agent.ini

# Configure [DEFAULT] section.
#iniset_sudo $conf DEFAULT interface_driver openvswitch
#iniset_sudo $conf DEFAULT force_metadata true

# Configure [ovs] section.
iniset_sudo $conf ovs ovsdb_interface vsctl

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configuring the Neutron database
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

reset_database neutron "$NEUTRON_DB_USER" "$NEUTRON_DBPASS"

echo "Populating the database."
sudo neutron-db-manage \
    --config-file /etc/neutron/neutron.conf \
    --config-file /etc/neutron/plugins/ml2/ml2_conf.ini \
    upgrade head

echo "Restarting nova services."
sudo service nova-api restart

echo "Restarting neutron-server."
sudo service neutron-server restart

echo "Restarting neutron-dhcp-agent."
sudo service neutron-dhcp-agent restart

echo "Restarting neutron-metadata-agent."
sudo service neutron-metadata-agent restart

if type neutron-l3-agent; then
    # Installed only for networking option 2 of the install-guide.
    echo "Restarting neutron-l3-agent."
    sudo service neutron-l3-agent restart
fi

echo "Restarting openvswitch-switch."
sudo service openvswitch-switch restart

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install and configure networking-odl - done later as part of Compute setup
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#sudo apt-get install -y python-pip git
#networking_odl_repo_path="/etc"
#
#echo "Cloning networking_odl repository."
#cd "$networking_odl_repo_path"
#sudo git clone https://github.com/openstack/networking-odl -b stable/newton
#
#echo "Installing tacker."
#cd "networking-odl"
#sudo python setup.py install
