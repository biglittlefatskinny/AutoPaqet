# AutoPaqet

Easy-to-use setup scripts for deploying Paqet server and client with automated configuration.

## What is AutoPaqet?

AutoPaqet provides:
- **Server Setup Script** (Linux) - Interactive menu-based installation with pre-configured profiles
- **Client Launcher Script** (Windows) - Automatic network detection and configuration from paqet:// links

## Folder Structure

```
AutoPaqet/
  README.md
  Server/
    server_setup.sh          # Interactive server installer
  Client/
    paqet.exe                # Windows Paqet binary
    auto-paqet.ps1           # Auto-configuration launcher
```

---

## Server Setup (Linux)

### Requirements
- Ubuntu/Debian Linux (tested on Ubuntu 24)
- Root/sudo access
- Internet connection for dependencies

### Installation

```bash
cd AutoPaqet/Server
sudo bash server_setup.sh
```

### Features

#### ?? Profile-Based Setup
Choose from 4 optimized profiles or customize everything:

| Profile | Use Case | KCP Mode | Connections | Best For |
|---------|----------|----------|-------------|----------|
| **Balanced** | General use | fast | 1 | Default choice |
| **Low Latency** | Gaming/Real-time | fast3 | 4 | Gaming, video calls |
| **High Throughput** | Downloads | normal | 8 | Bulk transfers |
| **Conservative** | Unstable networks | normal | 2 | High packet loss |
| **Custom** | Full control | Your choice | Your choice | Advanced users |

#### ?? Interactive Setup Flow

```bash
Step 1/5: Choose Configuration Profile
  ? Select a profile or go custom

Step 2/5: Network Configuration  
  ? Choose port (443/HTTPS recommended)

Step 3/5: Logging Configuration
  ? Select log level (info recommended)

Step 4/5: Advanced KCP Configuration (if Custom or modifying profile)
  ? KCP mode, cipher, connections, MTU, windows

Step 5/5: TCP Flags Configuration
  ? Pre-configured options or custom
```

#### ??? Management Menu

After installation, run the script again to access:

```
============================================
      PAQET MANAGER MENU
============================================
Status: RUNNING

1)  Start Service
2)  Stop Service
3)  Restart Service
4)  Show KCP Key & Link
5)  View Live Logs
6)  Show System Info
7)  Reconfigure Server
8)  Backup Configuration
9)  Restore Configuration
10) Uninstall Paqet
0)  Exit
```

#### ?? Configuration Management
- **Automatic backups** on installation and configuration changes
- **Restore from previous configs** via menu
- **Reconfigure without reinstalling** to update settings
- Backups stored in `/etc/paqet/backups/`

#### ?? Getting Your Connection Link

Option 4 in the menu displays:
```
================================================
CURRENT CONFIGURATION
================================================
KCP Key:      <your-key>
Server IP:    <your-ip>
Port:         443
KCP Mode:     fast
Cipher:       aes
------------------------------------------------
PAQET LINK:
paqet://<base64-encoded-config>
================================================
```

Copy this link for your Windows client!

### Port Selection

The script offers common ports with descriptions:
- **443 (HTTPS)** - Recommended, looks like HTTPS traffic
- **8443** - Alternative HTTPS port
- **80 (HTTP)** - HTTP traffic disguise
- **22 (SSH)** - SSH traffic disguise
- **Custom** - Any port 1-65535

### Profile Settings Explained

#### Balanced (Default)
```
KCP Mode: fast
Connections: 1
MTU: 1350
Windows: 1024/1024
Best for: General internet use, browsing, streaming
```

#### Low Latency (Gaming)
```
KCP Mode: fast3
Connections: 4
MTU: 1400
Windows: 2048/2048
Best for: Gaming, video calls, real-time applications
```

#### High Throughput (Downloads)
```
KCP Mode: normal
Connections: 8
MTU: 1400
Windows: 4096/4096
Best for: Large file downloads, bulk data transfer
```

#### Conservative (Unstable Network)
```
KCP Mode: normal
Connections: 2
MTU: 1200
Windows: 512/512
Best for: High packet loss, unstable connections, mobile networks
```

### Modifying Profile Settings

After selecting a profile, you can review and modify its settings:

```bash
? Profile 'Conservative (Unstable Network)' loaded

Profile Settings:
  KCP Mode:       normal
  Cipher:         aes
  Connections:    2
  MTU:            1200

Do you want to modify any of these settings? [y/N]: y

# Then configure only what you want to change
```

### System Service

The script creates a systemd service at `/etc/systemd/system/paqet.service`:

```bash
# Check status
systemctl status paqet

# View logs
journalctl -u paqet -f

# Start/stop/restart
systemctl start paqet
systemctl stop paqet
systemctl restart paqet
```

