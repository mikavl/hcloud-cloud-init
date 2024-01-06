#!/bin/bash
#
# cloud-init script to configure a VM with a static private IP address.
# Copy-paste into user data.
set -e
set -o noglob
set -u

# Purge some packages we won't need. Omit qemu-guest-agent if you want to be
# able to reset the root password.
DEBIAN_FRONTEND=noninteractive apt-get purge --assume-yes --autoremove \
  hc-utils \
  qemu-guest-agent \
  resolvconf

# Get the first ethernet interface
interface="$(ip link show |
  grep --extended-regexp '^[0-9]+:\s+en' |
  head --lines 1 |
  tr --delete ':' |
  awk '{print $2}')"

# Then get its IPv4 address
address="$(ip -4 address show dev "$interface" |
  grep --extended-regexp '^\s+inet\s+' |
  awk '{print $2}' |
  cut --delimiter '/' --fields 1)"

# Gateway is the first address in the network. This assumes that the network
# address of the subnet ends in 0.
gateway="${address%.*}.1"

# Nameserver is assumed to be the first usable address in the network. Change
# this if it's not.
nameserver="${address%.*}.2"

# Kill DHCP client processes started by hc-utils and flush the addresses
ps -e |
  grep --extended-regexp '\s+dhclient$' |
  awk '{print $1}' |
  xargs kill

ip address flush dev "$interface"

# Configure the network interface
cat << EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto $interface
iface $interface inet static
  address $address/32
  gateway $gateway
  pointopoint $gateway
EOF

# I guess it's obvious what this does
echo "nameserver $nameserver" > /etc/resolv.conf

# Good to go!
ifup "$interface"
