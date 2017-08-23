#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR"||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"
source "$CONFIG_DIR/openstack"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Set up OpenStack Networking (neutron) for compute node.
# http://docs.openstack.org/ocata/install-guide-ubuntu/neutron-compute-install.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure Compute to use Networking
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

neutron_admin_user=neutron

echo "Configuring Compute to use Networking."
conf=/etc/nova/nova.conf
iniset_sudo $conf neutron url http://controller:9696
iniset_sudo $conf neutron auth_url http://controller:35357
iniset_sudo $conf neutron auth_type password
iniset_sudo $conf neutron project_domain_name default
iniset_sudo $conf neutron user_domain_name default
iniset_sudo $conf neutron region_name "$REGION"
iniset_sudo $conf neutron project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf neutron username "$neutron_admin_user"
iniset_sudo $conf neutron password "$NEUTRON_PASS"

# Deepak
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure networking_sfc
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
echo "Populating the database."
node_ssh controller "export TOP_DIR=\$PWD; \
source \"\$TOP_DIR/config/paths\"; \
source \"\$CONFIG_DIR/credentials\"; \
source \"\$LIB_DIR/functions.guest.sh\"; \
sudo neutron-db-manage --subproject networking-sfc --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head; "

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Finalize installation
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Restarting the Compute service."
sudo service nova-compute restart

# Deepak
echo "Restarting neutron-openvswitch-agent."
sudo service neutron-openvswitch-agent restart

#------------------------------------------------------------------------------
# Networking Option 2: Self-service networks
# http://docs.openstack.org/ocata/install-guide-ubuntu/neutron-verify-option2.html
#------------------------------------------------------------------------------

echo "Sourcing the admin credentials."
source "$CONFIG_DIR/admin-openstackrc.sh"

echo "Listing agents to verify successful launch of the neutron agents."

echo "neutron agent-list"
neutron agent-list
