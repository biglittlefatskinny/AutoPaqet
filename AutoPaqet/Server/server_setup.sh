#!/usr/bin/env bash
set -e

# ============================================================================== 
#  PAQET SERVER MANAGER (PRO EDITION v2)
# ============================================================================== 

# ---- Configuration ----
PAQET_BIN="/usr/local/bin/paqet"
CONFIG_FILE="/etc/paqet/config.yaml"
SERVICE_FILE="/etc/systemd/system/paqet.service"
BACKUP_DIR="/etc/paqet/backups"
GO_VERSION="1.25.6"

# ---- Colors & Formatting ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# ---- Root Check ----
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root."
   exit 1
fi

# ============================================================================== 
#  HELPERS
# ============================================================================== 

get_config_value() {
    grep "$1:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"' | tr -d "'"
}

get_current_port() {
    if [ -f "$CONFIG_FILE" ]; then
        grep "addr:" "$CONFIG_FILE" | head -n 1 | awk -F":" '{print $2}' | tr -d '"' | tr -d "'"
    fi
}

check_status() {
    if systemctl is-active --quiet paqet; then
        echo -e "Status: ${GREEN}RUNNING${NC}"
    else
        echo -e "Status: ${RED}STOPPED${NC}"
    fi
}

# Enhanced menu selection function
select_option() {
    local prompt="$1"
    shift
    local options=("$@")
    local REPLY opt
    
    echo -e "\n${BOLD}${prompt}${NC}" >&2
    
    PS3="Enter your choice (number): "
    select opt in "${options[@]}"; do
        if [[ -n "$opt" ]]; then
            echo "$opt"
            break
        else
            echo -e "${RED}[ERROR]${NC} Invalid selection. Please try again." >&2
        fi
    done
}

# Number input with validation
get_number() {
    local prompt="$1"
    local min="$2"
    local max="$3"
    local default="$4"
    local value

    while true; do
        read -p "${prompt} [${min}-${max}, default: ${default}]: " value
        value="${value:-$default}"
        
        if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge "$min" ] && [ "$value" -le "$max" ]; then
            echo "$value"
            return 0
        else
            log_error "Please enter a number between $min and $max"
        fi
    done
}

# Yes/No confirmation
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    if [ "$default" = "y" ]; then
        read -p "${prompt} [Y/n]: " response
        response="${response:-y}"
    else
        read -p "${prompt} [y/N]: " response
        response="${response:-n}"
    fi
    
    [[ "$response" =~ ^[Yy] ]]
}

build_paqet_link() {
    SERVER_IP="$1"
    PORT="$2"
    KCP_CONN="$3"
    KCP_MODE="$4"
    KCP_MTU="$5"
    KCP_RCVWND="$6"
    KCP_SNDWND="$7"
    KCP_BLOCK="$8"
    KEY="$9"
    TCP_FLAGS="${10}"

    PAQET_LINK=$(SERVER_IP="$SERVER_IP" PORT="$PORT" KCP_CONN="$KCP_CONN" KCP_MODE="$KCP_MODE" \
KCP_MTU="$KCP_MTU" KCP_RCVWND="$KCP_RCVWND" KCP_SNDWND="$KCP_SNDWND" KCP_BLOCK="$KCP_BLOCK" \
KEY="$KEY" TCP_FLAGS="$TCP_FLAGS" python3 - <<'PY'
import os, json, base64
payload = {
  "v": 1,
  "server": {"addr": f"{os.environ['SERVER_IP']}:{os.environ['PORT']}"},
  "transport": {
    "protocol": "kcp",
    "conn": int(os.environ["KCP_CONN"]),
    "kcp": {
      "mode": os.environ["KCP_MODE"],
      "mtu": int(os.environ["KCP_MTU"]),
      "rcvwnd": int(os.environ["KCP_RCVWND"]),
      "sndwnd": int(os.environ["KCP_SNDWND"]),
      "block": os.environ["KCP_BLOCK"],
      "key": os.environ["KEY"]
    }
  },
  "tcp": {
    "local_flag": os.environ["TCP_FLAGS"].replace(" ", "").split(","),
    "remote_flag": ["PA"]
  }
}
raw = json.dumps(payload, separators=(",", ":")).encode()
b64 = base64.urlsafe_b64encode(raw).decode().rstrip("=")
print(f"paqet://{b64}")
PY
)
    echo "$PAQET_LINK"
}

