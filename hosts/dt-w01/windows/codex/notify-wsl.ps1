param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }),
    [string]$Distribution = 'NixOS',
    [string]$WslUser = 'nemo',
    [string]$NotifyExecutable = '/home/nemo/.nix-profile/bin/codex-notify',
    [string]$Route = 'xyz',
    # Keep this script ASCII-compatible with Windows PowerShell 5's default encoding.
    [string]$Title = ('ChatGPT Desktop' + [char]0x5b8c + [char]0x6210),
    [switch]$InitializeOnly
)

$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)

function Get-DesktopCodexExecutable {
    $ancestor = $PID
    for ($depth = 0; $depth -lt 10 -and $ancestor; $depth++) {
        $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$ancestor" -ErrorAction SilentlyContinue
        if (-not $parent) { break }
        if ($parent.Name -eq 'codex.exe' -and $parent.CommandLine -match '\bapp-server\b') {
            return $parent.ExecutablePath
        }
        $ancestor = $parent.ParentProcessId
    }
    $runtimeRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin\'
    $running = Get-CimInstance Win32_Process -Filter "Name='codex.exe'" |
        Where-Object { $_.CommandLine -match '\bapp-server\b' -and $_.ExecutablePath -like "$runtimeRoot*" } |
        Select-Object -First 1
    if ($running) { return $running.ExecutablePath }
    $app = Get-AppxPackage -Name OpenAI.Codex | Select-Object -First 1
    if (-not $app) { throw 'ChatGPT desktop package was not found' }
    return Join-Path $app.InstallLocation 'app\resources\codex.exe'
}

function ConvertTo-WslDrivePath([string]$NativePath) {
    $full = [IO.Path]::GetFullPath($NativePath)
    if ($full -notmatch '^([A-Za-z]):\\(.*)$') { throw 'An absolute Windows drive path is required' }
    return '/mnt/' + $Matches[1].ToLowerInvariant() + '/' + $Matches[2].Replace('\', '/')
}

function Quote-NativeArgument([string]$Value) {
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    return '"' + [regex]::Replace($escaped, '(\\+)$', '$1$1') + '"'
}

try {
    $CodexHome = [IO.Path]::GetFullPath($CodexHome)
    $executable = Get-DesktopCodexExecutable
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'Desktop Codex executable is missing' }
    $descriptor = @{ codexHome = $CodexHome; codexExecutable = $executable } | ConvertTo-Json -Compress
    $bridgePath = Join-Path $CodexHome 'wsl-bridge.json'
    $temporary = $bridgePath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, $descriptor, $utf8)
        if ([IO.File]::Exists($bridgePath)) {
            [IO.File]::Replace($temporary, $bridgePath, [NullString]::Value)
        } else {
            [IO.File]::Move($temporary, $bridgePath)
        }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
    if ($InitializeOnly) { exit 0 }

    $reader = [IO.StreamReader]::new([Console]::OpenStandardInput(), $utf8)
    $payload = $reader.ReadToEnd()
    $arguments = @(
        '-d', $Distribution, '-u', $WslUser, '--exec', $NotifyExecutable,
        'notify', 'chatgpt-desktop', '--route', $Route,
        '--title', $Title, '--require-transcript',
        '--codex-home', (ConvertTo-WslDrivePath $CodexHome), '--wecom-relay'
    )
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $env:WINDIR 'System32\wsl.exe'
    $start.Arguments = ($arguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' '
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = $utf8
    $start.StandardErrorEncoding = $utf8
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        # Windows PowerShell 5/.NET Framework has no StandardInputEncoding.
        $bytes = $utf8.GetBytes($payload)
        $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $process.StandardInput.BaseStream.Close()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'WSL notification timed out'
        }
        [void]$stdout.GetAwaiter().GetResult()
        $errorOutput = $stderr.GetAwaiter().GetResult().Trim()
        if ($process.ExitCode -ne 0) { throw "WSL notification exited with code $($process.ExitCode): $errorOutput" }
    } finally {
        $process.Dispose()
    }
} catch {
    # A Stop hook must not block or restart the agent's turn.
    try {
        [IO.Directory]::CreateDirectory((Join-Path $CodexHome 'logs')) | Out-Null
        $message = (Get-Date -Format o) + ' ' + $_.Exception.Message + [Environment]::NewLine
        [IO.File]::AppendAllText((Join-Path $CodexHome 'logs\codex-notify-wsl.log'), $message, $utf8)
    } catch { }
}
exit 0
