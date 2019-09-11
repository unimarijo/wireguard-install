#!/bin/bash

function isRoot {
    if [ "$EUID" -ne 0 ]; then
        echo "Sorry, you need to run this script as root."
        exit 1
    fi
}

function checkOS {
    if [[ -e /etc/debian_version ]]; then
        # shellcheck disable=SC1091
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
}

function detectVirtualization {
    if [ "$(systemd-detect-virt)" == "openvz" ]; then
        echo "OpenVZ virtualization is not supported."
        exit 1
    elif [ "$(systemd-detect-virt)" == "lxc" ]; then
        echo "LXC is not supported (yet)."
        echo "WireGuard can technically run in an LXC container,"
        echo "but the kernel module has to be installed on the host,"
        echo "the container has to be run with some specific parameters"
        echo "and only the tools need to be installed in the container."
        exit 1
    fi
}

function compatibilityCheck {
    isRoot
    checkOS
    detectVirtualization
}

function installation {
    clear
    echo "Welcome to the WireGuard Installer!"
    echo "Source code is available at GitHub: https://github.com/angristan/wireguard-install."
    echo ""

    echo "I need to ask you a few questions before starting the setup."
    echo "You can leave the default options and just press enter if you are OK with them."

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
            read -rp "Please choose the right option [1-2]: " -e -i 1 IP_CHOICE
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
        read -rp "Please choose the right option [1-2]: " -e -i 1 PUB_NIC_CHOICE
    done
    case $PUB_NIC_CHOICE in
        1) ;;
        2)
            read -rp "Public interface: " -e -i "${SERVER_PUB_NIC}" SERVER_PUB_NIC
        ;;
    esac

    SERVER_WG_NIC="wg0"
    echo ""
    echo "How do you want to name the WireGuard interface?"
    echo "   1) Default: ${SERVER_WG_NIC}"
    echo "   2) Custom"
    until [[ "$WG_NIC_CHOICE" =~ ^[1-2]$ ]]; do
        read -rp "Please choose the right option [1-2]: " -e -i 1 WG_NIC_CHOICE
    done
    case $WG_NIC_CHOICE in
        1) ;;
        2)
            read -rp "WireGuard interface name: " -e -i ${SERVER_WG_NIC} SERVER_WG_NIC
        ;;
    esac

    SERVER_WG_IPV4="10.38.72.1"
    echo ""
    echo "What private IPv4 address for WireGuard server do you want to use?"
    echo "   1) Default: ${SERVER_WG_IPV4}"
    echo "   2) Custom"
    until [[ "$SERVER_WG_IPV4_CHOICE" =~ ^[1-2]$ ]]; do
        read -rp "Please choose the right option [1-2]: " -e -i 1 SERVER_WG_IPV4_CHOICE
    done
    case $SERVER_WG_IPV4_CHOICE in
        1) ;;
        2)
            read -rp "WireGuard server private IPv4 address: " -e -i ${SERVER_WG_IPV4} SERVER_WG_IPV4
        ;;
    esac

    SERVER_WG_IPV6="fd18:56:42::1"
    echo ""
    echo "What private IPv6 address for WireGuard server do you want to use?"
    echo "   1) Default: ${SERVER_WG_IPV6}"
    echo "   2) Custom"
    until [[ "$SERVER_WG_IPV6_CHOICE" =~ ^[1-2]$ ]]; do
        read -rp "Please choose the right option [1-2]: " -e -i 1 SERVER_WG_IPV6_CHOICE
    done
    case $SERVER_WG_IPV6_CHOICE in
        1) ;;
        2)
            read -rp "WireGuard server private IPv6 address: " -e -i ${SERVER_WG_IPV6} SERVER_WG_IPV6
        ;;
    esac

    SERVER_PORT=51820
    echo ""
    echo "What port do you want WireGuard to listen to?"
    echo "   1) Default: ${SERVER_PORT}"
    echo "   2) Custom"
    until [[ "$PORT_CHOICE" =~ ^[1-2]$ ]]; do
        read -rp "Please choose the right option [1-2]: " -e -i 1 PORT_CHOICE
    done
    case $PORT_CHOICE in
        1) ;;
        2)
            until [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] && [ "$SERVER_PORT" -ge 1 ] && [ "$SERVER_PORT" -le 65535 ]; do
                read -rp "WireGuard port [1-65535]: " -e -i ${SERVER_PORT} SERVER_PORT
            done
        ;;
    esac

    # Check if selected public IP is IPv6 or not
    if [[ ${SERVER_PUB_IP} =~ .*:.* ]]; then
        ENDPOINT="[$SERVER_PUB_IP]:$SERVER_PORT"
    else
        ENDPOINT="$SERVER_PUB_IP:$SERVER_PORT"
    fi

    # Install WireGuard tools and module
    if [[ "$OS" = "ubuntu" ]]; then
        add-apt-repository -y ppa:wireguard/wireguard
        apt-get update
        apt-get install "linux-headers-$(uname -r)"
        apt-get install -y wireguard iptables
    elif [[ "$OS" = "debian" ]]; then
        echo "deb http://deb.debian.org/debian/ unstable main" > /etc/apt/sources.list.d/unstable.list
        printf 'Package: *\nPin: release a=unstable\nPin-Priority: 90\n' > /etc/apt/preferences.d/limit-unstable
        apt-get update -y
        apt-get install "linux-headers-$(uname -r)"
        apt-get install -y wireguard iptables
    elif [[ "$OS" = "fedora" ]]; then
        dnf copr enable jdoss/wireguard
        dnf install -y wireguard-dkms wireguard-tools iptables
    elif [[ "$OS" = "centos" ]]; then
        curl -Lo /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-7/jdoss-wireguard-epel-7.repo
        yum install -y epel-release
        yum install -y wireguard-dkms wireguard-tools iptables
    elif [[ "$OS" = "arch" ]]; then
        pacman -S linux-headers
        pacman --noconfirm -S wireguard-tools wireguard-arch iptables
    fi

    # Make sure the directory exists (this does not seem the be the case on fedora)
    mkdir /etc/wireguard > /dev/null 2>&1

    # Generate key pair for the server
    SERVER_PRIV_KEY=$(wg genkey)
    SERVER_PUB_KEY=$(echo "$SERVER_PRIV_KEY" | wg pubkey)

    # Add server interface
    printf "# Server data: {\"PUBLIC_KEY\": \"$SERVER_PUB_KEY\", \"ENDPOINT\": \"$ENDPOINT\"}\n\n[Interface]