### Configuration Files

- **Config**: `/etc/paqet/config.yaml`
- **Binary**: `/usr/local/bin/paqet`
- **Service**: `/etc/systemd/system/paqet.service`
- **Backups**: `/etc/paqet/backups/config_YYYYMMDD_HHMMSS.yaml`

---

## Client Setup (Windows)

### Requirements

1. **Npcap** installed in WinPcap-compatible mode
   - Download: https://npcap.com/#download
   - During installation: Check "WinPcap API-compatible Mode"

2. **PowerShell** running as **Administrator**

3. **paqet.exe** for Windows
   - Download from: https://github.com/hanselime/paqet/releases
   - Place in `AutoPaqet/Client/` folder

### Quick Start

```powershell
cd AutoPaqet\Client
.\auto-paqet.ps1 -link "paqet://<your-link-from-server>"
```

### What It Does

The script automatically:
1. ? Detects active network interface
2. ? Finds your IPv4 address
3. ? Discovers router MAC address
4. ? Decodes the paqet:// link
5. ? Generates config.yaml
6. ? Starts paqet.exe with SOCKS5 proxy

### Output Example

```
[INFO] Detected Interface: Ethernet 2
[INFO] Detected IPv4: 192.168.1.100
[INFO] Detected Router MAC: aa:bb:cc:dd:ee:ff
[INFO] Server: 203.0.113.10:443
[INFO] KCP Mode: fast
[INFO] KCP Block: aes
[INFO] KCP Key: 7331ec...
[INFO] TCP Flags: PA / PA
[INFO] Wrote config to .\config.yaml
2026/02/05 14:30:00 Client started, SOCKS5 listening on 127.0.0.1:1080
```

### Custom Parameters

```powershell
# Custom config and binary paths
.\auto-paqet.ps1 -link "paqet://..." `
  -ConfigPath "C:\custom\path\config.yaml" `
  -PaqetPath "C:\custom\path\paqet.exe"

# Default values if not specified:
# -ConfigPath: .\config.yaml
# -PaqetPath: .\paqet.exe
```

### Using the SOCKS5 Proxy

Once connected, configure your applications:
- **Proxy type**: SOCKS5
- **Host**: 127.0.0.1
- **Port**: 1080 (default, configurable via server link)

**Browser Setup (Firefox example)**:
1. Settings ? General ? Network Settings
2. Manual proxy configuration
3. SOCKS Host: `127.0.0.1`, Port: `1080`
4. Select "SOCKS v5"

**System-wide (Windows)**:
```powershell
# Set system proxy
netsh winhttp set proxy proxy-server="socks=127.0.0.1:1080"

# Remove system proxy
netsh winhttp reset proxy
```

### Troubleshooting

#### "Router MAC not detected"
Run PowerShell as Administrator:
```powershell
Start-Process powershell -Verb runAs
```

#### "No active network interface found"
- Ensure you're connected to a network (Ethernet or Wi-Fi)
- Check: `Get-NetIPConfiguration`

#### "Failed to load configuration: invalid TCP flag"
This is fixed in the updated script. Make sure you're using the latest version from this package.

#### Connection issues
- **Wi-Fi**: May experience packet loss, try Ethernet if possible
- **Firewall**: Ensure Windows Firewall allows paqet.exe
- **Antivirus**: May block raw packet access, add exception for paqet.exe

### Generated Config Location

By default: `AutoPaqet\Client\config.yaml`

Example structure:
```yaml
role: "client"
network:
  interface: Ethernet 2
  guid: \Device\NPF_{GUID}
  ipv4:
    addr: 192.168.1.100:0
    router_mac: aa:bb:cc:dd:ee:ff
  tcp:
    local_flag:
      - PA
    remote_flag:
      - PA
transport:
  protocol: kcp
  conn: 1
  kcp:
    mode: fast
    mtu: 1350
    key: <server-key>
server:
  addr: 203.0.113.10:443
socks5:
  - listen: 127.0.0.1:1080
```

---

## Understanding paqet:// Links

The paqet:// link is a base64-encoded JSON containing:

```json
{
  "v": 1,
  "server": {"addr": "server-ip:port"},
  "transport": {
    "protocol": "kcp",
    "conn": 2,
    "kcp": {
      "mode": "fast",
      "mtu": 1350,
      "rcvwnd": 1024,
      "sndwnd": 1024,
      "block": "aes",
      "key": "encryption-key"
    }
  },
  "tcp": {
    "local_flag": ["PA"],
    "remote_flag": ["PA"]
  }
}
```

**Security Note**: This link contains the encryption key. Share securely!

