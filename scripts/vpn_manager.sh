#!/data/data/com.termux/files/usr/bin/bash

# ============================================
# VPN MANAGER + TUNNELBEAR INTEGRATION
# ============================================

CONFIG_DIR="$HOME/vpn-advanced"
LOG_FILE="$CONFIG_DIR/logs/vpn.log"

# =========================================================
# CONFIGURACIÓN
# =========================================================
IMG="/data/data/com.termux/files/home/storage/pictures/Anonymus.png"

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_message() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# ============================================
# FUNCIONES CON TUNNELBEAR
# ============================================

check_tunnelbear_installed() {
    if pm list packages | grep -q "com.tunnelbear.android"; then
        return 0
    else
        echo "❌ TunnelBear no instalado"
        echo "📥 Descárgalo de Play Store: https://play.google.com/store/apps/details?id=com.tunnelbear.android"
        return 1
    fi
}

open_tunnelbear() {
    log_message "Abriendo TunnelBear..."
    am start -n com.tunnelbear.android/.ui.SplashActivity
    sleep 3
}

connect_tunnelbear() {
    log_message "Conectando TunnelBear..."
    
    # Método 1: Intentar usar accesibilidad (necesita config)
    if command -v termux-notification >/dev/null 2>&1; then
        termux-notification -t "Conectando VPN" \
            -c "Por favor, activa TunnelBear manualmente"
    fi
    
    # Método 2: Abrir y esperar conexión manual
    open_tunnelbear
    
    echo "========================================"
    echo "🐻 POR FAVOR:"
    echo "1. Abre TunnelBear"
    echo "2. Selecciona país"
    echo "3. Activa el interruptor de VPN"
    echo "4. El kill switch DE TUNNELBEAR se activará automáticamente"
    echo "========================================"
    
    read -p "Presiona Enter cuando estés conectado..."
}

check_vpn_active() {
    # Verificar si hay VPN activa (TunnelBear u otra)
    if ifconfig | grep -q "tun0"; then
        return 0
    elif ip addr show | grep -q "tun"; then
        return 0
    else
        # Verificar con netstat
        if netstat -rn | grep -q "tun"; then
            return 0
        fi
    fi
    return 1
}

# ============================================
# ROTACIÓN SIMULADA CON TUNNELBEAR
# ============================================

rotate_tunnelbear() {
    log_message "Sugiriendo cambio de servidor en TunnelBear..."
    
    # Lista de países sugeridos
    countries=("United States" "Canada" "Germany" "Japan" "United Kingdom" "Netherlands")
    random_country=${countries[$RANDOM % ${#countries[@]}]}
    
    echo "🔄 Sugerencia: Cambia a $random_country en TunnelBear"
    
    # Abrir TunnelBear para cambio manual
    open_tunnelbear
    
    echo "========================================"
    echo "🔄 MANUAL: En TunnelBear:"
    echo "1. Toca 'Elige tu país oso'"
    echo "2. Selecciona: $random_country"
    echo "3. Espera a que se reconecte"
    echo "========================================"
    
    read -p "Enter cuando hayas cambiado de país..."
}

# ============================================
# DNS Y SEGURIDAD COMPLEMENTARIA
# ============================================

configure_dns_no_root() {
    log_message "Configurando DNS seguro..."
    
    # Cambiar DNS temporalmente (sin root)
    echo "nameserver 9.9.9.9" > $PREFIX/etc/resolv.conf
    echo "nameserver 1.1.1.1" >> $PREFIX/etc/resolv.conf
    
    # Usar herramientas de Termux para proxy DNS
    if command -v dnsmasq >/dev/null 2>&1; then
        log_message "Configurando dnsmasq local..."
        echo "server=9.9.9.9" > $PREFIX/etc/dnsmasq.conf
        echo "server=1.1.1.1" >> $PREFIX/etc/dnsmasq.conf
        dnsmasq
    fi
    
    log_message "DNS configurado (localmente)"
}

# ============================================
# MONITOREO DE CONEXIÓN
# ============================================

monitor_connection_no_root() {
    log_message "Iniciando monitor de conexión..."
    
    while true; do
        if ! ping -c 1 -W 2 9.9.9.9 >/dev/null 2>&1; then
            log_message "⚠️  Posible pérdida de conexión"
            log_message "   TunnelBear kill switch debería activarse"
            
            # Notificación
            if command -v termux-notification >/dev/null; then
                termux-notification -t "Verifica VPN" \
                    -c "La conexión podría estar expuesta"
            fi
        fi
        
        # Verificar cada 30 segundos
        sleep 30
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
    echo -e "${LRED}      [+] PROYECTO: VPN MANAGER + TUNNELBEAR${NC}"
    echo -e "${LRED}      [+] ESTADO  : ${GREEN}ACTIVO${NC}"
    echo -e "${LRED}=================================================${NC}"
    echo "🐻 TunnelBear detectado: $(check_tunnelbear_installed && echo '✅' || echo '❌')"
    echo ""
    echo "1) 🚀 Conectar TunnelBear (recomendado)"
    echo "2) 🔄 Rotar servidor (cambiar país)"
    echo "3) 📊 Ver estado de conexión"
    echo "4) 🌐 Configurar DNS seguro"
    echo "5) 🔍 Monitorear conexión en segundo plano"
    echo "6) 📋 Ver logs"
    echo "7) 🚪 Salir"
    echo ""
    
    read -p "Selecciona: " choice
    
    case $choice in
        1)
            check_tunnelbear_installed && connect_tunnelbear
            ;;
        2)
            rotate_tunnelbear
            ;;
        3)
            if check_vpn_active; then
                echo -e "✅ VPN activa (probablemente TunnelBear)"
                echo "🌍 Probando conexión..."
                ping -c 2 9.9.9.9 | tail -2
            else
                echo -e "❌ No hay VPN activa"
                echo "🐻 Activa TunnelBear desde la app"
            fi
            ;;
        4)
            configure_dns_no_root
            ;;
        5)
            monitor_connection_no_root &
            echo "✅ Monitor activado en segundo plano"
            ;;
        6)
            [ -f "$LOG_FILE" ] && tail -20 "$LOG_FILE" || echo "No hay logs"
            ;;
        7)
            echo "🐻 Gracias por usar TunnelBear + VPN Manager"
            exit 0
            ;;
    esac
    
    read -p "Enter para continuar..."
    show_menu
}

# ============================================
# INSTALACIÓN DE DEPENDENCIAS ÚTILES
# ============================================

install_recommended_tools() {
    echo "📦 Instalando herramientas recomendadas..."
    
    # Termux:API para notificaciones
    pkg install termux-api -y
    
    # Herramientas de red
    pkg install net-tools dnsutils curl -y
    
    # Python para scripts adicionales
    pkg install python -y
    pip install requests
    
    echo "✅ Herramientas instaladas"
    echo "📱 Ahora puedes recibir notificaciones del estado VPN"
}

# ============================================
# INICIO
# ============================================

echo "🐻 VPN MANAGER con TunnelBear"
echo "============================="

# Verificar si TunnelBear está instalado
if ! check_tunnelbear_installed; then
    echo ""
    echo "⚠️  Para mejor experiencia:"
    echo "1. Instala TunnelBear desde Play Store"
    echo "2. Activa su kill switch en configuración"
    echo "3. Vuelve a ejecutar este script"
    echo ""
    read -p "¿Instalar herramientas de monitoreo? (s/n): " install_choice
    [[ "$install_choice" == "s" ]] && install_recommended_tools
fi

show_menu
