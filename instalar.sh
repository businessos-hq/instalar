#!/usr/bin/env bash
# instalar.sh — el instalador de MateOS 🧉 para CLIENTES (macOS / Linux).
#
# Es el comando que copia y pega el dueño de un negocio, sin saber nada de programación:
#
#   curl -fsSL https://raw.githubusercontent.com/businessos-hq/instalar/main/instalar.sh | bash
#
# y de ahí en adelante todo es guiado, de a un paso por vez:
#
#   1. Las herramientas: git, uv y GitHub CLI (`gh`). Instala lo que falte, de a una.
#   2. Tu cuenta de GitHub: `gh auth login` por el navegador, si no entraste todavía.
#   3. El acceso a MateOS: chequea que ya aceptaste la invitación a la vidriera.
#   4. Tu cerebro: crea TU repo privado desde la plantilla y lo baja a tu compu.
#   5. Instala el comando `mateos` y activa el equipo de agentes (`mateos install`).
#   6. El chat con IA: Claude Code o Codex (opcional; ofrece instalar Claude Code).
#   y al final abre `mateos ui`.
#
# ── instalar.* vs. install.* ─────────────────────────────────────────────────
# `instalar.sh`/`instalar.ps1` = el camino del CLIENTE: arranca de cero, crea su repo desde la
# vidriera y no supone nada. `install.sh`/`install.ps1` = el camino de DESARROLLO y soporte:
# se corre parado adentro de un repo ya clonado y no crea repos. Los dos viajan al cliente
# (`distribucion.yml`); este además vive en el repo PÚBLICO `businessos-hq/instalar`, porque
# la vidriera es privada y un `curl` anónimo a su raw no anda.
#
# ── Reglas del script (no aflojarlas) ────────────────────────────────────────
# - Funciona con `curl … | bash`: el script entero está adentro de `principal` y se llama en
#   la ÚLTIMA línea, así bash lo lee completo antes de ejecutar nada y ningún comando hijo se
#   come el resto del script desde stdin. Las preguntas se leen de /dev/tty, nunca de stdin.
# - Idempotente: re-correrlo salta lo que ya está hecho (herramientas, login, repo, carpeta).
# - Nunca `sudo` sin avisar antes qué se instala y por qué, y sin preguntar.
# - Ante un error: mensaje humano + qué hacer + cómo pedir ayuda. La salida técnica de cada
#   comando va al archivo de registro (LOG), no a la pantalla.
# - Compatible con el bash 3.2 que trae macOS: nada de arrays asociativos ni `${x,,}`.
# - Nada de secretos acá: el login lo hace `gh` con el navegador y guarda él la credencial.
#
# ── Ojo con mover la carpeta ─────────────────────────────────────────────────
# `uv tool install --editable` graba la RUTA ABSOLUTA de la carpeta del cerebro. Si después se
# mueve o renombra, `mateos` se rompe con `ModuleNotFoundError: No module named 'mateos_cli'`
# sin ninguna pista. Por eso el paso 4 pregunta la carpeta ANTES de instalar y lo advierte.
# Arreglo si ya pasó: `uv tool uninstall mateos-cli`, y re-correr este instalador con
# `--carpeta <la nueva>`.
#
# Flags (para soporte; el cliente no necesita ninguna):
#   --vidriera <owner/repo>   La plantilla de la que sale el cerebro (default businessos-hq/mateos).
#   --nombre <nombre>         Nombre del cerebro / de tu repo (default mi-cerebro).
#   --carpeta <ruta>          Dónde queda en tu compu (default ~/MateOS/<nombre>).
#   --sin-ia                  No ofrece instalar Claude Code.
#   --si                      No pregunta nada: acepta todo lo que viene por default.
#   -h, --help                Esta ayuda.
#
# Con `curl … | bash`, las flags van después de `-s --`:
#   curl -fsSL <url>/instalar.sh | bash -s -- --nombre mi-negocio

# shellcheck disable=SC2088,SC2016,SC2024
# SC2088: "~/MateOS/…" va entre comillas A PROPÓSITO (es lo que se le muestra al cliente;
#         `expandir_ruta` lo expande). SC2016: los `bash -c '…' _ "$x"` reciben la ruta como
#         argumento, no interpolada. SC2024: `sudo -v </dev/tty` sólo renueva el permiso.
set -Eeuo pipefail

