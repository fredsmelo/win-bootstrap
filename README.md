# win-bootstrap

PowerShell bootstrap + orchestration + drift detection para devices Windows pessoais. Genérico: clone, fork, ou use os scripts hospedados via `irm | iex`.

Scripts servidos direto do `raw.githubusercontent.com` (sem hosting próprio).

## Layout

```
bootstrap/
├── device.ps1           # bootstrap inicial generico (pubkey via $env:DEVICE_PUBKEY)
├── device-fixkey.ps1    # re-injetar pubkey se sshd quebrou
├── orchestrate-local.ps1 # orquestrador rodando NO proprio device (via setup-device alias)
├── default.ps1          # endpoint placeholder com usage hint
└── lib/                 # scripts idempotentes parametrizados
    ├── inventory.ps1    # snapshot read-only hardware/OS
    ├── setup-tools.ps1  # NuGet + PSWindowsUpdate + Microsoft.WinGet.Client
    ├── fix-ntp.ps1      # W32Time hardening (TLS cert validation, CMOS bat workaround)
    ├── install-ntp-boot-task.ps1   # Scheduled Task: w32tm resync 1min apos boot
    ├── win-update.ps1   # Windows Update via Scheduled Task SYSTEM
    ├── install-apps.ps1 # winget installs (param: -Apps array, hashtables OK)
    ├── tailscale-up.ps1 # install + connect Tailscale (param: -AuthKey)
    ├── touchscreen.ps1  # disable/enable touchscreen (param: -Action)
    ├── power-lid.ps1    # acao do lid AC+DC (param: -OnAC, -OnDC)
    ├── quick-access.ps1 # reseta pinned Quick Access (param: -Paths)
    ├── remove-bloatware.ps1
    ├── harden-taskbar.ps1
    ├── clean-desktop.ps1
    ├── tweaks-qol.ps1
    ├── start-menu.ps1
    ├── install-state-sync-task.ps1   # drift detection per-device (chamado por state-sync-setup.sh)
    └── uninstall-state-sync.ps1
configs/
└── example.conf         # template per-device (gitignored exceto este)
orchestrate.sh           # admin-host driver (SSH-eh os lib scripts em sequencia)
state-sync-setup.sh      # liga drift detection via repo privado GitHub
```

## Bootstrap inicial (fresh-install)

PowerShell admin no Windows:

```powershell
$env:DEVICE_PUBKEY = "ssh-ed25519 AAAA... mydevice"; irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/device.ps1 | iex
```

O que acontece:
1. Habilita OpenSSH Server + firewall TCP 22
2. Injeta `$env:DEVICE_PUBKEY` em `C:\ProgramData\ssh\administrators_authorized_keys`
3. Default shell sshd = PowerShell
4. Instala função `setup-device` no profile (PS 5.1 + PS 7)

Após bootstrap, o device é acessível via SSH com a pubkey correspondente.

## Invocation patterns

**Lib scripts sem args:**

```powershell
irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/inventory.ps1 | iex
irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/setup-tools.ps1 | iex
irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/win-update.ps1 | iex
```

**Lib scripts com params (scriptblock pattern):**

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/install-apps.ps1).Trim())) `
    -Apps @('Microsoft.PowerToys','AgileBits.1Password',
            @{Id='Obsidian.Obsidian'; Silent=$false},
            @{Id='9NKSQGP7F2NH'; Source='msstore'})

& ([scriptblock]::Create((irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/tailscale-up.ps1).Trim())) `
    -AuthKey 'tskey-auth-xxxxxxxxxxxx'
