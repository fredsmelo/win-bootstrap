#!/usr/bin/env bash
# orchestrate.sh — setup completo de um device Windows via SSH.
#
# Uso:
#   ./orchestrate.sh <ssh-host> [config-file]                       # SEM Tailscale (default)
#   TAILSCALE_AUTH_KEY=tskey-... ./orchestrate.sh <ssh-host>        # COM Tailscale
#   FORCE_TAILSCALE=true ./orchestrate.sh <ssh-host>                # checar status (no install)
#
# Cada step usa scripts hospedados em https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/.
# Idempotente — re-rodar é seguro (lib scripts skipam se já feito).
#
# Config (configs/<host>.conf, opcional):
#   APPS='@("Microsoft.PowerToys", ...)'   # PowerShell array literal
#   DISABLE_TOUCHSCREEN=true|false
#   SKIP_HARDENING=true|false              # default: false
#   SKIP_WIN_UPDATE=true|false             # default: false
#   SKIP_INSTALL_APPS=true|false           # default: false
#
# Tailscale: OPT-IN. Só roda se TAILSCALE_AUTH_KEY for fornecida via env.
# Auth key NUNCA em config file (one-time secret).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HOST="${1:?Usage: $0 <ssh-host> [config-file]}"
CONFIG="${2:-${SCRIPT_DIR}/configs/${HOST}.conf}"

URL_BASE="${URL_BASE:-https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib}"

# Defaults
APPS=""
DISABLE_TOUCHSCREEN=false
SKIP_HARDENING=false
SKIP_WIN_UPDATE=false
SKIP_INSTALL_APPS=false
SKIP_TAILSCALE=false

if [ -f "$CONFIG" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG"
    echo "config: $CONFIG"
else
    echo "config: (nenhum, usando defaults + env vars)"
fi

# ---------- helpers ----------

filter_warnings() {
    grep -v "WARNING\|post-quantum\|store now\|upgraded" || true
}

step() {
    local title="$1"
    echo ""
    echo "================================================================"
    echo "==> $title"
    echo "================================================================"
}

run_remote() {
    local script="$1"
    step "$HOST :: $script"
    ssh -o ConnectTimeout=15 "$HOST" "irm $URL_BASE/$script | iex" 2>&1 | filter_warnings
}

run_remote_with_args() {
    local script="$1"
    local args="$2"
    step "$HOST :: $script"
    ssh -o ConnectTimeout=15 "$HOST" \
        "& ([scriptblock]::Create((irm $URL_BASE/$script).Trim())) $args" 2>&1 | filter_warnings
}

wait_ssh() {
    echo ""
    echo "--- aguardando $HOST voltar (reboot detectado?) ---"
    local tries=0
    until ssh -o ConnectTimeout=5 "$HOST" 'whoami' >/dev/null 2>&1; do
        sleep 15
        tries=$((tries+1))
        echo "$(date +%H:%M:%S) ... ($tries)"
        if [ "$tries" -gt 40 ]; then
            echo "ERRO: 10min sem resposta, abortando." >&2
            exit 1
        fi
    done
    echo "$(date +%H:%M:%S) ONLINE"
}

# ---------- sequence ----------

echo ""
echo "==> ORCHESTRATING $HOST"
echo "    started:  $(date)"

# 1. Inventory (read-only)
run_remote inventory.ps1

# 2. Setup tools
run_remote setup-tools.ps1

# 2b. NTP / W32Time hardening + Scheduled Task pra resync no boot
# Rodar ANTES de installs/WU: se CMOS bat morta, clock errado quebra TLS cert validation.
run_remote fix-ntp.ps1
run_remote install-ntp-boot-task.ps1

# 3. Windows Update (idempotente — exit clean se nada pendente)
if [ "$SKIP_WIN_UPDATE" != "true" ]; then
    run_remote win-update.ps1
    sleep 30
    if ! ssh -o ConnectTimeout=5 "$HOST" 'whoami' >/dev/null 2>&1; then
        wait_ssh
        step "$HOST :: re-checking win-update após reboot"
        run_remote win-update.ps1
    fi
fi

# 4. Install apps (idempotente — SKIP se já instalado)
if [ "$SKIP_INSTALL_APPS" != "true" ] && [ -n "$APPS" ]; then
    run_remote_with_args install-apps.ps1 "-Apps $APPS"
fi

# 5. Tailscale (OPT-IN: só roda se TAILSCALE_AUTH_KEY for fornecida via env)
#    Sem env var, step inteiro pulado — mantém comando "decorável" sem Tailscale.
#    Pra forçar verificação (skip se já conectado, error se não), use FORCE_TAILSCALE=true.
if [ -n "$TAILSCALE_AUTH_KEY" ]; then
    run_remote_with_args tailscale-up.ps1 "-AuthKey '$TAILSCALE_AUTH_KEY'"
elif [ "$FORCE_TAILSCALE" == "true" ]; then
    run_remote tailscale-up.ps1
fi

# 6. Touchscreen disable (per-device)
if [ "$DISABLE_TOUCHSCREEN" == "true" ]; then
    run_remote_with_args touchscreen.ps1 "-Action disable"
fi

# 7. Hardening (idempotente)
if [ "$SKIP_HARDENING" != "true" ]; then
    run_remote remove-bloatware.ps1
    run_remote harden-taskbar.ps1
    run_remote clean-desktop.ps1
    run_remote tweaks-qol.ps1
    run_remote start-menu.ps1
fi

# 8. Final inventory pra confirmar estado
step "$HOST :: inventory final"
run_remote inventory.ps1 | tail -20

echo ""
echo "==> ORCHESTRATION COMPLETE for $HOST"
echo "    finished: $(date)"
echo ""
echo "Pra ligar drift detection (state sync via repo privado, 1x por device):"
echo "  ${SCRIPT_DIR}/state-sync-setup.sh $HOST"