VIDRIERA_DEFAULT="businessos-hq/mateos"
TOTAL_PASOS=6

principal() {
  VIDRIERA="${MATEOS_VIDRIERA:-$VIDRIERA_DEFAULT}"
  NOMBRE=""
  CARPETA=""
  SIN_IA=0
  SI=0
  PASO_ACTUAL=0
  PASO_TITULO="la preparación"
  SO=""
  DUENIO=""
  TOOL_IA=""
  CARPETA_DEFAULT=0

  leer_flags "$@"
  preparar_pantalla
  preparar_log
  trap 'al_fallar $?' ERR
  trap 'al_cortar' INT

  detectar_so
  chequear_terminal

  bienvenida

  paso 1 "Las herramientas"
  asegurar_git
  asegurar_uv
  asegurar_gh

  paso 2 "Tu cuenta de GitHub"
  asegurar_login

  paso 3 "El acceso a MateOS"
  asegurar_acceso_vidriera

  paso 4 "Tu cerebro"
  elegir_nombre_y_carpeta
  asegurar_repo_propio

  paso 5 "Instalar MateOS"
  detectar_ia
  instalar_mateos

  paso 6 "El chat con IA"
  asegurar_ia

  despedida
}

# ─── Flags ────────────────────────────────────────────────────────────────────

uso() {
  cat <<'EOF'
Instalador de MateOS para macOS y Linux.

Uso:
  curl -fsSL https://raw.githubusercontent.com/businessos-hq/instalar/main/instalar.sh | bash
  curl -fsSL <misma url> | bash -s -- [opciones]
  ./instalar.sh [opciones]

Opciones (para soporte; no hace falta ninguna):
  --vidriera <owner/repo>   Plantilla de la que sale tu cerebro (default businessos-hq/mateos)
  --nombre <nombre>         Nombre de tu cerebro (default mi-cerebro)
  --carpeta <ruta>          Dónde queda en tu compu (default ~/MateOS/<nombre>)
  --sin-ia                  No ofrecer instalar Claude Code
  --si                      No preguntar nada: aceptar todo lo que viene por default
  -h, --help                Esta ayuda
EOF
}

falta_valor() {
  if [ $# -lt 2 ] || [ -z "$2" ]; then
    printf 'A la opción %s le falta el valor (ej: %s algo).\n' "$1" "$1" >&2
    exit 2
  fi
}

leer_flags() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --vidriera)   falta_valor "$@"; VIDRIERA="$2"; shift ;;
      --vidriera=*) VIDRIERA="${1#*=}" ;;
      --nombre)     falta_valor "$@"; NOMBRE="$2"; shift ;;
      --nombre=*)   NOMBRE="${1#*=}" ;;
      --carpeta)    falta_valor "$@"; CARPETA="$2"; shift ;;
      --carpeta=*)  CARPETA="${1#*=}" ;;
      --sin-ia)     SIN_IA=1 ;;
      --si)         SI=1 ;;
      -h|--help)    uso; exit 0 ;;
      *)
        printf 'No conozco la opción "%s". Corré con --help para ver las que hay.\n' "$1" >&2
        exit 2 ;;
    esac
    shift
  done
  if ! printf '%s' "$VIDRIERA" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then
    printf 'La vidriera tiene que tener la forma dueño/repo (me llegó "%s").\n' "$VIDRIERA" >&2
    exit 2
  fi
  if [ -n "$NOMBRE" ] && ! nombre_valido "$NOMBRE"; then
    printf 'El nombre "%s" no sirve: usá minúsculas, números y guiones (ej: mi-cerebro).\n' "$NOMBRE" >&2
    exit 2
  fi
}

# ─── Pantalla ─────────────────────────────────────────────────────────────────

preparar_pantalla() {
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_OK=$'\033[1;32m'; C_ERR=$'\033[1;31m'; C_AVISO=$'\033[1;33m'
    C_PASO=$'\033[1;36m'; C_SUAVE=$'\033[2m'; C_NEG=$'\033[1m'; C_FIN=$'\033[0m'
  else
    C_OK=""; C_ERR=""; C_AVISO=""; C_PASO=""; C_SUAVE=""; C_NEG=""; C_FIN=""
  fi
}

