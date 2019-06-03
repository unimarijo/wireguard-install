#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Sorry, you need to run this script as root."
    exit 1
fi

if [ "$(systemd-detect-virt)" == "openvz" ]; then
    echo "OpenVZ virtualization is not supported."
    exit
fi

if [ "$(systemd-detect-virt)" == "lxc" ]; then
    echo "LXC is not supported (yet)."
    echo "WireGuard can technically run in an LXC container,"
    echo "but the kernel module has to be installed on the host,"
    echo "the container has to be run with some specific parameters"
    echo "and only the tools need to be installed in the container."
    exit
fi

# Check OS version
if [[ -e /etc/debian_version ]]; then
    source /etc/os-release
    OS=$ID # debian or ubuntu
elif [[ -e /etc/fedora-release ]]; then
    OS=fedora
elif [[ -e /etc/centos-release ]]; then
    OS=centos
elif [[ -e /etc/arch-release ]]; then
    OS=arch
else
    echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS or Arch Linux system."
    exit 1
fi

clear
echo "Welcome to the WireGuard installer!"
echo "The git repository is available at: https://github.com/angristan/wireguard-install"
echo ""

echo "I need to ask you a few questions before starting the setup."
echo "You can leave the default options and just press enter if you are ok with them."
echo ""
echo "I need to know the IPv4 address of the network interface you want WireGuard listening to."
echo "Unless your server is behind NAT, it should be your public IPv4 address."

# Check if server has the IPv6 address
if [[ $(curl -s https://api6.ipify.org) =~ .*:.* ]]; then
    SERVER_PUB_IPV4=$(curl -s https://api.ipify.org)
    SERVER_PUB_IPV6=$(curl -s https://api6.ipify.org)
    echo ""
    echo "Which public IP do you want to use for WireGuard?"
    echo "   1) IPv4: ${SERVER_PUB_IPV4}"
    echo "   2) IPv6: ${SERVER_PUB_IPV6}"
    until [[ "$IP_CHOICE" =~ ^[1-2]$ ]]; do
        read -rp "Public IP choice [1-2]: " -e -i 1 IP_CHOICE
    done
    case $IP_CHOICE in
        1) SERVER_PUB_IP=${SERVER_PUB_IPV4};;
        2) SERVER_PUB_IP=${SERVER_PUB_IPV6};;
    esac
else
    SERVER_PUB_IP=$(curl -s https://api.ipify.org)
fi

# Detect public interface and pre-fill for the user
SERVER_PUB_NIC="$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)"
echo ""
echo "What public interface do you want to use for WireGuard?"
echo "   1) Default: ${SERVER_PUB_NIC}"
echo "   2) Custom"
until [[ "$PUB_NIC_CHOICE" =~ ^[1-2]$ ]]; do
    read -rp "Public interface [1-2]: " -e -i 1 PUB_NIC_CHOICE
done
case $PUB_NIC_CHOICE in
    1) ;;
    2)
        read -rp "Custom public interface: " -e -i ${SERVER_PUB_NIC} SERVER_PUB_NIC
    ;;
esac

SERVER_WG_NIC="wg0"
echo ""
echo "How do you want to name the WireGuard interface?"
echo "   1) Default: ${SERVER_WG_NIC}"
echo "   2) Custom"
until [[ "$WG_NIC_CHOICE" =~ ^[1-2]$ ]]; do
    read -rp "WireGuard interface name choice [1-2]: " -e -i 1 WG_NIC_CHOICE
done
case $WG_NIC_CHOICE in
    1) ;;
    2)
        read -rp "Custom WireGuard interface name: " -e -i ${SERVER_WG_NIC} SERVER_WG_NIC
    ;;
esac

SERVER_WG_IPV4="10.66.66.1"
echo ""
echo "What private IPv4 address for WireGuard server do you want to use?"
echo "   1) Default: ${SERVER_WG_IPV4}"
echo "   2) Custom"
until [[ "$WG_IPV4_CHOICE" =~ ^[1-2]$ ]]; do
    read -rp "Server's WireGuard private IPv4 address [1-2]: " -e -i 1 WG_IPV4_CHOICE
