#!/data/data/com.termux/files/usr/bin/bash

# ============================================
# VPN MANAGER - CONTROL DE APPS EXTERNAS
# ============================================

CONFIG_DIR="$HOME/vpn-advanced"
LOG_FILE="$CONFIG_DIR/logs/vpn.log"

# =========================================================
# CONFIGURACIÓN
# =========================================================
IMG="/data/data/com.termux/files/home/storage/pictures/Anonymus.png"

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'

log_message() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

# ============================================
# DETECCIÓN DE TUNNELBEAR MOD
# ============================================

detect_tunnelbear_mod() {
    echo "🔍 Buscando TunnelBear MOD..."
    
    # Buscar paquete por nombres comunes de mods
    local package_names=(
        "com.tunnelbear.android"
        "com.tunnelbear.mod"
        "tunnelbear.mod"
        "com.tunnelbear.premium"
    )
    
    for package in "${package_names[@]}"; do
        if pm list packages | grep -qi "$package"; then
            echo "✅ Encontrado: $package"
            TUNNELBEAR_PACKAGE=$(pm list packages | grep -i "$package" | head -1 | cut -d: -f2)
            return 0
        fi
    done
    
    # Buscar en directorio de APKs
    if ls ~/storage/downloads/*tunnelbear*apk 2>/dev/null; then
        echo "📦 APK encontrado en Downloads"
        return 0
    fi
    
    echo "❌ TunnelBear MOD no encontrado"
    return 1
}

# ============================================
# CONTROL DE LA APP INSTALADA
# ============================================

start_tunnelbear_app() {
    log_message "Iniciando TunnelBear MOD..."
    
    # Intentar diferentes activities
    local activities=(
        "com.tunnelbear.android.ui.SplashActivity"
        "com.tunnelbear.android.MainActivity"
        "com.tunnelbear.android.HomeActivity"
    )
    
    for activity in "${activities[@]}"; do
        if am start -n "$TUNNELBEAR_PACKAGE/$activity" 2>/dev/null; then
            log_message "✅ App iniciada: $activity"
            return 0
        fi
    done
    
    # Intentar abrir solo el paquete
    am start -n "$TUNNELBEAR_PACKAGE/.MainActivity" ||
    am start -a android.intent.action.MAIN -n "$TUNNELBEAR_PACKAGE/.LauncherActivity"
    
    log_message "⚠️  Abre TunnelBear MOD manualmente desde el menú de apps"
}

get_tunnelbear_status() {
    # Verificar si la app está en primer plano
    if dumpsys window windows | grep -q "$TUNNELBEAR_PACKAGE"; then
        echo "📱 TunnelBear está en primer plano"
        return 0
    fi
    
    # Verificar si está en segundo plano
    if dumpsys activity activities | grep -q "$TUNNELBEAR_PACKAGE"; then
        echo "🔄 TunnelBear está en segundo plano"
        return 0
    fi
    
    echo "❌ TunnelBear no está ejecutándose"
    return 1
}

# ============================================
# INSTALACIÓN ALTERNATIVA EN TERMUX
# ============================================

install_tunnelbear_in_termux() {
    echo "🛠️  Métodos para 'instalar' VPN en Termux sin root:"
    echo ""
    echo "1. SSH Tunnel (recomendado):"
    echo "   ssh -D 1080 -N usuario@servidor-ssh.com"
    echo ""
    echo "2. WireGuard (necesita kernel compatible):"
    echo "   pkg install wireguard-tools"
    echo "   wg-quick up tun0"
    echo ""
    echo "3. OpenVPN (puede funcionar sin root en algunos casos):"
    echo "   pkg install openvpn"
    echo "   openvpn --config config.ovpn"
    echo ""
    echo "4. Shadowsocks (sin root):"
    echo "   pip install shadowsocks"
    echo "   sslocal -s servidor.com -p 8388 -k password -m aes-256-cfb"
    
    read -p "¿Quieres configurar SSH Tunnel? (s/n): " choice
    if [[ "$choice" == "s" ]]; then
        setup_ssh_tunnel
    fi
}

setup_ssh_tunnel() {
    echo "🔧 Configurando SSH Tunnel..."
    
    read -p "Servidor SSH: " ssh_server
    read -p "Usuario: " ssh_user
    read -p "Puerto (22): " ssh_port
    ssh_port=${ssh_port:-22}
    
    # Crear script de conexión
    cat > ~/vpn-advanced/scripts/ssh_tunnel.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
# SSH Tunnel VPN

echo "🌐 Conectando a $ssh_server..."
ssh -D 1080 -f -C -q -N -o ServerAliveInterval=60 \\
    -o ServerAliveCountMax=3 \\
    -o ExitOnForwardFailure=yes \\
    -o ConnectTimeout=30 \\
    $ssh_user@$ssh_server -p $ssh_port

if [ \$? -eq 0 ]; then
    echo "✅ Tunnel SSH activado en socks5://127.0.0.1:1080"
    
    # Configurar proxy
    export http_proxy="socks5://127.0.0.1:1080"
    export https_proxy="socks5://127.0.0.1:1080"
    
    echo "🔧 Proxy configurado"
    echo "📊 Para verificar: curl --socks5 127.0.0.1:1080 ifconfig.me"
else
    echo "❌ Error al conectar"
fi
EOF
    
    chmod +x ~/vpn-advanced/scripts/ssh_tunnel.sh
    echo "✅ Script creado: ~/vpn-advanced/scripts/ssh_tunnel.sh"
}

# ============================================
# VPN SIN ROOT DENTRO DE TERMUX
# ============================================

start_vpn_in_termux() {
    echo "🔐 Opciones de VPN dentro de Termux (sin root):"
    echo ""
    echo "1. Proton VPN CLI (gratis, 3 países)"
    echo "2. Outline (desde contenedor Docker)"
    echo "3. Tor + Proxy"
    echo "4. HTTP/SOCKS5 Proxy"
    
    read -p "Elige opción: " vpn_choice
    
    case $vpn_choice in
        1)
            install_protonvpn_cli
            ;;
        2)
            install_outline
            ;;
        3)
            install_tor_proxy
            ;;
        4)
            setup_proxy_manual
            ;;
    esac
}

install_protonvpn_cli() {
    echo "📦 Instalando Proton VPN CLI..."
    
    # Instalar dependencias
    pkg install python-pip openvpn dialog -y
    pip install protonvpn-cli
    
    # Inicializar
    protonvpn init
    
    echo "✅ Proton VPN instalado"
    echo "🔌 Comandos:"
    echo "   protonvpn connect    # Conectar"
    echo "   protonvpn c -f       # Conexión más rápida"
    echo "   protonvpn disconnect # Desconectar"
}

install_tor_proxy() {
    echo "🧅 Configurando Tor Proxy..."
    
    pkg install tor torsocks -y
    
    # Configurar Tor
    echo "SOCKSPort 9050" > $PREFIX/etc/tor/torrc
    echo "Log notice file $PREFIX/var/log/tor/notices.log" >> $PREFIX/etc/tor/torrc
    
    # Iniciar Tor
    tor &
    
    echo "✅ Tor ejecutándose en socks5://127.0.0.1:9050"
    echo "🔧 Uso: torsocks curl ifconfig.me"
}

# ============================================
# MONITOREO Y AUTOMATIZACIÓN
# ============================================

monitor_vpn_status() {
    echo "📊 Monitoreando estado de VPN..."
    
    while true; do
        clear
        echo "=== MONITOR VPN ==="
        echo ""
        
        # Verificar conexión
        if ping -c 1 -W 2 9.9.9.9 >/dev/null 2>&1; then
            echo "🌐 Conexión: ✅"
        else
            echo "🌐 Conexión: ❌"
        fi
        
        # Verificar IP pública
        echo -n "🌍 IP pública: "
        curl -s --max-time 5 ifconfig.me || echo "No disponible"
        
        # Verificar DNS
        echo -n "🔍 DNS: "
        dig +short google.com | head -1 || echo "No disponible"
        
        # Verificar fugas WebRTC (simplificado)
        echo -n "🛡️  WebRTC: "
        if curl -s --max-time 5 https://ipleak.net/json/ | grep -q "ip_address"; then
            echo "⚠️  Verificar"
        else
            echo "✅"
        fi
        
        echo ""
        echo "⏳ Actualizando en 10 segundos (Ctrl+C para salir)..."
        sleep 10
    done
}

# =========================================================
# BANNER (IMAGEN REAL)
# =========================================================
clear

if command -v chafa >/dev/null 2>&1 && [ -f "$IMG" ]; then
    chafa --center=on --size=60x30 "$IMG"
else
    echo -e "${RED}[!] No se pudo cargar la imagen o chafa no está instalado${NC}"
fi

    echo
    echo -e "${LRED}      [+] CREADOR : Andro_Os${NC}"
    echo -e "${LRED}      [+] PROYECTO: Geo-Auto Final${NC}"
    echo -e "${LRED}      [+] ESTADO  : ${GREEN}ACTIVO${NC}"
    echo -e "${LRED}=================================================${NC}"
    
    # Detectar TunnelBear MOD
    if detect_tunnelbear_mod; then
        echo "🐻 TunnelBear MOD: ✅ INSTALADO"
    else
        echo "🐻 TunnelBear MOD: ❌ NO ENCONTRADO"
    fi
    
    echo ""
    echo "1) 🚀 Controlar TunnelBear MOD"
    echo "2) 🔧 Configurar VPN dentro de Termux"
    echo "3) 🌐 SSH Tunnel (recomendado)"
    echo "4) 📊 Monitor de conexión"
    echo "5) 🔍 Verificar fugas"
    echo "6) 📋 Ver logs"
    echo "7) 🚪 Salir"
    echo ""
    
    read -p "Selecciona: " choice
    
    case $choice in
        1)
            if detect_tunnelbear_mod; then
                start_tunnelbear_app
                echo ""
                echo "💡 Consejo: Activa el kill switch en TunnelBear MOD:"
                echo "   Configuración → Vigilante → ACTIVAR"
            else
                echo "❌ Instala TunnelBear MOD primero"
                echo "📥 Descarga el APK y instálalo manualmente"
            fi
            ;;
        2)
            start_vpn_in_termux
            ;;
        3)
            setup_ssh_tunnel
            ;;
        4)
            monitor_vpn_status
            ;;
        5)
            check_leaks
            ;;
        6)
            [ -f "$LOG_FILE" ] && tail -20 "$LOG_FILE" || echo "No hay logs"
            ;;
        7)
            echo "👋 Hasta luego!"
            exit 0
            ;;
    esac
    
    read -p "Enter para continuar..."
    show_menu
}

check_leaks() {
    echo "🔍 Verificando fugas..."
    
    echo "1. Verificando IP..."
    echo "   Sin proxy:"
    curl -s --max-time 10 ifconfig.me
    echo ""
    
    echo "2. Verificando DNS..."
    dig +short myip.opendns.com @resolver1.opendns.com
    
    echo "3. Verificando WebRTC (simplificado)..."
    echo "   💡 Usa Firefox con privacy.resistFingerprinting=true"
    
    echo ""
    echo "📱 Para pruebas completas, usa:"
    echo "   https://ipleak.net"
    echo "   https://dnsleaktest.com"
}

# ============================================
# INICIO
# ============================================

echo "🔓 VPN MANAGER - MODO SIN ROOT"
echo "==============================="

# Crear directorios
mkdir -p ~/vpn-advanced/{scripts,logs,configs}

show_menu
