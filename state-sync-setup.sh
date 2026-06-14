#!/usr/bin/env bash
# state-sync-setup.sh -- liga drift detection num device via repo privado no GitHub.
#
# Uso:
#   STATE_REPO=<owner>/<repo> ./state-sync-setup.sh <hostname>
#
# Ex.:
#   STATE_REPO=myuser/device-state ./state-sync-setup.sh mydevice
#
# Ou exporta STATE_REPO no shell rc (~/.bashrc):
#   export STATE_REPO=<owner>/<repo>
#
# O que faz (idempotente, re-runs sao safe):
#   1. Verifica gh auth (MFA-gated OAuth) + STATE_REPO setado
#   2. Cria repo privado $STATE_REPO se nao existe
#   3. Gera SSH key dedicada por device em ~/.ssh/id_ed25519_<host>_state
#   4. Sobe pubkey como deploy key (write access) via gh api
#   5. SCP private key pro device em C:\ProgramData\device-bootstrap\ssh\
#   6. Roda install-state-sync-task.ps1 no device via SSH (parametrizado por hostname)
#   7. Guarda chave no 1Password vault "Active SSH Keys" (best-effort)
#
# Setup precisa MFA-gated gh CLI. Por isso fica fora do orchestrate.sh
# (que e zero-touch). Roda 1x por device, depois sync e automatico.
#
# Revogar a qualquer hora:
#   gh api repos/$STATE_REPO/keys/<id> -X DELETE
#   (ou github UI -> repo settings -> deploy keys)

set -e

HOST="${1:?Usage: STATE_REPO=<owner>/<repo> $0 <hostname>}"

if [ -z "$STATE_REPO" ]; then
    echo "ERRO: variavel STATE_REPO ausente." >&2
    echo "" >&2
    echo "Setup esperado:" >&2
    echo "  STATE_REPO=<owner>/<repo> $0 $HOST" >&2
    echo "ou exporta no shell rc (~/.bashrc):" >&2
    echo "  export STATE_REPO=<owner>/<repo>" >&2
    exit 1
fi

LIB_URL="${LIB_URL:-https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib}"
KEY="$HOME/.ssh/id_ed25519_${HOST}_state"
REMOTE_KEY_DIR='C:\ProgramData\device-bootstrap\ssh'
REMOTE_KEY_PATH="${REMOTE_KEY_DIR}\\id_${HOST}_state"

echo "==> state-sync-setup for $HOST"
echo "    repo: $STATE_REPO"
echo "    key:  $KEY"
echo ""

# ---- 1. Sanity: gh CLI autenticado ----
echo "[1/7] Verificando gh auth..."
if ! command -v gh >/dev/null 2>&1; then
    echo "ERRO: gh CLI nao instalado. brew install gh" >&2
    exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
    echo "ERRO: gh nao autenticado. Rode: gh auth login" >&2
    exit 1
fi
echo "    OK"

# ---- 2. Garantir repo state existe (privado) ----
echo "[2/7] Verificando repo $STATE_REPO..."
if gh repo view "$STATE_REPO" >/dev/null 2>&1; then
    echo "    ja existe."
else
    echo "    criando repo privado..."
    gh repo create "$STATE_REPO" --private \
        --description "Per-device state snapshots; drift = git diff" \
        --add-readme
fi

# ---- 3. Gerar SSH key dedicada (se nao existe) ----
echo "[3/7] SSH key local em $KEY..."
if [ -f "$KEY" ]; then
    echo "    ja existe (idempotente)."
else
    ssh-keygen -t ed25519 -f "$KEY" -N '' -C "${HOST}-state" -q
    echo "    gerada."
fi
chmod 600 "$KEY"
chmod 644 "$KEY.pub"

# ---- 4. Upload pubkey como deploy key (write access) ----
echo "[4/7] Subindo pubkey como deploy key..."
PUBKEY="$(cat "$KEY.pub")"
KEY_TITLE="${HOST}-state-$(date +%Y-%m-%d)"