done
case $WG_IPV4_CHOICE in
    1) ;;
    2)
        read -rp "Custom server's WireGuard private IPv4 address: " -e -i ${SERVER_WG_IPV4} SERVER_WG_IPV4
    ;;
esac

SERVER_WG_IPV6="fd42:42:42::1"
echo ""
echo "What private IPv6 address for WireGuard server do you want to use?"
echo "   1) Default: ${SERVER_WG_IPV6}"
echo "   2) Custom"
until [[ "$WG_IPV6_CHOICE" =~ ^[1-2]$ ]]; do
    read -rp "Server's WireGuard private IPv6 address [1-2]: " -e -i 1 WG_IPV6_CHOICE
done
case $WG_IPV6_CHOICE in
    1) ;;
    2)
        read -rp "Custom server's WireGuard private IPv6 address: " -e -i ${SERVER_WG_IPV6} SERVER_WG_IPV6
    ;;
esac

SERVER_PORT=51820
echo ""
echo "What port do you want WireGuard to listen to?"
echo "   1) Default: ${SERVER_PORT}"
echo "   2) Custom"
echo "   3) Random [49152-65535]"
until [[ "$PORT_CHOICE" =~ ^[1-3]$ ]]; do
    read -rp "Port choice [1-3]: " -e -i 1 PORT_CHOICE
done
case $PORT_CHOICE in
    1) ;;
    2)
        until [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] && [ "$SERVER_PORT" -ge 1 ] && [ "$SERVER_PORT" -le 65535 ]; do
            read -rp "Custom WireGuard port [1-65535]: " -e -i ${SERVER_PORT} SERVER_PORT
        done
    ;;
    3)
        # Generate random number within private ports range
        SERVER_PORT=$(shuf -i49152-65535 -n1)
        echo "Random Port: $SERVER_PORT"
    ;;
esac

echo ""
echo "What DNS resolvers do you want to use with the VPN?"
echo "   1) Current system resolvers (from /etc/resolv.conf)"
echo "   2) Cloudflare (Anycast: worldwide)"
echo "   3) Quad9 (Anycast: worldwide)"
echo "   4) Quad9 uncensored (Anycast: worldwide)"
echo "   5) FDN (France)"
echo "   6) DNS.WATCH (Germany)"
echo "   7) OpenDNS (Anycast: worldwide)"
echo "   8) Google (Anycast: worldwide)"
echo "   9) Yandex Basic (Russia)"
echo "   10) AdGuard DNS (Russia)"
until [[ "$DNS_CHOICE" =~ ^[0-9]+$ ]] && [ "$DNS_CHOICE" -ge 1 ] && [ "$DNS_CHOICE" -le 11 ]; do
    read -rp "DNS [1-10]: " -e -i 2 DNS_CHOICE
done
case $DNS_CHOICE in
    1)
        # Locate the proper resolv.conf
        # Needed for systems running systemd-resolved
        if grep -q "127.0.0.53" "/etc/resolv.conf"; then
            RESOLVCONF='/run/systemd/resolve/resolv.conf'
        else
            RESOLVCONF='/etc/resolv.conf'
        fi
        # Obtain the resolvers from resolv.conf and use them for OpenVPN
        grep -v '#' $RESOLVCONF | grep 'nameserver' | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | while read -r line; do
            CLIENT_DNS_1=${line}
            CLIENT_DNS_2=${line}
        done
    ;;
    2) # Cloudflare
        CLIENT_DNS_1="1.1.1.1"
        CLIENT_DNS_2="1.0.0.1"
    ;;
    3) # Quad9
        CLIENT_DNS_1="9.9.9.9"
        CLIENT_DNS_2="149.112.112.112"
    ;;
    4) # Quad9 uncensored
        CLIENT_DNS_1="9.9.9.10"
        CLIENT_DNS_2="149.112.112.10"
    ;;
    5) # FDN
        CLIENT_DNS_1="80.67.169.40"
        CLIENT_DNS_2="80.67.169.12"
    ;;
    6) # DNS.WATCH
        CLIENT_DNS_1="84.200.69.80"
        CLIENT_DNS_2="84.200.70.40"
    ;;
    7) # OpenDNS
        CLIENT_DNS_1="208.67.222.222"
        CLIENT_DNS_2="208.67.220.220"
    ;;
    8) # Google
        CLIENT_DNS_1="8.8.8.8"
        CLIENT_DNS_2="8.8.4.4"
    ;;
    9) # Yandex Basic
        CLIENT_DNS_1="77.88.8.8"
        CLIENT_DNS_2="77.88.8.1"
    ;;
    10) # AdGuard DNS
        CLIENT_DNS_1="176.103.130.130"
        CLIENT_DNS_2="176.103.130.131"
    ;;
