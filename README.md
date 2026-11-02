
```markdown
# 🛡️ Bitter APT - Bangladesh Campaign Emulation Range

> **⚠️ AUTHORIZED LAB USE ONLY:** This project executes real Tactics, Techniques, and Procedures (TTPs) including LSASS memory dumping, registry modification, and scheduled task creation. It must **only** be used in an isolated, dedicated lab environment with explicit authorization. Never run this in a production network or against unauthorized targets.

A realistic, real-time emulation range of the **Bitter APT** (also known as T-APT-17, APT-C-08, or Hazy Tiger) kill chain targeting **Bangladesh** — specifically the **Rapid Action Battalion (RAB)** unit of the Bangladesh Police. 

Based on threat intelligence from **Cisco Talos (May 2022)**, this range emulates the August 2021+ campaign utilizing the **ZxxZ Trojan**, Equation Editor exploits (CVE-2017-11882), and spoofed Pakistani government senders.

## 📑 Table of Contents
1. [Architecture](#️-architecture)
2. [Prerequisites](#-prerequisites)
3. [Deployment Guide](#-deployment-guide)
   - [Step 1: Setup the Server](#step-1-setup-the-server)
   - [Step 2: Deploy the Agent](#step-2-deploy-the-agent)
4. [Tools Tutorial (Web UI)](#️-tools-tutorial-web-ui)
   - [Target Workstation Panel](#1-target-workstation-panel-right-side)
   - [Emulation Control Panel](#2-emulation-control-panel-left--center)
   - [Wazuh Detection Center (SOC)](#3-wazuh-detection-center-bottom)
5. [Campaign Stages & TTPs](#-campaign-stages--ttps)
6. [Indicators of Compromise (IOCs)](#️-indicators-of-compromise-iocs)
7. [Troubleshooting](#️-troubleshooting)
8. [References](#-references)

---

## 🏗️ Architecture

This project is **Docker-free** and runs natively on Windows. It consists of two main components:
*   **Server (Node.js/Express):** Runs on a centralized Windows host. Provides the web UI, manages emulation stages, and ingests telemetry. It uses the built-in `node:sqlite` module so no C++ build tools are required.
*   **Agent (Python):** Deployed to target Windows workstations. Polls the server for jobs, executes the real TTPs locally, and returns the output and telemetry.

---

## 📋 Prerequisites

*   **Host Machine (Server):** Windows 10/11 or Windows Server.
    *   **Node.js v23.4.0 or newer** (Required for the built-in `node:sqlite` module). 
        *   Install via winget: `winget install --id OpenJS.NodeJS.LTS -e`
*   **Target Machine (Agent):** Windows 10/11.
    *   **Python 3.10+** (Required to run the agent).
        *   Install via winget: `winget install --id Python.Python.3.12 -e`
    *   *(Optional but recommended)* Sysmon and Wazuh Agent installed for full telemetry capture.

---

## 🚀 Deployment Guide

### Step 1: Setup the Server
1. Download or clone this repository to your host machine.
2. Open an **Elevated PowerShell** (Run as Administrator) and navigate to the folder containing `bitterbitter.ps1`.
3. Run the installer script:
   ```powershell
   .\bitterbitter.ps1
   ```
   *This script will create a `bitter-cyberrange` folder, install all Node.js dependencies, and generate all necessary files.*
4. Navigate into the newly created folder and start the server:
   ```powershell
   cd .\bitter-cyberrange
   .\start.ps1
   ```
5. The server will automatically open your browser to `http://localhost:8000`. 
   *   **Default Login:** `admin`
   *   **Default Password:** `admin`

### Step 2: Deploy the Agent
1. Copy the entire `agent` folder from the server machine to your target Windows workstation.
2. On the target workstation, open an **Elevated Command Prompt** (Run as Administrator for full realism).
3. Run the installer:
   ```cmd
   agent\install-agent.bat
   ```
4. Configure the Agent connection:
   *   If the server is on a different machine, open `agent\.env.agent` and set `GB_SERVER=http://<YOUR_SERVER_IP>:8000`.
5. Start the agent:
   ```cmd
   agent\start-agent.bat
   ```
   *The agent will present a menu of all local IP addresses on that machine.* **Select the exact IP** that you plan to discover and manage in the web UI. The agent will now register with the server and begin polling for jobs.

---

## 🖥️ Tools Tutorial (Web UI)

The web interface is divided into three main sections designed for a complete Red vs. Blue team exercise. 

### 1. Target Workstation Panel (Right Side)
This is where you manage your victims and network discovery.
*   **DISCOVER:** Click this to scan your network. The backend uses ICMP (ping), TCP (ports 445, 135, 3389), and ARP to find hosts, even if they block pings. Leave the subnet box empty to scan all local adapters.
*   **+ Register:** When the discovery list populates, find the IP of your agent machine and click **+ Register**. This adds it to your database.
*   **Select Workstation:** Choose your registered agent from this dropdown. The UI will update to show its OS, IP, Wazuh status, and Agent Connection status.
*   **IP Menu:** The `start-agent.bat` script on the victim machine will show a menu of IPs. Make sure the IP you select there matches the one you registered here.