Address = $SERVER_WG_IPV4/24, $SERVER_WG_IPV6/64
ListenPort = $SERVER_PORT
PrivateKey = $SERVER_PRIV_KEY
PostUp = iptables -A FORWARD -i $SERVER_WG_NIC -j ACCEPT; iptables -t nat -A POSTROUTING -o $SERVER_PUB_NIC -j MASQUERADE; ip6tables -A FORWARD -i $SERVER_WG_NIC -j ACCEPT; ip6tables -t nat -A POSTROUTING -o $SERVER_PUB_NIC -j MASQUERADE
PostDown = iptables -D FORWARD -i $SERVER_WG_NIC -j ACCEPT; iptables -t nat -D POSTROUTING -o $SERVER_PUB_NIC -j MASQUERADE; ip6tables -D FORWARD -i $SERVER_WG_NIC -j ACCEPT; ip6tables -t nat -D POSTROUTING -o $SERVER_PUB_NIC -j MASQUERADE" > "/etc/wireguard/$SERVER_WG_NIC.conf"

    # Prompt user to add a client
    addClient

    chmod 600 -R /etc/wireguard/

    # Enable routing on the server
    echo "net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1" > /etc/sysctl.d/wg.conf

    sysctl --system

    systemctl start "wg-quick@$SERVER_WG_NIC"
    systemctl enable "wg-quick@$SERVER_WG_NIC"
}

