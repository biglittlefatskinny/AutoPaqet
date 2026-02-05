param(
  [Parameter(Mandatory = $true)]
  [string]$Link,
  [string]$ConfigPath = ".\\config.yaml",
  [string]$PaqetPath = ".\\paqet.exe"
)

function Write-Info($Message) {
  Write-Host "[INFO] $Message"
}

function Decode-PaqetLink($LinkValue) {
  $value = $LinkValue
  if ($value.StartsWith("paqet://")) {
    $value = $value.Substring(8)
  }
  $value = $value.Replace("-", "+").Replace("_", "/")
  switch ($value.Length % 4) {
    2 { $value += "==" }
    3 { $value += "=" }
  }

  $bytes = [Convert]::FromBase64String($value)
  $json = [Text.Encoding]::UTF8.GetString($bytes)
  return $json | ConvertFrom-Json
}

function Get-NetworkInfo {
  $cfg = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq "Up" } | Select-Object -First 1
  if (-not $cfg) {
    throw "No active network interface found."
  }

  $iface = $cfg.InterfaceAlias
  $gateway = $cfg.IPv4DefaultGateway.NextHop
  $guid = (Get-NetAdapter -Name $iface | Select-Object -ExpandProperty InterfaceGuid)
  $ipv4 = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias $iface | Where-Object { $_.IPAddress -and $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1 -ExpandProperty IPAddress)

  $routerMac = (Get-NetNeighbor -IPAddress $gateway -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty LinkLayerAddress)
  if (-not $routerMac) {
    ping -n 1 $gateway | Out-Null
    $routerMac = (Get-NetNeighbor -IPAddress $gateway -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty LinkLayerAddress)
  }
  if (-not $routerMac) {
    $line = (arp -a | Select-String $gateway | Select-Object -First 1).ToString()
    if ($line) {
      $routerMac = ($line -split "\s+")[2]
    }
  }

  if (-not $routerMac) {
    throw "Router MAC not detected. Run PowerShell as Administrator."
  }

  $guidClean = ($guid.ToString().Trim("{}"))
  return [pscustomobject]@{
    Interface = $iface
    Guid = $guidClean
    IPv4 = $ipv4
    RouterMac = ($routerMac -replace "-", ":").ToLower()
    Gateway = $gateway
  }
}

function Ensure-Path($PathValue) {
  $dir = Split-Path -Parent $PathValue
  if ($dir -and -not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir | Out-Null
  }
}

function Format-FlagsYaml($Flags, $Indent = "    ") {
  if ($null -eq $Flags) { 
    return "${Indent}- PA"
  }
  if ($Flags -is [string]) { 
    return "${Indent}- $Flags"
  }
  return ($Flags | ForEach-Object { "${Indent}- $_" }) -join "`n"
}

function Join-Flags($Flags) {
  if ($null -eq $Flags) { return "PA" }
  if ($Flags -is [string]) { return $Flags }
  return ($Flags -join ",")
}

if (-not (Test-Path $PaqetPath)) {
  throw "paqet.exe not found at $PaqetPath"
}

$payload = Decode-PaqetLink $Link
$net = Get-NetworkInfo

$serverAddr = $payload.server.addr
$kcp = $payload.transport.kcp
$kcpMode = $kcp.mode
$kcpBlock = $kcp.block
$kcpKey = $kcp.key
$kcpConn = $payload.transport.conn
$kcpMtu = $kcp.mtu
$kcpRcvwnd = $kcp.rcvwnd
$kcpSndwnd = $kcp.sndwnd
$tcpLocal = Join-Flags $payload.tcp.local_flag
$tcpRemote = Join-Flags $payload.tcp.remote_flag

# Generate YAML flag lists
$tcpLocalYaml = Format-FlagsYaml $payload.tcp.local_flag
$tcpRemoteYaml = Format-FlagsYaml $payload.tcp.remote_flag

Write-Info "Detected Interface: $($net.Interface)"
Write-Info "Detected IPv4: $($net.IPv4)"
Write-Info "Detected Router MAC: $($net.RouterMac)"
Write-Info "Server: $serverAddr"
Write-Info "KCP Mode: $kcpMode"
Write-Info "KCP Block: $kcpBlock"
Write-Info "KCP Key: $kcpKey"
Write-Info "TCP Flags: $tcpLocal / $tcpRemote"

$socks5 = $payload.socks5
if (-not $socks5) {
  $socks5 = @(@{ listen = "127.0.0.1:1080"; username = ""; password = "" })
}

$guidPath = "\Device\NPF_{$($net.Guid)}"

Ensure-Path $ConfigPath

$socksYaml = ($socks5 | ForEach-Object {
  @"
  - listen: $($_.listen)
    username: "$($_.username)"
    password: "$($_.password)"
"@
}) -join ""

$config = @"
role: "client"
log:
  level: info
network:
  interface: $($net.Interface)
  guid: $guidPath
  ipv4:
    addr: $($net.IPv4):0
    router_mac: $($net.RouterMac)
  tcp:
    local_flag:
$tcpLocalYaml
    remote_flag:
$tcpRemoteYaml
  pcap:
    sockbuf: 4194304
transport:
  protocol: kcp
  conn: $kcpConn
  kcp:
    mode: $kcpMode
    mtu: $kcpMtu
    rcvwnd: $kcpRcvwnd
    sndwnd: $kcpSndwnd
    block: $kcpBlock
    key: $kcpKey
server:
  addr: $serverAddr
socks5:
$socksYaml
"@

$config | Set-Content -Path $ConfigPath -Encoding ASCII
Write-Info "Wrote config to $ConfigPath"

& $PaqetPath run -c $ConfigPath