ok()    { printf '  %s✓%s %s\n' "$C_OK" "$C_FIN" "$1"; }
mal()   { printf '  %s✗%s %s\n' "$C_ERR" "$C_FIN" "$1"; }
aviso() { printf '  %s!%s %s\n' "$C_AVISO" "$C_FIN" "$1"; }
info()  { printf '    %s\n' "$1"; }
suave() { printf '    %s%s%s\n' "$C_SUAVE" "$1" "$C_FIN"; }

paso() {
  PASO_ACTUAL="$1"
  PASO_TITULO="$2"
  printf '\n%s── Paso %s de %s · %s ──%s\n\n' "$C_PASO" "$1" "$TOTAL_PASOS" "$2" "$C_FIN"
}

bienvenida() {
  printf '\n%s🧉 Hola. Vamos a instalar MateOS en tu compu.%s\n\n' "$C_NEG" "$C_FIN"
  info "Te voy a ir guiando de a un paso por vez. Son estos $TOTAL_PASOS:"
  printf '\n'
  info "  1. Las herramientas que MateOS necesita (las instalo si faltan)"
  info "  2. Entrar a tu cuenta de GitHub (se abre el navegador)"
  info "  3. Revisar que ya tengas acceso a MateOS"
  info "  4. Crear tu cerebro: una copia privada, sólo tuya"
  info "  5. Instalar MateOS y su equipo de agentes"
  info "  6. El chat con IA (opcional)"
  printf '\n'
  info "Si algo sale mal, podés volver a pegar el mismo comando: lo que ya"
  info "está hecho se saltea y sigue desde donde quedó."
  if [ "$SI" -eq 0 ]; then
    printf '\n'
    esperar_enter "Apretá Enter para empezar (o Ctrl+C para salir)."
  fi
}

# ─── Preguntas (siempre desde /dev/tty: stdin puede ser el propio script) ─────

chequear_terminal() {
  [ "$SI" -eq 1 ] && return 0
  if ! { : </dev/tty; } 2>/dev/null; then
    printf '\nEste instalador te va a hacer algunas preguntas, y no encuentro una\n' >&2
    printf 'terminal donde hacértelas. Abrí la app "Terminal" y pegá el comando ahí.\n\n' >&2
    exit 1
  fi
}

# preguntar <texto> <default> → deja la respuesta en RESPUESTA
preguntar() {
  RESPUESTA=""
  if [ "$SI" -eq 1 ]; then
    RESPUESTA="$2"
    return 0
  fi
  printf '  %s?%s %s %s[%s]%s ' "$C_PASO" "$C_FIN" "$1" "$C_SUAVE" "$2" "$C_FIN" >/dev/tty
  IFS= read -r RESPUESTA </dev/tty || RESPUESTA=""
  [ -z "$RESPUESTA" ] && RESPUESTA="$2"
  return 0
}

# confirmar <texto> → 0 si dice que sí (Enter = sí)
confirmar() {
  local r
  if [ "$SI" -eq 1 ]; then
    return 0
  fi
  while true; do
    printf '  %s?%s %s %s[S/n]%s ' "$C_PASO" "$C_FIN" "$1" "$C_SUAVE" "$C_FIN" >/dev/tty
    IFS= read -r r </dev/tty || r=""
    case "$r" in
      ""|s|S|si|sí|Si|Sí|SI|y|Y|yes) return 0 ;;
      n|N|no|No|NO) return 1 ;;
      *) info "Contestá s (sí) o n (no)." ;;
    esac
  done
}

esperar_enter() {
  [ "$SI" -eq 1 ] && return 0
  printf '  %s→%s %s ' "$C_PASO" "$C_FIN" "$1" >/dev/tty
  IFS= read -r _ </dev/tty || true
}

# ─── Registro y errores ───────────────────────────────────────────────────────

preparar_log() {
  local base="${TMPDIR:-/tmp}"
  LOG="${base%/}/mateos-instalar-$(date +%Y%m%d-%H%M%S).log"
  : >"$LOG" 2>/dev/null || { LOG="/dev/null"; }
  printf 'Instalador de MateOS — %s\n' "$(date)" >>"$LOG"
}

pedir_ayuda() {
  printf '\n'
  info "Si vuelve a fallar, pedí ayuda a quien te pasó MateOS: mandale una"
  info "foto de esta pantalla y este archivo, que tiene el detalle técnico:"
  info "  $LOG"
  printf '\n'
}

# fallar <qué pasó> <qué hacer> — el error con nombre y apellido.
fallar() {
  trap - ERR
  printf '\n'
  mal "$1"
  [ -n "${2:-}" ] && info "$2"
  pedir_ayuda
  exit 1
}

