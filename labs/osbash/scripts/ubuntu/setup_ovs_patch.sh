#!/usr/bin/env bash
TOP_DIR=$(cd $(cat "../TOP_DIR"||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

# Deepak
source "$CONFIG_DIR/config.controller"

sudo ovs-vsctl -- add-port $EXT_BRIDGE_NAME_1 patchPortEx1 -- set interface patchPortEx1 type=patch options:peer=patchPortInt1 -- add-port br-int patchPortInt1 -- set interface patchPortInt1 type=patch  options:peer=patchPortEx1

sudo ovs-vsctl -- add-port $EXT_BRIDGE_NAME_2 patchPortEx2 -- set interface patchPortEx2 type=patch options:peer=patchPortInt2 -- add-port br-int patchPortInt2 -- set interface patchPortInt2 type=patch  options:peer=patchPortEx2

# Now add patch port in EXT_BRIDGE_NAME_1 and connect it to br-int
#sudo ovs-vsctl add-port $EXT_BRIDGE_NAME_1 patchPortEx1
#sudo ovs-vsctl set interface patchPortEx1 type=patch
#sudo ovs-vsctl add-port br-int patchPortInt1
#sudo ovs-vsctl set interface patchPortInt1 type=patch
#sudo ovs-vsctl set interface patchPortEx1 options:peer=patchPortInt1
#sudo ovs-vsctl set interface patchPortInt1 options:peer=patchPortEx1
# Now add patch port in EXT_BRIDGE_NAME_2 and connect it to br-int
#sudo ovs-vsctl add-port $EXT_BRIDGE_NAME_2 patchPortEx2
#sudo ovs-vsctl set interface patchPortEx2 type=patch
#sudo ovs-vsctl add-port br-int patchPortInt2
#sudo ovs-vsctl set interface patchPortInt2 type=patch
#sudo ovs-vsctl set interface patchPortEx2 options:peer=patchPortInt2
#sudo ovs-vsctl set interface patchPortInt2 options:peer=patchPortEx2

#Add flows on EXT_BRIDGE_NAME_1:
#sudo ovs-ofctl add-flow $EXT_BRIDGE_NAME_1 action=NORMAL
# From patch port(let’s say port num 1) to tunnel(let’s say port num 2)
#sudo ovs-ofctl -O Openflow13 add-flow br-int "dl_type=0x800, in_port=5, actions=output:1"
# From tunnel port(let’s say port num 2) to patch port(let’s say port num 1)
#sudo ovs-ofctl -O Openflow13 add-flow br-int "dl_type=0x800, in_port=1, actions=output:5"