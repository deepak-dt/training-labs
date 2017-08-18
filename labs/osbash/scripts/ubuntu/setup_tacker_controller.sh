#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR"||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto

# Wait for keystone to come up
wait_for_keystone

#------------------------------------------------------------------------------
# Install the tacker Service
# https://docs.openstack.org/tacker/latest/install/manual_installation.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#echo "Modifying heat’s policy.json file under /etc/heat/policy.json file to allow users in non-admin projects with ‘admin’ roles to create flavors."
#"resource_types:OS::Nova::Flavor": "role:admin"

echo "Setting up database for tacker."
setup_database tacker "$TACKER_DB_USER" "$TACKER_DBPASS"

echo "Sourcing the admin credentials."
source "$CONFIG_DIR/admin-openstackrc.sh"

tacker_admin_user=tacker

# Wait for keystone to come up
wait_for_keystone

echo "Creating tacker user and giving it admin role under service tenant."
openstack user create \
    --domain default \
    --password "$TACKER_PASS" \
    "$tacker_admin_user"

openstack role add \
    --project "$SERVICE_PROJECT_NAME" \
    --user "$tacker_admin_user" \
    "$ADMIN_ROLE_NAME"

echo "Creating the tacker service entity."
openstack service create \
    --name tacker \
    --description "Tacker Project" \
    nfv-orchestration

echo "Creating tacker endpoints."
openstack endpoint create \
    --region "$REGION" \
    nfv-orchestration public http://controller:9890/

openstack endpoint create \
    --region "$REGION" \
    nfv-orchestration internal http://controller:9890/

openstack endpoint create \
    --region "$REGION" \
    nfv-orchestration admin http://controller:9890/

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install and configure components
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sudo apt-get install -y python-pip git
tacker_repo_path="/etc"

echo "Cloning tacker repository."
cd "$tacker_repo_path"
sudo git clone https://github.com/openstack/tacker -b stable/newton
#sudo git clone https://github.com/openstack/tacker

echo " Installing all requirements."
cd "tacker"
sudo pip install -r requirements.txt
sudo pip install tosca-parser

echo "Installing tacker."
sudo python setup.py install

echo "Creating ‘tacker’ directory in ‘/var/log’."
sudo mkdir /var/log/tacker

function get_database_url {
    local db_user=$TACKER_DB_USER
    local database_host=controller

    echo "mysql://$db_user:$TACKER_DBPASS@$database_host:3306/tacker?charset=utf8"
}

database_url=$(get_database_url)
echo "Database connection: $database_url."

echo "Generating the tacker.conf.sample using tools/generate_config_file_sample.sh"
sudo ./tools/generate_config_file_sample.sh

echo "Configuring tacker.conf."
sudo mv etc/tacker/tacker.conf.sample etc/tacker/tacker.conf
sudo cp etc/tacker/tacker.conf /usr/local/etc/tacker/tacker.conf

conf=/usr/local/etc/tacker/tacker.conf
# Configure [DEFAULT] section.
iniset_sudo $conf DEFAULT auth_strategy keystone
iniset_sudo $conf DEFAULT policy_file /usr/local/etc/tacker/policy.json
iniset_sudo $conf DEFAULT debug true
iniset_sudo $conf DEFAULT use_syslog false
iniset_sudo $conf DEFAULT bind_host controller
iniset_sudo $conf DEFAULT bind_port 9890
iniset_sudo $conf DEFAULT service_plugins nfvo,vnfm
iniset_sudo $conf DEFAULT state_path /var/lib/tacker

# Configure [nfvo] section.
iniset_sudo $conf nfvo vim_drivers openstack

# Configure [keystone_authtoken] section.
iniset_sudo $conf keystone_authtoken region_name RegionOne
iniset_sudo $conf keystone_authtoken auth_uri http://controller:5000
iniset_sudo $conf keystone_authtoken auth_url http://controller:35357
iniset_sudo $conf keystone_authtoken memcached_servers controller:11211
iniset_sudo $conf keystone_authtoken auth_type password
iniset_sudo $conf keystone_authtoken project_domain_name default
iniset_sudo $conf keystone_authtoken user_domain_name default
iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf keystone_authtoken username "$tacker_admin_user"
iniset_sudo $conf keystone_authtoken password "$TACKER_PASS"

