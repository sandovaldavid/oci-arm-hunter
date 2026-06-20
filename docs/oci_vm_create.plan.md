# Plan de Automatización: Cazador de VMs ARM Always Free (Oracle Cloud)

Este repositorio contiene la planificación, estrategia y estructura técnica para automatizar la reserva de instancias **VM.Standard.A1.Flex (Ampere ARM con hasta 4 OCPUs y 24 GB de RAM)** en el tier gratuito de Oracle Cloud Infrastructure (OCI).

Debido a la alta demanda de estos recursos gratuitos, este plano está diseñado para saltarse el error `Out of capacity` mediante peticiones continuas y automatizadas a la API oficial de OCI usando la herramienta nativa `oci-cli`.

## 🏗️ Arquitectura de la Solución

```
[ VM.Standard.E2.1.Micro (Always Free) ]
         │
         ├───► Lee configuración desde .env
         │
         ├───► Usa 'oci-cli' (ya autenticado con API Key de Oracle)
         │
         ├───► Inyecta la Llave SSH Pública (leída del .env, originada en Bitwarden)
         │
         └───► [ Bucle de Reintentos ] ───► Envía petición a la API de Oracle
                                                   │
                       ┌───────────────────────────┴───────────────────────────┐
                       ▼ SI (Recurso disponible)                               ▼ NO (Sin stock)
         [ VM ARM de 24 GB RAM Creada ]                         [ Error: Out of capacity ]
                       │                                                       │
                       ▼                                                       ▼
         (Notificación + log de éxito)                  (Jitter cooldown y rota Availability Domain)
```

## 📋 Fase 1: Prerrequisitos y Configuración de Seguridad

### 1. Gestión de Llaves en Bitwarden (Acceso SSH)

Para garantizar la máxima seguridad y portabilidad, no se generarán ni almacenarán archivos de llave privada (`.key` / `.pem`) expuestos directamente en el disco:

- **Generación:** Crear un registro de tipo _Inicio de Sesión_ o _Nota Segura_ en Bitwarden. Utilizar el generador de llaves SSH integrado seleccionando el algoritmo `Ed25519` (más corto, rápido y moderno que RSA).

- **Llave Pública:** Se copia desde Bitwarden **una sola vez** y se pega en el archivo `.env` del proyecto bajo la variable `SSH_PUBLIC_KEY`. Al ser una llave pública, no es información sensible y puede vivir en texto plano en el archivo de configuración.

- **Llave Privada:** Permanece cifrada en Bitwarden y se consume exclusivamente en memoria mediante el **Bitwarden SSH Agent** al momento de conectar a la VM ya creada.

### 2. OCI-CLI (Autenticación ya configurada)

La autenticación con la API de Oracle está completada. El archivo `~/.oci/config` contiene el perfil activo con las referencias a las llaves de API. No se requiere ningún paso adicional de autenticación para ejecutar el script.

> Si en el futuro se necesita reconfigurar: `oci setup config` y subir la nueva llave pública a _Profile > API Keys_ en la consola web de Oracle.

## 🔧 Fase 2: Archivo de Configuración `.env`

Toda la parametrización del script vive en un único archivo `.env` en la raíz del proyecto. Esto permite cambiar cualquier parámetro (región, shape, imagen, Availability Domain, etc.) sin tocar la lógica del script.

```bash
# .env — NO commitear a git si el repo es público

# Identidad OCI
TENANCY_OCID="ocid1.tenancy.oc1..xxxxxxxxxx"
COMPARTMENT_OCID="ocid1.compartment.oc1..xxxxxxxxxx"

# Red
SUBNET_OCID="ocid1.subnet.oc1..xxxxxxxxxx"

# Availability Domains a rotar (separados por espacio)
# Obtener con: oci iam availability-domain list --query "data[].name" --output table
AVAILABILITY_DOMAINS="xxxx:XX-REGION-1-AD-1 xxxx:XX-REGION-1-AD-2 xxxx:XX-REGION-1-AD-3"

# Imagen y Shape
IMAGE_OCID="ocid1.image.oc1..xxxxxxxxxx"
SHAPE="VM.Standard.A1.Flex"
OCPUS=4
MEMORY_GB=24

# Nombre de la instancia
DISPLAY_NAME="arm-always-free"

# Llave SSH (pública — no sensible)
SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... comentario"

# Comportamiento del bucle
COOLDOWN_MIN=45
COOLDOWN_MAX=75

# Notificación al éxito (opcional — webhook de ntfy.sh, Telegram, etc.)
NOTIFY_URL=""
```

> 💡 **Cómo obtener los OCIDs:** La forma más rápida es simular la creación de la VM ARM desde la interfaz web de Oracle. Antes de confirmar, usar la opción **"Save as CLI Command"** — genera el comando completo con todos los OCIDs ya estructurados.

> ⚠️ Agregar `.env` al `.gitignore` si el repositorio es público o compartido.