show_key() {
    if [ -f "$CONFIG_FILE" ]; then
        KEY=$(grep "key:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"' | tr -d "'")
        PORT=$(get_current_port)
        SERVER_IP=$(grep "addr:" "$CONFIG_FILE" | head -n 1 | awk -F":" '{print $1}' | awk '{print $2}')
        TCP_FLAGS=$(grep -A1 "local_flag" "$CONFIG_FILE" | tail -n 1 | tr -d " -[]\"" | tr ',' ' ')
        KCP_MODE=$(grep "mode:" "$CONFIG_FILE" | head -n 1 | awk '{print $2}')
        KCP_MTU=$(grep "mtu:" "$CONFIG_FILE" | awk '{print $2}')
        KCP_RCVWND=$(grep "rcvwnd:" "$CONFIG_FILE" | awk '{print $2}')
        KCP_SNDWND=$(grep "sndwnd:" "$CONFIG_FILE" | awk '{print $2}')
        KCP_BLOCK=$(grep "block:" "$CONFIG_FILE" | awk '{print $2}')
        KCP_CONN=$(grep "conn:" "$CONFIG_FILE" | awk '{print $2}')

        if [ -z "$SERVER_IP" ]; then
            SERVER_IP=$(hostname -I | awk '{print $1}')
        fi

        LINK=$(build_paqet_link "$SERVER_IP" "$PORT" "$KCP_CONN" "$KCP_MODE" "$KCP_MTU" "$KCP_RCVWND" "$KCP_SNDWND" "$KCP_BLOCK" "$KEY" "$TCP_FLAGS")

        echo ""
        echo "================================================"
        echo -e "${BOLD}CURRENT CONFIGURATION${NC}"
        echo "================================================"
        echo -e "KCP Key:      ${YELLOW}${KEY}${NC}"
        echo "Server IP:    ${SERVER_IP}"
        echo "Port:         ${PORT}"
        echo "KCP Mode:     ${KCP_MODE}"
        echo "Cipher:       ${KCP_BLOCK}"
        echo "Connections:  ${KCP_CONN}"
        echo "MTU:          ${KCP_MTU}"
        echo "TCP Flags:    ${TCP_FLAGS}"
        echo "------------------------------------------------"
        echo -e "${BOLD}PAQET LINK:${NC}"
        echo "$LINK"
        echo "================================================"
    else
        log_error "Config file not found."
    fi
}

show_logs() {
    journalctl -u paqet -n 50 -f
}

backup_config() {
    if [ -f "$CONFIG_FILE" ]; then
        mkdir -p "$BACKUP_DIR"
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        cp "$CONFIG_FILE" "$BACKUP_DIR/config_$TIMESTAMP.yaml"
        log_success "Configuration backed up to $BACKUP_DIR/config_$TIMESTAMP.yaml"
    fi
}

restore_config() {
    if [ ! -d "$BACKUP_DIR" ]; then
        log_error "No backups found."
        return
    fi
    
    BACKUPS=($(ls -t "$BACKUP_DIR"/config_*.yaml 2>/dev/null))
    if [ ${#BACKUPS[@]} -eq 0 ]; then
        log_error "No backup files found."
        return
    fi
    
    echo -e "\n${BOLD}Available backups:${NC}"
    PS3="Select backup to restore: "
    select backup in "${BACKUPS[@]}" "Cancel"; do
        if [ "$backup" = "Cancel" ]; then
            return
        elif [ -n "$backup" ]; then
            if confirm "Restore configuration from $backup?"; then
                cp "$backup" "$CONFIG_FILE"
                systemctl restart paqet
                log_success "Configuration restored and service restarted."
            fi
            return
        fi
    done
}

# ============================================================================== 
#  PRE-CONFIGURED PROFILES
# ============================================================================== 

apply_profile() {
    local profile="$1"
    
    case "$profile" in
        *"Low Latency"*|*"Gaming"*)
            KCP_MODE="fast3"
            KCP_CONN=4
            KCP_MTU=1400
            KCP_RCVWND=2048
            KCP_SNDWND=2048
            KCP_BLOCK="aes"
            PCAP_SOCKBUF=16777216
            ;;
        *"Balanced"*|*"Default"*)
            KCP_MODE="fast"
            KCP_CONN=1
            KCP_MTU=1350
            KCP_RCVWND=1024
            KCP_SNDWND=1024
            KCP_BLOCK="aes"
            PCAP_SOCKBUF=8388608
            ;;
        *"High Throughput"*|*"Downloads"*)
            KCP_MODE="normal"
            KCP_CONN=8
            KCP_MTU=1400
            KCP_RCVWND=4096
            KCP_SNDWND=4096
            KCP_BLOCK="aes-128-gcm"
            PCAP_SOCKBUF=33554432
            ;;
        *"Conservative"*|*"Unstable"*)
            KCP_MODE="normal"
            KCP_CONN=2
            KCP_MTU=1200
            KCP_RCVWND=512
            KCP_SNDWND=512
            KCP_BLOCK="aes"
            PCAP_SOCKBUF=4194304
            ;;
        *"Custom"*)
            return 1
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

