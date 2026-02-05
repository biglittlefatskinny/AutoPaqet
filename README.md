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
    paqet.exe                # Windows Paqet binary (download from releases)
    auto-paqet.ps1           # Auto-configuration launcher
```

---

## Server Setup (Linux)

### Requirements
- Ubuntu/Debian Linux
- Root/sudo access
- Internet connection for dependencies

### Install (curl, one line)

```bash
curl -fsSL https://raw.githubusercontent.com/biglittlefatskinny/AutoPaqet/main/Server/server_setup.sh | sudo bash
```

### Install (clone and run)

```bash
git clone https://github.com/biglittlefatskinny/AutoPaqet.git
cd AutoPaqet/Server
sudo bash server_setup.sh
```

You will be prompted for port and transport settings. Press Enter to accept defaults.

#### Management Menu

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

#### Getting Your Connection Link

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

Copy this link for your Windows client.

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

This will:
- auto-detect interface/IP/router MAC
- generate config.yaml
- start `paqet.exe` (opens a local SOCKS5 socket and connects to the server)

### Custom Parameters

```powershell
# Custom config and binary paths
.\auto-paqet.ps1 -link "paqet://..." `
  -ConfigPath "C:\custom\path\config.yaml" `
  -PaqetPath "C:\custom\path\paqet.exe"

# Custom SOCKS5 port (local port on your PC)
.\auto-paqet.ps1 -link "paqet://..." -SocksPort 4545
```

### Using the SOCKS5 Proxy

Proxy settings:
- Host: `127.0.0.1`
- Port: `1080` (default) or your custom port

The server script **does not** set the client’s local SOCKS port.  
Each client can choose their own local port with `-SocksPort`.

---

## Notes
- If the client uses Wi-Fi and you see drops, try Ethernet for best stability.
- The paqet:// link contains only server/transport settings, not local interface values.
- The link contains the encryption key. Share it securely.
