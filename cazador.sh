#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# cazador.sh — Bucle de reintentos para capturar una VM.Standard.A1.Flex
# en el tier Always Free de Oracle Cloud Infrastructure.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/bin:$PATH"
ENV_FILE="$SCRIPT_DIR/.env"
LOG_FILE="$SCRIPT_DIR/cazador.log"
SSH_KEY_TMP="/tmp/oci_cazador_key.pub"

# ---------------------------------------------------------------------------
# Colores
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"

  case "$level" in
    INFO)  echo -e "${CYAN}[$ts] [INFO]${RESET}  $msg" | tee -a "$LOG_FILE" ;;
    OK)    echo -e "${GREEN}[$ts] [OK]${RESET}    $msg" | tee -a "$LOG_FILE" ;;
    WARN)  echo -e "${YELLOW}[$ts] [WARN]${RESET}  $msg" | tee -a "$LOG_FILE" ;;
    ERROR) echo -e "${RED}[$ts] [ERROR]${RESET} $msg" | tee -a "$LOG_FILE" ;;
  esac
}

# ---------------------------------------------------------------------------
# Cargar y validar .env
# ---------------------------------------------------------------------------
load_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${RED}[ERROR]${RESET} No se encontró el archivo .env en $SCRIPT_DIR"
    echo -e "        Copia .env.example a .env y completa los valores."
    exit 1
  fi

  # shellcheck source=/dev/null
  source "$ENV_FILE"

  local required=(
    TENANCY_OCID COMPARTMENT_OCID SUBNET_OCID
    AVAILABILITY_DOMAINS IMAGE_OCID SHAPE
    OCPUS MEMORY_GB DISPLAY_NAME SSH_PUBLIC_KEY
    COOLDOWN_MIN COOLDOWN_MAX
  )

  local missing=()
  for var in "${required[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RED}[ERROR]${RESET} Faltan variables en .env: ${missing[*]}"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Preparar llave SSH temporal
# ---------------------------------------------------------------------------
prepare_ssh_key() {
  echo "$SSH_PUBLIC_KEY" > "$SSH_KEY_TMP"
  chmod 600 "$SSH_KEY_TMP"
}

# ---------------------------------------------------------------------------
# Notificación al éxito
# ---------------------------------------------------------------------------
notify() {
  local msg="$1"
  if [[ -n "${NOTIFY_URL:-}" ]]; then
    curl -sf --max-time 10 \
      -d "$msg" \
      "$NOTIFY_URL" > /dev/null 2>&1 || true
  fi
}

# ---------------------------------------------------------------------------
# Lanzar instancia en un Availability Domain específico
# Retorna el JSON de la instancia o el mensaje de error
# ---------------------------------------------------------------------------
launch_instance() {
  local ad="$1"
  local cmd=(
    oci compute instance launch
    --compartment-id   "$COMPARTMENT_OCID"
    --availability-domain "$ad"
    --display-name     "$DISPLAY_NAME"
    --image-id         "$IMAGE_OCID"
    --shape            "$SHAPE"
    --shape-config     "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEMORY_GB}"
    --subnet-id        "$SUBNET_OCID"
    --assign-public-ip true
    --ssh-authorized-keys-file "$SSH_KEY_TMP"
  )

  if [[ -n "${BOOT_VOLUME_SIZE_GB:-}" ]]; then
    cmd+=(--boot-volume-size-in-gbs "$BOOT_VOLUME_SIZE_GB")
  fi

  "${cmd[@]}" 2>&1
}

# ---------------------------------------------------------------------------
# Bucle principal
# ---------------------------------------------------------------------------
main() {
  load_env
  prepare_ssh_key

  # Convertir la lista de ADs a un array
  read -ra AD_LIST <<< "$AVAILABILITY_DOMAINS"
  local ad_count=${#AD_LIST[@]}
  local ad_index=0
  local attempt=0

  log INFO "Iniciando cazador — Shape: ${SHAPE} | OCPUs: ${OCPUS} | RAM: ${MEMORY_GB} GB"
  log INFO "Availability Domains disponibles: ${AD_LIST[*]}"
  log INFO "Log persistente en: $LOG_FILE"
  echo ""

  while true; do
    attempt=$((attempt + 1))
    local ad="${AD_LIST[$ad_index]}"
    local ad_short="${ad##*:}"  # solo la parte legible, ej. MX-QUERETARO-1-AD-1

    log INFO "Intento #${attempt} — AD: ${ad_short}"

    local response
    response="$(launch_instance "$ad")" || true

    # --- Caso: éxito ---
    if echo "$response" | grep -q '"lifecycleState"' && \
       echo "$response" | grep -qE '"PROVISIONING"|"RUNNING"'; then

      local instance_id
      instance_id="$(echo "$response" | grep -o '"id": "ocid[^"]*"' | head -1 | cut -d'"' -f4)"
      local public_ip
      public_ip="$(echo "$response" | grep -o '"publicIp": "[^"]*"' | head -1 | cut -d'"' -f4 || echo 'pendiente')"

      echo ""
      log OK "¡INSTANCIA CAZADA! 🎉"
      log OK "  ID:        $instance_id"
      log OK "  AD:        $ad_short"
      log OK "  IP Pública: $public_ip (puede demorar unos minutos en asignarse)"
      log OK "  Conectar:  ssh ubuntu@${public_ip}"

      notify "OCI ARM cazada! ID: $instance_id | IP: $public_ip | AD: $ad_short"
      rm -f "$SSH_KEY_TMP"
      exit 0
    fi

    # --- Caso: sin capacidad ---
    if echo "$response" | grep -qiE "Out of host capacity|Out of capacity|InsufficientServiceCapacity"; then
      log WARN "Sin capacidad en $ad_short — rotando AD y esperando cooldown..."

    # --- Caso: rate limiting ---
    elif echo "$response" | grep -qiE "TooManyRequests|LimitExceeded"; then
      log WARN "Rate limit alcanzado — esperando cooldown extendido..."
      sleep $((COOLDOWN_MAX * 2))
      continue

    # --- Caso: error de autenticación / configuración ---
    elif echo "$response" | grep -qiE "NotAuthenticated|InvalidParameter|NotAuthorized"; then
      log ERROR "Error de autenticación o parámetros inválidos. Revisa .env y la config de oci-cli."
      log ERROR "Respuesta:\n$response"
      rm -f "$SSH_KEY_TMP"
      exit 1

    # --- Caso: excepción de red / request ---
    elif echo "$response" | grep -qi "RequestException"; then
      log WARN "Error de conexión (RequestException) — reintentando..."
      log WARN "Respuesta:\n$response"

    # --- Caso: error desconocido ---
    else
      log WARN "Respuesta inesperada — reintentando..."
      log WARN "Respuesta:\n$response"
    fi

    # Rotar al siguiente AD
    ad_index=$(( (ad_index + 1) % ad_count ))

    # Cooldown con jitter
    local cooldown=$(( COOLDOWN_MIN + RANDOM % (COOLDOWN_MAX - COOLDOWN_MIN + 1) ))
    log INFO "Esperando ${cooldown}s antes del próximo intento..."
    sleep "$cooldown"
  done
}

main "$@"
