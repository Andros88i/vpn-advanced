#!/data/data/com.termux/files/usr/bin/bash

# ============================================
# KILL SWITCH AVANZADO PARA TERMUX
# ============================================

CONFIG_DIR="$HOME/vpn-advanced"
LOG_FILE="$CONFIG_DIR/logs/killswitch.log"
WHITELIST="$CONFIG_DIR/lists/whitelist.txt"
VPN_INTERFACE="tun0"
WG_INTERFACE="wg0"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_ks() {
    echo -e "${PURPLE}[KILLSWITCH][$(date '+%H:%M:%S')]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}Este script necesita permisos root${NC}"
        echo "Ejecuta: sudo su"
        exit 1
    fi
}

get_vpn_status() {
    # Verificar si hay interfaz VPN activa
    if ip link show $VPN_INTERFACE >/dev/null 2>&1 || \
       ip link show $WG_INTERFACE >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

setup_advanced_killswitch() {
    log_ks "Configurando Kill Switch Avanzado..."
    
    # ========== LIMPIAR REGLAS EXISTENTES ==========
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    ip6tables -F
    ip6tables -X
    
    # ========== POLÍTICAS POR DEFECTO ==========
    iptables -P INPUT DROP
    iptables -P OUTPUT DROP
    iptables -P FORWARD DROP
    ip6tables -P INPUT DROP
    ip6tables -P OUTPUT DROP
    ip6tables -P FORWARD DROP
    
    # ========== REGLAS BÁSICAS ==========
    
    # Loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # Conexiones establecidas
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # ========== WHITELIST ==========
    if [ -f "$WHITELIST" ]; then
        log_ks "Aplicando whitelist..."
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            
            # Analizar tipo de regla
            if [[ "$line" == *":"* ]]; then
                # IP:Puerto
                local ip=$(echo $line | cut -d: -f1)
                local port=$(echo $line | cut -d: -f2)
                iptables -A OUTPUT -d $ip -p tcp --dport $port -j ACCEPT
                iptables -A OUTPUT -d $ip -p udp --dport $port -j ACCEPT
            elif [[ "$line" == "-PROTO:"* ]]; then
                # Protocolo específico
                local proto=$(echo $line | cut -d: -f2 | cut -d' ' -f1)
                local ip=$(echo $line | awk '{print $2}')
                iptables -A OUTPUT -p $proto -d $ip -j ACCEPT
            else
                # IP/CIDR normal
                iptables -A OUTPUT -d $line -j ACCEPT
            fi
        done < "$WHITELIST"
    fi
    
    # ========== DNS PERMITIDO ==========
    local dns_servers=("9.9.9.9" "149.112.112.112" "1.1.1.1" "1.0.0.1")
    for dns in "${dns_servers[@]}"; do
        iptables -A OUTPUT -d $dns -p udp --dport 53 -j ACCEPT
        iptables -A OUTPUT -d $dns -p tcp --dport 53 -j ACCEPT
        iptables -A OUTPUT -d $dns -p tcp --dport 853 -j ACCEPT  # DNS sobre TLS
    done
    
    # ========== VPN TRAFFIC ==========
    iptables -A OUTPUT -o $VPN_INTERFACE -j ACCEPT
    iptables -A OUTPUT -o $WG_INTERFACE -j ACCEPT
    iptables -A INPUT -i $VPN_INTERFACE -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -i $WG_INTERFACE -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # ========== BLOQUEO IPv6 COMPLETO ==========
    ip6tables -A INPUT -j DROP
    ip6tables -A OUTPUT -j DROP
    ip6tables -A FORWARD -j DROP
    
    # ========== BLOQUEOS ESPECÍFICOS ==========
    
    # Bloquear DNS no autorizado
    iptables -A OUTPUT -p udp --dport 53 -j DROP
    iptables -A OUTPUT -p tcp --dport 53 -j DROP
    
    # Bloquear WebRTC y fugas
    iptables -A OUTPUT -p udp --dport 3478:3497 -j DROP
    iptables -A OUTPUT -p udp --dport 5349 -j DROP
    
    # Bloquear multicast
    iptables -A OUTPUT -d 224.0.0.0/4 -j DROP
    iptables -A OUTPUT -d 255.255.255.255 -j DROP
    
    # ========== NAT PARA VPN ==========
    iptables -t nat -A POSTROUTING -o $VPN_INTERFACE -j MASQUERADE
    iptables -t nat -A POSTROUTING -o $WG_INTERFACE -j MASQUERADE
    
    # ========== LOGGING ==========
    iptables -A INPUT -j LOG --log-prefix "[KS-BLOCKED-IN] "
    iptables -A OUTPUT -j LOG --log-prefix "[KS-BLOCKED-OUT] "
    
    log_ks "${GREEN}Kill Switch Avanzado activado${NC}"
    show_status
}

disable_killswitch() {
    log_ks "Desactivando Kill Switch..."
    
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD ACCEPT
    ip6tables -P INPUT ACCEPT
    ip6tables -P OUTPUT ACCEPT
    ip6tables -P FORWARD ACCEPT
    
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    ip6tables -F
    ip6tables -X
    
    log_ks "Kill Switch desactivado"
}

emergency_lockdown() {
    log_ks "${RED}EMERGENCIA - BLOQUEO TOTAL${NC}"
    
    # Bloquear TODO inmediatamente
    iptables -F
    iptables -P INPUT DROP
    iptables -P OUTPUT DROP
    iptables -P FORWARD DROP
    
    # Solo permitir loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # Matar todas las conexiones de red
    pkill -9 ssh
    pkill -9 openvpn
    pkill -9 wg-quick
    
    log_ks "Sistema en bloqueo total"
}

monitor_vpn() {
    log_ks "Iniciando monitor VPN..."
    
    local failure_count=0
    local max_failures=3
    
    while true; do
        if ! get_vpn_status; then
            ((failure_count++))
            log_ks "${YELLOW}VPN caída - Intento $failure_count/$max_failures${NC}"
            
            if [ $failure_count -ge $max_failures ]; then
                log_ks "${RED}VPN perdida - Activando Kill Switch${NC}"
                emergency_lockdown
                break
            fi
        else
            failure_count=0
        fi
        
        sleep 5
    done
}

show_status() {
    echo -e "\n${BLUE}═════ ESTADO KILL SWITCH ═════${NC}"
    
    echo -e "\n${YELLOW}Reglas iptables OUTPUT:${NC}"
    iptables -L OUTPUT -n --line-numbers | tail -20
    
    echo -e "\n${YELLOW}Reglas iptables INPUT:${NC}"
    iptables -L INPUT -n --line-numbers | tail -20
    
    echo -e "\n${YELLOW}Interfaces de red:${NC}"
    ip link show | grep -E "(tun|wg|eth|wlan)"
    
    echo -e "\n${YELLOW}Estado VPN:${NC}"
    if get_vpn_status; then
        echo -e "${GREEN}✓ VPN activa${NC}"
    else
        echo -e "${RED}✗ VPN inactiva${NC}"
    fi
}

save_rules() {
    local backup_file="$CONFIG_DIR/backups/iptables_$(date +%Y%m%d_%H%M%S).rules"
    mkdir -p "$CONFIG_DIR/backups"
    iptables-save > "$backup_file"
    ip6tables-save > "${backup_file}.ip6"
    log_ks "Reglas guardadas en: $backup_file"
}

restore_rules() {
    local backup_file=$(ls -t "$CONFIG_DIR/backups/"*.rules 2>/dev/null | head -1)
    
    if [ -f "$backup_file" ]; then
        iptables-restore < "$backup_file"
        log_ks "Reglas restauradas desde: $backup_file"
    else
        log_ks "No hay backup disponible"
    fi
}

show_menu() {
    clear
    echo -e "${RED}╔══════════════════════════════════════╗${NC}"
    echo -e "${RED}║      KILL SWITCH AVANZADO            ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo "1) Activar Kill Switch Avanzado"
    echo "2) Desactivar Kill Switch"
    echo "3) Estado actual"
    echo "4) Monitorizar VPN (auto-activación)"
    echo "5) Bloqueo total de emergencia"
    echo "6) Guardar configuración actual"
    echo "7) Restaurar configuración"
    echo "8) Mostrar todas las reglas"
    echo "9) Probar fugas"
    echo "0) Salir"
    echo ""
    
    read -p "Selecciona: " choice
    
    case $choice in
        1) setup_advanced_killswitch ;;
        2) disable_killswitch ;;
        3) show_status ;;
        4) monitor_vpn & ;;
        5) emergency_lockdown ;;
        6) save_rules ;;
        7) restore_rules ;;
        8) 
            echo -e "\n${YELLOW}Todas las reglas iptables:${NC}"
            iptables -L -n -v
            ;;
        9)
            echo "Probando fugas..."
            curl -s https://ipleak.net/json/ || echo "Test fallado"
            ;;
        0) exit 0 ;;
        *) echo "Opción inválida" ;;
    esac
    
    read -p "Enter para continuar..."
    show_menu
}

# Inicializar
mkdir -p $CONFIG_DIR/{logs,backups}
touch $LOG_FILE

# Verificar root
check_root

if [ "$1" = "auto" ]; then
    setup_advanced_killswitch
    monitor_vpn &
else
    show_menu
fi