# El error que no anticipamos: nunca un stack trace, siempre qué hacer.
al_fallar() {
  trap - ERR
  printf '\n'
  mal "Algo salió mal en el paso $PASO_ACTUAL ($PASO_TITULO)."
  info "Probá volver a pegar el mismo comando: lo que ya quedó hecho se"
  info "saltea y sigue desde acá."
  pedir_ayuda
  exit "${1:-1}"
}

al_cortar() {
  trap - ERR INT
  printf '\n\n'
  aviso "Cortaste la instalación. No pasa nada: cuando quieras, volvé a pegar"
  info "el mismo comando y sigue desde donde quedó."
  printf '\n'
  exit 130
}

# correr <descripción> <comando…>: corre sin ensuciar la pantalla (todo al LOG) y avisa ✓/✗.
correr() {
  local desc="$1" volver=""
  shift
  # En una terminal se ve "… haciendo X" y la misma línea pasa a ✓/✗; en un log, sólo el final.
  if [ -t 1 ]; then
    printf '  %s…%s %s' "$C_SUAVE" "$C_FIN" "$desc"
    volver=$'\r\033[K'
  fi
  printf '\n$ %s\n' "$*" >>"$LOG"
  if "$@" </dev/null >>"$LOG" 2>&1; then
    printf '%s  %s✓%s %s\n' "$volver" "$C_OK" "$C_FIN" "$desc"
    return 0
  fi
  printf '%s  %s✗%s %s\n' "$volver" "$C_ERR" "$C_FIN" "$desc"
  return 1
}

# ─── El sistema ───────────────────────────────────────────────────────────────

detectar_so() {
  case "$(uname -s 2>/dev/null || echo desconocido)" in
    Darwin) SO="mac" ;;
    Linux)  SO="linux" ;;
    *)
      fallar "Este instalador es para Mac y Linux." \
        "En Windows abrí PowerShell y pegá: irm https://raw.githubusercontent.com/businessos-hq/instalar/main/instalar.ps1 | iex" ;;
  esac
}

sumar_al_path() {
  local d
  for d in "$@"; do
    case ":$PATH:" in
      *":$d:"*) ;;
      *) [ -d "$d" ] && PATH="$d:$PATH" ;;
    esac
  done
  export PATH
}

hay() { command -v "$1" >/dev/null 2>&1; }

# Gestor de paquetes de Linux (vacío si no hay uno que sepamos usar).
gestor_linux() {
  if hay apt-get; then echo apt
  elif hay dnf; then echo dnf
  else echo ""
  fi
}

# instalar_con_sudo <paquete> <para qué>: avisa, pregunta, y recién ahí usa sudo.
instalar_con_sudo() {
  local paquete="$1" para="$2" gestor
  gestor="$(gestor_linux)"
  [ -z "$gestor" ] && return 1
  aviso "Para instalar $paquete necesito permiso de administrador (sudo)."
  info "Es para $para. Te va a pedir la contraseña con la que entrás a la"
  info "compu (mientras la escribís no se ve nada: es normal)."
  confirmar "¿Lo instalo?" || return 1
  if [ "$gestor" = "apt" ]; then
    sudo -v </dev/tty || return 1
    correr "Instalando $paquete" sudo apt-get update -qq || return 1
    correr "Instalando $paquete (sigue)" sudo apt-get install -y "$paquete" || return 1
  else
    sudo -v </dev/tty || return 1
    correr "Instalando $paquete" sudo dnf install -y "$paquete" || return 1
  fi
}

# ─── Paso 1: herramientas ─────────────────────────────────────────────────────

asegurar_git() {
  if git --version >/dev/null 2>&1; then
    ok "git ya está instalado (guarda el historial de tu cerebro)."
    return 0
  fi
  info "Falta git: es el programa que guarda el historial de tu cerebro."
  if [ "$SO" = "mac" ]; then
    xcode-select --install >>"$LOG" 2>&1 || true
    info "Se abrió una ventana de Apple que ofrece instalar las \"herramientas"
    info "de línea de comandos\". Tocá Instalar y esperá a que termine (tarda"
    info "unos minutos)."
    local intento=0
    while ! git --version >/dev/null 2>&1; do
      intento=$((intento + 1))
      if [ "$SI" -eq 1 ] || [ "$intento" -gt 3 ]; then
        fallar "Todavía no encuentro git." \
          "Si tenés Homebrew, probá: brew install git — o bajalo de https://git-scm.com/download/mac y volvé a pegar el comando."
      fi
      esperar_enter "Cuando la instalación termine, apretá Enter."
    done
  else
    instalar_con_sudo git "guardar el historial de tu cerebro" || true
    git --version >/dev/null 2>&1 || fallar "No pude instalar git." \
      "Instalalo desde https://git-scm.com/download/linux y volvé a pegar el comando."
  fi
  ok "git instalado."
}

