<#
.SYNOPSIS
  Spotify TV и голосовой мост для Яндекс Станции 1 — установка с Windows.
.DESCRIPTION
  Внутри этого файла уже находится тот же install.sh, что запускается в AliceBridge.
  Он передаётся на Станцию по SSH и выполняется там: Spotify TV скачивает сама колонка,
  с проверкой SHA-256 и сертификата. Нужны root и SSH через AliceBridge и штатный
  OpenSSH Windows. Python, Java, ADB и репозиторий на ПК не нужны.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -Ip <STATION_IP>
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -Ip <STATION_IP> -Command login
#>
[CmdletBinding()]
param(
    [string]$Ip,
    [ValidateRange(1,65535)][int]$Port = 22,
    [string]$Key,
    [string]$BindAddress,
    [ValidateSet('install','login','status','logout','reconnect','repair','repair-app','disable','enable','uninstall')]
    [string]$Command = 'install'
)
$ErrorActionPreference = 'Stop'

function Quote-NativeArgument([string]$Value) {
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}
function Invoke-StationSsh([string]$RemoteCommand, [byte[]]$Payload) {
    $nativeArgs = @($script:sshOptions) + @("root@$Ip", $RemoteCommand)
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:sshPath
    $info.Arguments = (($nativeArgs | ForEach-Object { Quote-NativeArgument $_ }) -join ' ')
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $false
    $info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    # Windows PowerShell 5.1 may prepend a UTF-8 BOM to redirected stdin.
    $previousInputEncoding = [Console]::InputEncoding
    try {
        [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
        [void]$proc.Start()
        $reading = $proc.StandardOutput.ReadToEndAsync()
        if ($Payload) { $proc.StandardInput.BaseStream.Write($Payload, 0, $Payload.Length) }
        $proc.StandardInput.Close()
        $output = $reading.GetAwaiter().GetResult()
        $proc.WaitForExit()
        return @{ Code = $proc.ExitCode; Output = $output }
    } finally { $proc.Dispose(); [Console]::InputEncoding = $previousInputEncoding }
}
function Same-Subnet([string]$A, [string]$B, [int]$Prefix) {
    $left = [Net.IPAddress]::Parse($A).GetAddressBytes()
    $right = [Net.IPAddress]::Parse($B).GetAddressBytes()
    for ($bit = 0; $bit -lt $Prefix; $bit++) {
        $octet = [int][math]::Floor($bit / 8)
        $mask = 1 -shl (7 - ($bit % 8))
        if (($left[$octet] -band $mask) -ne ($right[$octet] -band $mask)) { return $false }
    }
    return $true
}

try {
    Write-Host "`nSpotify для Станции 1`n" -ForegroundColor Green
    if (-not $Ip) { $Ip = (Read-Host 'IP-адрес Станции').Trim() }
    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($Ip, [ref]$parsed) -or $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw 'Нужен корректный IPv4-адрес колонки.' }
    $script:sshPath = (Get-Command ssh.exe -ErrorAction Stop).Source
    if (-not $Key) {
        foreach ($name in @('alice_ed25519', 'id_ed25519', 'id_rsa')) {
            $candidate = Join-Path $env:USERPROFILE ".ssh\$name"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $Key = $candidate; break }
        }
    }
    if ($Key) { $Key = (Resolve-Path -LiteralPath $Key).Path }
    if (-not $BindAddress -and (Get-Command Get-NetIPAddress -ErrorAction SilentlyContinue)) {
        foreach ($adapter in Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue) {
            if ($adapter.IPAddress -notmatch '^(127\.|169\.254\.)' -and (Same-Subnet $adapter.IPAddress $Ip $adapter.PrefixLength)) { $BindAddress = $adapter.IPAddress; break }
        }
    }
    $script:sshOptions = @('-p', "$Port", '-o', 'ConnectTimeout=12', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ServerAliveInterval=15')
    if ($Key) { $script:sshOptions += @('-i', $Key, '-o', 'IdentitiesOnly=yes') }
    if ($BindAddress) { $script:sshOptions += @('-o', "BindAddress=$BindAddress") }
    if (-not $Key) { Write-Host 'Введите пароль root, когда его запросит SSH. Он не сохраняется.' }

    Write-Host 'Проверяю подключение и модель Станции...'
    $preflight = (Invoke-StationSsh 'export ANDROID_DATA=/data ANDROID_ROOT=/system; echo ROOT=$(id -u); echo SDK=$(getprop ro.build.version.sdk); echo DEVICE=$(getprop ro.product.device); test -f /data/dropbear/start.sh && echo ALICEBRIDGE=yes; test -f /data/station1-spotify/install.sh && echo INSTALLED=yes; true' $null).Output
    if ($preflight -notmatch '(?m)^ROOT=0\s*$') { throw 'Нужен SSH-доступ от root.' }
    if ($preflight -notmatch '(?m)^SDK=23\s*$' -or $preflight -notmatch '(?m)^DEVICE=tulip') { throw 'Установщик предназначен для Яндекс Станции 1: tulip, Android 6.0.1.' }
    if ($preflight -notmatch 'ALICEBRIDGE=yes') { throw 'Сначала установите root и SSH через AliceBridge: https://hackalice.me/start/root-android/#station-1' }

    $installer = [Convert]::FromBase64String('__INSTALLER_BASE64__')
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $digest = [BitConverter]::ToString($sha.ComputeHash($installer)).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
    if ($digest -ne '__INSTALLER_SHA256__') { throw 'Встроенный установщик повреждён. Скачайте install.ps1 заново.' }

    $stationArgs = $Command
    if ($Command -eq 'logout') {
        $answer = Read-Host 'Удалить вход Spotify и локальные настройки Spotify на Станции? Введите YES'
        if ($answer -cne 'YES') { Write-Host 'Отменено.'; return }
        $stationArgs = 'logout --yes'
    }
    if ($Command -eq 'install' -or $Command -eq 'repair-app' -or $preflight -notmatch 'INSTALLED=yes') {
        if ($Command -ne 'install' -and $Command -ne 'repair-app') { throw 'Spotify для Станции ещё не установлен. Запустите установку без -Command.' }
        Write-Host 'Передаю установщик и запускаю его на Станции. Загрузка Spotify может занять несколько минут...'
        $remote = 'umask 077; f=/data/local/tmp/install-spotify.sh; cat > $f && [ "$(/sbin/busybox sha256sum $f | /sbin/busybox cut -d '' '' -f 1)" = __INSTALLER_SHA256__ ] && sh $f ' + $stationArgs + '; code=$?; rm -f $f; exit $code'
        $result = Invoke-StationSsh $remote $installer
    } else {
        $result = Invoke-StationSsh ('sh /data/station1-spotify/install.sh ' + $stationArgs) $null
    }
    Write-Host $result.Output
    if ($result.Code -ne 0) { throw "Команда на Станции завершилась с ошибкой $($result.Code)." }
    if ($result.Output -match 'spotify\.com/pair') { Write-Host 'Откройте https://spotify.com/pair и введите код выше.' -ForegroundColor Green }
    Write-Host 'Готово.' -ForegroundColor Green
} catch {
    Write-Host "`nНе удалось выполнить: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
