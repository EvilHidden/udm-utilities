#!/bin/sh

## configuration variables:
VLAN=5
IPV4_IP="10.0.5.3"
IPV4_GW="10.0.5.1/24"

# if you want IPv6 support, generate a ULA, select an IP for nextdns and an
# appropriate gateway address on the same /64 network. Make sure that the
# 20-dns.conflist is updated appropriately. It will need the IP and GW added
# along with a ::/0 route. Also make sure that additional --dns options are
# passed to podman with your nextdns IPv6 DNS IPs when deploying the nextdns
# container for the first time.
IPV6_IP=""
IPV6_GW=""

# set this to the interface(s) on which you want DNS TCP/UDP port 53 traffic
# re-routed through nextdns. separate interfaces with spaces.
#e.g. "br0" or "br0 br1"
FORCED_INTFC=""

# uncomment after after the container has been deployed
#PODMAN_START=1

## nextdns network configuration and startup:

mkdir -p /opt/cni
ln -s /mnt/data/podman/cni/ /opt/cni/bin
ln -s /mnt/data/podman/cni/20-dns.conflist /etc/cni/net.d/20-dns.conflist

# set VLAN bridge promiscuous
ip link set br${VLAN} promisc on

# create macvlan bridge and add IPv4 IP
ip link add br${VLAN}.mac link br${VLAN} type macvlan mode bridge
ip addr add ${IPV4_GW} dev br${VLAN}.mac noprefixroute

# (optional) add IPv6 IP to VLAN bridge macvlan bridge
if [ -n "${IPV6_GW}" ]; then
  ip -6 addr add ${IPV6_GW} dev br${VLAN}
  ip -6 addr add ${IPV6_GW} dev br${VLAN}.mac noprefixroute
fi

# set macvlan bridge promiscuous and bring it up
ip link set br${VLAN}.mac promisc on
ip link set br${VLAN}.mac up

# add IPv4 route to nextdns
ip route add ${IPV4_IP}/32 dev br${VLAN}.mac

# (optional) add IPv6 route to nextdns
if [ -n "${IPV6_IP}" ]; then
  ip -6 route add ${IPV6_IP}/128 dev br${VLAN}.mac
fi

# Start the container
if [ "${PODMAN_START}" == "1" ]; then
  podman start nextdns
fi

# (optional) IPv4 force DNS (TCP/UDP 53) through nextdns
for intfc in ${FORCED_INTFC}; do
  for proto in udp tcp; do
    prerouting_rule="PREROUTING -i ${intfc} -p ${proto} ! -s ${IPV4_IP} ! -d ${IPV4_IP} --dport 53 -j DNAT --to ${IPV4_IP}"
    iptables -t nat -C ${prerouting_rule} || iptables -t nat -A ${prerouting_rule}

    postrouting_rule="POSTROUTING -o ${intfc} -d ${IPV4_IP} -p ${proto} --dport 53 -j MASQUERADE"
    iptables -t nat -C ${postrouting_rule} || iptables -t nat -A ${postrouting_rule}

    # (optional) IPv6 force DNS (TCP/UDP 53) through nextdns
    if [ -n "${IPV6_IP}" ]; then
      prerouting_rule="PREROUTING -i ${intfc} -p ${proto} ! -s ${IPV6_IP} ! -d ${IPV6_IP} --dport 53 -j DNAT --to ${IPV6_IP}"
      ip6tables -t nat -C ${prerouting_rule} || ip6tables -t nat -A ${prerouting_rule}

      postrouting_rule="POSTROUTING -o ${intfc} -d ${IPV6_IP} -p ${proto} --dport 53 -j MASQUERADE"
      ip6tables -t nat -C ${postrouting_rule} || ip6tables -t nat -A ${postrouting_rule}
    fi
  done
done