function uninstallation {
    read -rp "Do you really want to uninstall WireGuard? [y/n]: " -e UNINSTALLATION_CHOICE
    if [[ "${UNINSTALLATION_CHOICE}" = "y" ]]; then
        if [[ "$OS" = "ubuntu" ]]; then
            add-apt-repository --remove -y ppa:wireguard/wireguard
            apt-get autoremove --purge -y wireguard
            apt-get update
        elif [[ "$OS" = "debian" ]]; then
            echo "There is no uninstallation for Debian yet."
        elif [[ "$OS" = "fedora" ]]; then
            echo "There is no uninstallation for Fedora yet."
        elif [[ "$OS" = "centos" ]]; then
            echo "There is no uninstallation for centOS yet."
        elif [[ "$OS" = "arch" ]]; then
            pacman --noconfirm -R wireguard-tools
        fi

        # Cleanup
        rm -Rf /etc/wireguard/
        rm -Rf /etc/sysctl.d/wg.conf
        find "$HOME" -maxdepth 2 -name "*-wg.conf" -delete
        find /root/ -maxdepth 2 -name "*-wg.conf" -delete

        sysctl --system
        systemctl daemon-reload

        echo ""
        echo "WireGuard has been uninstalled."
    else
        echo "WireGuard uninstallation has been canceled."
    fi
}

function addClient {
    CLIENT_SERVER_WG_NIC="wg0"
    echo ""
    echo "To what WireGuard interface do you want to add a new client?"
    echo "   1) Default: ${CLIENT_SERVER_WG_NIC}"
    echo "   2) Custom"
    until [[ "$CLIENT_WG_NIC_CHOICE" =~ ^[1-2]$ ]]; do
        read -rp "Please choose the right option [1-2]: " -e -i 1 CLIENT_WG_NIC_CHOICE
    done
    case $CLIENT_WG_NIC_CHOICE in
        1) ;;
        2)
            read -rp "WireGuard interface name: " -e -i ${CLIENT_SERVER_WG_NIC} CLIENT_SERVER_WG_NIC
        ;;
    esac

    CLIENT_NAME="client-$(python3 -c 'import secrets; print(secrets.token_hex(4))')"
    echo ""
    echo "How do you want to name a new client?"
    echo "   1) Default: ${CLIENT_NAME}"
    echo "   2) Custom"
    until [[ "$CLIENT_NAME_CHOICE" =~ ^[1-2]$ ]]; do
        read -rp "Please choose the right option [1-2]: " -e -i 1 CLIENT_NAME_CHOICE
    done
    case $CLIENT_NAME_CHOICE in
        1) ;;
        2)
            read -rp "A new client's name: " -e -i "${CLIENT_NAME}" CLIENT_NAME
        ;;
    esac

    echo ""
    echo "Do you want to use symmetric key mode?"
    echo "   1) Default: yes"
    echo "   2) No"
    until [[ "$WG_USE_SYMMETRIC_CHOICE" =~ ^[1-2]$ ]]; do
        read -rp "Please choose the right option [1-2]: " -e -i 1 WG_USE_SYMMETRIC_CHOICE
    done
    case $WG_USE_SYMMETRIC_CHOICE in
        1) SERVER_WG_SYMMETRIC_KEY="Yes";;
        2) SERVER_WG_SYMMETRIC_KEY="No";;
    esac

    CLIENT_WG_IPV4="10.38.72.2"
    echo ""
    echo "What private IPv4 address do you want to use for a new client?"
    echo "   1) Default: ${CLIENT_WG_IPV4}"
    echo "   2) Custom"
    until [[ "$CLIENT_WG_IPV4_CHOICE" =~ ^[1-2]$ ]]; do
        read -rp "Please choose the right option [1-2]: " -e -i 1 CLIENT_WG_IPV4_CHOICE
    done
    case $CLIENT_WG_IPV4_CHOICE in
        1) ;;
        2)
            read -rp "WireGuard client private IPv4 address: " -e -i ${CLIENT_WG_IPV4} CLIENT_WG_IPV4
        ;;
    esac

    CLIENT_WG_IPV6="fd18:56:42::2"
    echo ""
    echo "What private IPv6 address for WireGuard client do you want to use?"
    echo "   1) Default: ${CLIENT_WG_IPV6}"
    echo "   2) Custom"
    until [[ "$CLIENT_WG_IPV6_CHOICE" =~ ^[1-2]$ ]]; do
        read -rp "Please choose the right option [1-2]: " -e -i 1 CLIENT_WG_IPV6_CHOICE
    done
    case $CLIENT_WG_IPV6_CHOICE in
        1) ;;
        2)
            read -rp "WireGuard client private IPv6 address: " -e -i ${CLIENT_WG_IPV6} CLIENT_WG_IPV6
        ;;
    esac

    echo ""
    echo "What DNS resolvers do you want to use for a new client?"
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
    echo "   11) Custom"
    until [[ "$DNS_CHOICE" =~ ^[0-9]+$ ]] && [ "$DNS_CHOICE" -ge 1 ] && [ "$DNS_CHOICE" -le 11 ]; do
        read -rp "Please choose the right option [1-11]: " -e -i 2 DNS_CHOICE
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
        11) # Custom
            read -rp "Primary DNS server: " -e -i "1.1.1.1" CLIENT_DNS_1
            read -rp "Secondary DNS server: " -e -i "1.0.0.1" CLIENT_DNS_2
        ;;
    esac

    SERVER_PUB_KEY=$(python3 -c "import json; SERVER_DATA = json.loads(open('/etc/wireguard/wg0.conf').readlines()[0]. \
    strip('# Server data: ').rstrip('\n')); print(SERVER_DATA['PUBLIC_KEY'])")
    ENDPOINT=$(python3 -c "import json; SERVER_DATA = json.loads(open('/etc/wireguard/wg0.conf').readlines()[0]. \
    strip('# Server data: ').rstrip('\n')); print(SERVER_DATA['ENDPOINT'])")

    # Generate key pair for a new client
    CLIENT_PRIV_KEY=$(wg genkey)
    CLIENT_PUB_KEY=$(echo "$CLIENT_PRIV_KEY" | wg pubkey)

    # Add the client as a peer to the server
    printf "\n\n# Client's name: $CLIENT_NAME\n[Peer]
