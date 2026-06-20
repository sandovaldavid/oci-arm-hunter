#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# setup.sh — Wizard interactivo para generar .env automáticamente
# usando oci-cli para obtener OCIDs sin entrar a la consola web.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()   { echo -e "${CYAN}[→]${RESET} $*"; }
ok()     { echo -e "${GREEN}[✓]${RESET} $*"; }
warn()   { echo -e "${YELLOW}[!]${RESET} $*"; }
error()  { echo -e "${RED}[✗]${RESET} $*" >&2; }
header() { echo -e "\n${BOLD}── $* ──${RESET}"; }
ask()    { read -r -p "    $* " "$2" </dev/tty; }

# ---------------------------------------------------------------------------
# Menú numerado interactivo
# Uso: pick_menu "Prompt" RESULT_VAR "nombre1|valor1" "nombre2|valor2" ...
# ---------------------------------------------------------------------------
pick_menu() {
  local prompt="$1"
  local result_var="$2"
  shift 2
  local -a entries=("$@")
  local count=${#entries[@]}
  local i=0

  for entry in "${entries[@]}"; do
    local label="${entry%%|*}"
    printf "  ${CYAN}[%d]${RESET} %s\n" "$i" "$label"
    i=$((i + 1))
  done

  local choice
  while true; do
    read -r -p "    $prompt [0-$((count-1))]: " choice </dev/tty
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 0 && choice < count )); then
      local selected="${entries[$choice]}"
      printf -v "$result_var" '%s' "${selected##*|}"
      ok "Seleccionado: ${selected%%|*}"
      return 0
    fi
    warn "Número inválido. Elige entre 0 y $((count-1))."
  done
}

# ---------------------------------------------------------------------------
# Paso 0: Verificar prerrequisitos
# ---------------------------------------------------------------------------
check_prereqs() {
  header "Verificando prerrequisitos"

  if ! command -v oci &>/dev/null; then
    error "oci-cli no está instalado."
    echo "  Instalar en Oracle Linux/Fedora: sudo dnf install python3-oci-cli"
    echo "  O via pip: pip install oci-cli"
    exit 1
  fi
  ok "oci-cli encontrado: $(oci --version 2>&1 | head -1)"

  if [[ ! -f ~/.oci/config ]]; then
    error "$HOME/.oci/config no existe. Configura OCI CLI con: oci setup config"
    exit 1
  fi
  if ! grep -q "^tenancy=" ~/.oci/config; then
    error "$HOME/.oci/config no tiene el campo 'tenancy'. Verifica tu configuración."
    exit 1
  fi
  ok "$HOME/.oci/config encontrado y válido."

  if ! command -v jq &>/dev/null; then
    error "jq no está instalado (requerido para parsear respuestas JSON)."
    echo "  Ubuntu/Debian:  sudo apt install jq"
    echo "  Oracle Linux:   sudo dnf install jq"
    exit 1
  fi
  ok "jq encontrado: $(jq --version)"

  if [[ -f "$ENV_FILE" ]]; then
    warn ".env ya existe en $ENV_FILE"
    local confirm
    read -r -p "    ¿Sobreescribir? [s/N]: " confirm </dev/tty
    if [[ ! "$confirm" =~ ^[sS]$ ]]; then
      echo "Operación cancelada."
      exit 0
    fi
  fi
}

# ---------------------------------------------------------------------------
# Paso 1: TENANCY_OCID (desde ~/.oci/config)
# ---------------------------------------------------------------------------
get_tenancy() {
  header "Paso 1/6 — Tenancy OCID"
  TENANCY_OCID=$(grep "^tenancy=" ~/.oci/config | cut -d'=' -f2 | tr -d ' \r')
  ok "TENANCY_OCID obtenido de ~/.oci/config"
  info "$TENANCY_OCID"
}

# ---------------------------------------------------------------------------
# Paso 2: AVAILABILITY_DOMAINS (automático)
# ---------------------------------------------------------------------------
get_availability_domains() {
  header "Paso 2/6 — Availability Domains"
  info "Consultando ADs de tu Home Region..."

  local raw
  raw=$(oci iam availability-domain list \
    --compartment-id "$TENANCY_OCID" \
    --all --output json 2>/dev/null)

  AVAILABILITY_DOMAINS=$(echo "$raw" | jq -r '.data[].name' | tr '\n' ' ' | xargs)

  if [[ -z "$AVAILABILITY_DOMAINS" ]]; then
    error "No se pudieron obtener los Availability Domains."
    exit 1
  fi

  ok "ADs encontrados: $AVAILABILITY_DOMAINS"
}

