function ConvertTo-ReportText([object]$value) {
    return [System.Net.WebUtility]::HtmlEncode([string]$value)
}

function Format-ReportSize([long]$bytes) {
    $units = @('B','KB','MB','GB','TB','PB'); $value = [double]$bytes; $index = 0
    while ($value -ge 1024 -and $index -lt $units.Count - 1) { $value /= 1024; $index++ }
    if ($index -eq 0) { return ('{0:N0} {1}' -f $value, $units[$index]) }
    return ('{0:N2} {1}' -f $value, $units[$index])
}

function Measure-ReportSum($items, [string]$propertyName) {
    [long]$total = 0
    if ($null -eq $items) { return $total }
    foreach ($item in @($items)) {
        if ($null -ne $item) { $total += [long]$item.$propertyName }
    }
    return $total
}

function Get-ReportFiles($rootNode) {
    $files = [System.Collections.Generic.List[object]]::new()
    $pending = [System.Collections.Generic.Stack[object]]::new(); $pending.Push($rootNode)
    while ($pending.Count) {
        $node = $pending.Pop()
        foreach ($file in $node.Files) { $files.Add($file) }
        foreach ($child in $node.Directories) { $pending.Push($child) }
    }
    return $files
}

function New-ReportBars($items, [long]$total, [string]$valueKind = 'size') {
    $builder = [Text.StringBuilder]::new(); $palette = @('#4F7FFF','#18A999','#F6A623','#8E6CEF','#E65F5C','#38A3D1','#7CB342','#EC6FA8')
    $index = 0
    foreach ($item in $items) {
        [long]$value = $item.Value; $percent = if ($total) { [Math]::Min(100, 100 * $value / $total) } else { 0 }
        $percentText = ([Math]::Max(0.8, $percent)).ToString('F1', [Globalization.CultureInfo]::InvariantCulture)
        $display = if ($valueKind -eq 'count') { '{0:N0}' -f $value } else { Format-ReportSize $value }
        [void]$builder.AppendFormat('<div class="bar-row"><div class="bar-label"><span>{0}</span><b>{1}</b></div><div class="track"><div class="fill" style="width:{2}%;background:{3}"></div></div></div>',
            (ConvertTo-ReportText $item.Label), $display, $percentText, $palette[$index % $palette.Count])
        $index++
    }
    return $builder.ToString()
}

function New-DonutStyle($items, [long]$total) {
    if (-not $total) { return 'background:#e8edf5' }
    $palette = @('#4F7FFF','#18A999','#F6A623','#8E6CEF','#E65F5C','#38A3D1')
    $segments = [System.Collections.Generic.List[string]]::new(); [double]$cursor = 0; $index = 0
    foreach ($item in $items) {
        $next = $cursor + (100 * [double]$item.Value / $total)
        $startText = $cursor.ToString('F2', [Globalization.CultureInfo]::InvariantCulture)
        $endText = $next.ToString('F2', [Globalization.CultureInfo]::InvariantCulture)
        $segments.Add(('{0} {1}% {2}%' -f $palette[$index % $palette.Count], $startText, $endText))
        $cursor = $next; $index++
    }
    return 'background:conic-gradient(' + ($segments -join ',') + ')'
}

function Find-ReportBrowser {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe')
    )
    return $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
}

