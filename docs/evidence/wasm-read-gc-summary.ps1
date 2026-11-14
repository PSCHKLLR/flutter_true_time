param([Parameter(Mandatory)][string]$LogDirectory)

$ErrorActionPreference = 'Stop'
$records = foreach ($mode in 'baseline', 'control', 'now', 'read') {
    foreach ($run in 1, 2, 3) {
        $trace = Join-Path $LogDirectory "wasm-gc-$mode-$run.txt"
        $markers = Join-Path $LogDirectory "wasm-gc-$mode-$run-markers.txt"
        $mark = @(Get-Content -LiteralPath $markers)
        if ($mark.Count -ne 2 -or $mark[0] -notmatch "^QUALIFICATION_BEGIN $mode 2000000 \S+ portable\.stopwatch\.v1$" -or
            $mark[1] -notmatch '^QUALIFICATION_END -?[0-9]+$') {
            throw "Unexpected benchmark markers in $markers"
        }
        $gc = @(foreach ($line in Get-Content -LiteralPath $trace) {
            $entry = [regex]::Match($line, '^\[(?<isolate>[^\]]+)\].*?\bgc=(?<type>\S+).*?\bstart_object_size=(?<start>\d+).*?\bend_object_size=(?<end>\d+).*?\ballocated=(?<allocated>\d+)')
            if (!$entry.Success) { throw "Unrecognized trace row in $trace" }
            $reported = [decimal]$entry.Groups['allocated'].Value
            if ($reported -gt [long]::MaxValue) { $reported -= [decimal]'18446744073709551616' }
            [pscustomobject]@{
                isolate = $entry.Groups['isolate'].Value
                type = $entry.Groups['type'].Value
                start = [long]$entry.Groups['start'].Value
                end = [long]$entry.Groups['end'].Value
                allocated = [long]$reported
            }
        })
        if (@($gc.isolate | Sort-Object -Unique).Count -ne 1) { throw "Unexpected isolate count in $trace" }
        $boundaries = @(for ($i = 0; $i -lt $gc.Count; $i++) {
            if ($gc[$i].type -eq 'mc') { $i }
        })
        if ($boundaries.Count -ne 4 -or $boundaries[1] -ne $boundaries[0] + 1 -or
            $boundaries[3] -ne $boundaries[2] + 1) { throw "Unexpected major GC sequence in $trace" }
        [long]$allocated = 0
        [long]$rowGrowth = 0
        $mismatchedRows = 0
        for ($i = $boundaries[1] + 1; $i -le $boundaries[2]; $i++) {
            $delta = $gc[$i].start - $gc[$i - 1].end
            if ($gc[$i].allocated -ne $delta) { $mismatchedRows++ }
            $rowGrowth += $delta
            $allocated += $gc[$i].allocated
        }
        [ordered]@{
            mode = $mode
            run = $run
            iterations = if ($mode -eq 'control') { 100000 } else { 2000000 }
            netHeapGrowthBytesBetweenCollections = $allocated
            adjacentRowGrowthBytes = $rowGrowth
            mismatchedRows = $mismatchedRows
            observedBytesPerRead = if ($mode -in 'now', 'read') { [Math]::Round($allocated / 2000000, 1) } else { $null }
            minorCollections = $boundaries[2] - $boundaries[1] - 1
            checksum = $mark[1].Substring('QUALIFICATION_END '.Length)
            traceSha256 = (Get-FileHash -LiteralPath $trace).Hash.ToLowerInvariant()
            markersSha256 = (Get-FileHash -LiteralPath $markers).Hash.ToLowerInvariant()
        }
    }
}
if (@($records | Where-Object { ($_.mode -eq 'baseline' -and [Math]::Abs($_.netHeapGrowthBytesBetweenCollections) -gt 100000) -or
      ($_.mode -eq 'control' -and $_.netHeapGrowthBytesBetweenCollections -lt 1000000) }).Count) {
    throw 'The baseline or positive allocation control did not behave as expected'
}
ConvertTo-Json -InputObject @($records) -Depth 5
