Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    throw 'Compilador C# do Windows não encontrado.'
}

$output = Join-Path $PSScriptRoot 'DiskScope.exe'
$arguments = @(
    '/nologo'
    '/optimize+'
    '/target:winexe'
    "/out:$output"
    "/resource:$PSScriptRoot\DiskScope.ps1,DiskScope.ps1"
    "/resource:$PSScriptRoot\DiskScanner.cs,DiskScanner.cs"
    "/resource:$PSScriptRoot\PdfReport.ps1,PdfReport.ps1"
    (Join-Path $PSScriptRoot 'Launcher.cs')
)

& $compiler $arguments
if ($LASTEXITCODE -ne 0) { throw "Falha na compilação (código $LASTEXITCODE)." }

$file = Get-Item -LiteralPath $output
$hash = Get-FileHash -LiteralPath $output -Algorithm SHA256
Write-Host ('Criado: {0}' -f $file.FullName) -ForegroundColor Green
Write-Host ('Tamanho: {0:N0} bytes' -f $file.Length)
Write-Host ('SHA-256: {0}' -f $hash.Hash)