function Export-DiskScopePdf {
    param(
        [Parameter(Mandatory)]$RootNode,
        [object[]]$DuplicateGroups = @(),
        [Parameter(Mandatory)][string]$OutputPath
    )

    $browser = Find-ReportBrowser
    if (-not $browser) { throw 'Microsoft Edge ou Google Chrome não foi encontrado para gerar o PDF.' }
    $files = @(Get-ReportFiles $RootNode)
    $now = [datetime]::Now

    $topFolders = @($RootNode.Directories | Select-Object -First 8 | ForEach-Object { [pscustomobject]@{ Label=$_.Name; Value=$_.TotalSize } })
    $typeGroups = @($files | Group-Object { if ($_.Extension) { $_.Extension.ToLowerInvariant() } else { '(sem extensão)' } } | ForEach-Object {
        [pscustomobject]@{ Label=$_.Name; Value=(Measure-ReportSum $_.Group 'Size'); Count=$_.Count }
    } | Sort-Object Value -Descending | Select-Object -First 8)

    $ageDefinitions = @(
        @{Label='Até 30 dias'; Min=0; Max=30}, @{Label='31 a 90 dias'; Min=31; Max=90},
        @{Label='91 dias a 1 ano'; Min=91; Max=365}, @{Label='1 a 3 anos'; Min=366; Max=1095},
        @{Label='Mais de 3 anos'; Min=1096; Max=[int]::MaxValue}
    )
    $ageGroups = foreach ($definition in $ageDefinitions) {
        $matches = @($files | Where-Object { $days = ($now - $_.LastWriteTime).TotalDays; $days -ge $definition.Min -and $days -le $definition.Max })
        [pscustomobject]@{ Label=$definition.Label; Value=$matches.Count; Bytes=(Measure-ReportSum $matches 'Size') }
    }

    $topFiles = @($files | Sort-Object Size -Descending | Select-Object -First 20)
    [long]$duplicateBytes = Measure-ReportSum $DuplicateGroups 'ReclaimableSize'
    $extraCopies = 0
    foreach ($group in $DuplicateGroups) { $extraCopies += [Math]::Max(0, $group.Files.Count - 1) }

    $folderBars = New-ReportBars $topFolders $RootNode.TotalSize
    $typeBars = New-ReportBars $typeGroups $RootNode.TotalSize
    $ageBars = New-ReportBars $ageGroups $files.Count 'count'
    $donutStyle = New-DonutStyle $ageGroups $files.Count

    $topFileRows = [Text.StringBuilder]::new()
    foreach ($file in $topFiles) {
        [void]$topFileRows.AppendFormat('<tr><td>{0}</td><td class="number">{1}</td><td>{2}</td><td class="number">{3:N0} dias</td></tr>',
            (ConvertTo-ReportText $file.FullPath), (Format-ReportSize $file.Size), $file.LastWriteTime.ToString('dd/MM/yyyy HH:mm'), [Math]::Max(0, ($now - $file.LastWriteTime).TotalDays))
    }

    $duplicateRows = [Text.StringBuilder]::new(); $groupIndex = 0
    foreach ($group in ($DuplicateGroups | Select-Object -First 20)) {
        $groupIndex++
        [void]$duplicateRows.AppendFormat('<tr><td>#{0}</td><td class="number">{1:N0}</td><td class="number">{2}</td><td class="number">{3}</td><td class="hash">{4}…</td></tr>',
            $groupIndex, $group.Files.Count, (Format-ReportSize $group.FileSize), (Format-ReportSize $group.ReclaimableSize), $group.Hash.Substring(0, 12))
    }
    if (-not $DuplicateGroups.Count) { [void]$duplicateRows.Append('<tr><td colspan="5" class="empty">Execute “Localizar duplicados” antes de gerar o relatório para preencher esta seção.</td></tr>') }

    $pathText = ConvertTo-ReportText $RootNode.FullPath
    $generatedText = $now.ToString('dd/MM/yyyy HH:mm')
    $html = @"
<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><style>
@page{size:A4;margin:14mm}*{box-sizing:border-box}body{font-family:"Segoe UI",Arial,sans-serif;color:#172033;margin:0;font-size:10px;-webkit-print-color-adjust:exact;print-color-adjust:exact}
.header{background:#172033;color:white;padding:22px 24px;border-radius:10px;margin-bottom:16px}.brand{font-size:25px;font-weight:700}.subtitle{color:#afc2e8;margin-top:4px}.path{margin-top:14px;font-size:9px;word-break:break-all}.meta{float:right;text-align:right;color:#afc2e8}.section{margin:18px 0 10px;font-size:16px;font-weight:700}.kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:9px}.kpi{border:1px solid #dde3ec;border-radius:8px;padding:12px;background:#f8faff}.kpi .value{font-size:18px;font-weight:700;color:#315fce}.kpi .label{color:#68758d;margin-top:3px}.charts{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:12px}.card{border:1px solid #dde3ec;border-radius:8px;padding:14px;break-inside:avoid}.card h3{margin:0 0 12px;font-size:12px}.bar-row{margin:8px 0}.bar-label{display:flex;justify-content:space-between;gap:8px;margin-bottom:3px}.bar-label span{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:72%}.track{height:7px;background:#e8edf5;border-radius:5px;overflow:hidden}.fill{height:100%;border-radius:5px}.age-layout{display:flex;align-items:center;gap:18px}.donut{width:112px;height:112px;border-radius:50%;position:relative;flex:none}.donut:after{content:"Idade";position:absolute;inset:25px;background:white;border-radius:50%;display:flex;align-items:center;justify-content:center;font-weight:700;color:#68758d}.age-bars{flex:1}.page-break{break-before:page}table{width:100%;border-collapse:collapse;font-size:8.5px}th{text-align:left;background:#172033;color:white;padding:7px}td{padding:6px 7px;border-bottom:1px solid #e5e9f0;vertical-align:top}tr:nth-child(even) td{background:#f8faff}.number{text-align:right;white-space:nowrap}.hash{font-family:Consolas,monospace}.empty{text-align:center;color:#68758d;padding:18px}.note{background:#eef4ff;border-left:4px solid #4f7fff;padding:9px 11px;margin:10px 0;color:#455066}.footer{position:fixed;bottom:-9mm;left:0;right:0;text-align:center;color:#8a94a6;font-size:8px}
</style></head><body>
<div class="footer">DiskScope - relatório local de armazenamento</div>
<div class="header"><div class="meta">Gerado em<br><b>$generatedText</b></div><div class="brand">DiskScope</div><div class="subtitle">Relatório objetivo de uso do armazenamento</div><div class="path">$pathText</div></div>
<div class="kpis"><div class="kpi"><div class="value">$(Format-ReportSize $RootNode.TotalSize)</div><div class="label">Volume analisado</div></div><div class="kpi"><div class="value">$($RootNode.FileCount.ToString('N0'))</div><div class="label">Arquivos</div></div><div class="kpi"><div class="value">$($RootNode.DirectoryCount.ToString('N0'))</div><div class="label">Pastas</div></div><div class="kpi"><div class="value">$(Format-ReportSize $duplicateBytes)</div><div class="label">Duplicados recuperáveis</div></div></div>
<div class="charts"><div class="card"><h3>Maiores pastas - participação no total</h3>$folderBars</div><div class="card"><h3>Tipos de arquivo - espaço ocupado</h3>$typeBars</div><div class="card" style="grid-column:1 / span 2"><h3>Idade por última modificação</h3><div class="age-layout"><div class="donut" style="$donutStyle"></div><div class="age-bars">$ageBars</div></div></div></div>
<div class="note">A idade considera a última modificação. O tamanho exibido é lógico e pode diferir do espaço fisicamente alocado.</div>
<div class="page-break"></div><div class="section">20 maiores arquivos</div><table><thead><tr><th>Caminho</th><th class="number">Tamanho</th><th>Modificado</th><th class="number">Idade</th></tr></thead><tbody>$topFileRows</tbody></table>
<div class="section">Duplicados</div><div class="kpis" style="grid-template-columns:repeat(3,1fr);margin-bottom:10px"><div class="kpi"><div class="value">$($DuplicateGroups.Count.ToString('N0'))</div><div class="label">Grupos confirmados</div></div><div class="kpi"><div class="value">$($extraCopies.ToString('N0'))</div><div class="label">Cópias extras</div></div><div class="kpi"><div class="value">$(Format-ReportSize $duplicateBytes)</div><div class="label">Potencial de recuperação</div></div></div>
<table><thead><tr><th>Grupo</th><th class="number">Cópias</th><th class="number">Cada arquivo</th><th class="number">Recuperável</th><th>SHA-256</th></tr></thead><tbody>$duplicateRows</tbody></table>
</body></html>
"@

    $temporaryHtml = Join-Path ([IO.Path]::GetTempPath()) ('DiskScope-Report-' + [Guid]::NewGuid().ToString('N') + '.html')
    $temporaryProfile = Join-Path ([IO.Path]::GetTempPath()) ('DiskScope-Browser-' + [Guid]::NewGuid().ToString('N'))
    $temporaryPdf = Join-Path ([IO.Path]::GetTempPath()) ('DiskScope-Report-' + [Guid]::NewGuid().ToString('N') + '.pdf')
    try {
        [void][IO.Directory]::CreateDirectory($temporaryProfile)
        [IO.File]::WriteAllText($temporaryHtml, $html, [Text.UTF8Encoding]::new($false))
        $absoluteOutput = [IO.Path]::GetFullPath($OutputPath)
        $outputDirectory = [IO.Path]::GetDirectoryName($absoluteOutput)
        if (-not [IO.Directory]::Exists($outputDirectory)) { throw "A pasta de destino não existe: $outputDirectory" }
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $browser; $startInfo.UseShellExecute = $false; $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardError = $true
        [void]$startInfo.ArgumentList.Add('--headless=new'); [void]$startInfo.ArgumentList.Add('--disable-gpu')
        [void]$startInfo.ArgumentList.Add('--disable-software-rasterizer')
        [void]$startInfo.ArgumentList.Add('--disable-extensions'); [void]$startInfo.ArgumentList.Add('--no-first-run')
        [void]$startInfo.ArgumentList.Add('--user-data-dir=' + $temporaryProfile)
        [void]$startInfo.ArgumentList.Add('--no-pdf-header-footer'); [void]$startInfo.ArgumentList.Add('--print-to-pdf-no-header')
        [void]$startInfo.ArgumentList.Add('--print-to-pdf=' + $temporaryPdf)
        [void]$startInfo.ArgumentList.Add(([Uri]::new($temporaryHtml)).AbsoluteUri)
        $process = [Diagnostics.Process]::Start($startInfo)
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) {
            try { $process.Kill($true) } catch { }
            throw 'O navegador excedeu 60 segundos durante a geração do PDF.'
        }
        $errors = $errorTask.GetAwaiter().GetResult()

        # Alguns navegadores encerram antes de o arquivo ficar visível para outro processo.
        for ($attempt = 0; $attempt -lt 50 -and -not (Test-Path -LiteralPath $temporaryPdf -PathType Leaf); $attempt++) {
            Start-Sleep -Milliseconds 100
        }
        if (-not (Test-Path -LiteralPath $temporaryPdf -PathType Leaf)) {
            $detail = if ($errors) { ($errors.Trim() -replace '\s+', ' ') } else { "código de saída $($process.ExitCode), sem detalhes adicionais" }
            if ($detail.Length -gt 1200) { $detail = $detail.Substring(0, 1200) + '…' }
            throw "O navegador não criou o arquivo PDF temporário ($detail)."
        }

        $temporaryInfo = Get-Item -LiteralPath $temporaryPdf
        if ($temporaryInfo.Length -lt 5) { throw 'O navegador criou um PDF vazio ou incompleto.' }
        $headerBytes = [byte[]]::new(5)
        $stream = [IO.File]::Open($temporaryPdf, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try { [void]$stream.Read($headerBytes, 0, 5) } finally { $stream.Dispose() }
        if ([Text.Encoding]::ASCII.GetString($headerBytes) -ne '%PDF-') { throw 'O arquivo gerado não possui um cabeçalho PDF válido.' }

        try {
            [IO.File]::Copy($temporaryPdf, $absoluteOutput, $true)
        } catch [UnauthorizedAccessException] {
            throw "O PDF foi gerado, mas o Windows negou acesso ao destino: $absoluteOutput"
        } catch [IO.IOException] {
            throw "O PDF foi gerado, mas não pôde ser salvo no destino. Verifique se o arquivo está aberto ou se a unidade está disponível: $absoluteOutput"
        }
        $outputInfo = Get-Item -LiteralPath $absoluteOutput
        if ($outputInfo.Length -ne $temporaryInfo.Length) { throw 'A cópia do PDF para o destino ficou incompleta.' }
        return $absoluteOutput
    } finally {
        if (Test-Path -LiteralPath $temporaryHtml) { Remove-Item -LiteralPath $temporaryHtml -Force }
        if (Test-Path -LiteralPath $temporaryPdf) { Remove-Item -LiteralPath $temporaryPdf -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $temporaryProfile) { Remove-Item -LiteralPath $temporaryProfile -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