# ============================================================================== 
#  CORE OPERATIONS
# ============================================================================== 

install_paqet() {
    echo "============================================================"
    echo "                 INSTALLING PAQET SERVER                    "
    echo "============================================================"

    # ---- Initialize variables ----
    KCP_MODE=""
    KCP_CONN=""
    KCP_MTU=""
    KCP_RCVWND=""
    KCP_SNDWND=""
    KCP_BLOCK=""
    PCAP_SOCKBUF=""

    # ---- Step 1: Choose Configuration Profile ----
    log_step "Step 1/5: Choose Configuration Profile"
    
    PROFILE=$(select_option "Select a configuration profile:" \
        "Balanced (Default)" \
        "Low Latency (Gaming)" \
        "High Throughput (Downloads)" \
        "Conservative (Unstable Network)" \
        "Custom Configuration")
    
    if apply_profile "$PROFILE"; then
        echo -e "${GREEN}✓${NC} Profile '$PROFILE' loaded"
    else
        log_info "Custom configuration selected"
    fi

    # ---- Step 2: Port Selection ----
    log_step "Step 2/5: Network Configuration"
    
    PORT_CHOICE=$(select_option "Select listen port:" \
        "443 (HTTPS - Recommended)" \
        "8443 (Alternative HTTPS)" \
        "80 (HTTP)" \
        "22 (SSH)" \
        "Custom Port")
    
    case "$PORT_CHOICE" in
        *"443"*) PORT=443 ;;
        *"8443"*) PORT=8443 ;;
        *"80"*) PORT=80 ;;
        *"22"*) PORT=22 ;;
        *"Custom"*) PORT=$(get_number "Enter custom port" 1 65535 443) ;;
    esac
    
    echo -e "${GREEN}✓${NC} Port: $PORT"

    # ---- Step 3: Logging Configuration ----
    log_step "Step 3/5: Logging Configuration"
    
    LOG_CHOICE=$(select_option "Select log level:" \
        "info (Recommended)" \
        "warn (Minimal logging)" \
        "debug (Verbose)" \
        "error (Errors only)" \
        "none (No logging)")
    
    # Extract just the log level name
    LOG_LEVEL=$(echo "$LOG_CHOICE" | awk '{print $1}')
    echo -e "${GREEN}✓${NC} Log Level: $LOG_LEVEL"

    # ---- Step 4: Advanced Settings (if Custom profile) ----
    if [ "$PROFILE" = "Custom Configuration" ]; then
        log_step "Step 4/5: Advanced KCP Configuration"
        
        KCP_CHOICE=$(select_option "KCP Mode (affects speed/reliability):" \
            "fast (Recommended)" \
            "fast2 (Faster)" \
            "fast3 (Fastest)" \
            "normal (Reliable)")
        KCP_MODE=$(echo "$KCP_CHOICE" | awk '{print $1}')
        
        CIPHER_CHOICE=$(select_option "Encryption cipher:" \
            "aes (Recommended)" \
            "aes-128-gcm (Modern)" \
            "aes-128 (Fast)" \
            "salsa20 (Alternative)" \
            "none (No encryption - Fastest)")
        KCP_BLOCK=$(echo "$CIPHER_CHOICE" | awk '{print $1}')
        
        KCP_CONN=$(get_number "Number of KCP connections" 1 256 1)
        KCP_MTU=$(get_number "MTU size (lower for unstable networks)" 500 1500 1350)
        KCP_RCVWND=$(get_number "Receive window size" 128 32768 1024)
        KCP_SNDWND=$(get_number "Send window size" 128 32768 1024)
        PCAP_SOCKBUF=$(get_number "PCAP socket buffer (MB)" 1 64 8)
        PCAP_SOCKBUF=$((PCAP_SOCKBUF * 1048576))
    else
        log_info "Using profile settings (Advanced config skipped)"
    fi

    # ---- Step 5: TCP Flags Configuration ----
    log_step "Step 5/5: TCP Flags Configuration"
    
    TCP_FLAGS_CHOICE=$(select_option "TCP Flags (affects detection evasion):" \
        "PA (Push-Ack - Recommended)" \
        "PA,S (Push-Ack + Syn)" \
        "PA,SA (Push-Ack + Syn-Ack)" \
        "S (Syn only)" \
        "Custom")
    
    case "$TCP_FLAGS_CHOICE" in
        *"PA,SA"*) TCP_FLAGS="PA,SA" ;;
        *"PA,S"*) TCP_FLAGS="PA,S" ;;
        *"S (Syn only)"*) TCP_FLAGS="S" ;;
        *"PA"*) TCP_FLAGS="PA" ;;
        *"Custom"*) read -p "Enter TCP flags (comma-separated, e.g., PA,S,SA): " TCP_FLAGS ;;
    esac
    
    echo -e "${GREEN}✓${NC} TCP Flags: $TCP_FLAGS"

    # ---- Configuration Summary ----
    echo ""
    echo "============================================================"
    echo -e "${BOLD}CONFIGURATION SUMMARY${NC}"
    echo "============================================================"
    echo "Profile:      $PROFILE"
    echo "Port:         $PORT"
    echo "Log Level:    $LOG_LEVEL"
    echo "KCP Mode:     $KCP_MODE"
    echo "Cipher:       $KCP_BLOCK"
    echo "Connections:  $KCP_CONN"
    echo "MTU:          $KCP_MTU"
    echo "TCP Flags:    $TCP_FLAGS"
    echo "============================================================"
    
    if ! confirm "Proceed with installation?" "y"; then
        log_warn "Installation cancelled."
        exit 0
    fi

    # ---- Network Detection ----
    log_info "Detecting network configuration..."
    DEFAULT_ROUTE=$(ip route | awk '/default/ {print $0; exit}')
    IFACE=$(awk '{for(i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}' <<<"$DEFAULT_ROUTE")
    GATEWAY_IP=$(awk '{for(i=1;i<=NF;i++) if ($i=="via") {print $(i+1); exit}}' <<<"$DEFAULT_ROUTE")

    SERVER_IP=$(ip -4 -o addr show dev "$IFACE" | awk '{print $4}' | cut -d/ -f1 | head -n1)

    if [ -n "${GATEWAY_IP:-}" ]; then
        ping -c 1 -W 1 "$GATEWAY_IP" >/dev/null 2>&1 || true
    fi
    ROUTER_MAC=$(ip neigh show "$GATEWAY_IP" 2>/dev/null | awk '{print $5; exit}')

    if [ -z "$ROUTER_MAC" ]; then
        log_error "Could not determine router MAC. Network detection failed."
        exit 1
    fi

    log_success "Detected: IFACE=$IFACE | IP=$SERVER_IP | GW=$GATEWAY_IP | MAC=$ROUTER_MAC"

    # ---- Dependencies ----
    log_info "Installing dependencies..."
    apt-get update -qq
    apt-get install -y -qq git build-essential libpcap-dev iptables curl python3 >/dev/null

    # ---- Install Go ----
    if ! command -v go &>/dev/null || ! go version | grep -q "$GO_VERSION"; then
        log_info "Installing Go ${GO_VERSION}..."
        rm -rf /usr/local/go
        curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | tar -C /usr/local -xz
        export PATH=$PATH:/usr/local/go/bin
    else
        log_info "Go ${GO_VERSION} already installed"
    fi

    # ---- Build Paqet ----
    log_info "Building Paqet..."
    rm -rf /opt/paqet
    git clone -q https://github.com/hanselime/paqet /opt/paqet
    cd /opt/paqet
    go build -o "$PAQET_BIN" ./cmd

    # ---- Generate Configuration ----
    KEY=$($PAQET_BIN secret | tr -d '\r\n')
    mkdir -p /etc/paqet
    mkdir -p "$BACKUP_DIR"

    TCP_FLAGS_CSV=$(echo "$TCP_FLAGS" | tr ' ' ',' | tr -s ',')
    TCP_FLAGS_YAML=$(echo "$TCP_FLAGS_CSV" | sed 's/,/","/g')

    cat >"$CONFIG_FILE" <<EOF
