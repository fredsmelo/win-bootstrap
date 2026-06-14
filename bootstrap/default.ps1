# Bootstrap remoto -- placeholder.
#
# Use o endpoint generico device.ps1 com pubkey via env var.

$ErrorActionPreference = 'Stop'

Write-Host "==> device-bootstrap" -ForegroundColor Cyan
Write-Host ""
Write-Host "Endpoint generico de bootstrap. Cole sua pubkey antes:" -ForegroundColor Yellow
Write-Host ""
Write-Host '  $env:DEVICE_PUBKEY = "ssh-ed25519 AAAA... mydevice"; irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/device.ps1 | iex' -ForegroundColor DarkGray
Write-Host ""
Write-Host "Fix-key isolado (re-injetar pubkey se sshd quebrou):" -ForegroundColor Yellow
Write-Host '  $env:DEVICE_PUBKEY = "..."; irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/device-fixkey.ps1 | iex' -ForegroundColor DarkGray
Write-Host ""
Write-Host "Orquestrador local (apos bootstrap, re-rodar pipeline completo):" -ForegroundColor Yellow
Write-Host "  irm https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/orchestrate-local.ps1 | iex" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Lib scripts (idempotentes, ver https://raw.githubusercontent.com/fredsmelo/win-bootstrap/main/bootstrap/lib/*):" -ForegroundColor Yellow
Write-Host "  inventory.ps1, setup-tools.ps1, win-update.ps1, install-apps.ps1," -ForegroundColor DarkGray
Write-Host "  fix-ntp.ps1, install-ntp-boot-task.ps1, harden-taskbar.ps1, clean-desktop.ps1," -ForegroundColor DarkGray
Write-Host "  tweaks-qol.ps1, start-menu.ps1, remove-bloatware.ps1, touchscreen.ps1," -ForegroundColor DarkGray
Write-Host "  power-lid.ps1, language-config.ps1, quick-access.ps1, tailscale-up.ps1," -ForegroundColor DarkGray
Write-Host "  install-state-sync-task.ps1, uninstall-state-sync.ps1" -ForegroundColor DarkGray
Write-Host ""
exit 1