---

## Advanced Usage

### Multiple Profiles on One Server

You can have multiple configurations:

```bash
# Reconfigure for different use case
sudo bash server_setup.sh
# ? Select option 7: Reconfigure Server
# ? Choose new profile
```

Old configurations are automatically backed up.

### Client on Multiple Machines

Use the same paqet:// link on multiple Windows clients. Each will:
- Auto-detect its own network interface
- Use its own router MAC address
- Connect to the same server

### Custom TCP Flags

TCP flags affect how traffic appears to DPI systems:

- **PA (Push-Ack)**: Most common, looks like normal data
- **S (Syn)**: Looks like connection attempts
- **SA (Syn-Ack)**: Looks like connection responses
- **Combinations**: PA,S or PA,SA for mixed traffic patterns

The server script offers pre-configured combinations or custom options.

---

## Performance Tips

### Server Side
- **Use fast3 for gaming**: Lowest latency, best for real-time
- **Use normal for downloads**: Better error correction
- **Higher connections**: More parallel streams (4-8 for throughput)
- **Lower MTU**: Better for unstable networks (1200 vs 1400)

### Client Side
- **Ethernet > Wi-Fi**: Raw packets work better on wired
- **Administrator rights**: Required for packet capture
- **Close other packet tools**: Only one raw socket at a time
- **Check logs**: `journalctl -u paqet -f` on server, console on client

### Network Considerations
- **Port 443**: Best for bypassing restrictions (HTTPS traffic)
- **Low loss networks**: Use fast/fast2/fast3 modes
- **High loss networks**: Use normal mode with lower windows

---

## Troubleshooting

### Server

**Service won't start:**
```bash
# Check service status
systemctl status paqet

# View detailed logs
journalctl -u paqet -n 50

# Check config syntax
/usr/local/bin/paqet run -c /etc/paqet/config.yaml --dry-run
```

**Port already in use:**
```bash
# Check what's using the port
sudo lsof -i :443

# Reconfigure to use different port
sudo bash server_setup.sh  # Option 7: Reconfigure
```

**Network detection failed:**
```bash
# Manual check
ip route show default
ip addr show

# Verify interface is up
ip link show
```

### Client

**"This script must be run with administrator privileges"**
- Right-click PowerShell ? Run as Administrator

**"Npcap not found"**
- Install Npcap from https://npcap.com/#download
- Enable WinPcap-compatible mode during installation

**Connection timeout:**
- Verify server is running: `systemctl status paqet`
- Check firewall allows traffic on server port
- Verify paqet:// link is correct
- Test basic connectivity: `ping <server-ip>`

**High latency/packet loss:**
- Try Conservative profile on server
- Use Ethernet instead of Wi-Fi on client
- Lower MTU value (1200 instead of 1400)
- Check `KCP_MODE`: use `normal` for unstable connections

---

## Security Considerations

1. **Keep your paqet:// link private** - It contains the encryption key
2. **Use strong encryption** - Default `aes` is good, `aes-128-gcm` is better
3. **Change ports periodically** - Use reconfigure feature
4. **Monitor logs** - Check for unusual connection patterns
5. **Backup configs** - Use built-in backup feature before changes

---

## Uninstalling

### Server
```bash
sudo bash server_setup.sh
# ? Select option 10: Uninstall Paqet
# ? Optionally preserve configurations
```

### Client
Simply stop the PowerShell process (Ctrl+C) and delete files:
```powershell
# Stop client
Ctrl+C

# Remove files (optional)
Remove-Item config.yaml
Remove-Item paqet.exe
```

---

## Version History

### v2.0 (Latest)
- ? Profile-based server setup (Balanced, Low Latency, High Throughput, Conservative)
- ? Menu-based selection (no more typing parameters)
- ? Configuration backup and restore
- ? Reconfigure without reinstalling
- ? Show system info and status
- ? Option to modify profile settings
- ?? Fixed client TCP flags YAML formatting issue
- ?? Improved documentation and user guidance

### v1.0
- Initial release with manual parameter input
- Basic server and client scripts

---

## Support & Resources

- **Paqet Project**: https://github.com/hanselime/paqet
- **Releases**: https://github.com/hanselime/paqet/releases
- **Npcap**: https://npcap.com/
- **Issues**: Report problems on the GitHub repository

---

## License

This project follows the same license as the main Paqet project. See the repository for details.

---

## Contributing

Improvements and bug fixes welcome! Please test thoroughly before submitting changes, especially:
- Different Linux distributions
- Various network configurations
- Edge cases in network detection

---

**Note**: Paqet uses raw packet sockets which requires elevated privileges. Always understand the security implications of running network tools with admin/root access.