## 🔍 Fase 3: Recolección de Metadatos (OCIDs)

| **Recurso** | **Descripción** | **Ubicación en la Consola** |
|---|---|---|
| **Tenancy OCID** | Identificador de tu cuenta general de Oracle. | Perfil (arriba a la derecha) > Tenancy |
| **Compartment OCID** | Compartimento raíz de tu cuenta. | Identity & Security > Compartments |
| **Subnet OCID** | Subred pública de tu Red Virtual (VCN). | Networking > Virtual Cloud Networks > [Tu VCN] |
| **Image OCID** | Identificador del sistema operativo (ej. Ubuntu 22.04 LTS ARM). | Compute > Images (filtrar por arquitectura ARM) |
| **Availability Domains** | Lista de los 3 ADs de tu Home Region. | `oci iam availability-domain list` |

## ⚙️ Fase 4: Lógica Operativa del Script (`cazador.sh`)

El script opera bajo un ciclo lógico persistente con las siguientes mejoras respecto al diseño original:

### Flujo de ejecución

1. **Carga y validación del `.env`:** Al iniciar, el script verifica que todas las variables requeridas estén definidas. Si falta alguna, termina con un mensaje claro antes de entrar al bucle.

2. **Preparación de la llave SSH:** Escribe `$SSH_PUBLIC_KEY` en un archivo temporal (`/tmp/oci_key.pub`) para satisfacer el parámetro `--ssh-authorized-keys-file` de `oci-cli`.

3. **Ciclo de reintentos (`while true`):**
   - Rota entre los Availability Domains definidos en `$AVAILABILITY_DOMAINS` en cada intento.
   - Ejecuta `oci compute instance launch` con `--shape-config` especificando OCPUs y RAM.
   - Captura la respuesta completa (stdout + stderr) en una variable.

4. **Análisis de respuesta:**

   | Caso | Condición detectada | Acción |
   |---|---|---|
   | **Sin capacidad** | Respuesta contiene `Out of capacity` | Espera cooldown con jitter y rota AD |
   | **Rate limiting** | Respuesta contiene `TooManyRequests` | Espera cooldown extendido (×2) |
   | **Error de red** | Comando no retorna JSON válido | Registra en log y reintenta |
   | **Éxito** | Respuesta contiene `"lifecycleState": "PROVISIONING"` | Notifica, registra y termina |

5. **Cooldown con jitter:** El tiempo de espera entre intentos es aleatorio dentro del rango `[COOLDOWN_MIN, COOLDOWN_MAX]` para evitar patrones regulares que puedan generar rate limiting adicional.

6. **Log persistente:** Cada intento queda registrado en `~/cazador.log` con marca de tiempo y AD utilizado.

### Referencia del comando de lanzamiento

```bash
oci compute instance launch \
  --compartment-id "$COMPARTMENT_OCID" \
  --availability-domain "$ad_actual" \
  --display-name "$DISPLAY_NAME" \
  --image-id "$IMAGE_OCID" \
  --shape "$SHAPE" \
  --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEMORY_GB}" \
  --subnet-id "$SUBNET_OCID" \
  --assign-public-ip true \
  --ssh-authorized-keys-file /tmp/oci_key.pub
```

## 🚀 Fase 5: Ejecución Persistente Desatendida (24/7)

El script corre dentro de la **VM.Standard.E2.1.Micro Always Free** existente. Al operar dentro de la propia infraestructura de Oracle tiene latencia mínima hacia la API y no consume recursos del equipo local.

### Opción A: `tmux` / `screen` (arranque rápido)

```bash
tmux new-session -s cazador
bash cazador.sh
# Ctrl+B, D para desconectar manteniendo el proceso vivo
```

### Opción B: Servicio `systemd` (recomendada para producción)

Convierte el script en un servicio que sobrevive reinicios de la VM sin intervención manual:

```ini
# /etc/systemd/system/cazador-arm.service
[Unit]
Description=OCI ARM Instance Hunter
After=network-online.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/oci_instance_creator
ExecStart=/bin/bash /home/ubuntu/oci_instance_creator/cazador.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now cazador-arm
sudo journalctl -fu cazador-arm  # seguir el log en tiempo real
```

## 🔒 Fase 6: Conexión SSH Segura una vez cazada la VM

Una vez que el script detecte disponibilidad y la instancia esté en estado _Running_:

1. Verifica el estado en el panel web: **Compute > Instances**.

2. Abre Bitwarden en tu equipo local y confirma que el **Bitwarden SSH Agent** está activo.

3. Conéctate con el usuario correspondiente a la imagen seleccionada (`ubuntu` para Ubuntu, `opc` para Oracle Linux):

    ```bash
    ssh ubuntu@[ip_publica_instancia]
    ```

4. El agente SSH de Bitwarden firma el handshake usando la llave privada en memoria, sin que esta toque ningún disco en ningún momento.
