param([ValidateSet('Apply','Restore','Check')][string]$Mode='Apply', [string]$AssetsPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

Write-Host @'

============================================================
                     SCRIPT BY ZzeK

             ZZZZZZ  ZZZZZZ  EEEEEE  K   K
                 Z       Z   E       K  K
                Z       Z    EEEE    KKK
               Z       Z     E       K  K
             ZZZZZZ  ZZZZZZ  EEEEEE  K   K
============================================================

'@ -ForegroundColor Cyan

function Get-Digest([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
}
function Read-Region($Stream,[long]$Offset,[int]$Length) {
    [void]$Stream.Seek($Offset,[IO.SeekOrigin]::Begin)
    $bytes=New-Object byte[] $Length
    $got=0
    while ($got -lt $Length) {
        $n=$Stream.Read($bytes,$got,$Length-$got)
        if ($n -eq 0) { throw 'Unexpected end of archive.' }
        $got+=$n
    }
    return ,$bytes
}
function Assert-Closed {
    if (Get-Process H1Z1,H1Z1_BE -ErrorAction SilentlyContinue) { throw 'Close ROTK/H1Z1, then run this script again.' }
}

$streams=@{}
$completed=New-Object System.Collections.Generic.List[object]
try {
    $manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
    if (!$AssetsPath) {
        Add-Type -AssemblyName System.Windows.Forms
        $picker=New-Object System.Windows.Forms.FolderBrowserDialog
        try {
            $picker.Description='Select your ROTK installation folder (the folder containing Resources).'
            $picker.ShowNewFolderButton=$false
            Write-Host 'Select your ROTK installation folder in the folder picker.'
            if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
                Write-Host 'Cancelled. No files have been changed.'
                exit 0
            }
            $AssetsPath=Join-Path $picker.SelectedPath 'Resources\Assets'
        } finally { $picker.Dispose() }
    }
    $AssetsPath=[IO.Path]::GetFullPath($AssetsPath)
    if (!(Test-Path -LiteralPath $AssetsPath -PathType Container)) {
        throw 'The selected folder does not contain Resources\Assets. Run again and select the ROTK installation folder.'
    }
    foreach ($packName in ($manifest.assets.pack | Select-Object -Unique)) {
        if (!(Test-Path -LiteralPath (Join-Path $AssetsPath $packName) -PathType Leaf)) {
            throw "Missing required archive: $packName. Select the correct ROTK installation folder. No files have been changed."
        }
    }
    Write-Host "Assets folder: $AssetsPath"
    Assert-Closed
    $plans=New-Object System.Collections.Generic.List[object]
    foreach ($group in ($manifest.assets | Group-Object pack)) {
        $pack=$group.Name
        if ([IO.Path]::GetFileName($pack) -ne $pack) { throw 'Invalid archive name.' }
        $path=Join-Path $AssetsPath $pack
        $access=if ($Mode -eq 'Check') { [IO.FileAccess]::Read } else { [IO.FileAccess]::ReadWrite }
        $stream=[IO.File]::Open($path,[IO.FileMode]::Open,$access,[IO.FileShare]::None)
        $streams[$pack]=$stream
        $head=Read-Region $stream 0 24
        if ([BitConverter]::ToString($head,0,4) -ne '50-41-4B-01') { throw "Unsupported archive: $pack" }
        $count=[BitConverter]::ToUInt32($head,4)
        $toc=[BitConverter]::ToUInt64($head,16)
        if ($count -gt 1000000 -or $toc+$count*32 -gt $stream.Length) { throw "Invalid archive index: $pack" }
        $entries=@{}
        $boundaries=New-Object System.Collections.Generic.List[long]
        $boundaries.Add([long]$toc);$boundaries.Add($stream.Length)
        $index=Read-Region $stream $toc ([int]($count*32))
        for ($i=0;$i -lt $count;$i++) {
            $p=$i*32
            $id=[BitConverter]::ToUInt64($index,$p).ToString()
            $off=[BitConverter]::ToUInt64($index,$p+8)
            $size=[BitConverter]::ToUInt64($index,$p+16)
            if ($off+$size -gt $stream.Length) { throw "Invalid asset bounds: $pack" }
            if ($entries.ContainsKey($id)) { throw "Duplicate asset ID: $pack" }
            $entries[$id]=@{offset=[long]$off;size=[long]$size;indexOffset=[long]($toc+$p);flags=[BitConverter]::ToUInt32($index,$p+24)}
            $boundaries.Add([long]$off)
        }
        foreach ($asset in $group.Group) {
            $id=[string]$asset.id
            if (!$entries.ContainsKey($id)) { throw "Missing asset: $($asset.name). This game build is not supported." }
            $entry=$entries[$id]
            if ($entry.flags -ne $asset.flags) { throw "Changed storage format: $($asset.name)" }
            $known=@{}
            foreach ($state in @('original','patched')) {
                $spec=$asset.$state
                if ([IO.Path]::GetFileName($spec.file) -ne $spec.file) { throw 'Invalid payload name.' }
                $bytes=[IO.File]::ReadAllBytes((Join-Path (Join-Path $PSScriptRoot 'files') $spec.file))
                if ($bytes.Length -ne $spec.size -or (Get-Digest $bytes) -ne $spec.sha256) { throw "Damaged package file: $($spec.file)" }
                $known[$state]=$bytes
            }
            if ($entry.size -gt 16777216) { throw 'Unexpected asset size.' }
            $current=Read-Region $stream $entry.offset ([int]$entry.size)
            $hash=Get-Digest $current
            $state=if ($hash -eq $asset.original.sha256) {'original'} elseif ($hash -eq $asset.patched.sha256) {'patched'} else { throw "Unrecognized asset version: $($asset.name). No files have been changed." }
            $oldIndex=Read-Region $stream $entry.indexOffset 32
            if ([BitConverter]::ToUInt32($oldIndex,28) -ne $asset.$state.crc) { throw "Unexpected archive checksum: $($asset.name)" }
            Write-Host ("{0}: {1}" -f $state,$asset.name)
            if ($Mode -eq 'Check') { continue }
            $wanted=if ($Mode -eq 'Apply') {'patched'} else {'original'}
            if ($state -eq $wanted) { continue }
            $target=$known[$wanted]
            $length=[Math]::Max($current.Length,$target.Length)
            $next=($boundaries | Where-Object {$_ -gt $entry.offset} | Measure-Object -Minimum).Minimum
            if ($entry.offset+$length -gt $next) { throw "Not enough safe space for $($asset.name). No files have been changed." }
            $before=Read-Region $stream $entry.offset $length
            $after=[byte[]]$before.Clone()
            [Array]::Copy($target,0,$after,0,$target.Length)
            $newIndex=[byte[]]$oldIndex.Clone()
            [Array]::Copy([BitConverter]::GetBytes([uint64]$target.Length),0,$newIndex,16,8)
            [Array]::Copy([BitConverter]::GetBytes([uint32]$asset.$wanted.crc),0,$newIndex,28,4)
            $plans.Add(@{pack=$pack;offset=$entry.offset;before=$before;after=$after})
            $plans.Add(@{pack=$pack;offset=$entry.indexOffset;before=$oldIndex;after=$newIndex})
        }
    }
    # Every asset and payload is verified before any game-file write.
    if ($Mode -eq 'Check') { Write-Host 'Inspection complete. No changes made.'; exit 0 }
    if ($plans.Count -eq 0) { Write-Host 'Already in the requested state. No changes needed.'; exit 0 }
    Assert-Closed
    $backupDir=Join-Path (Join-Path $PSScriptRoot 'backups') ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    [void][IO.Directory]::CreateDirectory($backupDir)
    $journal=@()
    for ($i=0;$i -lt $plans.Count;$i++) {
        $p=$plans[$i];$file="$i.bin"
        [IO.File]::WriteAllBytes((Join-Path $backupDir $file),$p.before)
        $journal+=@{pack=$p.pack;offset=$p.offset;file=$file;sha256=(Get-Digest $p.before);length=$p.before.Length}
    }
    @{assetsPath=$AssetsPath;mode=$Mode;regions=$journal} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $backupDir 'journal.json') -Encoding UTF8
    foreach ($p in $plans) {
        $stream=$streams[$p.pack]
        $completed.Add($p)
        [void]$stream.Seek($p.offset,[IO.SeekOrigin]::Begin)
        $stream.Write($p.after,0,$p.after.Length)
        $stream.Flush($true)
        if ((Get-Digest (Read-Region $stream $p.offset $p.after.Length)) -ne (Get-Digest $p.after)) { throw 'Write verification failed.' }
    }
    Write-Host "SUCCESS: $Mode completed and verified. Backups: $backupDir" -ForegroundColor Green
} catch {
    $failure=$_.Exception.Message
    for ($i=$completed.Count-1;$i -ge 0;$i--) {
        $p=$completed[$i]
        try {
            $s=$streams[$p.pack];[void]$s.Seek($p.offset,[IO.SeekOrigin]::Begin)
            $s.Write($p.before,0,$p.before.Length);$s.Flush($true)
            if ((Get-Digest (Read-Region $s $p.offset $p.before.Length)) -ne (Get-Digest $p.before)) { throw 'Rollback verification failed.' }
        } catch { Write-Host "ROLLBACK ERROR: $($_.Exception.Message). Keep the backups folder." -ForegroundColor Red }
    }
    Write-Host "STOPPED: $failure" -ForegroundColor Red
    exit 1
} finally {
    foreach ($stream in $streams.Values) { $stream.Dispose() }
}
