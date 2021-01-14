
# load platform-specific sqlite binaries
& "$PSScriptRoot\loadbinaries.ps1"

# load logic (dot-sourced)
. "$PSScriptRoot\logic.ps1"

# declare public module members
Export-ModuleMember -Function Get-Database, Import-Database

# register argument completers


Register-ArgumentCompleter -ParameterName TableName -CommandName Import-Database -ScriptBlock {
  param
  (
    $CommandName,
    $ParameterName,
    $WordToComplete,
    $CommandAst,
    $params
  )

  
  if ($params.ContainsKey('Database'))
  {
    $db = $params['Database'] -as [Database]
    if ($db -ne $null)
    {
      try 
      {
        $tables = $db.GetTables()
        $tables.Keys -like "$WordToComplete*" |
          ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, [System.Management.Automation.CompletionResultType]::ParameterValue, ("$($tables[$_])".Trim() | Out-String))
          }
      }
      catch {}
    }
  }
}

Register-ArgumentCompleter -ParameterName Database -CommandName Import-Database -ScriptBlock {
  param
  (
    $CommandName,
    $ParameterName,
    $WordToComplete,
    $CommandAst,
    $params
  )

  Get-Variable | Where-Object {
    $_.Value -is [Database]
  } | ForEach-Object {
    $value = '${0}' -f $_.Name
    [System.Management.Automation.CompletionResult]::new($value, $value, [System.Management.Automation.CompletionResultType]::Variable, ("$($_.Value)".Trim() | Out-String))
  }
}