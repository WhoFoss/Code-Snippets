#!/data/data/com.termux/files/usr/bin/sh
# devhealth.sh — relatório de saúde do dispositivo (bateria + UFS), via root
# Combina: charge_full/design, cycle_count, temp, health_descriptor UFS A/B

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_RED="\033[31m"
C_CYAN="\033[36m"

# --- Largura adaptável à tela do Termux ---
TERMCOLS=$(tput cols 2>/dev/null)
[ -z "$TERMCOLS" ] && TERMCOLS=$(stty size 2>/dev/null | cut -d' ' -f2)
[ -z "$TERMCOLS" ] && TERMCOLS=42

MAXINNER=46
MININNER=30
INNER=$((TERMCOLS - 2))
[ "$INNER" -gt "$MAXINNER" ] && INNER=$MAXINNER
[ "$INNER" -lt "$MININNER" ] && INNER=$MININNER

LABEL_W=10
VALUE_W=$((INNER - LABEL_W - 3))

# --- Margem para centralizar a caixa na largura do terminal ---
BOXWIDTH=$((INNER + 2))
LMARGIN=$(((TERMCOLS - BOXWIDTH) / 2))
[ "$LMARGIN" -lt 0 ] && LMARGIN=0

indent() { printf '%*s' "$LMARGIN" ""; }

line() { indent; printf "+"; for i in $(seq 1 "$INNER"); do printf "-"; done; printf "+\n"; }

# Linha de seção centralizada dentro da caixa, ex: |   BATERIA   |
section() {
    text="$1"
    len=${#text}
    totalpad=$((INNER - len))
    [ "$totalpad" -lt 0 ] && totalpad=0
    left=$((totalpad / 2))
    right=$((totalpad - left))
    indent
    printf "|"
    printf '%*s' "$left" ""
    printf "%s" "$text"
    printf '%*s' "$right" ""
    printf "|\n"
}

row() {
    # row "label" "valor"
    label="$1"
    value="$2"
    len=${#label}
    pad=$((LABEL_W - len))
    [ "$pad" -lt 0 ] && pad=0
    indent
    printf "| %s" "$label"
    printf '%*s' "$pad" ""
    printf " %*s |\n" "$VALUE_W" "$value"
}

row_color() {
    # row_color "label" "valor" "cor"
    label="$1"
    value="$2"
    color="$3"
    len=${#label}
    pad=$((LABEL_W - len))
    [ "$pad" -lt 0 ] && pad=0
    padded_value=$(printf '%*s' "$VALUE_W" "$value")
    indent
    printf "| %s" "$label"
    printf '%*s' "$pad" ""
    printf " ${color}%s${C_RESET} |\n" "$padded_value"
}

health_color() {
    h=$1
    if [ "$h" -ge 90 ]; then echo "$C_GREEN"
    elif [ "$h" -ge 70 ]; then echo "$C_YELLOW"
    else echo "$C_RED"
    fi
}

# Mapeia o código de desgaste UFS (JEDEC health descriptor) para texto curto
interpretar_ufs() {
    case "$1" in
        0x00) echo "Novo";;
        0x01) echo "0-10% desgaste";;
        0x02) echo "10-20% desgaste";;
        0x03) echo "20-30% desgaste";;
        0x04) echo "30-40% desgaste";;
        0x05) echo "40-50% desgaste";;
        0x06) echo "50-60% desgaste";;
        0x07) echo "60-70% desgaste";;
        0x08) echo "70-80% desgaste";;
        0x09) echo "80-90% desgaste";;
        0x0A) echo "90-100% desgaste";;
        0x0B) echo "Critico";;
        ""|*) echo "N/D";;
    esac
}

# Mapeia pre_eol_info do eMMC (estado de fim de vida)
interpretar_eol() {
    case "$1" in
        0x01) echo "Normal";;
        0x02) echo "Aviso (80% uso)";;
        0x03) echo "Urgente (90% uso)";;
        ""|*) echo "N/D";;
    esac
}

# --- Verifica se realmente temos root (não só a presença do binário su) ---
# O "su" stub do Termux sem root existe como arquivo, mas só imprime um aviso
# em vez de executar algo — por isso o teste real é checar "id -u" == 0.
as_root() { su -c "$1" 2>/dev/null; }

HAS_ROOT=0
if command -v su >/dev/null 2>&1; then
    UIDCHECK=$(as_root "id -u")
    case "$UIDCHECK" in
        0) HAS_ROOT=1 ;;
    esac
fi

