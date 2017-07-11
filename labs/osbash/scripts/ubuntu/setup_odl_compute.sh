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
# Stop neutron-server service on controller
node_ssh controller "sudo service neutron-server stop"

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

echo "Sourcing the admin credentials."
source "$CONFIG_DIR/admin-openstackrc.sh"

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
iniset_sudo $conf ml2 mechanism_drivers opendaylight
iniset_sudo $conf ml2 extension_drivers port_security

# Edit the [ml2_type_flat] section.
iniset_sudo $conf ml2_type_flat flat_networks provider

# Deepak
# Edit the [ml2_type_vxlan] section.
iniset_sudo $conf ml2_type_vxlan vni_ranges 1:1000

# Edit the [securitygroup] section.
iniset_sudo $conf securitygroup enable_ipset true

# Configure [ml2_odl] section.
iniset_sudo $conf ml2_odl username admin
iniset_sudo $conf ml2_odl password admin
iniset_sudo $conf ml2_odl url http://$OPENDAYLIGHT_MANAGEMENT_IP:8080/controller/nb/v2/neutron

# Configure [ovs] section.
iniset_sudo $conf ovs local_ip "$OVERLAY_INTERFACE_IP_ADDRESS"

# Configure [agent] section.
iniset_sudo $conf agent tunnel_types vxlan

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Reset the Neutron database on CONTROLLER
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

node_ssh controller "export TOP_DIR=\$PWD; \
source \"\$TOP_DIR/config/paths\"; \
source \"\$CONFIG_DIR/credentials\"; \
source \"\$LIB_DIR/functions.guest.sh\"; reset_database neutron \"\$NEUTRON_DB_USER\" \"\$NEUTRON_DBPASS\"; \
sudo neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head; "

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Restarting the services on CONTROLLER
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Restarting nova services, neutron-server, neutron-dhcp-agent, neutron-metadata-agent, neutron-l3-agent, openvswitch-switch on CONTROLLER."
node_ssh controller "sudo service nova-api restart; sudo service neutron-server restart; sudo service neutron-dhcp-agent restart; sudo service neutron-metadata-agent restart; \
if type neutron-l3-agent; then
    sudo service neutron-l3-agent restart
fi; sudo service openvswitch-switch restart"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Restarting the services on COMPUTE
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
echo "Restarting openvswitch-switch."
sudo service openvswitch-switch restart

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install and configure networking-odl on CONTROLLER
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
echo "Installing and configuring networking-odl on CONTROLLER."
node_ssh controller "sudo apt-get install -y python-pip git; \
networking_odl_repo_path=\"/etc\"; \
cd \"\$networking_odl_repo_path\"; \
sudo git clone https://github.com/openstack/networking-odl \-b stable/newton; \
cd \"networking-odl\"; sudo python setup.py install"