# Configure [agent] section.
root_helper_string="sudo /usr/local/bin/tacker-rootwrap\ /usr/local/etc/tacker/rootwrap.conf"
iniset_sudo $conf agent root_helper "$root_helper_string"

# Configure [database] section.
iniset_sudo $conf database connection "$database_url"

# Configure [tacker] section.
iniset_sudo $conf tacker monitor_driver ping,http_ping

sudo cp /usr/local/etc/tacker/tacker.conf etc/tacker/tacker.conf

echo "Populating Tacker database."
/usr/local/bin/tacker-db-manage --config-file /usr/local/etc/tacker/tacker.conf upgrade head

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install Tacker client
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Cloning tacker-client repository."
cd "$tacker_repo_path"
sudo git clone https://github.com/openstack/python-tackerclient -b stable/newton
#sudo git clone https://github.com/openstack/python-tackerclient

echo "Installing tacker-client."
cd python-tackerclient
sudo python setup.py install

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install Tacker horizon
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Cloning tacker-horizon repository."
cd "$tacker_repo_path"

sudo git clone https://github.com/openstack/tacker-horizon -b stable/newton
################################################################
# Remove first line, i.e. 'tacker_horizon' from _80_nfv.py file
################################################################
line_to_rep_orig="'tacker_horizon',"
line_to_rep_new=""

sed -n "1h;2,\$H;\${g;s/$line_to_rep_orig/$line_to_rep_new/;p}" tacker-horizon/openstack_dashboard_extensions/_80_nfv.py > tacker-horizon/openstack_dashboard_extensions/_80_nfv_new.py
mv tacker-horizon/openstack_dashboard_extensions/_80_nfv_new.py tacker-horizon/openstack_dashboard_extensions/_80_nfv.py
################################################################

#sudo git clone https://github.com/openstack/tacker-horizon

echo "Installing tacker-horizon."
cd tacker-horizon

sudo python setup.py install

echo "Enabling tacker horizon in dashboard."
sudo cp openstack_dashboard_extensions/* \
    /usr/share/openstack-dashboard/openstack_dashboard/enabled/
#sudo cp tacker_horizon/enabled/* \
#    /usr/share/openstack-dashboard/openstack_dashboard/enabled/

echo " Restarting Apache server."
sudo service apache2 restart

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prepare config.yaml file - to be used when registering default VIM
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
echo "Prepare config.yaml file."
conf=$tacker_repo_path/tacker/config.yaml

sudo -- sh -c "echo 'auth_url: http://controller:5000/v3/
username: $tacker_admin_user
password: $TACKER_PASS
project_name: $SERVICE_PROJECT_NAME
project_domain_name: default
user_domain_name: default
' > $conf"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Starting Tacker server - for reference only
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#sudo python /usr/local/bin/tacker-server \
#    --config-file /usr/local/etc/tacker/tacker.conf \
#    --log-file /var/log/tacker/tacker.log &

#source admin-openrc.sh
#tacker vim-register --is-default --config-file /etc/tacker/config.yaml --description Aricent_Gurugram_network VIM.Aricent.Gurugram

#1).Open a new console and launch tacker-server. A separate terminal is required because the console will be locked by a running process.

#sudo python /usr/local/bin/tacker-server \
#    --config-file /usr/local/etc/tacker/tacker.conf \
#    --log-file /var/log/tacker/tacker.log

#------------------------------------------------------------------------------
# Registering default VIM - for reference only
#------------------------------------------------------------------------------

#1.) Register the VIM that will be used as a default VIM for VNF deployments. This will be required when the optional argument –vim-id is not provided by the user during vnf-create.
#
# source admin-openrc.sh
#
#tacker vim-register --is-default --config-file config.yaml \
#       --description <Default VIM description> <Default VIM Name>
#2.) The config.yaml will contain VIM specific parameters as below:
#
#auth_url: http://<keystone_public_endpoint_url>:5000 [http://controller:5000/v3/]
#username: <Tacker service username> [tacker]
#password: <Tacker service password> [tacker_user_secret]
#project_name: <project_name> [service]
#Add following parameters to config.yaml if VIM is using keystone v3:
#
#project_domain_name: <domain_name> [default]
#user_domain_name: <domain_name> [default]

#-Note: 
#Here username must point to the user having ‘admin’ and ‘advsvc’ role on the project that will be used for deploying VNFs.
