#!/bin/bash

clear
mkdir -p ~/.cloudshell && touch ~/.cloudshell/no-apt-get-warning # Для Google Cloud Shell, но лучше там не выполнять
echo "Установка зависимостей..."
apt update -y && apt install sudo -y # Для Aeza Terminator, там sudo не установлен по умолчанию
# Для GitHub Codespaces
out="$(sudo apt-get update -y --fix-missing 2>&1)" || {
  echo "$out" | grep -qiE "dl\.yarnpkg\.com|NO_PUBKEY 62D54FD4003F6525|is not signed" || { echo "$out"; exit 1; }
  echo "[WARN] Yarn repo ломает apt update — удаляю yarn.list и повторяю..."
  sudo rm -f /etc/apt/sources.list.d/yarn.list
}
sudo apt-get update -y --fix-missing && sudo apt-get install wireguard-tools jq wget qrencode -y --fix-missing # Update второй раз, если sudo установлен и обязателен (в строке выше не сработал)

priv="${1:-$(wg genkey | tr -d '\n')}"
pub="${2:-$(printf "%s" "${priv}" | wg pubkey | tr -d '\n')}"
api="https://api.cloudflareclient.com/v0i1909051800"
ins() { curl -s -H 'User-Agent: okhttp/3.12.1' -H 'Content-Type: application/json' -X "$1" "${api}/$2" "${@:3}"; }
sec() { ins "$1" "$2" -H "Authorization: Bearer $3" "${@:4}"; }
response=$(ins POST "reg" -d "{\"install_id\":\"\",\"tos\":\"$(date -u +%FT%TZ)\",\"key\":\"${pub}\",\"fcm_token\":\"\",\"type\":\"ios\",\"locale\":\"en_US\"}")

clear
id=$(echo "$response" | jq -r '.result.id')
token=$(echo "$response" | jq -r '.result.token')
# Если Cloudflare вернул ошибку
if [ "$id" = "null" ] || [ -z "$id" ] || [ "$token" = "null" ] || [ -z "$token" ]; then
  echo "[ERROR] Registration failed:"
  echo "$response" | jq .
  exit 1
fi
response=$(sec PATCH "reg/${id}" "$token" -d '{"warp_enabled":true}')
peer_pub=$(echo "$response" | jq -r '.result.config.peers[0].public_key')
#peer_endpoint=$(echo "$response" | jq -r '.result.config.peers[0].endpoint.host')
client_ipv4=$(echo "$response" | jq -r '.result.config.interface.addresses.v4')
client_ipv6=$(echo "$response" | jq -r '.result.config.interface.addresses.v6')


conf=$(cat <<-EOM
[Interface]
PrivateKey = ${priv}
Address = ${client_ipv4}, ${client_ipv6}
DNS = 1.1.1.1, 2606:4700:4700::1111, 1.0.0.1, 2606:4700:4700::1001
MTU = 1280

[Peer]
PublicKey = ${peer_pub}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 162.159.192.1:500

[Obfuscation]
Type = amnezia
JunkPacketCount = 120
JunkPacketMinSize = 23
JunkPacketMaxSize = 911
InitPacketJunkSize = 1
ResponsePacketJunkSize = 2
InitPacketMagicHeader = 1
ResponsePacketMagicHeader = 2
UnderloadPacketMagicHeader = 3
TransportPacketMagicHeader = 4
EOM
)

AWG_JSON=$(jq -n \
    --arg pr "$priv" \
    --arg v4 "$client_ipv4" \
    --arg v6 "$client_ipv6" \
    --arg pp "$peer_pub" \
    --arg cf "$conf" \
    '{
        allowed_ips: ["0.0.0.0/0", "::/0"],
        client_ip: ($v4 + ", " + $v6),
        client_priv_key: $pr,
        config: ($cf | gsub("\n"; "\r\n")),
        hostName: "162.159.192.1",
        mtu: 1280,
        port: 500,
        server_pub_key: $pp,
        obfuscation: {
            type: "amnezia",
            junkPacketCount: 120,
            junkPacketMinSize: 23,
            junkPacketMaxSize: 911,
            initPacketJunkSize: 1,
            responsePacketJunkSize: 2,
            initPacketMagicHeader: 1,
            responsePacketMagicHeader: 2,
            underloadPacketMagicHeader: 3,
            transportPacketMagicHeader: 4
        }
    }')

AMNEZIA_JSON=$(jq -n \
    --arg last "$AWG_JSON" \
    --arg name "Cloudflare WARP" \
    '{
        containers: [
            {
                container: "amnezia-awg",
                awg: {
                    isThirdPartyConfig: true,
                    last_config: $last,
                    port: "500",
                    transport_proto: "udp"
                }
            }
        ],
        defaultContainer: "amnezia-awg",
        description: $name,
        hostName: "162.159.192.1"
    }')

VPN_KEY="vpn://$(echo -n "$AMNEZIA_JSON" | base64 -w 0)"

[ -t 1 ] && echo "########## СТРОКА ДЛЯ AMNEZIAVPN ##########"
echo "$VPN_KEY"
[ -t 1 ] && echo "########### КОНЕЦ СТРОКИ ДЛЯ AMNEZIAVPN ###########"

echo -e "\n\n\n"
[ -t 1 ] && echo "########## НАЧАЛО КОНФИГА ##########"
echo "${conf}"
[ -t 1 ] && echo "########### КОНЕЦ КОНФИГА ###########"

echo -e "\n"
conf_base64=$(echo -n "${conf}" | base64 -w 0)
echo "Скачать конфиг файлом: https://immalware.vercel.app/download?filename=WARP.conf&content=${conf_base64}"
echo "Импортируйте конфиг в приложение AmneziaVPN! Приложение AmneziaWG не поддерживает этот формат!"
echo -e "\n"
echo "Что-то не получилось? Есть вопросы? Пишите в чат: https://t.me/immalware_chat"