role: "server"
log:
  level: "${LOG_LEVEL}"
listen:
  addr: ":${PORT}"
network:
  interface: "${IFACE}"
  ipv4:
    addr: "${SERVER_IP}:${PORT}"
    router_mac: "${ROUTER_MAC}"
  tcp:
    local_flag: ["${TCP_FLAGS_YAML}"]
  pcap:
    sockbuf: ${PCAP_SOCKBUF}
transport:
  protocol: "kcp"
  conn: ${KCP_CONN}
  kcp:
    mode: "${KCP_MODE}"
    mtu: ${KCP_MTU}
    rcvwnd: ${KCP_RCVWND}
    sndwnd: ${KCP_SNDWND}
    block: "${KCP_BLOCK}"
    key: "${KEY}"
EOF

    # ---- Apply Firewall Rules ----
    log_info "Applying iptables rules..."
    iptables -t raw -C PREROUTING -p tcp --dport ${PORT} -j NOTRACK 2>/dev/null || \
    iptables -t raw -A PREROUTING -p tcp --dport ${PORT} -j NOTRACK

    iptables -t raw -C OUTPUT -p tcp --sport ${PORT} -j NOTRACK 2>/dev/null || \
    iptables -t raw -A OUTPUT -p tcp --sport ${PORT} -j NOTRACK

    iptables -t mangle -C OUTPUT -p tcp --sport ${PORT} --tcp-flags RST RST -j DROP 2>/dev/null || \
    iptables -t mangle -A OUTPUT -p tcp --sport ${PORT} --tcp-flags RST RST -j DROP

    # ---- Create Service ----
    cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=Paqet Server