asegurar_uv() {
  sumar_al_path "$HOME/.local/bin" "$HOME/.cargo/bin"
  if hay uv; then
    ok "uv ya está instalado (instala MateOS sin tocar el resto de tu compu)."
    return 0
  fi
  info "Falta uv: instala MateOS aislado, sin tocar el resto de tu compu."
  correr "Instalando uv (instalador oficial)" \
    bash -c 'set -o pipefail; curl -LsSf https://astral.sh/uv/install.sh | sh' \
    || fallar "No pude instalar uv." "Revisá tu conexión a internet y volvé a pegar el comando."
  sumar_al_path "$HOME/.local/bin" "$HOME/.cargo/bin"
  hay uv || fallar "Se instaló uv pero esta ventana todavía no lo ve." \
    "Cerrá la Terminal, abrí una nueva y volvé a pegar el comando."
  ok "uv instalado."
}

asegurar_gh() {
  sumar_al_path /opt/homebrew/bin /usr/local/bin
  if hay gh; then
    ok "GitHub CLI ya está instalado (conecta tu compu con tu cuenta de GitHub)."
    return 0
  fi
  info "Falta GitHub CLI (gh): conecta tu compu con tu cuenta de GitHub, que"
  info "es donde se guarda tu cerebro."
  if hay brew; then
    correr "Instalando GitHub CLI con Homebrew" brew install gh || true
  elif [ "$SO" = "linux" ]; then
    instalar_con_sudo gh "conectar tu compu con GitHub" || true
  fi
  local intento=0
  while ! hay gh; do
    intento=$((intento + 1))
    if [ "$SI" -eq 1 ] || [ "$intento" -gt 3 ]; then
      fallar "Todavía no encuentro GitHub CLI." \
        "Bajalo de https://cli.github.com, instalalo y volvé a pegar el comando."
    fi
    aviso "No pude instalar GitHub CLI solo."
    info "Bajalo de https://cli.github.com (botón Download), instalalo como"
    info "cualquier programa y volvé a esta ventana."
    esperar_enter "Cuando esté instalado, apretá Enter."
    sumar_al_path /opt/homebrew/bin /usr/local/bin
  done
  ok "GitHub CLI instalado."
}

# ─── Paso 2: login ────────────────────────────────────────────────────────────

asegurar_login() {
  if gh auth status >/dev/null 2>&1; then
    ok "Ya entraste a GitHub."
  else
    if [ "$SI" -eq 1 ]; then
      fallar "No entraste a GitHub todavía." \
        "Corré: gh auth login --web --git-protocol https — y volvé a correr el instalador."
    fi
    info "Ahora entrás a tu cuenta de GitHub. Va a pasar esto:"
    info "  1. Te muestro un código de 8 letras: copialo."
    info "  2. Apretá Enter y se abre el navegador."
    info "  3. Pegá el código y tocá Authorize (Autorizar)."
    printf '\n'
    if ! gh auth login --web --git-protocol https --hostname github.com </dev/tty >/dev/tty 2>&1; then
      fallar "No se pudo completar la entrada a GitHub." \
        "Volvé a pegar el comando y repetí el paso del navegador. Si no tenés cuenta, creala gratis en https://github.com/signup"
    fi
    ok "Entraste a GitHub."
  fi
  correr "Conectando git con tu cuenta" gh auth setup-git \
    || fallar "No pude conectar git con tu cuenta de GitHub." "Volvé a pegar el comando."
  DUENIO="$(gh api user --jq .login 2>>"$LOG" || true)"
  [ -n "$DUENIO" ] || fallar "No pude saber cuál es tu usuario de GitHub." \
    "Revisá tu conexión a internet y volvé a pegar el comando."
  suave "Tu usuario: $DUENIO"
}