# ---------------------------------------------------------------------------
# Paso 3: COMPARTMENT_OCID (lista + elección)
# ---------------------------------------------------------------------------
get_compartment() {
  header "Paso 3/6 — Compartimento"
  info "Consultando compartimentos activos..."

  local raw
  raw=$(oci iam compartment list \
    --compartment-id "$TENANCY_OCID" \
    --lifecycle-state ACTIVE \
    --all --output json 2>/dev/null)

  local -a entries=("root (tenancy)|$TENANCY_OCID")

  while IFS= read -r line; do
    entries+=("$line")
  done < <(echo "$raw" | jq -r '.data[] | "\(.name)|\(.id)"')

  echo ""
  pick_menu "Elige el compartimento:" COMPARTMENT_OCID "${entries[@]}"
}

# ---------------------------------------------------------------------------
# Crear stack de red completo (VCN + IG + Route Table + Security List + Subnet)
# Variables de salida: VCN_ID (local al caller), SUBNET_OCID (global)
# ---------------------------------------------------------------------------
create_vcn_stack() {
  info "Provisionando red desde cero..."

  # 1. VCN
  local vcn_raw
  vcn_raw=$(oci network vcn create \
    --compartment-id "$COMPARTMENT_OCID" \
    --cidr-block "10.0.0.0/16" \
    --display-name "vcn-arm-hunter" \
    --dns-label "vcnarmhunter" \
    --output json 2>&1) || {
    error "Error al crear VCN — respuesta de OCI:"
    echo "$vcn_raw"
    exit 1
  }

  local vcn_id default_rt_id default_sl_id
  vcn_id=$(echo "$vcn_raw"        | jq -r '.data.id')
  default_rt_id=$(echo "$vcn_raw" | jq -r '.data."default-route-table-id"')
  default_sl_id=$(echo "$vcn_raw" | jq -r '.data."default-security-list-id"')
  ok "VCN creada: vcn-arm-hunter"

  # 2. Internet Gateway
  local ig_raw ig_id
  ig_raw=$(oci network internet-gateway create \
    --compartment-id "$COMPARTMENT_OCID" \
    --vcn-id "$vcn_id" \
    --is-enabled true \
    --display-name "ig-arm-hunter" \
    --output json 2>&1) || {
    error "Error al crear Internet Gateway — respuesta de OCI:"
    echo "$ig_raw"
    exit 1
  }

  ig_id=$(echo "$ig_raw" | jq -r '.data.id')
  ok "Internet Gateway creado: ig-arm-hunter"

  # 3. Route Table: 0.0.0.0/0 → Internet Gateway
  local rt_out
  rt_out=$(oci network route-table update \
    --rt-id "$default_rt_id" \
    --route-rules "[{\"destination\":\"0.0.0.0/0\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$ig_id\"}]" \
    --force --output json 2>&1) || {
    error "Error al actualizar Route Table — respuesta de OCI:"
    echo "$rt_out"
    exit 1
  }
  ok "Route Table: 0.0.0.0/0 → Internet Gateway"

  # 4. Security List: SSH (22) + ICMP MTU + egress total
  local sl_out
  sl_out=$(oci network security-list update \
    --security-list-id "$default_sl_id" \
    --ingress-security-rules '[{"source":"0.0.0.0/0","protocol":"6","isStateless":false,"tcpOptions":{"destinationPortRange":{"min":22,"max":22}}},{"source":"0.0.0.0/0","protocol":"1","isStateless":false,"icmpOptions":{"type":3,"code":4}}]' \
    --egress-security-rules '[{"destination":"0.0.0.0/0","protocol":"all","isStateless":false}]' \
    --force --output json 2>&1) || {
    error "Error al actualizar Security List — respuesta de OCI:"
    echo "$sl_out"
    exit 1
  }
  ok "Security List: SSH ingress + egress configurados"

  # 5. Subnet pública
  local subnet_raw
  subnet_raw=$(oci network subnet create \
    --compartment-id "$COMPARTMENT_OCID" \
    --vcn-id "$vcn_id" \
    --cidr-block "10.0.0.0/24" \
    --display-name "subnet-public-arm" \
    --dns-label "subnetpublic" \
    --route-table-id "$default_rt_id" \
    --security-list-ids "[\"$default_sl_id\"]" \
    --prohibit-public-ip-on-vnic false \
    --output json 2>&1) || {
    error "Error al crear Subnet — respuesta de OCI:"
    echo "$subnet_raw"
    exit 1
  }

  SUBNET_OCID=$(echo "$subnet_raw" | jq -r '.data.id')
  ok "Subnet creada: subnet-public-arm — red lista."
}