if [ "$HAS_ROOT" -ne 1 ]; then
    printf "${C_RED}[ERRO]${C_RESET} Acesso root não disponível.\n"
    printf "      Este relatório precisa de root (su) para ler bateria e saúde da UFS.\n"
    exit 1
fi

# --- Coleta: Bateria ---
CHARGE_FULL=$(as_root "cat /sys/class/power_supply/battery/charge_full 2>/dev/null")
CHARGE_DESIGN=$(as_root "cat /sys/class/power_supply/battery/charge_full_design 2>/dev/null")
case "$CHARGE_FULL"   in ''|*[!0-9]*) CHARGE_FULL="" ;; esac
case "$CHARGE_DESIGN" in ''|*[!0-9]*) CHARGE_DESIGN="" ;; esac

BATT_OK=0
if [ -n "$CHARGE_FULL" ] && [ -n "$CHARGE_DESIGN" ] && [ "$CHARGE_DESIGN" -gt 0 ]; then
    FULL_MAH=$((CHARGE_FULL / 1000))
    DESIGN_MAH=$((CHARGE_DESIGN / 1000))
    WEAR_MAH=$((DESIGN_MAH - FULL_MAH))
    HEALTH=$(awk "BEGIN{printf \"%.1f\", ($CHARGE_FULL/$CHARGE_DESIGN)*100}")
    HEALTH_INT=${HEALTH%%.*}
    HCOLOR=$(health_color "$HEALTH_INT")
    BATT_OK=1
fi

CYCLES=$(as_root "cat /sys/class/power_supply/battery/cycle_count 2>/dev/null")
case "$CYCLES" in ''|*[!0-9]*) CYCLES="" ;; esac

TEMP_RAW=$(as_root "cat /sys/class/power_supply/battery/temp 2>/dev/null")
case "$TEMP_RAW" in ''|*[!0-9]*) TEMP_RAW="" ;; esac
TEMP_C=""
[ -n "$TEMP_RAW" ] && TEMP_C=$(awk "BEGIN{printf \"%.1f\", $TEMP_RAW/10}")

VOLT_RAW=$(as_root "cat /sys/class/power_supply/battery/voltage_now 2>/dev/null")
case "$VOLT_RAW" in ''|*[!0-9]*) VOLT_RAW="" ;; esac
VOLT_V=""
[ -n "$VOLT_RAW" ] && VOLT_V=$(awk "BEGIN{printf \"%.3f\", $VOLT_RAW/1000000}")

STATUS_RAW=$(as_root "cat /sys/class/power_supply/battery/status 2>/dev/null")
case "$STATUS_RAW" in
    Charging|Discharging|"Not charging"|Full|Unknown) ;;
    *) STATUS_RAW="" ;;
esac
traduzir_status() {
    case "$1" in
        Charging) echo "Carregando";;
        Discharging) echo "Descarregando";;
        "Not charging") echo "Nao carregando";;
        Full) echo "Completa";;
        Unknown) echo "Desconhecido";;
        ""|*) echo "N/D";;
    esac
}

# current_now pode ser negativo (descarregando) dependendo do driver/kernel
CURRENT_RAW=$(as_root "cat /sys/class/power_supply/battery/current_now 2>/dev/null")
case "$CURRENT_RAW" in
    [0-9]*) ;;
    -[0-9]*) ;;
    *) CURRENT_RAW="" ;;
esac
CURRENT_MA=""
POWER_W=""
if [ -n "$CURRENT_RAW" ]; then
    CURRENT_MA=$(awk "BEGIN{printf \"%.1f\", $CURRENT_RAW/1000}")
    if [ -n "$VOLT_RAW" ]; then
        POWER_W=$(awk "BEGIN{printf \"%.2f\", ($VOLT_RAW/1000000)*($CURRENT_RAW/1000000)}")
    fi
fi

# --- Coleta: UFS (vida útil) ---
UFS_A=$(as_root "cat /sys/devices/platform/soc/*ufshc/health_descriptor/life_time_estimation_a 2>/dev/null")
UFS_B=$(as_root "cat /sys/devices/platform/soc/*ufshc/health_descriptor/life_time_estimation_b 2>/dev/null")
case "$UFS_A" in 0x[0-9A-Fa-f]*) ;; *) UFS_A="" ;; esac
case "$UFS_B" in 0x[0-9A-Fa-f]*) ;; *) UFS_B="" ;; esac