EXISTING_KEY_ID="$(gh api "repos/$STATE_REPO/keys" --jq ".[] | select(.key | startswith(\"$(echo "$PUBKEY" | awk '{print $1" "$2}')\")) | .id" 2>/dev/null | head -1)"

if [ -n "$EXISTING_KEY_ID" ]; then
    echo "    pubkey ja registrada (id=$EXISTING_KEY_ID). skip."
else
    gh api "repos/$STATE_REPO/keys" \
        -X POST \
        -f "title=$KEY_TITLE" \
        -f "key=$PUBKEY" \
        -F "read_only=false" >/dev/null
    echo "    OK (title: $KEY_TITLE)"
fi

# ---- 5. SCP private key pro device ----
echo "[5/7] Copiando private key pro device via SCP..."
# Garantir dir remoto. ssh roda powershell por default (config do rbs.ps1).
ssh -o ConnectTimeout=15 "$HOST" "New-Item -ItemType Directory -Path '$REMOTE_KEY_DIR' -Force | Out-Null"
scp -o ConnectTimeout=15 -q "$KEY" "${HOST}:${REMOTE_KEY_PATH}"
echo "    OK ($REMOTE_KEY_PATH)"

# ---- 6. Instalar Scheduled Task no device ----
echo "[6/7] Instalando state-sync no device..."
ssh -o ConnectTimeout=15 "$HOST" \
    "& ([scriptblock]::Create((irm $LIB_URL/install-state-sync-task.ps1).Trim())) -Hostname '$HOST' -StateRepo '$STATE_REPO'"

# ---- 7. 1Password backup (best-effort, opt-in via OP_VAULT env) ----
# Cria SecureNote com notesPlain estruturado (private + public key + paths).
# Categoria "SSH Key" do op CLI nao aceita import de chave existente -- so gera nova.
# Setar OP_VAULT=<nome do vault> pra habilitar; sem ele, skip o backup.
echo "[7/7] 1Password backup..."
if [ -n "$OP_VAULT" ] && command -v op >/dev/null 2>&1 && op vault list 2>/dev/null | grep -q "$OP_VAULT"; then
    OP_TITLE="SSH Key: ${HOST}-state"
    if op item get "$OP_TITLE" --vault "$OP_VAULT" >/dev/null 2>&1; then
        echo "    ja existe no 1P. skip."
    else
        OP_NOTES=$(cat <<EOF
Chave SSH dedicada pro state-sync de ${HOST} (drift detection via ${STATE_REPO}).

PUBLIC KEY:
$(cat "$KEY.pub")

PRIVATE KEY:
$(cat "$KEY")

Caminho no admin host:
  $KEY
  $KEY.pub

Caminho no device:
  ${REMOTE_KEY_PATH}

Deploy key em (write access):
  https://github.com/${STATE_REPO}/settings/keys
  title: ${KEY_TITLE}

Revogar (kill switch):
  gh api repos/${STATE_REPO}/keys --jq '.[] | select(.title=="${KEY_TITLE}") | .id'
  gh api repos/${STATE_REPO}/keys/<id> -X DELETE

Gerada em: $(date +%Y-%m-%d)
EOF
)
        if op item create --category=SecureNote --vault="$OP_VAULT" \
            --title="$OP_TITLE" \
            "notesPlain=$OP_NOTES" >/dev/null 2>&1; then
            echo "    OK"
        else
            echo "    WARN: op create falhou (manual: 1Password app)"
        fi
    fi
elif [ -z "$OP_VAULT" ]; then
    echo "    OP_VAULT nao setado, skip backup 1P (opt-in via 'export OP_VAULT=<vault-name>')."
else
    echo "    op CLI ou vault '$OP_VAULT' indisponivel. Backup manual recomendado:"
    echo "      cat $KEY  # copiar pro 1Password"
fi

echo ""
echo "==> state-sync ATIVO em $HOST"
echo ""
echo "Validar:"
echo "  gh api repos/$STATE_REPO/commits --jq '.[0].commit.message'"
echo "  ssh $HOST 'Get-ScheduledTask DeviceBootstrap.StateSync | Format-List TaskName,State'"
echo "  ssh $HOST 'Get-Content C:\\Users\\Public\\device-bootstrap-state-sync.log -Tail 20'"
echo ""
echo "Revogar (kill switch):"
echo "  gh api repos/$STATE_REPO/keys --jq '.[] | select(.title==\"$KEY_TITLE\") | .id'"
echo "  gh api repos/$STATE_REPO/keys/<id> -X DELETE"
