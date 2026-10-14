Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('DiskScope-Test-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path (Join-Path $root 'alpha'), (Join-Path $root 'beta\nested') -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $root 'root.bin'), [byte[]]::new(100))
    [IO.File]::WriteAllBytes((Join-Path $root 'alpha\a.bin'), [byte[]]::new(200))
    [IO.File]::WriteAllBytes((Join-Path $root 'beta\nested\b.bin'), [byte[]]::new(300))
    Add-Type -Path (Join-Path $PSScriptRoot 'DiskScanner.cs')
    $job = [DiskScope.Core.Scanner]::Start($root)
    $result = $job.Task.GetAwaiter().GetResult()
    if ($result.TotalSize -ne 600) { throw "Tamanho incorreto: $($result.TotalSize)" }
    if ($result.FileCount -ne 3) { throw "Contagem de arquivos incorreta: $($result.FileCount)" }
    if ($result.DirectoryCount -ne 3) { throw "Contagem de pastas incorreta: $($result.DirectoryCount)" }
    if ($result.Directories[0].Name -ne 'beta') { throw 'Ordenação por tamanho incorreta.' }
    [IO.File]::WriteAllBytes((Join-Path $root 'alpha\copia.bin'), [byte[]]::new(200))
    $rescan = [DiskScope.Core.Scanner]::Start($root).Task.GetAwaiter().GetResult()
    $duplicates = [DiskScope.Core.DuplicateFinder]::Start($rescan).Task.GetAwaiter().GetResult()
    if ($duplicates.Count -ne 1) { throw "Grupos duplicados incorretos: $($duplicates.Count)" }
    if ($duplicates[0].Files.Count -ne 2 -or $duplicates[0].FileSize -ne 200) { throw 'Conteúdo do grupo duplicado incorreto.' }
    Write-Host 'OK — scanner e SHA-256 validados (metadados, contagens e duplicados).' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