# ---------------------------------------------------------------------------
# Paso 4: SUBNET_OCID (VCN → Subnet)
# ---------------------------------------------------------------------------
get_subnet() {
  header "Paso 4/6 — Subnet"
  info "Consultando VCNs en el compartimento seleccionado..."

  local vcn_raw
  vcn_raw=$(oci network vcn list \
    --compartment-id "$COMPARTMENT_OCID" \
    --all --output json 2>/dev/null)

  local vcn_count
  vcn_count=$(echo "$vcn_raw" | jq '.data | length')

  if [[ "$vcn_count" -eq 0 ]]; then
    warn "No hay VCNs en el compartimento seleccionado. Buscando en toda la cuenta..."

    # Búsqueda recursiva en toda la tenancy
    local all_vcn_raw
    all_vcn_raw=$(oci network vcn list \
      --compartment-id "$TENANCY_OCID" \
      --compartment-id-in-subtree true \
      --all --output json 2>/dev/null)

    local all_vcn_count
    all_vcn_count=$(echo "$all_vcn_raw" | jq '.data | length')

    if [[ "$all_vcn_count" -gt 0 ]]; then
      ok "Se encontraron $all_vcn_count VCN(s) en otros compartimentos."
      vcn_raw="$all_vcn_raw"
      vcn_count="$all_vcn_count"
    else
      warn "No hay VCNs en toda la cuenta."
      local confirm
      read -r -p "    ¿Crear una VCN nueva con conectividad pública? [s/N]: " confirm </dev/tty
      if [[ "$confirm" =~ ^[sS]$ ]]; then
        create_vcn_stack
        return 0
      else
        error "Se necesita una VCN para continuar."
        exit 1
      fi
    fi
  fi

  local VCN_ID
  if [[ "$vcn_count" -eq 1 ]]; then
    VCN_ID=$(echo "$vcn_raw" | jq -r '.data[0].id')
    local vcn_name
    vcn_name=$(echo "$vcn_raw" | jq -r '.data[0]."display-name"')
    ok "VCN detectada: $vcn_name — seleccionada automáticamente."
  else
    local -a vcn_entries=()
    while IFS= read -r line; do
      vcn_entries+=("$line")
    done < <(echo "$vcn_raw" | jq -r '.data[] | "\(."display-name") [\(."cidr-block")] — \(."compartment-id" | split(".") | last | .[0:8])|\(.id)"')
    echo ""
    pick_menu "Elige la VCN:" VCN_ID "${vcn_entries[@]}"
  fi

  # Usar el compartimento de la VCN elegida (puede diferir del seleccionado en paso 3)
  local vcn_compartment_id
  vcn_compartment_id=$(echo "$vcn_raw" | jq -r --arg id "$VCN_ID" '.data[] | select(.id == $id) | ."compartment-id"')

  info "Consultando subnets de la VCN..."
  local subnet_raw
  subnet_raw=$(oci network subnet list \
    --compartment-id "$vcn_compartment_id" \
    --vcn-id "$VCN_ID" \
    --all --output json 2>/dev/null)

  local subnet_count
  subnet_count=$(echo "$subnet_raw" | jq '.data | length')

  if [[ "$subnet_count" -eq 0 ]]; then
    error "No hay subnets en la VCN seleccionada."
    exit 1
  fi

  if [[ "$subnet_count" -eq 1 ]]; then
    SUBNET_OCID=$(echo "$subnet_raw" | jq -r '.data[0].id')
    local subnet_name
    subnet_name=$(echo "$subnet_raw" | jq -r '.data[0]."display-name"')
    ok "Subnet única detectada: $subnet_name — seleccionada automáticamente."
  else
    local -a subnet_entries=()
    while IFS= read -r line; do
      subnet_entries+=("$line")
    done < <(echo "$subnet_raw" | jq -r '.data[] | "\(."display-name") [\(."cidr-block")]|\(.id)"')
    echo ""
    pick_menu "Elige la subnet:" SUBNET_OCID "${subnet_entries[@]}"
  fi
}

# ---------------------------------------------------------------------------
# Paso 5: IMAGE_OCID (lista de imágenes ARM disponibles)
# ---------------------------------------------------------------------------
get_image() {
  header "Paso 5/6 — Imagen del sistema operativo"
  info "Consultando imágenes compatibles con VM.Standard.A1.Flex..."

  local raw
  raw=$(oci compute image list \
    --compartment-id "$TENANCY_OCID" \
    --shape "VM.Standard.A1.Flex" \
    --lifecycle-state AVAILABLE \
    --sort-by TIMECREATED \
    --sort-order DESC \
    --all --output json 2>/dev/null)

  local img_count
  img_count=$(echo "$raw" | jq '.data | length')

  if [[ "$img_count" -eq 0 ]]; then
    error "No se encontraron imágenes ARM disponibles."
    exit 1
  fi

  # Limitar a las 15 más recientes para no saturar la pantalla
  local -a img_entries=()
  while IFS= read -r line; do
    img_entries+=("$line")
  done < <(echo "$raw" | jq -r '.data[:15][] | "\(."display-name")|\(.id)"')

  echo ""
  pick_menu "Elige la imagen:" IMAGE_OCID "${img_entries[@]}"
}