After=network.target

[Service]
Type=simple
ExecStart=$PAQET_BIN run -c $CONFIG_FILE
Restart=on-failure
RestartSec=2
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now paqet

    # ---- Initial backup ----
    backup_config

    LINK=$(build_paqet_link "$SERVER_IP" "$PORT" "$KCP_CONN" "$KCP_MODE" "$KCP_MTU" "$KCP_RCVWND" "$KCP_SNDWND" "$KCP_BLOCK" "$KEY" "$TCP_FLAGS")

    echo ""
    log_success "Installation Complete!"
    echo "================= PAQET SETTINGS ================="
    echo "Profile:     ${PROFILE}"
    echo "Server IP:   ${SERVER_IP}"
    echo "Port:        ${PORT}"
    echo "Interface:   ${IFACE}"
    echo "Gateway IP:  ${GATEWAY_IP}"
    echo "Router MAC:  ${ROUTER_MAC}"
    echo "Log Level:   ${LOG_LEVEL}"
    echo "KCP Mode:    ${KCP_MODE}"
    echo "KCP Block:   ${KCP_BLOCK}"
    echo "KCP Conn:    ${KCP_CONN}"
    echo "MTU:         ${KCP_MTU}"
    echo "RCVWND:      ${KCP_RCVWND}"
    echo "SNDWND:      ${KCP_SNDWND}"
    echo "TCP Flags:   ${TCP_FLAGS}"
    echo "KCP Key:     ${KEY}"
    echo "---------------------------------------------------"
    echo -e "${BOLD}PAQET LINK:${NC}"
    echo "$LINK"
    echo "==================================================="
    echo ""
    echo "💡 Tip: Save this link! You can retrieve it anytime from the menu."
}

reconfigure_paqet() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Paqet is not installed. Please install it first."
        return
    fi
    
    log_warn "This will backup current config and create a new one."
    if ! confirm "Continue with reconfiguration?"; then
        return
    fi
    
    backup_config
    
    # Get current port for iptables cleanup
    OLD_PORT=$(get_current_port)
    
    # Run installation process (will overwrite config)
    install_paqet
    
    # Clean up old iptables rules if port changed
    if [ -n "$OLD_PORT" ] && [ "$OLD_PORT" != "$PORT" ]; then
        log_info "Cleaning old iptables rules for port $OLD_PORT..."
        iptables -t raw -D PREROUTING -p tcp --dport "$OLD_PORT" -j NOTRACK 2>/dev/null || true
        iptables -t raw -D OUTPUT -p tcp --sport "$OLD_PORT" -j NOTRACK 2>/dev/null || true
        iptables -t mangle -D OUTPUT -p tcp --sport "$OLD_PORT" --tcp-flags RST RST -j DROP 2>/dev/null || true
    fi
}

