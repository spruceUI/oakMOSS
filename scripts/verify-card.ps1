# verify-card.ps1 - READ-ONLY: compare an SD card, sector by sector, with the image written to it.
# Works without a drive letter (reads \\.\PhysicalDriveN), which Win32DiskImager's "Verify Only" needs.
#
# Run from an elevated (Administrator) PowerShell:
#   powershell -ExecutionPolicy Bypass -File verify-card.ps1 -Image "C:\path\to\card.img"
#   (add -DiskNumber N if more than one USB disk is attached)
#
# It never writes: the card is opened with read access only.
# It deliberately does NOT use Get-Disk / Get-Partition / Disk Management: querying a card through
# Windows storage management is suspected of rewriting a GPT whose backup is not at the end of the
# disk (seen 2026-09-18: primary header rebuilt, 128 entries written at LBA 2-33 over boot0). Disks
# are found with the classic Win32_DiskDrive query, which only reads.
param(
    [Parameter(Mandatory = $true)][string]$Image,
    [int]$DiskNumber = -1
)
$ErrorActionPreference = 'Stop'

$img = Get-Item -LiteralPath $Image
$len = [long]$img.Length
if ($len % 512) { throw "image size $len is not a multiple of 512 bytes" }

$all = @(Get-CimInstance Win32_DiskDrive)
$all | Select-Object Index, Model, InterfaceType, MediaType, Size | Sort-Object Index | Format-Table -AutoSize
if ($DiskNumber -lt 0) {
    $cand = @($all | Where-Object { $_.InterfaceType -eq 'USB' -and $_.MediaType -eq 'Removable Media' -and [long]$_.Size -ge $len })
    if ($cand.Count -ne 1) { throw "found $($cand.Count) removable USB disks large enough; rerun with -DiskNumber <Index> from the table above" }
    $DiskNumber = [int]$cand[0].Index
}
$disk = $all | Where-Object { [int]$_.Index -eq $DiskNumber }
if (-not $disk) { throw "no disk with index $DiskNumber" }
if ($disk.InterfaceType -ne 'USB' -or $disk.MediaType -ne 'Removable Media') { throw "disk $DiskNumber is not removable USB media - refusing" }
$disk | Add-Member -NotePropertyName FriendlyName -NotePropertyValue $disk.Model -Force
"Comparing $($img.Name) ($len bytes)"
"     with \\.\PhysicalDrive$DiskNumber  $($disk.FriendlyName)  ($($disk.Size) bytes)"

$dev = [IO.FileStream]::new("\\.\PhysicalDrive$DiskNumber", [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite, 1, [IO.FileOptions]::None)
$src = [IO.File]::OpenRead($img.FullName)
$sha = [Security.Cryptography.SHA256]::Create()
$chunk = 1MB
$a = New-Object byte[] $chunk
$b = New-Object byte[] $chunk
$pos = [long]0
$badSectors = [long]0
$badTable = 0
$ranges = New-Object System.Collections.Generic.List[string]
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
    while ($pos -lt $len) {
        $want = [int][Math]::Min([long]$chunk, $len - $pos)
        $n = 0
        while ($n -lt $want) { $r = $src.Read($a, $n, $want - $n); if ($r -le 0) { throw "image ended early at $pos" }; $n += $r }
        $got = $dev.Read($b, 0, $want)
        if ($got -ne $want) { throw "short read from the card at byte $pos (wanted $want, got $got)" }
        $ha = [BitConverter]::ToString($sha.ComputeHash($a, 0, $want))
        $hb = [BitConverter]::ToString($sha.ComputeHash($b, 0, $want))
        if ($ha -ne $hb) {
            # Locate the differing sectors inside this chunk.
            $runStart = -1
            for ($s = 0; $s -lt $want / 512; $s++) {
                $o = $s * 512
                $same = ([BitConverter]::ToString($sha.ComputeHash($a, $o, 512)) -eq [BitConverter]::ToString($sha.ComputeHash($b, $o, 512)))
                $lba = [long]($pos / 512) + $s
                if (-not $same) { $badSectors++; if ($lba -lt 34) { $badTable++ }; if ($runStart -lt 0) { $runStart = $lba } }
                elseif ($runStart -ge 0) { $ranges.Add("$runStart-$($lba - 1)"); $runStart = -1 }
            }
            if ($runStart -ge 0) { $ranges.Add("$runStart-$([long]($pos / 512) + $want / 512 - 1)") }
        }
        $pos += $want
        if (($pos % 64MB) -eq 0) { Write-Host -NoNewline "`r  $([int]($pos * 100 / $len))% " }
    }
} finally { $src.Close(); $dev.Close() }

""
if ($badSectors -eq 0) {
    "PASS: all $($len / 512) sectors match the image  ($([int]$sw.Elapsed.TotalSeconds) s)"
} else {
    "FAIL: $badSectors sector(s) differ from the image"
    "  of which in the partition-table area (sectors 0-33): $badTable"
    "differing sector ranges (first 40): $(($ranges | Select-Object -First 40) -join ', ')"
}
