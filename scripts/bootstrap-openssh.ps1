# Enable OpenSSH Server so the instance accepts SSH logins (password auth, Administrator account)
if (-not (Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*' | Where-Object State -eq 'Installed')) {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
}
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic

if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
}

New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force | Out-Null