### 2. Emulation Control Panel (Left & Center)
This is where you launch the attacks.
*   **Campaign Stages (Left):** Click any of the 8 stages (01 to 08) to select it. 
*   **RUN STAGE:** Sends a job to the agent to execute the real TTPs for that stage on the target machine.
*   **STOP:** Attempts to halt the agent if a script is hanging.
*   **CLEANUP:** Sends a cleanup command to the agent to remove files, scheduled tasks, and registry keys created by that stage (to reset the lab).
*   **Output Tabs (Center):**
    *   **EMULATION OUTPUT:** Live console showing job queues and agent responses.
    *   **COMMANDS:** Detailed breakdown of every command executed on the target, along with its stdout/stderr.
    *   **TELEMETRY:** Hints on what Sysmon/Windows Event IDs you should be looking for in your SIEM.
    *   **MITRE ATT&CK:** A detailed breakdown of the specific techniques, red/blue team notes, and detection logic for the selected stage.
    *   **ACTIVITY:** Audit log of who ran what stage and when.

### 3. Wazuh Detection Center (Bottom)
Simulates a SOC (Security Operations Center) dashboard to hunt for the emulated attacks.
*   **LIVE ALERTS:** Real-time WebSocket feed of alerts from your Wazuh Indexer.
*   **SEARCH:** Query Wazuh logs using filters (Agent, Rule ID, MITRE ID, Level). *Note: Requires connection to a Wazuh Indexer API.*
*   **RULES:** View Wazuh rules currently loaded on the manager.
*   **RULE BUILDER:** Select a preset rule from the dropdown, modify the XML, click **Validate**, and then **Deploy** (saves it to the server for you to apply to your Wazuh manager).
*   **RULE TESTER:** Paste raw Windows Event JSON here to test it against the Wazuh `logtest` API.
*   **AGENTS:** View connected Wazuh agents.
*   **TIMELINE:** Correlates alerts from the same agent into a visual attack chain.

---

## 🎯 Campaign Stages & TTPs

| # | Stage | Key Techniques / Tools |
|---|-------|------------------------|
| **01** | **Initial Access** | Spearphishing RAB, CVE-2017-11882, weaponized RTF/XLSX, spoofed Pakistani senders (`arc@desto.gov.pk`), CDR lure themes. |
| **02** | **Execution & C2** | ZxxZ Trojan execution, encoded PowerShell, AMSI bypass, HTTP beacon with `ZxxZ` separator, 17-second polling cycle. |
| **03** | **Discovery** | Host recon (`systeminfo`, `whoami`), process scanning for Windows Defender/Kaspersky, `net view`, `arp -a`. |
| **04** | **Persistence** | Creates scheduled tasks `Rdx` & `RdxFac` (cURL to Music folder), Registry Run keys, Startup folder `.lnk`. |
| **05** | **Defense Evasion** | XOR string encoding (key `0x42`), renaming utilities (`certutil.exe`), `wevtutil cl` (clear logs), process hollowing. |
| **06** | **Credential Access** | LSASS memory dump via `comsvcs.dll`, `reg save HKLM\SAM`, downloading `procdump64.exe`, Impacket `secretsdump`. |
| **07** | **Lateral Movement** | Port scanning (RDP/WMI/SMB), `net use`, `Invoke-WmiMethod`, `PsExec64.exe`, `tar.exe` staging. |
| **08** | **Exfiltration** | Archiving RAB data, HTTPS POST to C2 `/api/c2/beacon`, proxy usage, DDNS (Fast Flux). |

---

## 🕵️ Indicators of Compromise (IOCs)

### C2 Infrastructure
*   `helpdesk[.]autodefragapp[.]com`
*   `99[.]83[.]154[.]118`
*   `olmajhnservice[.]com`
*   `levarisnetqlsvc[.]net`

### Host Artifacts (ZxxZ Trojan)
*   **Drop location:** `%LOCALAPPDATA%\Debug\Update.exe`
*   **Scheduled Tasks:** `Rdx`, `RdxFac`
*   **Download Path:** `%USERPROFILE%\Music\RdxFactory.exe`
*   **XOR Key:** `0x42` (used for string obfuscation)

---

## 🛠️ Troubleshooting

**Q: The server fails to start (`npm install` errors).**
*   Ensure you have Node.js v23.4.0 or newer installed. The server uses the built-in `node:sqlite` module to avoid native C++ compilation errors on Windows. Run `node -v` to check.

**Q: The agent cannot connect to the server.**
*   Ensure inbound TCP port 8000 is allowed in the Windows Firewall on the server machine.
*   Ensure `GB_SERVER` in `agent\.env.agent` points to the correct server IP address.

**Q: Discovery doesn't find my agent machine.**
*   Windows Firewall on the target machine might be blocking ICMP (Ping). The scanner also uses TCP ports (445, 135, 3389) and ARP, but ensure the target is on the same subnet.
*   Make sure you select the correct IP in the `start-agent.bat` menu.

**Q: "Cleanup" doesn't remove everything.**
*   Some actions (like `wevtutil cl` to clear event logs) are irreversible. If a stage fails midway, run the **CLEANUP** button for that specific stage again, or manually inspect the `%LOCALAPPDATA%\Bitter-BD-Lab` folder on the target machine.

---

## 📚 References
*   [Cisco Talos: Bitter APT Campaign Targeting Bangladesh](https://blog.talosintelligence.com/2022/05/bitter-apt-targets-bangladesh.html)
*   [MITRE ATT&CK: Bitter (G1002)](https://attack.mitre.org/groups/G1002/)

---
*Built for the cybersecurity community. Stay safe, stay authorized.*
```
