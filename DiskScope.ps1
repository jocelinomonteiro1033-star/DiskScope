param([string]$Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Add-Type -Path (Join-Path $scriptRoot 'DiskScanner.cs')
. (Join-Path $scriptRoot 'PdfReport.ps1')

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DiskScope — analisador de espaço" Height="720" Width="1180"
        MinHeight="520" MinWidth="820" WindowStartupLocation="CenterScreen"
        Background="#F5F7FA" FontFamily="Segoe UI">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="#172033" CornerRadius="10" Padding="16">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" Margin="0,0,16,0">
          <TextBlock Text="DiskScope" Foreground="White" FontWeight="SemiBold" FontSize="22"/>
          <TextBlock Text="Mapa local de uso do disco" Foreground="#AFC2E8" FontSize="12"/>
        </StackPanel>
        <TextBox x:Name="PathBox" Grid.Column="1" Height="34" Margin="0,3,10,3" IsReadOnly="True"
                 VerticalContentAlignment="Center" Padding="10,0" BorderThickness="0"/>
        <StackPanel Grid.Column="2" Orientation="Horizontal">
          <Button x:Name="ChooseButton" Content="Escolher pasta" Padding="16,7" Margin="0,3,8,3"/>
          <Button x:Name="ScanButton" Content="Analisar" Padding="16,7" Margin="0,3,8,3" Background="#4F7FFF" Foreground="White"/>
          <Button x:Name="CancelButton" Content="Cancelar" Padding="16,7" Margin="0,3" IsEnabled="False"/>
        </StackPanel>
      </Grid>
    </Border>

    <Grid Grid.Row="1" Margin="0,12,0,12">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="150"/>
        <ColumnDefinition Width="150"/>
        <ColumnDefinition Width="145"/>
        <ColumnDefinition Width="120"/>
        <ColumnDefinition Width="130"/>
      </Grid.ColumnDefinitions>
      <TextBox x:Name="FilterBox" Grid.Column="0" Height="32" Margin="0,0,12,0" Padding="9,0"
               VerticalContentAlignment="Center" ToolTip="Filtra os itens da pasta selecionada"/>
      <ComboBox x:Name="AgeFilter" Grid.Column="1" Height="32" Margin="0,0,8,0" SelectedIndex="0">
        <ComboBoxItem Content="Todas as idades" Tag="0"/><ComboBoxItem Content="Mais de 30 dias" Tag="30"/>
        <ComboBoxItem Content="Mais de 90 dias" Tag="90"/><ComboBoxItem Content="Mais de 1 ano" Tag="365"/>
        <ComboBoxItem Content="Mais de 3 anos" Tag="1095"/>
      </ComboBox>
      <Button x:Name="FindDuplicatesButton" Grid.Column="2" Content="Localizar duplicados" Margin="0,0,8,0" IsEnabled="False"/>
      <Button x:Name="DeleteSelectedButton" Grid.Column="3" Content="Excluir seleção" Margin="0,0,8,0" IsEnabled="False"/>
      <Button x:Name="ExportPdfButton" Grid.Column="4" Content="Relatório PDF" Margin="0,0,8,0" IsEnabled="False"/>
      <Button x:Name="ExportButton" Grid.Column="5" Content="Exportar CSV" IsEnabled="False"/>
    </Grid>

    <Grid Grid.Row="2">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="360" MinWidth="250"/>
        <ColumnDefinition Width="8"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <Border Grid.Column="0" Background="White" CornerRadius="8" BorderBrush="#DDE3EC" BorderThickness="1" Padding="6">
        <TreeView x:Name="FolderTree" BorderThickness="0"/>
      </Border>
      <GridSplitter Grid.Column="1" HorizontalAlignment="Stretch" Background="Transparent"/>
      <Border Grid.Column="2" Background="White" CornerRadius="8" BorderBrush="#DDE3EC" BorderThickness="1" Padding="6">
        <TabControl x:Name="ResultTabs" BorderThickness="0">
          <TabItem Header="Conteúdo">
            <DataGrid x:Name="ItemsGrid" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False"
                      GridLinesVisibility="Horizontal" HeadersVisibility="Column" BorderThickness="0"
                      SelectionMode="Extended" AlternatingRowBackground="#F7F9FC">
              <DataGrid.Columns>
                <DataGridTextColumn Header="Nome" Binding="{Binding Name}" Width="*" MinWidth="190"/>
                <DataGridTextColumn Header="Tipo" Binding="{Binding Type}" Width="75"/>
                <DataGridTextColumn Header="Tamanho" Binding="{Binding SizeText}" Width="100"/>
                <DataGridTextColumn Header="%" Binding="{Binding PercentText}" Width="60"/>
                <DataGridTextColumn Header="Idade" Binding="{Binding AgeText}" Width="90"/>
                <DataGridTextColumn Header="Criado" Binding="{Binding Created}" Width="130"/>
                <DataGridTextColumn Header="Modificado" Binding="{Binding Modified}" Width="130"/>
              </DataGrid.Columns>
            </DataGrid>
          </TabItem>
          <TabItem x:Name="DuplicatesTab" Header="Duplicados">
            <Grid>
              <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
              <DockPanel Grid.Row="0" Margin="5,4,5,8">
                <Button x:Name="DeleteDuplicatesButton" Content="Enviar marcados à Lixeira" Padding="12,6" IsEnabled="False" DockPanel.Dock="Right"/>
                <TextBlock x:Name="DuplicateSummaryText" Text="Execute a busca de duplicados." VerticalAlignment="Center"/>
              </DockPanel>
              <DataGrid x:Name="DuplicateGrid" Grid.Row="1" AutoGenerateColumns="False" CanUserAddRows="False"
                        GridLinesVisibility="Horizontal" HeadersVisibility="Column" BorderThickness="0"
                        SelectionMode="Extended" AlternatingRowBackground="#F7F9FC">
                <DataGrid.Columns>
                  <DataGridCheckBoxColumn Header="Excluir" Binding="{Binding Delete, UpdateSourceTrigger=PropertyChanged}" Width="60"/>
                  <DataGridTextColumn Header="Grupo" Binding="{Binding Group}" IsReadOnly="True" Width="60"/>
                  <DataGridTextColumn Header="Arquivo" Binding="{Binding Path}" IsReadOnly="True" Width="*" MinWidth="260"/>
                  <DataGridTextColumn Header="Tamanho" Binding="{Binding SizeText}" IsReadOnly="True" Width="100"/>
                  <DataGridTextColumn Header="Idade" Binding="{Binding AgeText}" IsReadOnly="True" Width="90"/>
                  <DataGridTextColumn Header="Modificado" Binding="{Binding Modified}" IsReadOnly="True" Width="130"/>
                </DataGrid.Columns>
              </DataGrid>
            </Grid>
          </TabItem>
        </TabControl>
      </Border>
    </Grid>

    <Grid Grid.Row="3" Margin="0,12,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0">
        <TextBlock x:Name="StatusText" Text="Escolha uma pasta para começar." Foreground="#455066"/>
        <ProgressBar x:Name="Progress" Height="4" Margin="0,7,18,0" Visibility="Collapsed" IsIndeterminate="True"/>
      </StackPanel>
      <TextBlock x:Name="SummaryText" Grid.Column="1" Foreground="#455066" VerticalAlignment="Top"/>
    </Grid>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$names = 'PathBox','ChooseButton','ScanButton','CancelButton','FilterBox','AgeFilter','FindDuplicatesButton','DeleteSelectedButton','ExportPdfButton','ExportButton','FolderTree','ResultTabs','ItemsGrid','DuplicatesTab','DuplicateGrid','DeleteDuplicatesButton','DuplicateSummaryText','StatusText','Progress','SummaryText'
foreach ($name in $names) { Set-Variable -Name $name -Value $window.FindName($name) }

$script:rootNode = $null
$script:selectedNode = $null
$script:scanJob = $null
$script:duplicateJob = $null
$script:duplicateRows = @()

function Format-Size([long]$bytes) {
    $units = @('B','KB','MB','GB','TB','PB')
    $value = [double]$bytes
    $index = 0
    while ($value -ge 1024 -and $index -lt $units.Count - 1) { $value /= 1024; $index++ }
    if ($index -eq 0) { return ('{0:N0} {1}' -f $value, $units[$index]) }
    return ('{0:N2} {1}' -f $value, $units[$index])
}

function Format-Age([datetime]$date) {
    $days = [Math]::Max(0, [int]([datetime]::Now - $date).TotalDays)
    if ($days -lt 1) { return 'Hoje' }
    if ($days -lt 60) { return "$days dias" }
    if ($days -lt 730) { return ('{0:N1} anos' -f ($days / 365.25)) }
    return ('{0:N0} anos' -f ($days / 365.25))
}

function Test-AgeFilter([datetime]$date) {
    $minimumDays = [int]$AgeFilter.SelectedItem.Tag
    return ($minimumDays -eq 0 -or ([datetime]::Now - $date).TotalDays -ge $minimumDays)
}

function New-TreeItem($node) {
    $item = [System.Windows.Controls.TreeViewItem]::new()
    $item.Header = '{0}  —  {1}' -f $node.Name, (Format-Size $node.TotalSize)
    $item.Tag = $node
    if ($node.Directories.Count -gt 0) {
        [void]$item.Items.Add([System.Windows.Controls.TreeViewItem]::new())
        $item.Add_Expanded({
            param($sender, $eventArgs)
            if ($sender.Items.Count -eq 1 -and $null -eq $sender.Items[0].Tag) {
                $sender.Items.Clear()
                foreach ($child in $sender.Tag.Directories) { [void]$sender.Items.Add((New-TreeItem $child)) }
            }
        })
    }
    return $item
}

function Show-Node($node) {
    $script:selectedNode = $node
    $filter = $FilterBox.Text.Trim()
    $rows = [System.Collections.Generic.List[object]]::new()
    $parentSize = [Math]::Max(1L, $node.TotalSize)

    foreach ($directory in $node.Directories) {
        if ($filter -and $directory.Name.IndexOf($filter, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        $rows.Add([pscustomobject]@{
            Name = $directory.Name; Type = if ($directory.IsReparsePoint) {'Link'} elseif ($directory.IsInaccessible) {'Sem acesso'} else {'Pasta'}
            Size = $directory.TotalSize; SizeText = Format-Size $directory.TotalSize
            PercentText = '{0:N1}%' -f (100 * $directory.TotalSize / $parentSize)
            FileCount = $directory.FileCount; AgeText = ''; Created = ''; Modified = ''; Source = $directory
        })
    }
    foreach ($file in $node.Files) {
        if ($filter -and $file.Name.IndexOf($filter, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        if (-not (Test-AgeFilter $file.LastWriteTime)) { continue }
        $rows.Add([pscustomobject]@{
            Name = $file.Name; Type = if ($file.Extension) {$file.Extension.TrimStart('.').ToUpperInvariant()} else {'Arquivo'}
            Size = $file.Size; SizeText = Format-Size $file.Size
            PercentText = '{0:N1}%' -f (100 * $file.Size / $parentSize)
            FileCount = 1; AgeText = Format-Age $file.LastWriteTime
            Created = $file.CreationTime.ToString('yyyy-MM-dd HH:mm')
            Modified = $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm'); Source = $file
        })
    }
    $ItemsGrid.ItemsSource = @($rows | Sort-Object Size -Descending)
    $SummaryText.Text = '{0} • {1:N0} arquivos • {2:N0} pastas' -f (Format-Size $node.TotalSize), $node.FileCount, $node.DirectoryCount
    $StatusText.Text = $node.FullPath
}

function Start-Scan {
    $target = $PathBox.Text
    if (-not $target) { return }
    try {
        $FolderTree.Items.Clear(); $ItemsGrid.ItemsSource = $null
        $script:rootNode = $null; $script:selectedNode = $null
        $script:scanJob = [DiskScope.Core.Scanner]::Start($target)
        $ScanButton.IsEnabled = $false; $ChooseButton.IsEnabled = $false
        $CancelButton.IsEnabled = $true; $ExportButton.IsEnabled = $false; $ExportPdfButton.IsEnabled = $false
        $FindDuplicatesButton.IsEnabled = $false; $DeleteSelectedButton.IsEnabled = $false
        $DuplicateGrid.ItemsSource = $null; $script:duplicateRows = @()
        $Progress.Visibility = 'Visible'; $StatusText.Text = 'Iniciando análise…'; $SummaryText.Text = ''
        $timer.Start()
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Não foi possível analisar', 'OK', 'Error') | Out-Null
    }
}

$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(250)
$timer.Add_Tick({
    if ($null -eq $script:scanJob) { return }
    $StatusText.Text = 'Analisando: {0}' -f $script:scanJob.CurrentPath
    $SummaryText.Text = '{0:N0} arquivos • {1:N0} pastas' -f $script:scanJob.FilesScanned, $script:scanJob.DirectoriesScanned
    if (-not $script:scanJob.Task.IsCompleted) { return }

    $timer.Stop(); $Progress.Visibility = 'Collapsed'
    $ScanButton.IsEnabled = $true; $ChooseButton.IsEnabled = $true; $CancelButton.IsEnabled = $false
    if ($script:scanJob.Task.IsCanceled) {
        $StatusText.Text = 'Análise cancelada.'; return
    }
    if ($script:scanJob.Task.IsFaulted) {
        $message = $script:scanJob.Task.Exception.GetBaseException().Message
        $StatusText.Text = 'Falha na análise.'
        [System.Windows.MessageBox]::Show($message, 'Erro de análise', 'OK', 'Error') | Out-Null
        return
    }
    $script:rootNode = $script:scanJob.Task.Result
    $rootItem = New-TreeItem $script:rootNode
    [void]$FolderTree.Items.Add($rootItem); $rootItem.IsExpanded = $true; $rootItem.IsSelected = $true
    Show-Node $script:rootNode
    $ExportButton.IsEnabled = $true; $ExportPdfButton.IsEnabled = $true; $FindDuplicatesButton.IsEnabled = $true
})

function Send-ToRecycleBin($source) {
    if ($source -is [DiskScope.Core.FileRecord]) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $source.FullPath,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
    } elseif ($source -is [DiskScope.Core.ScanNode]) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
            $source.FullPath,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
    }
}

function Start-DuplicateSearch {
    if (-not $script:rootNode) { return }
    try {
        $script:duplicateJob = [DiskScope.Core.DuplicateFinder]::Start($script:rootNode)
        $FindDuplicatesButton.IsEnabled = $false; $ScanButton.IsEnabled = $false; $ChooseButton.IsEnabled = $false
        $CancelButton.IsEnabled = $true; $DeleteDuplicatesButton.IsEnabled = $false
        $Progress.Visibility = 'Visible'; $DuplicateGrid.ItemsSource = $null
        $DuplicateSummaryText.Text = 'Preparando candidatos…'; $ResultTabs.SelectedItem = $DuplicatesTab
        $duplicateTimer.Start()
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Busca de duplicados', 'OK', 'Error') | Out-Null
    }
}

$duplicateTimer = [System.Windows.Threading.DispatcherTimer]::new()
$duplicateTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$duplicateTimer.Add_Tick({
    if ($null -eq $script:duplicateJob) { return }
    $done = $script:duplicateJob.HashedFiles; $total = $script:duplicateJob.CandidateFiles
    $StatusText.Text = 'Calculando SHA-256: {0}' -f $script:duplicateJob.CurrentPath
    $DuplicateSummaryText.Text = '{0:N0} de {1:N0} candidatos verificados' -f $done, $total
    if (-not $script:duplicateJob.Task.IsCompleted) { return }

    $duplicateTimer.Stop(); $Progress.Visibility = 'Collapsed'
    $ScanButton.IsEnabled = $true; $ChooseButton.IsEnabled = $true; $CancelButton.IsEnabled = $false
    $FindDuplicatesButton.IsEnabled = $true
    if ($script:duplicateJob.Task.IsCanceled) {
        $StatusText.Text = 'Busca de duplicados cancelada.'; return
    }
    if ($script:duplicateJob.Task.IsFaulted) {
        $message = $script:duplicateJob.Task.Exception.GetBaseException().Message
        [System.Windows.MessageBox]::Show($message, 'Erro na busca de duplicados', 'OK', 'Error') | Out-Null
        return
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $groupNumber = 0; [long]$reclaimable = 0
    foreach ($group in $script:duplicateJob.Task.Result) {
        $groupNumber++; $reclaimable += $group.ReclaimableSize; $index = 0
        foreach ($file in $group.Files) {
            $rows.Add([pscustomobject]@{
                Delete = ($index -gt 0); Group = $groupNumber; Path = $file.FullPath
                Size = $file.Size; SizeText = Format-Size $file.Size
                AgeText = Format-Age $file.LastWriteTime; Modified = $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
                Source = $file; Hash = $group.Hash
            })
            $index++
        }
    }
    $script:duplicateRows = @($rows)
    $DuplicateGrid.ItemsSource = $script:duplicateRows
    $duplicateFiles = $script:duplicateRows.Count - $groupNumber
    $DuplicateSummaryText.Text = '{0:N0} grupos • {1:N0} cópias extras • {2} recuperáveis' -f $groupNumber, $duplicateFiles, (Format-Size $reclaimable)
    $StatusText.Text = if ($groupNumber) { 'Duplicados confirmados por conteúdo (SHA-256).' } else { 'Nenhum arquivo duplicado encontrado.' }
    $DeleteDuplicatesButton.IsEnabled = ($groupNumber -gt 0)
})

function Remove-SelectedItems {
    $selected = @($ItemsGrid.SelectedItems)
    if ($selected.Count -eq 0) { return }
    $preview = @($selected | Select-Object -First 5 | ForEach-Object { $_.Source.FullPath }) -join "`n"
    if ($selected.Count -gt 5) { $preview += "`n… e mais $($selected.Count - 5) item(ns)" }
    $answer = [System.Windows.MessageBox]::Show(
        "Enviar $($selected.Count) item(ns) para a Lixeira?`n`n$preview",
        'Confirmar exclusão', 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { return }

    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $selected) {
        try { Send-ToRecycleBin $row.Source }
        catch { $errors.Add(('{0}: {1}' -f $row.Source.FullPath, $_.Exception.Message)) }
    }
    if ($errors.Count) {
        [System.Windows.MessageBox]::Show(($errors -join "`n"), 'Alguns itens não foram removidos', 'OK', 'Warning') | Out-Null
    }
    Start-Scan
}

function Remove-MarkedDuplicates {
    [void]$DuplicateGrid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true)
    [void]$DuplicateGrid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
    $marked = @($script:duplicateRows | Where-Object { $_.Delete -and (Test-Path -LiteralPath $_.Path -PathType Leaf) })
    if ($marked.Count -eq 0) { return }

    foreach ($group in ($script:duplicateRows | Group-Object Hash)) {
        $existing = @($group.Group | Where-Object { Test-Path -LiteralPath $_.Path -PathType Leaf })
        if ($existing.Count -gt 0 -and @($existing | Where-Object { -not $_.Delete }).Count -eq 0) {
            [System.Windows.MessageBox]::Show(
                "O grupo $($group.Group[0].Group) está com todas as cópias marcadas. Desmarque ao menos uma.",
                'Uma cópia deve ser preservada', 'OK', 'Warning') | Out-Null
            return
        }
    }

    [long]$bytes = ($marked | Measure-Object Size -Sum).Sum
    $answer = [System.Windows.MessageBox]::Show(
        "Enviar $($marked.Count) duplicata(s) para a Lixeira e recuperar aproximadamente $(Format-Size $bytes)?`n`nA cópia mais recente de cada grupo veio desmarcada por padrão.",
        'Confirmar limpeza de duplicados', 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { return }

    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $marked) {
        try { Send-ToRecycleBin $row.Source }
        catch { $errors.Add(('{0}: {1}' -f $row.Path, $_.Exception.Message)) }
    }
    if ($errors.Count) {
        [System.Windows.MessageBox]::Show(($errors -join "`n"), 'Algumas duplicatas não foram removidas', 'OK', 'Warning') | Out-Null
    }
    Start-Scan
}

$ChooseButton.Add_Click({
    $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = 'Selecione a pasta ou unidade que deseja analisar'
    if ($PathBox.Text) { $dialog.SelectedPath = $PathBox.Text }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $PathBox.Text = $dialog.SelectedPath }
    $dialog.Dispose()
})
$ScanButton.Add_Click({ Start-Scan })
$CancelButton.Add_Click({
    if ($script:scanJob -and -not $script:scanJob.Task.IsCompleted) { $script:scanJob.Cancel() }
    if ($script:duplicateJob -and -not $script:duplicateJob.Task.IsCompleted) { $script:duplicateJob.Cancel() }
    $StatusText.Text = 'Cancelando…'
})
$FolderTree.Add_SelectedItemChanged({ if ($FolderTree.SelectedItem) { Show-Node $FolderTree.SelectedItem.Tag } })
$FilterBox.Add_TextChanged({ if ($script:selectedNode) { Show-Node $script:selectedNode } })
$AgeFilter.Add_SelectionChanged({ if ($script:selectedNode) { Show-Node $script:selectedNode } })
$ItemsGrid.Add_SelectionChanged({ $DeleteSelectedButton.IsEnabled = ($ItemsGrid.SelectedItems.Count -gt 0) })
$ItemsGrid.Add_MouseDoubleClick({
    $row = $ItemsGrid.SelectedItem
    if ($row -and $row.Source -is [DiskScope.Core.ScanNode]) { Show-Node $row.Source }
})
$FindDuplicatesButton.Add_Click({ Start-DuplicateSearch })
$DeleteSelectedButton.Add_Click({ Remove-SelectedItems })
$DeleteDuplicatesButton.Add_Click({ Remove-MarkedDuplicates })
$ExportPdfButton.Add_Click({
    if (-not $script:rootNode) { return }
    $dialog = [Microsoft.Win32.SaveFileDialog]::new()
    $dialog.Filter = 'PDF (*.pdf)|*.pdf'; $dialog.FileName = 'relatorio-diskscope.pdf'
    if ($dialog.ShowDialog() -ne $true) { return }
    try {
        $ExportPdfButton.IsEnabled = $false; $StatusText.Text = 'Gerando relatório PDF…'
        $groups = @()
        if ($script:duplicateJob -and $script:duplicateJob.Task.IsCompletedSuccessfully) { $groups = @($script:duplicateJob.Task.Result) }
        $created = Export-DiskScopePdf -RootNode $script:rootNode -DuplicateGroups $groups -OutputPath $dialog.FileName
        $StatusText.Text = 'PDF criado: {0}' -f $created
        [System.Windows.MessageBox]::Show("Relatório criado com sucesso:`n$created", 'Relatório PDF', 'OK', 'Information') | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Não foi possível gerar o PDF', 'OK', 'Error') | Out-Null
        $StatusText.Text = 'Falha ao gerar o PDF.'
    } finally {
        $ExportPdfButton.IsEnabled = ($null -ne $script:rootNode)
    }
})
$ExportButton.Add_Click({
    if (-not $script:rootNode) { return }
    $dialog = [Microsoft.Win32.SaveFileDialog]::new()
    $dialog.Filter = 'CSV (*.csv)|*.csv'; $dialog.FileName = 'diskscope.csv'
    if ($dialog.ShowDialog() -ne $true) { return }
    $allRows = [System.Collections.Generic.List[object]]::new()
    $pending = [System.Collections.Generic.Stack[object]]::new(); $pending.Push($script:rootNode)
    while ($pending.Count) {
        $node = $pending.Pop()
        $allRows.Add([pscustomobject]@{ Type='Folder'; Path=$node.FullPath; SizeBytes=$node.TotalSize; Created=''; Modified=''; AgeDays=''; Files=$node.FileCount; Folders=$node.DirectoryCount })
        foreach ($file in $node.Files) {
            $allRows.Add([pscustomobject]@{
                Type='File'; Path=$file.FullPath; SizeBytes=$file.Size
                Created=$file.CreationTime.ToString('o'); Modified=$file.LastWriteTime.ToString('o')
                AgeDays=[int]([datetime]::Now - $file.LastWriteTime).TotalDays; Files=1; Folders=0
            })
        }
        foreach ($child in $node.Directories) { $pending.Push($child) }
    }
    $allRows | Export-Csv -LiteralPath $dialog.FileName -NoTypeInformation -Encoding UTF8
    $StatusText.Text = 'CSV exportado: {0}' -f $dialog.FileName
})
$window.Add_Closing({
    if ($script:scanJob -and -not $script:scanJob.Task.IsCompleted) { $script:scanJob.Cancel() }
    if ($script:duplicateJob -and -not $script:duplicateJob.Task.IsCompleted) { $script:duplicateJob.Cancel() }
})

if ($Path -and (Test-Path -LiteralPath $Path -PathType Container)) { $PathBox.Text = (Resolve-Path -LiteralPath $Path).Path }
[void]$window.ShowDialog()