# ---------------------------------------------------------------------------
# Paso 6: SSH_PUBLIC_KEY (input manual desde Bitwarden)
# ---------------------------------------------------------------------------
get_ssh_key() {
  header "Paso 6/6 — Llave SSH Pública"
  echo ""
  info "Abre Bitwarden y copia tu llave SSH pública (la línea que empieza con 'ssh-ed25519' o 'ssh-rsa')."
  echo ""

  local key
  while true; do
    read -r -p "    Pega la llave pública aquí: " key </dev/tty
    if [[ "$key" =~ ^(ssh-|ecdsa-) ]]; then
      SSH_PUBLIC_KEY="$key"
      ok "Llave SSH válida."
      break
    fi
    warn "Formato inválido. Debe empezar con 'ssh-ed25519', 'ssh-rsa', 'ecdsa-', etc."
  done
}

# ---------------------------------------------------------------------------
# Configuración opcional (con defaults)
# ---------------------------------------------------------------------------
get_optional_config() {
  header "Configuración opcional (Enter para usar el valor por defecto)"
  echo ""

  local input

  read -r -p "    Nombre de la instancia [arm-always-free]: " input </dev/tty
  DISPLAY_NAME="${input:-arm-always-free}"

  read -r -p "    URL de notificación al éxito [vacío para omitir]: " input </dev/tty
  NOTIFY_URL="${input:-}"
  if [[ -n "$NOTIFY_URL" && "$NOTIFY_URL" != http* ]]; then
    NOTIFY_URL="https://$NOTIFY_URL"
    warn "Se agregó https:// automáticamente: $NOTIFY_URL"
  fi

  read -r -p "    Cooldown mínimo en segundos [45]: " input </dev/tty
  COOLDOWN_MIN="${input:-45}"

  read -r -p "    Cooldown máximo en segundos [75]: " input </dev/tty
  COOLDOWN_MAX="${input:-75}"
}

# ---------------------------------------------------------------------------
# Escribir .env
# ---------------------------------------------------------------------------
write_env() {
  header "Generando .env"

  cat > "$ENV_FILE" <<EOF
# Generado por setup.sh el $(date '+%Y-%m-%d %H:%M:%S')

# Identidad OCI
TENANCY_OCID="$TENANCY_OCID"
COMPARTMENT_OCID="$COMPARTMENT_OCID"

# Red
SUBNET_OCID="$SUBNET_OCID"

# Availability Domains (separados por espacios)
AVAILABILITY_DOMAINS="$AVAILABILITY_DOMAINS"

# Imagen y Shape
IMAGE_OCID="$IMAGE_OCID"
SHAPE="VM.Standard.A1.Flex"
OCPUS=4
MEMORY_GB=24

# Nombre de la instancia
DISPLAY_NAME="$DISPLAY_NAME"

# Llave SSH pública
SSH_PUBLIC_KEY="$SSH_PUBLIC_KEY"

# Cooldown entre intentos (segundos)
COOLDOWN_MIN=$COOLDOWN_MIN
COOLDOWN_MAX=$COOLDOWN_MAX

# URL de notificación al éxito (vacío para deshabilitar)
NOTIFY_URL="$NOTIFY_URL"
EOF

  chmod 600 "$ENV_FILE"
  ok ".env generado en $ENV_FILE"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}║   OCI ARM Hunter — Configuración inicial     ║${RESET}"
  echo -e "${BOLD}╚══════════════════════════════════════════════╝${RESET}"
  echo ""

  check_prereqs
  get_tenancy
  get_availability_domains
  get_compartment
  get_subnet
  get_image
  get_ssh_key
  get_optional_config
  write_env

  echo ""
  echo -e "${GREEN}${BOLD}¡Configuración completa!${RESET}"
  echo ""
  echo "  Para iniciar el cazador:"
  echo -e "    ${CYAN}make run${RESET}       — primer plano"
  echo -e "    ${CYAN}make run-bg${RESET}    — background (tmux)"
  echo -e "    ${CYAN}make install${RESET}   — servicio systemd (recomendado en VM Micro)"
  echo ""
}

main "$@"
