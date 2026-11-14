param([Parameter(Mandatory)][string]$LogDirectory)

$ErrorActionPreference = 'Stop'
$culture = [Globalization.CultureInfo]::InvariantCulture
$summaries = foreach ($mode in 'baseline', 'now', 'read') {
    foreach ($run in 1, 2, 3) {
        $path = Join-Path $LogDirectory "native-gc-$mode-$run.txt"
        $lines = @(Get-Content -LiteralPath $path)
        $begin = @($lines | Where-Object { $_ -match '^QUALIFICATION_BEGIN ' })
        $end = @($lines | Where-Object { $_ -match '^QUALIFICATION_END ' })
        if ($begin.Count -ne 1 -or $end.Count -ne 1 -or
            $begin[0] -ne "QUALIFICATION_BEGIN $mode 2000000 windows.qpc.us.v1") {
            throw "Missing or unexpected markers in $path"
        }
        $first = [array]::IndexOf($lines, $begin[0])
        $last = [array]::IndexOf($lines, $end[0])
        if ($first -ge $last) { throw "Out-of-order markers in $path" }
        $rows = for ($i = $first + 1; $i -lt $last; $i++) {
            if ($lines[$i] -notmatch '^\[\s*main\s*,') { continue }
            $parts = $lines[$i].Split(',')
            if ($parts[1] -notmatch '^\s*Scavenge\(') { throw "Non-scavenge collection in $path" }
            [pscustomobject]@{
                id = [int]$parts[2]
                before = [decimal]::Parse($parts[5].Trim(), $culture)
                after = [decimal]::Parse($parts[6].Trim(), $culture)
            }
        }
        $rows = @($rows)
        $mib = [decimal]0
        for ($i = 1; $i -lt $rows.Count; $i++) {
            if ($rows[$i].id -ne $rows[$i - 1].id + 1) { throw "Missing collection rows in $path" }
            $growth = $rows[$i].before - $rows[$i - 1].after
            if ($growth -lt 0) { throw "Negative heap growth in $path" }
            $mib += $growth
        }
        if (($mode -eq 'baseline' -and $rows.Count -ne 0) -or ($mode -ne 'baseline' -and $rows.Count -lt 2)) {
            throw "Unexpected scavenge count in $path"
        }
        $observedIntervals = [Math]::Max(0, $rows.Count - 1)
        [ordered]@{
            mode = $mode
            run = $run
            calls = 2000000
            scavenges = $rows.Count
            observedIntervals = $observedIntervals
            youngGrowthMiB = if ($observedIntervals) { $mib } else { $null }
            observedYoungGrowthBytesPerCall = if ($observedIntervals) { [Math]::Round($mib * 1MB / 2000000, 1) } else { $null }
            maxRoundingUncertaintyBytesPerCall = if ($observedIntervals) { [Math]::Round($observedIntervals * 0.1 * 1MB / 2000000, 1) } else { $null }
            checksum = $end[0].Substring('QUALIFICATION_END '.Length)
            rawLogSha256 = (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()
        }
    }
}
ConvertTo-Json -InputObject @($summaries) -Depth 5