esac

# Check if selected public IP is IPv6 or not
if [[ ${SERVER_PUB_IP} =~ .*:.* ]]; then
    ENDPOINT="[$SERVER_PUB_IP]:$SERVER_PORT"
else
    ENDPOINT="$SERVER_PUB_IP:$SERVER_PORT"
fi

# Install WireGuard tools and module
if [[ "$OS" = 'ubuntu' ]]; then
    add-apt-repository ppa:wireguard/wireguard
    apt-get update
    apt-get install wireguard
elif [[ "$OS" = 'debian' ]]; then
    echo "deb http://deb.debian.org/debian/ unstable main" > /etc/apt/sources.list.d/unstable.list
    printf 'Package: *\nPin: release a=unstable\nPin-Priority: 90\n' > /etc/apt/preferences.d/limit-unstable
    apt update
    apt install wireguard
elif [[ "$OS" = 'fedora' ]]; then
    dnf copr enable jdoss/wireguard
    dnf install wireguard-dkms wireguard-tools
elif [[ "$OS" = 'centos' ]]; then
    curl -Lo /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-7/jdoss-wireguard-epel-7.repo
    yum install epel-release
    yum install wireguard-dkms wireguard-tools
elif [[ "$OS" = 'arch' ]]; then
    pacman -S wireguard-tools
fi

# Make sure the directory exists (this does not seem the be the case on fedora)
mkdir /etc/wireguard > /dev/null 2>&1

# Generate key pair for the server
SERVER_PRIV_KEY=$(wg genkey)
SERVER_PUB_KEY=$(echo "$SERVER_PRIV_KEY" | wg pubkey)

# Generate key pair for the server
CLIENT_PRIV_KEY=$(wg genkey)
CLIENT_PUB_KEY=$(echo "$CLIENT_PRIV_KEY" | wg pubkey)

# Add server interface
echo "[Interface]
Address = $SERVER_WG_IPV4/24, $SERVER_WG_IPV6/64
ListenPort = $SERVER_PORT
PrivateKey = $SERVER_PRIV_KEY
PostUp = iptables -t nat -A POSTROUTING -o $SERVER_PUB_NIC -j MASQUERADE; ip6tables -t nat -A POSTROUTING -o $SERVER_PUB_NIC -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o $SERVER_PUB_NIC -j MASQUERADE; ip6tables -t nat -D POSTROUTING -o $SERVER_PUB_NIC -j MASQUERADE" > "/etc/wireguard/$SERVER_WG_NIC.conf"

# Add the client as a peer to the server
echo "[Peer]
PublicKey = $CLIENT_PUB_KEY
AllowedIPs = $CLIENT_WG_IPV4/32, $CLIENT_WG_IPV6/128" >> "/etc/wireguard/$SERVER_WG_NIC.conf"

# Create client file with interface
echo "[Interface]
PrivateKey = $CLIENT_PRIV_KEY
Address = $CLIENT_WG_IPV4/24, $CLIENT_WG_IPV6/64
DNS = $CLIENT_DNS_1,$CLIENT_DNS_2" > "$HOME/$SERVER_WG_NIC-client.conf"

# Add the server as a peer to the client
echo "[Peer]
PublicKey = $SERVER_PUB_KEY
Endpoint = $ENDPOINT
AllowedIPs = 0.0.0.0/0, ::/0" >> "$HOME/$SERVER_WG_NIC-client.conf"

chmod 600 -R /etc/wireguard/

# Enable routing on the server
echo "net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1" > /etc/sysctl.d/wg.conf

sysctl --system

systemctl start "wg-quick@$SERVER_WG_NIC"
systemctl enable "wg-quick@$SERVER_WG_NIC"
