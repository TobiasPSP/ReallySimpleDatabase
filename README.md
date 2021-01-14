# ReallySimpleDatabase
Home of the PowerShell module ReallySimpleDatabase to work with SQLite databases

## Install

Install module from *PowerShell Gallery*:

```powershell
Install-Module -Name ReallySimpleDatabase -Scope CurrentUser
```

## Usage

The module imports two cmdlets: `Get-Database` and `Import-Database`.  With these two cmdlets, you can create new SQLite databases, add data to existing databases, or read data from existing database tables. 

There are no additional dependencies required, and the SQLite database created is a single file that is easily manageable.

### Create New Database / Open Existing Database

To create a new SQLite database (or open an existing database), use `Get-Database`:

```
PS> $database = Get-Database -Path $env:temp\mydb.db
PS> $database

Path                 Connection           IsOpen QueryT LockDa Enable
                                                 imeout tabase Unsafe
                                                               Perfor
                                                               manceM
                                                               ode
----                 ----------           ------ ------ ------ ------
C:\Users\tobia\Ap...                      False     600 False  False


PS> $database | Select-Object -Property *


EnableUnsafePerformanceMode : False
LockDatabase                : False
FileSize                    : 118.784 KB
Path                        : C:\Users\tobia\AppData\Local\Temp\mydb.db
Connection                  :
IsOpen                      : False
QueryTimeout                : 600
```

If you omit the parameter `-Path`, then a in-memory-database is created which is very fast but won't persist.

### Creating Tables

To create new tables, simply pipe data to `Import-Database`:

```powershell
Get-Process | Import-Database -Database $database -TableName Processes
Get-Service | Import-Database -Database $database -TableName Services
```

`Import-Database` automatically analyzes the objects and creates the field definitions on the fly.

### Adding Data to Tables

To add more data to an existing database table, pipe to `Import-Database`:

```powershell
# add another process to table "processes"
Get-Process -Id $Pid | Import-Database -Database $database -TableName Processes
```

### List Tables

To list all tables in a database, run this:

```powershell
PS> $database = Get-Database -Path $env:temp\mydb.db
PS> $database.GetTables()

Name      Value
----      -----
Processes 197   :Name,SI,Handles,VM,WS,PM,NPM,Path,Company,CPU,FileVersion,ProductVe...
Services  292   :Name,RequiredServices,CanPauseAndContinue,CanShutdown,CanStop,Displ...
```

### Read Data

Use standard **SQL** to read data from a database:

```
PS> $database = Get-Database -Path $env:temp\mydb.db
PS> $database.InvokeSql('select * from processes where name like "a%"') | Format-Table

Name                 SI Handles            VM        WS       PM   NPM Path
----                 -- -------            --        --       --   --- ----
ApplicationFrameHost  1     460 2203637399552 110505984 61837312 27328 C:\WINDOWS\sy...
armsvc                0     123      69296128   6488064  1630208  8688
```

## Example: Dump Chrome Passwords

The browser *Chrome* uses a **SQLite** database to internally store password data. The user can dump this information like so:

```powershell
# default path to Chrome user passwords database:
$Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
# check whether database exists:
$exists = Test-Path -Path $path -PathType Leaf
# if it is missing, then you might not be using the Google Chrome browser:
if (!$exists)
{
  Write-Warning "No Chrome Database found."
  return
}

# define function to decrypt encrypted text
function Unprotect-Secret($value)
{
  Add-Type -AssemblyName System.Security
  $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect($value,$null,[System.Security.Cryptography.DataProtectionScope]::CurrentUser)
  [System.Text.Encoding]::Default.GetString($bytes)
}

# copy the database (the original file is locked while Chrome is running):
$Destination = "$env:temp\database.db"
Copy-Item -Path $Path -Destination $Destination

# query to retrieve the cached passwords:
$sql = "SELECT action_url, username_value, password_value FROM logins"

#region define calculated properties
# rename column headers:
$url = @{N='Url';E={$_.action_url}}
$username = @{N='Username';E={$_.username_value}}
$password = @{N='Password'; E={Unprotect-Secret -Secret $_.password_value}} 
#endregion define calculated properties                          

$db = Get-Database -Path $Destination
$db.InvokeSql($sql) | Select-Object $url, $username,$password 
```

Note that only the user who saved the passwords can dump them. Chrome uses the Windows cryptography API which protects the passwords by using the machine and user identity.
