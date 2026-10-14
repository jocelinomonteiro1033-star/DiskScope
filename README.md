# DiskScope

Protótipo clean-room de um analisador de espaço em disco para Windows. Ele não usa código, binários ou formatos privados do TreeSize.

## Executar

1. Abra `DiskScope.exe` (forma recomendada).
2. Escolha uma pasta ou a raiz de uma unidade.
3. Clique em **Analisar**.

O executável é um pacote único, mas requer o PowerShell 7 instalado no Windows. Ele extrai os componentes em uma pasta temporária, abre a interface sem janela de console e remove os arquivos temporários ao fechar.

Como alternativa para desenvolvimento, abra `Iniciar-DiskScope.cmd`.

Também é possível arrastar uma pasta para o arquivo `.cmd` ou informar o caminho no terminal:

```powershell
pwsh -NoProfile -STA -File .\DiskScope.ps1 -Path 'C:\Users'
```

## Funcionalidades atuais

- análise em segundo plano, sem congelar a janela;
- cancelamento durante a varredura;
- árvore de diretórios carregada sob demanda;
- arquivos e pastas ordenados por tamanho;
- filtro da pasta selecionada;
- data de criação, modificação e idade dos arquivos;
- filtros de idade (30/90 dias, 1 ano e 3 anos);
- busca de duplicados confirmada por hash SHA-256;
- seleção automática das cópias extras, preservando por padrão a mais recente;
- exclusão individual, múltipla ou em massa pela Lixeira, sempre com confirmação;
- exportação completa para CSV;
- relatório PDF executivo com indicadores, gráficos de pastas, tipos e idade, maiores arquivos e resumo de duplicados;
- links/reparse points não são atravessados, evitando ciclos;
- erros de acesso não interrompem a análise.

## Limitações desta primeira versão

- apresenta tamanho lógico, não o espaço alocado em disco;
- ainda não lê diretamente a MFT do NTFS;
- não tenta elevar privilégios;
- mantém metadados de arquivos em memória durante a análise;
- ainda não desenha treemap nesta etapa;
- o cálculo SHA-256 lê integralmente os arquivos candidatos e pode demorar em discos lentos;
- exclusões em locais sem suporte à Lixeira são recusadas pelo Windows e apresentadas como erro.
- a geração de PDF utiliza o Microsoft Edge ou Google Chrome instalado, sem enviar dados para a internet.

## Teste do núcleo

```powershell
pwsh -NoProfile -File .\Test-Scanner.ps1
```

O teste cria uma árvore temporária conhecida, valida tamanho, contagens e ordenação e remove os dados ao terminar.

## Recompilar o executável

```powershell
pwsh -NoProfile -File .\Build-Exe.ps1
```

O script usa o compilador C# incluído no Windows e incorpora `DiskScope.ps1` e `DiskScanner.cs` como recursos internos do executável.