# Se não houver UFS, tenta detectar eMMC (mmcblkN) como fallback
STORAGE_MODE="UFS"
EMMC_A=""
EMMC_B=""
EMMC_EOL=""
if [ -z "$UFS_A" ] && [ -z "$UFS_B" ]; then
    STORAGE_MODE="EMMC"
    EMMC_DEV=$(as_root "ls /sys/block 2>/dev/null | grep -E '^mmcblk[0-9]+\$' | head -n1")
    if [ -n "$EMMC_DEV" ]; then
        EMMC_LIFE=$(as_root "cat /sys/block/${EMMC_DEV}/device/life_time 2>/dev/null")
        EMMC_EOL=$(as_root "cat /sys/block/${EMMC_DEV}/device/pre_eol_info 2>/dev/null")
        EMMC_A=$(echo "$EMMC_LIFE" | awk '{print $1}')
        EMMC_B=$(echo "$EMMC_LIFE" | awk '{print $2}')
        case "$EMMC_A"   in 0x[0-9A-Fa-f]*) ;; *) EMMC_A="" ;; esac
        case "$EMMC_B"   in 0x[0-9A-Fa-f]*) ;; *) EMMC_B="" ;; esac
        case "$EMMC_EOL" in 0x[0-9A-Fa-f]*) ;; *) EMMC_EOL="" ;; esac
    fi
    if [ -z "$EMMC_A" ] && [ -z "$EMMC_B" ] && [ -z "$EMMC_EOL" ]; then
        STORAGE_MODE="NONE"
    fi
fi

# --- Coleta: Memória RAM/Swap (não precisa de root) ---
MEM_RAW=$(free -m 2>/dev/null | awk '
/^Mem:/{printf "%d|%.1f|%.1f|%.1f", int($2/1024+0.99), $3/1024, ($2>0)?($3/$2)*100:0, $7/1024}
/^Swap:/{printf "|%.1f|%.1f", $3/1024, $2/1024}
')

is_num() { case "$1" in ''|*[!0-9.]*) return 1 ;; esac; return 0; }

MEM_TOTAL_GB=$(echo "$MEM_RAW" | cut -d'|' -f1)
MEM_USED_GB=$(echo "$MEM_RAW"  | cut -d'|' -f2)
MEM_PCT=$(echo "$MEM_RAW"      | cut -d'|' -f3)
MEM_AVAIL_GB=$(echo "$MEM_RAW" | cut -d'|' -f4)
SWAP_USED_GB=$(echo "$MEM_RAW" | cut -d'|' -f5)
SWAP_TOTAL_GB=$(echo "$MEM_RAW" | cut -d'|' -f6)

is_num "$MEM_TOTAL_GB"  || MEM_TOTAL_GB=""
is_num "$MEM_USED_GB"   || MEM_USED_GB=""
is_num "$MEM_PCT"       || MEM_PCT=""
is_num "$MEM_AVAIL_GB"  || MEM_AVAIL_GB=""
is_num "$SWAP_USED_GB"  || SWAP_USED_GB=""
is_num "$SWAP_TOTAL_GB" || SWAP_TOTAL_GB=""

MEM_OK=0
[ -n "$MEM_TOTAL_GB" ] && [ -n "$MEM_USED_GB" ] && [ -n "$MEM_PCT" ] && [ -n "$MEM_AVAIL_GB" ] && MEM_OK=1

# --- Coleta: Deep sleep desde o boot (via dumpsys batterystats, requer root) ---
# Converte uma string de duração no estilo do dumpsys (ex: "2d5h12m33s500ms",
# com ou sem espaços entre os blocos) em segundos.
to_seg() {
    total_ms=0
    for tok in $(echo "$1" | grep -oE '[0-9]+(ms|d|h|m|s)'); do
        case "$tok" in
            *ms) val=${tok%ms}; total_ms=$((total_ms + val)) ;;
            *d)  val=${tok%d};  total_ms=$((total_ms + val * 86400000)) ;;
            *h)  val=${tok%h};  total_ms=$((total_ms + val * 3600000)) ;;
            *m)  val=${tok%m};  total_ms=$((total_ms + val * 60000)) ;;
            *s)  val=${tok%s};  total_ms=$((total_ms + val * 1000)) ;;
        esac
    done
    echo $((total_ms / 1000))
}

fmt_dur() {
    s=$1
    d=$((s / 86400))
    h=$(((s % 86400) / 3600))
    m=$(((s % 3600) / 60))
    ss=$((s % 60))
    if [ "$d" -gt 0 ]; then
        printf "%dd %dh %dm" "$d" "$h" "$m"
    else
        printf "%dh %dm %ds" "$h" "$m" "$ss"
    fi
}