```

## Orquestração — `orchestrate.sh` (admin-host driver)

Setup completo de um device em um comando, do admin host (Mac/Linux com SSH ao device):

```bash
./orchestrate.sh <host>
```

Config per-device em `configs/<host>.conf` (sourced bash):

```bash
APPS='@(...)'                # PS array literal
DISABLE_TOUCHSCREEN=true|false
LID_AC=nothing|sleep|hibernate|shutdown    # opt-in: lid plugado
LID_DC=nothing|sleep|hibernate|shutdown    # opt-in: lid bateria
SKIP_HARDENING=true|false
SKIP_WIN_UPDATE=true|false
SKIP_INSTALL_APPS=true|false
```

Tailscale auth key SEMPRE via env, nunca em config (one-time secret):

```bash
TAILSCALE_AUTH_KEY=tskey-auth-... ./orchestrate.sh <host>
```

`configs/*.conf` são gitignored exceto `example.conf`. Mantenha configs reais num overlay privado (repo separado ou local apenas).

Sequência: inventory → setup-tools → fix-ntp → ntp-boot-task → win-update (aguarda reboot) → install-apps → tailscale-up → touchscreen → remove-bloatware → harden-taskbar → clean-desktop → tweaks-qol → start-menu → inventory final. Todos idempotentes.

## Orquestração local — `setup-device` (no proprio device)

Equivalente do `orchestrate.sh` mas rodando NO device (após bootstrap):

```powershell
setup-device
```

Sem win-update (que pode rebootar e matar a sessão). Pra esse step, separado:

```powershell
irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/win-update.ps1 | iex
```

## Drift detection — `state-sync-setup.sh`

Liga sync diário/boot do estado do device pra um repo privado no GitHub. Mudanças entre runs = git commits (drift visível como diff).

```bash
export STATE_REPO=<owner>/<repo>      # repo privado pro state (ver criado se nao existe)
./state-sync-setup.sh <host>
```

O que monta:
- SSH key dedicada per-device (write deploy key no repo state)
- Scheduled Task `DeviceBootstrap.StateSync` no device (boot+2min + daily 06:00)
- `state-sync.ps1` local que coleta state estruturado e commita só se ha diff
- 1Password backup opcional (`OP_VAULT=<vault>` env var pra habilitar)

State coletado:
- `inventory.md` (human-readable)
- `state.json` (estruturado: OS, hardware, BIOS, TPM, BitLocker, apps via winget, services, scheduled tasks)
- `meta.json` (estavel, sem timestamps)

Revogar a qualquer hora (kill switch):
```bash
gh api repos/$STATE_REPO/keys --jq '.[] | {id,title}'
gh api repos/$STATE_REPO/keys/<id> -X DELETE
```

## Adicionando um novo device

1. **Gerar par SSH dedicado no admin host:**
   ```bash
   ssh-keygen -t ed25519 -N "" -C "<device>" -f ~/.ssh/id_ed25519_<device>
   ```
2. **Backup da chave** (1Password ou outro vault de sua escolha).
3. **Adicionar alias ao `~/.ssh/config`** (LAN + Tailscale opcional).
4. **Bootstrap no device** (fresh-install Windows admin):
   ```powershell
   $env:DEVICE_PUBKEY = "<conteudo de ~/.ssh/id_ed25519_<device>.pub>"; irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/device.ps1 | iex
   ```
5. **(Opcional) Criar `configs/<device>.conf`** (cópia de `example.conf`, mantida local/overlay privado).
6. **Rodar orchestrate.sh** do admin host.
7. **(Opcional) state-sync-setup.sh** pra drift detection.

## Princípios

- **Pubkey por device.** Nada de chave compartilhada.
- **Pubkey via env var, nunca embedded no script público.**
- **Sem usernames hardcoded.** Scripts rodam no contexto da sessão SSH atual.
- **Args mínimos.** Só onde realmente varia per-run (auth keys, listas customizadas).
- **ASCII puro nos PS1.** Sem unicode (em-dash, aspas curvas, emoji).
- **Idempotente.** Rodar N vezes não duplica nem quebra.
- **Public repo, public scripts.** Sem credentials no repo; secrets via env var no momento do uso.
- **Personal configs em overlay privado.** `configs/*.conf` gitignored. Use repo privado separado, ou cópia local.

## Hosting

Sem hosting próprio. Scripts são servidos diretamente pelo raw do GitHub:

```
https://raw.githubusercontent.com/<owner>/<repo>/main/bootstrap/<path>.ps1
```

GitHub raw tem cache curto (~5 min) e rate limit 60 req/hr unauth — suficiente pra uso pessoal/setup de devices.

Para fork: substitua `fredsmelo/win-bootstrap` pelo seu `<owner>/<repo>` nas URLs hardcoded dos scripts (ou sobrescreva via `URL_BASE` env var quando rodando `orchestrate.sh`).