# ─── Paso 3: acceso a la vidriera ─────────────────────────────────────────────

asegurar_acceso_vidriera() {
  local dueno_vidriera="${VIDRIERA%%/*}"
  while ! gh api "repos/$VIDRIERA" >>"$LOG" 2>&1; do
    mal "Todavía no tenés acceso a MateOS."
    info "Lo más probable es que no hayas aceptado la invitación. Revisá tu mail"
    info "(buscá \"invited you\" de GitHub) o entrá a:"
    info "  https://github.com/$dueno_vidriera/${VIDRIERA#*/}/invitations"
    info "y tocá Accept invitation (Aceptar)."
    if [ "$SI" -eq 1 ]; then
      fallar "Sin acceso a $VIDRIERA." "Aceptá la invitación y volvé a correr el instalador."
    fi
    esperar_enter "Cuando la aceptes, apretá Enter y pruebo de nuevo."
  done
  ok "Tenés acceso a MateOS."
}

# ─── Paso 4: el repo propio ───────────────────────────────────────────────────

nombre_valido() {
  printf '%s' "$1" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' && [ "${#1}" -le 60 ]
}

expandir_ruta() {
  case "$1" in
    "~")   printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${1#\~/}" ;;
    /*)    printf '%s' "$1" ;;
    *)     printf '%s/%s' "$(pwd)" "$1" ;;
  esac
}

# ¿La carpeta ya es un clon de <dueño>/<nombre>? (para saltar el paso si se re-corre)
es_mi_clon() {
  local url
  [ -d "$1/.git" ] || return 1
  url="$(git -C "$1" remote get-url origin 2>/dev/null || true)"
  case "$url" in
    *"github.com/$DUENIO/$NOMBRE.git"|*"github.com/$DUENIO/$NOMBRE"|*"github.com:$DUENIO/$NOMBRE.git") return 0 ;;
  esac
  return 1
}

carpeta_libre() {
  [ ! -e "$1" ] && return 0
  [ -d "$1" ] && [ -z "$(ls -A "$1" 2>/dev/null)" ]
}

elegir_nombre_y_carpeta() {
  info "Tu cerebro es una copia de MateOS sólo tuya: un repo PRIVADO en tu"
  info "cuenta de GitHub, más una carpeta en esta compu."
  printf '\n'
  while true; do
    if [ -z "$NOMBRE" ]; then
      preguntar "¿Cómo le ponemos? (minúsculas, números y guiones)" "mi-cerebro"
      NOMBRE="$RESPUESTA"
    fi
    if nombre_valido "$NOMBRE"; then
      break
    fi
    mal "\"$NOMBRE\" no sirve: usá sólo minúsculas, números y guiones (ej: mi-negocio)."
    [ "$SI" -eq 1 ] && fallar "Nombre inválido." "Pasá otro con --nombre."
    NOMBRE=""
  done

  while true; do
    if [ -z "$CARPETA" ]; then
      preguntar "¿En qué carpeta lo guardo?" "~/MateOS/$NOMBRE"
      CARPETA="$RESPUESTA"
      [ "$CARPETA" = "~/MateOS/$NOMBRE" ] && CARPETA_DEFAULT=1
    fi
    CARPETA="$(expandir_ruta "$CARPETA")"
    if ! mkdir -p "$(dirname "$CARPETA")" 2>>"$LOG"; then
      mal "No puedo crear carpetas en $(dirname "$CARPETA")."
      [ "$SI" -eq 1 ] && fallar "Carpeta inválida." "Pasá otra con --carpeta."
      info "Elegí otra (por ejemplo ~/MateOS/$NOMBRE)."
      CARPETA=""
      CARPETA_DEFAULT=0
      continue
    fi
    if es_mi_clon "$CARPETA" || carpeta_libre "$CARPETA"; then
      break
    fi
    mal "La carpeta $CARPETA ya existe y tiene otras cosas adentro."
    [ "$SI" -eq 1 ] && fallar "Carpeta ocupada." "Pasá otra con --carpeta."
    info "Elegí otra (por ejemplo ~/MateOS/$NOMBRE-2)."
    CARPETA=""
  done
  aviso "Importante: después de instalar, no muevas ni le cambies el nombre a"
  info "esta carpeta. MateOS se acuerda de dónde está y, si la movés, deja de"
  info "abrir. (Si te pasa, volvé a correr este instalador.)"
}

esperar_repo_listo() {
  # GitHub arma el repo desde la plantilla en segundo plano: unos segundos sin ramas.
  local url="$1" i=0
  while [ "$i" -lt 30 ]; do
    if [ -n "$(git ls-remote --heads "$url" 2>>"$LOG" || true)" ]; then
      return 0
    fi
    i=$((i + 1))
    sleep 2
  done
  return 1
}

asegurar_repo_propio() {
  local url="https://github.com/$DUENIO/$NOMBRE.git"
  if es_mi_clon "$CARPETA"; then
    ok "Tu cerebro ya está en $(ruta_para_mostrar "$CARPETA") (lo dejo como está)."
    chequear_que_es_mateos
    return 0
  fi

  while gh repo view "$DUENIO/$NOMBRE" --json name >>"$LOG" 2>&1; do
    aviso "Ya tenés un repo que se llama \"$NOMBRE\" en tu GitHub."
    if confirmar "¿Es tu cerebro de MateOS y querés usar ése?"; then
      break
    fi
    NOMBRE=""
    while [ -z "$NOMBRE" ] || ! nombre_valido "$NOMBRE"; do
      preguntar "Entonces, ¿qué otro nombre le ponemos?" "mi-cerebro-2"
      NOMBRE="$RESPUESTA"
    done
    url="https://github.com/$DUENIO/$NOMBRE.git"
    # La carpeta por default sigue al nombre nuevo; una elegida a mano se respeta.
    if [ "$CARPETA_DEFAULT" -eq 1 ]; then
      CARPETA="$(expandir_ruta "~/MateOS/$NOMBRE")"
    fi
    if ! carpeta_libre "$CARPETA" && ! es_mi_clon "$CARPETA"; then
      fallar "La carpeta $CARPETA ya existe y tiene otras cosas adentro." \
        "Volvé a pegar el comando y elegí otra carpeta."
    fi
    if es_mi_clon "$CARPETA"; then
      ok "Tu cerebro ya está en $(ruta_para_mostrar "$CARPETA") (lo dejo como está)."
      chequear_que_es_mateos
      return 0
    fi
  done

  if ! gh repo view "$DUENIO/$NOMBRE" --json name >/dev/null 2>&1; then
    correr "Creando tu repo privado \"$NOMBRE\" desde la plantilla" \
      gh repo create "$NOMBRE" --template "$VIDRIERA" --private \
      || fallar "No pude crear tu repo en GitHub." \
           "Revisá que tengas acceso a MateOS (paso 3) y volvé a pegar el comando."
    correr "Esperando que GitHub lo termine de armar" esperar_repo_listo "$url" \
      || fallar "GitHub está tardando en armar tu repo." \
           "Esperá un minuto y volvé a pegar el comando (va a usar el repo que ya se creó)."
  fi

  mkdir -p "$(dirname "$CARPETA")" 2>>"$LOG"
  correr "Bajando tu cerebro a $(ruta_para_mostrar "$CARPETA")" git clone "$url" "$CARPETA" \
    || fallar "No pude bajar tu repo a la compu." "Revisá tu conexión y volvé a pegar el comando."
  chequear_que_es_mateos
  ok "Tu cerebro está listo en $(ruta_para_mostrar "$CARPETA")"
}

chequear_que_es_mateos() {
  if ! grep -q '^name = "mateos-cli"' "$CARPETA/pyproject.toml" 2>/dev/null; then
    fallar "El repo \"$NOMBRE\" no parece un MateOS." \
      "Volvé a correr el instalador y elegí otro nombre para tu cerebro."
  fi
}

# ─── Paso 5: instalar MateOS ──────────────────────────────────────────────────

detectar_ia() {
  if hay claude; then TOOL_IA="claude"
  elif hay codex; then TOOL_IA="codex"
  else TOOL_IA=""
  fi
}

instalar_mateos() {
  correr "Instalando MateOS (la primera vez tarda unos minutos)" \
    bash -c 'cd "$1" && uv tool install --editable ".[completo]" --force' _ "$CARPETA" \
    || fallar "No pude instalar MateOS." \
         "Revisá tu conexión a internet y volvé a pegar el comando."

  local bin
  bin="$(uv tool dir --bin 2>>"$LOG" || true)"
  [ -n "$bin" ] && sumar_al_path "$bin"
  uv tool update-shell >>"$LOG" 2>&1 || true
  hay mateos || fallar "MateOS se instaló, pero esta ventana todavía no lo ve." \
    "Cerrá la Terminal, abrí una nueva y volvé a pegar el comando."

  if (cd "$CARPETA" && mateos verificar --sin-ping) </dev/null >>"$LOG" 2>&1; then
    ok "Revisé tu compu: está todo en orden."
  else
    aviso "Revisé tu compu y hay algo para mirar más adelante (no frena nada)."
  fi

  local args="--tool claude"
  [ "$TOOL_IA" = "codex" ] && args="--tool codex"
  # shellcheck disable=SC2086  # args son palabras fijas, sin espacios
  correr "Activando tu equipo de agentes" \
    bash -c 'cd "$1" && shift && mateos install "$@"' _ "$CARPETA" $args \
    || fallar "No pude activar el equipo de agentes." "Volvé a pegar el comando."
}

# ─── Paso 6: IA ───────────────────────────────────────────────────────────────

asegurar_ia() {
  if [ -n "$TOOL_IA" ]; then
    if [ "$TOOL_IA" = "claude" ]; then
      ok "Ya tenés Claude Code: el chat con IA va a andar."
    else
      ok "Ya tenés Codex: el chat con IA va a andar."
    fi
    return 0
  fi
  if [ "$SIN_IA" -eq 1 ]; then
    suave "Salteado (--sin-ia). El chat con IA se puede sumar cuando quieras."
    return 0
  fi
  info "El chat con IA de MateOS necesita Claude Code (de Anthropic). Sin eso,"
  info "MateOS anda igual: la bienvenida guiada no lo necesita."
  if ! confirmar "¿Instalo Claude Code ahora?"; then
    suave "Dale. Cuando quieras sumarlo: https://claude.ai/download"
    return 0
  fi
  if ! correr "Instalando Claude Code (instalador oficial)" \
      bash -c 'set -o pipefail; curl -fsSL https://claude.ai/install.sh | bash'; then
    aviso "No pude instalar Claude Code. MateOS anda igual; lo podés sumar después"
    info "desde https://claude.ai/download"
    return 0
  fi
  sumar_al_path "$HOME/.local/bin"
  if ! hay claude; then
    aviso "Claude Code quedó instalado; vas a poder usarlo cuando abras una"
    info "Terminal nueva."
    return 0
  fi
  ok "Claude Code instalado."
  info "La primera vez tenés que entrar con tu cuenta de Claude: abrí la"
  info "Terminal, escribí claude y seguí los pasos. Al terminar, escribí /exit."
  if [ "$SI" -eq 0 ] && confirmar "¿Entrás ahora?"; then
    info "Cuando hayas entrado, escribí /exit para volver acá."
    (cd "$CARPETA" && claude) </dev/tty >/dev/tty 2>&1 || true
    ok "Listo con Claude Code."
  fi
}

# ─── Final ────────────────────────────────────────────────────────────────────

# La ruta como la tipearía el cliente: ~/MateOS/mi-cerebro (entre comillas si tiene espacios).
ruta_para_mostrar() {
  local r="$1"
  case "$r" in
    *" "*) printf '"%s"' "$r" ;;
    "$HOME"/*) printf '~/%s' "${r#"$HOME"/}" ;;
    *) printf '%s' "$r" ;;
  esac
}

despedida() {
  PASO_TITULO="el final"
  printf '\n%s── Listo 🧉 ──%s\n\n' "$C_OK" "$C_FIN"
  info "MateOS quedó instalado en: $(ruta_para_mostrar "$CARPETA")"
  printf '\n'
  info "Para abrirlo cualquier día, abrí la Terminal y escribí:"
  printf '\n      %scd %s && mateos ui%s\n\n' "$C_NEG" "$(ruta_para_mostrar "$CARPETA")" "$C_FIN"
  info "(Si en una Terminal nueva no reconoce \"mateos\", cerrala y abrí otra.)"
  printf '\n'
  if confirmar "¿Lo abro ahora?"; then
    info "Se abre en el navegador. Para cerrarlo, volvé acá y apretá Ctrl+C."
    trap - ERR
    cd "$CARPETA"
    if [ "$SI" -eq 1 ]; then
      mateos ui </dev/null || true
    else
      mateos ui </dev/tty || true
    fi
  else
    info "Dale. ¡Que lo disfrutes!"
  fi
}

principal "$@"