DEEPSLEEP_LINE=$(as_root "dumpsys batterystats" | grep "Total run time")
REALTIME_STR=$(echo "$DEEPSLEEP_LINE" | sed -E 's/.*Total run time: (.*) realtime,.*/\1/')
UPTIME_STR=$(echo "$DEEPSLEEP_LINE" | sed -E 's/.*realtime, (.*) uptime.*/\1/')

REALTIME_SEC=""
UPTIME_SEC=""
DEEPSLEEP_SEC=""
if [ -n "$REALTIME_STR" ] && [ "$REALTIME_STR" != "$DEEPSLEEP_LINE" ] \
   && [ -n "$UPTIME_STR" ] && [ "$UPTIME_STR" != "$DEEPSLEEP_LINE" ]; then
    REALTIME_SEC=$(to_seg "$REALTIME_STR")
    UPTIME_SEC=$(to_seg "$UPTIME_STR")
    case "$REALTIME_SEC" in ''|*[!0-9]*) REALTIME_SEC="" ;; esac
    case "$UPTIME_SEC"   in ''|*[!0-9]*) UPTIME_SEC="" ;; esac
    if [ -n "$REALTIME_SEC" ] && [ -n "$UPTIME_SEC" ]; then
        DEEPSLEEP_SEC=$((REALTIME_SEC - UPTIME_SEC))
        [ "$DEEPSLEEP_SEC" -lt 0 ] && DEEPSLEEP_SEC=0
    fi
fi

# --- Renderização ---
printf "\n"
indent
printf "${C_BOLD}${C_CYAN}[INFO]${C_RESET} Relatorio de saude do dispositivo (root)\n"
line
section "BATERIA"
line
if [ "$BATT_OK" -eq 1 ]; then
    row "Nominal"  "${DESIGN_MAH} mAh"
    row "Atual"    "${FULL_MAH} mAh"
    row "Desgaste" "${WEAR_MAH} mAh"
    row_color "Saude" "${HEALTH}%" "$HCOLOR"
else
    row "Saude" "N/D"
fi
row "Ciclos" "${CYCLES:-N/D}"
if [ -n "$TEMP_C" ]; then
    row "Temp." "${TEMP_C} C"
else
    row "Temp." "N/D"
fi
if [ -n "$VOLT_V" ]; then
    row "Tensao" "${VOLT_V} V"
else
    row "Tensao" "N/D"
fi
row "Status" "$(traduzir_status "$STATUS_RAW")"
if [ -n "$CURRENT_MA" ]; then
    row "Corrente" "${CURRENT_MA} mA"
else
    row "Corrente" "N/D"
fi
if [ -n "$POWER_W" ]; then
    row "Potencia" "${POWER_W} W"
else
    row "Potencia" "N/D"
fi
line
if [ "$STORAGE_MODE" = "UFS" ]; then
    section "ARMAZENAMENTO (UFS)"
    line
    row "UFS A"   "${UFS_A:-N/D}"
    row "Estado A" "$(interpretar_ufs "$UFS_A")"
    row "UFS B"   "${UFS_B:-N/D}"
    row "Estado B" "$(interpretar_ufs "$UFS_B")"
elif [ "$STORAGE_MODE" = "EMMC" ]; then
    section "ARMAZENAMENTO (eMMC)"
    line
    row "Tipo A"   "${EMMC_A:-N/D}"
    row "Estado A" "$(interpretar_ufs "$EMMC_A")"
    row "Tipo B"   "${EMMC_B:-N/D}"
    row "Estado B" "$(interpretar_ufs "$EMMC_B")"
    row "Fim Vida" "$(interpretar_eol "$EMMC_EOL")"
else
    section "ARMAZENAMENTO"
    line
    row "Tipo" "N/D"
fi
line
section "MEMORIA (RAM)"
line
if [ "$MEM_OK" -eq 1 ]; then
    row "Total"  "${MEM_TOTAL_GB} GB"
    row "Usado"  "${MEM_USED_GB} GB (${MEM_PCT}%)"
    row "Livre"  "${MEM_AVAIL_GB} GB"
    if [ -n "$SWAP_TOTAL_GB" ]; then
        row "Swap" "${SWAP_USED_GB}/${SWAP_TOTAL_GB} GB"
    else
        row "Swap" "N/D"
    fi
else
    row "Total" "N/D"
fi
line
section "SISTEMA"
line
if [ -n "$DEEPSLEEP_SEC" ]; then
    row "Realtime"   "$(fmt_dur "$REALTIME_SEC")"
    row "Uptime"     "$(fmt_dur "$UPTIME_SEC")"
    row "Deep Sleep" "$(fmt_dur "$DEEPSLEEP_SEC")"
else
    row "Deep Sleep" "N/D"
fi
line
printf "\n"
    