PublicKey = $CLIENT_PUB_KEY
AllowedIPs = $CLIENT_WG_IPV4/32, $CLIENT_WG_IPV6/128" >> "/etc/wireguard/$CLIENT_SERVER_WG_NIC.conf"

    # Create client file with interface
    printf "[Interface]
PrivateKey = $CLIENT_PRIV_KEY
Address = $CLIENT_WG_IPV4/24, $CLIENT_WG_IPV6/64
DNS = $CLIENT_DNS_1, $CLIENT_DNS_2" > "$HOME/$CLIENT_NAME-wg.conf"

    # Add the server as a peer to the client
    printf "\n\n[Peer]
PublicKey = $SERVER_PUB_KEY
Endpoint = $ENDPOINT
AllowedIPs = 0.0.0.0/0, ::/0" >> "$HOME/$CLIENT_NAME-wg.conf"

    if [ "$SERVER_WG_SYMMETRIC_KEY" == "Yes" ]; then
        SERVER_WG_SYMMETRIC_KEY=$(wg genpsk)
        printf "\nPresharedKey = $SERVER_WG_SYMMETRIC_KEY" >> "/etc/wireguard/$CLIENT_SERVER_WG_NIC.conf"
        printf "\nPresharedKey = $SERVER_WG_SYMMETRIC_KEY" >> "$HOME/$CLIENT_NAME-wg.conf"
    fi
}

function manageInstallation {
    clear
    echo "Welcome to the WireGuard Installer!"
    echo "Source code is available at GitHub: https://github.com/angristan/wireguard-install."
    echo ""
    echo "It looks like WireGuard is already installed."
    echo "What do you want to do?"
    echo "   1) Add a new user"
    echo "   2) Remove existing user"
    echo "   3) Uninstall WireGuard"
    echo "   4) Reinstall WireGuard"
    echo "   5) Exit"
    until [[ "$MENU_OPTION_CHOICE" =~ ^[1-5]$ ]]; do
        read -rp "Please choose the right option [1-5]: " MENU_OPTION_CHOICE
    done

    case $MENU_OPTION_CHOICE in
        1)
            addClient
        ;;
        2)
            removeClient
        ;;
        3)
            uninstallation
        ;;
        4)
            uninstallation
            installation
        ;;
        5)
            exit 0
        ;;
    esac
}

# Check if system is comptatible with this script
compatibilityCheck
if ! [ -x "$(command -v wg)" ]; then
    installation
else
    manageInstallation
fi
