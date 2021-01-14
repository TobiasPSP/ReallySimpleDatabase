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

```powershell
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

```powershell
PS> $database = Get-Database -Path $env:temp\mydb.db
PS> $database.InvokeSql('select * from processes where name like "a%"') | Format-Table

Name                 SI Handles            VM        WS       PM   NPM Path
----                 -- -------            --        --       --   --- ----
ApplicationFrameHost  1     460 2203637399552 110505984 61837312 27328 C:\WINDOWS\sy...
armsvc                0     123      69296128   6488064  1630208  8688
```
