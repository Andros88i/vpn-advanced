#!/data/data/com.termux/files/usr/bin/bash

# ============================================
# DNS MANAGER - Control avanzado de DNS
# ============================================

CONFIG_DIR="$HOME/vpn-advanced"
LOG_FILE="$CONFIG_DIR/logs/dns.log"
DNS_SERVERS=(
    "9.9.9.9"           # Quad9 - Seguridad
    "149.112.112.112"   # Quad9 - Alternativo
    "1.1.1.1"           # Cloudflare - Rápido
    "1.0.0.1"           # Cloudflare - Secundario
    "8.8.8.8"           # Google - Compatibilidad
    "8.8.4.4"           # Google - Secundario
    "94.140.14.14"      # AdGuard - Bloqueo anuncios
    "94.140.15.15"      # AdGuard - Secundario
)
CURRENT_DNS=""

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_dns() {
    echo -e "${BLUE}[DNS][$(date '+%H:%M:%S')]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

block_all_dns() {
    log_dns "Bloqueando todo el tráfico DNS excepto servidores permitidos..."
    
    # Flush reglas DNS
    iptables -F DNS_OUTPUT 2>/dev/null
    iptables -X DNS_OUTPUT 2>/dev/null
    iptables -N DNS_OUTPUT
    
    # Redirigir OUTPUT a cadena DNS
    iptables -A OUTPUT -p tcp --dport 53 -j DNS_OUTPUT
    iptables -A OUTPUT -p udp --dport 53 -j DNS_OUTPUT
    
    # Permitir solo DNS especificados
    for server in "${DNS_SERVERS[@]}"; do
        iptables -A DNS_OUTPUT -d $server -j ACCEPT
        log_dns "Permitido DNS: $server"
    done
    
    # Bloquear el resto
    iptables -A DNS_OUTPUT -j DROP
    
    # Bloquear DNS sobre HTTPS/TLS (puertos comunes)
    iptables -A OUTPUT -p tcp --dport 853 -j DROP  # DNS sobre TLS
    iptables -A OUTPUT -p tcp --dport 443 -m string --string "application/dns-message" --algo bm -j DROP
    
    log_dns "Bloqueo DNS activado"
}

set_custom_dns() {
    local primary=$1
    local secondary=$2
    
    log_dns "Configurando DNS: $primary, $secondary"
    
    # Configurar resolv.conf
    echo "nameserver $primary" > $PREFIX/etc/resolv.conf
    echo "nameserver $secondary" >> $PREFIX/etc/resolv.conf
    
    # Configurar mediante propiedades
    setprop net.dns1 $primary
    setprop net.dns2 $secondary
    
    CURRENT_DNS="$primary|$secondary"
    
    # Configurar iptables para estos DNS
    iptables -F DNS_OUTPUT 2>/dev/null
    iptables -A DNS_OUTPUT -d $primary -j ACCEPT
    iptables -A DNS_OUTPUT -d $secondary -j ACCEPT
    iptables -A DNS_OUTPUT -j DROP
    
    log_dns "DNS configurado exitosamente"
}

enable_dns_over_tls() {
    log_dns "Habilitando DNS sobre TLS..."
    
    # Configurar stubby (si está instalado)
    if command -v stubby >/dev/null; then
        cat > $PREFIX/etc/stubby/stubby.yml << EOF
resolution_type: GETDNS_RESOLUTION_STUB
dns_transport_list:
  - GETDNS_TRANSPORT_TLS
tls_authentication: GETDNS_AUTHENTICATION_REQUIRED
tls_query_padding_blocksize: 128
edns_client_subnet_private : 1
round_robin_upstreams: 1
idle_timeout: 10000
listen_addresses:
  - 127.0.0.1@8053
upstream_recursive_servers:
  - address_data: 9.9.9.9
    tls_auth_name: "dns.quad9.net"
  - address_data: 1.1.1.1
    tls_auth_name: "cloudflare-dns.com"
EOF
        stubby -g &
        set_custom_dns "127.0.0.1" "8053"
    else
        log_dns "Stubby no instalado. Instala con: pkg install stubby"
    fi
}

flush_dns_cache() {
    log_dns "Limpiando cache DNS..."
    
    # Métodos para limpiar cache
    ndc resolver flushdefaultif
    ndc resolver clearnetdns
    
    # Limpiar cache de aplicaciones
    killall -HUP dnsmasq 2>/dev/null
    killall -HUP systemd-resolved 2>/dev/null
    
    # Limpiar cache del sistema
    ip route flush cache
    
    log_dns "Cache DNS limpiado"
}

test_dns() {
    local server=$1
    log_dns "Probando DNS: $server"
    
    # Test básico
    if nslookup google.com $server >/dev/null 2>&1; then
        echo -e "${GREEN}✓ DNS $server funciona${NC}"
        return 0
    else
        echo -e "${RED}✗ DNS $server falló${NC}"
        return 1
    fi
}

find_fastest_dns() {
    log_dns "Buscando DNS más rápido..."
    
    local fastest=""
    local fastest_time=9999
    
    for server in "${DNS_SERVERS[@]}"; do
        local start_time=$(date +%s%N)
        
        if nslookup google.com $server >/dev/null 2>&1; then
            local end_time=$(date +%s%N)
            local duration=$((($end_time - $start_time)/1000000))
            
            echo "  $server: $duration ms"
            
            if [ $duration -lt $fastest_time ]; then
                fastest_time=$duration
                fastest=$server
            fi
        fi
    done
    
    if [ -n "$fastest" ]; then
        echo -e "${GREEN}DNS más rápido: $fastest (${fastest_time}ms)${NC}"
        set_custom_dns "$fastest" "1.1.1.1"
    else
        log_dns "No se encontró DNS funcional"
    fi
}

monitor_dns_leaks() {
    log_dns "Iniciando monitor de fugas DNS..."
    
    while true; do
        local current_resolver=$(getprop net.dns1)
        local expected_resolver=$(echo $CURRENT_DNS | cut -d'|' -f1)
        
        if [ "$current_resolver" != "$expected_resolver" ]; then
            log_dns "${RED}FUGA DETECTADA! Resolver: $current_resolver${NC}"
            block_all_dns
            set_custom_dns "${DNS_SERVERS[0]}" "${DNS_SERVERS[1]}"
        fi
        
        # Verificar consultas DNS no autorizadas
        local rogue_dns=$(iptables -L DNS_OUTPUT -n -v | grep DROP | awk '{print $2}')
        if [ "$rogue_dns" -gt 0 ]; then
            log_dns "Bloqueadas $rogue_dns consultas DNS no autorizadas"
        fi
        
        sleep 30
    done
}

show_menu() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        GESTOR DNS AVANZADO           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo "1) Configurar Quad9 (9.9.9.9)"
    echo "2) Configurar Cloudflare (1.1.1.1)"
    echo "3) Configurar Google (8.8.8.8)"
    echo "4) Usar DNS sobre TLS"
    echo "5) Buscar DNS más rápido"
    echo "6) Bloquear todo DNS excepto permitidos"
    echo "7) Limpiar cache DNS"
    echo "8) Probar todos los DNS"
    echo "9) Monitorear fugas DNS"
    echo "0) Salir"
    echo ""
    echo -e "DNS actual: ${YELLOW}$CURRENT_DNS${NC}"
    echo ""
    
    read -p "Selecciona: " choice
    
    case $choice in
        1) set_custom_dns "9.9.9.9" "149.112.112.112" ;;
        2) set_custom_dns "1.1.1.1" "1.0.0.1" ;;
        3) set_custom_dns "8.8.8.8" "8.8.4.4" ;;
        4) enable_dns_over_tls ;;
        5) find_fastest_dns ;;
        6) block_all_dns ;;
        7) flush_dns_cache ;;
        8) 
            for server in "${DNS_SERVERS[@]}"; do
                test_dns $server
            done
            ;;
        9) monitor_dns_leaks & ;;
        0) exit 0 ;;
        *) echo "Opción inválida" ;;
    esac
    
    read -p "Enter para continuar..."
    show_menu
}

# Inicializar
mkdir -p $CONFIG_DIR/logs
touch $LOG_FILE

if [ "$1" = "auto" ]; then
    set_custom_dns "9.9.9.9" "1.1.1.1"
    block_all_dns
    monitor_dns_leaks &
else
    show_menu
fi