uninstall_paqet() {
    echo -e "${RED}${BOLD}WARNING: This will remove Paqet and all configurations.${NC}"
    if ! confirm "Are you sure you want to uninstall?"; then
        return
    fi

    if confirm "Create a final backup before uninstalling?"; then
        backup_config
    fi

    log_info "Stopping service..."
    systemctl stop paqet || true
    systemctl disable paqet || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload

    OLD_PORT=$(get_current_port)
    if [ -n "$OLD_PORT" ]; then
        log_info "Cleaning iptables rules for port $OLD_PORT..."
        iptables -t raw -D PREROUTING -p tcp --dport "$OLD_PORT" -j NOTRACK 2>/dev/null || true
        iptables -t raw -D OUTPUT -p tcp --sport "$OLD_PORT" -j NOTRACK 2>/dev/null || true
        iptables -t mangle -D OUTPUT -p tcp --sport "$OLD_PORT" --tcp-flags RST RST -j DROP 2>/dev/null || true
    fi

    if confirm "Remove all configuration files and backups?"; then
        log_info "Removing all files..."
        rm -rf /opt/paqet
        rm -rf /etc/paqet
        rm -f "$PAQET_BIN"
    else
        log_info "Removing binary only (configs preserved)..."
        rm -rf /opt/paqet
        rm -f "$PAQET_BIN"
    fi

    log_success "Uninstallation complete."
    exit 0
}

show_info() {
    echo ""
    echo "============================================================"
    echo -e "${BOLD}SYSTEM INFORMATION${NC}"
    echo "============================================================"
    
    if systemctl is-active --quiet paqet; then
        echo -e "Service Status:  ${GREEN}RUNNING${NC}"
        echo "Uptime:          $(systemctl show paqet --property=ActiveEnterTimestamp --value | xargs -I {} date -d {} +'%Y-%m-%d %H:%M:%S')"
    else
        echo -e "Service Status:  ${RED}STOPPED${NC}"
    fi
    
    if [ -f "$CONFIG_FILE" ]; then
        PORT=$(get_current_port)
        echo "Listen Port:     $PORT"
        echo "Config File:     $CONFIG_FILE"
        
        if [ -d "$BACKUP_DIR" ]; then
            BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/config_*.yaml 2>/dev/null | wc -l)
            echo "Backups:         $BACKUP_COUNT available"
        fi
    fi
    
    echo "Go Version:      $(go version 2>/dev/null | awk '{print $3}' || echo 'Not installed')"
    echo "Paqet Binary:    $PAQET_BIN"
    echo "============================================================"
}

# ============================================================================== 
#  MAIN LOGIC
# ============================================================================== 

if [ -f "$PAQET_BIN" ]; then
    while true; do
        echo ""
        echo "============================================"
        echo -e "      ${BOLD}PAQET MANAGER MENU${NC}"
        echo "============================================"
        check_status
        echo ""
        echo "1)  Start Service"
        echo "2)  Stop Service"
        echo "3)  Restart Service"
        echo "4)  Show KCP Key & Link"
        echo "5)  View Live Logs"
        echo "6)  Show System Info"
        echo "7)  Reconfigure Server"
        echo "8)  Backup Configuration"
        echo "9)  Restore Configuration"
        echo "10) Uninstall Paqet"
        echo "0)  Exit"
        echo ""
        read -p "Select an option: " OPTION

        case $OPTION in
            1) systemctl start paqet; log_success "Service started." ;;
            2) systemctl stop paqet; log_success "Service stopped." ;;
            3) systemctl restart paqet; log_success "Service restarted." ;;
            4) show_key ;;
            5) show_logs ;;
            6) show_info ;;
            7) reconfigure_paqet ;;
            8) backup_config ;;
            9) restore_config ;;
            10) uninstall_paqet ;;
            0) exit 0 ;;
            *) log_error "Invalid option." ;;
        esac
    done
else
    install_paqet
fi
