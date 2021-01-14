

#region Class Definitions
# this class represents a table column
class Field
{
  #region public properties

  # store all important details such as the table this column belongs to
  # the table object includes a reference to the database
  [Table]$Table
  [string]$Name
  [string]$Type
  [bool]$NotNull
  [object]$DefaultValue
  [int]$Id
  #endregion public properties

  #region CONSTRUCTOR
  # the constructor takes the table object plus the datarow returned by the
  # database with the column details
  Field([Table]$Table, [System.Data.DataRow]$ColumnInfo)
  {
    # translate the raw datarow information to the Column object properties:
    $this.Name = $ColumnInfo.Name
    $this.Type = $ColumnInfo.type
    $this.NotNull = $ColumnInfo.notnull
    $this.DefaultValue = $ColumnInfo.dflt_value
    $this.Table = $Table
    $this.Id = $ColumnInfo.cid
  }
  #endregion CONSTRUCTOR
  
  #region methods

  #region dynamic methods (bound to instance object)
  # create an index for this column
  [void]AddIndex()
  {
    # do we have an index for this column already?
    $tbl = $this.Table
    $clm = $this.Name
    
    $existingIndex = $tbl.GetIndexes() | 
    Where-Object { $_.Column.Name -eq $this.Name } | 
    Select-Object -First 1
    
    if ($existingIndex -ne $null)
    {
      $existing = $existingIndex.Name
      throw "$clm uses index $existing already. Remove this index before adding a new one."
    }
    
    $columnName = $this.Name
    $tableName = $this.Table.Name
    $indexName = "idx_" + $this.Name 
    $database = $this.Table.Database
    
    $database.AddIndex($indexName, $tableName, $columnName, $false)
  }
  
  # create an index for this column
  [void]AddUniqueIndex()
  {
    $columnName = $this.Name
    $tableName = $this.Table.Name
    $indexName = "idx_" + $this.Name 
    $database = $this.Table.Database
    
    $database.AddIndex($indexName, $tableName, $columnName, $true)
  }

  # removes all indices for this column
  [void]DropIndex()
  {
    $indexes = $this.Table.GetIndexes()[$this.Name]
    foreach($index in $indexes)
    {
      $sql = "Drop Index If Exists $($index.Name)"
      $this.Table.Database.InvokeSqlNoResult($sql)
    }
  }
    
  # override the ToString() method to provide a more meaningful display
  [string]ToString()
  {
    return '{0} ({1})' -f $this.Name, $this.Type
  }

  #endregion dynamic methods (bound to instance object)

  #endregion methods
}



# this class represents a single property
# it specifies the property name and the property value type
class NewFieldRequest
{
  [string]$Name
  [string]$Type
  
  NewFieldRequest([string]$Name, [string]$Type)
  {
    $this.Name = $Name
    $this.Type = $Type
  }

  # override the default ToString() method to provide a more
  # meaningful display
  [string]ToString()
  {
    # show the property name and property value type
    if ($this.Type -eq 'String')
    {
      return "'{0}' '{1}' COLLATE NOCASE" -f $this.Name, $this.Type
    }
    return "'{0}' '{1}'" -f $this.Name, $this.Type
  }
}


# represents a SQLite database and can either be file-based or memory-based
# requires the SQLite DLL to be imported
# requires these classes:
class Database
{
  #region public properties
  [string]$Path
  [System.Data.SQLite.SQLiteConnection]$Connection
  [bool]$IsOpen = $false

  # maximum time (in sec) for a query to complete
  # if a query takes more time, an exception is thrown
  # 600 represents 600 sec. = 10 min.
  # make sure you adjust this property if the query is expected to 
  # take longer, i.e. when inserting large numbers of objects
  # via Import-Database
  [int]$QueryTimeout = 600
  #endregion public properties

  #region hidden properties
  hidden [bool]$_enableUnsafePerformanceMode = $false
  hidden [bool]$_lockDatabase = $false
  hidden [string]$_path
  #endregion hidden properties

  #region define CONSTRUCTOR (Path: path to the database, or :memory:)

  # constructor takes the path to the database file
  # the file does not need to exist yet. It will be created if it does not yet exist.
  # If the path is ":memory:", then a memory-based database is created
  Database([string]$Path)
  {
        

    #region validate submitted path
    if ($Path -ne ':memory:')
    {
      # store the path
      $this.Path = $Path

      # check valid file path
      $valid = Test-Path -Path $Path -IsValid
      if (!$valid)
      {
        throw [System.ArgumentException]::new("Path is invalid: $Path") 
      }
        
      # emit a file extension warning if a non-default extension is used
      $extension = [IO.Path]::GetExtension($this.Path)
      if ($extension -ne '.db')
      {
        Write-Warning "Database files should use the extension '.db'. You are using extension '$extension'."
      }
        
      # check whether the path is relative
      $resolved = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        
      # emit a warning on relative paths
      if ($resolved -ne $Path) 
      { 
        Write-Warning "Absolute file paths preferred. Your path '$Path' resolved to '$resolved'"
        $this.Path = $resolved 
      }

      # save the path in hidden field
      $this._path = $this.Path
    }
    else
    {
      # save the path in hidden field
      $this._path = $Path
      $this.Path = '[memory]'
    }
    #endregion validate submitted path
    
    #region add SETTER properties (implemented via Add-Member)
    # add a scriptproperty to mimick setter properties

    #region "EnableUnsafePerformanceMode"
    #
    # when a new value is assigned, the database changes
    # when this property is set to $true, a number of database features
    # are changed to increase performance at the expense of safety
    # - the journal is switched to MEMORY which might cause data corruption when the
    #   script crashes in the middle of adding new data
    # - database synchronization is turned off which can cause data corruption
    #   when the database crashes
    $this | Add-Member -MemberType ScriptProperty -Name EnableUnsafePerformanceMode -Value {$this._enableUnsafePerformanceMode } -SecondValue {
      param($enable)
      
      # a hidden property is used to store the desired mode
      $this._enableUnsafePerformanceMode = $enable
      # if the database is open already, the change is made immediately
      # else, the change is performed later whenever Open() is called
      if ($this.IsOpen)
      {
        if ($enable)
        {
          $mode1 = 'OFF'
          $mode2 = 'MEMORY'
        }
        else
        {
          $mode1 = 'ON'
          $mode2 = 'DELETE'
        }
        $this.InvokeSqlNoResult("PRAGMA JOURNAL_MODE=$mode2")
        $this.InvokeSqlNoResult("PRAGMA SYNCHRONOUS=$mode1")
      }
    }
    #endregion "EnableUnsafePerformanceMode"

    #region "LockDatabase"
        
    # yet another scriptproperty that works very similar to EnableUnsafePerformanceMode
    # to increase performance, the database file can be locked
    # when the database file is locked, no other can access, delete, copy or move
    # the file
    $this | Add-Member -MemberType ScriptProperty -Name LockDatabase -Value {$this._lockDatabase } -SecondValue {
      param($enable)
      
      $this._lockDatabase = $enable
      if ($this.IsOpen)
      {
        if ($enable)
        {
          $mode = 'exclusive'
        }
        else
        {
          $mode = 'normal'
        }
        $this.InvokeSqlNoResult("PRAGMA LOCKING_MODE=$mode")
      }
    }
    #endregion "LockDatabase"

    #endregion add SETTER properties (implemented via Add-Member)

    #region add GETTER properties (implemented via Add-Member)...

    # the purpose of GETTER properties is to execute code
    # whenever the property is read. This way, the property
    # can return up-to-date information for things that are
    # not static

        
    #region "FileSize"
        
    # the getter is used to freshly calculate the actual
    # database file size
    $this | Add-Member -MemberType ScriptProperty -Name FileSize -Value {
      if ($this._Path -eq ':memory:')
      {
        'In-Memory Database'
      }
      else
      {
        $exists = Test-Path -Path $this.Path -PathType Leaf
        if ($exists)
        {
          "{0:n0} KB" -f (Get-Item -LiteralPath $this.Path).Length
        }
        else
        {
          'no file created yet'
        }
      }
    } 
    #endregion "FileSize"

    #endregion add GETTER properties (implemented via Add-Member)...
  }  
  #endregion define CONSTRUCTOR (Path: path to the database, or :memory:)

  #region define METHODS

  #region dynamic methods (bound to an object instance)

  #region Invoke Sql Statements

  #region "InvokeSqlNoResult"

  # send a SQL statement to the database
  # this method is used for sql statements that do not return anything
  [void]InvokeSqlNoResult([string]$Sql)
  {
    # the database is opened in case it is not open yet
    # if it is open already, the call does nothing
    # generally, the database is kept open after all methods
    # it is closed only when PowerShell ends, or when Close() is called
    # explicitly
    $this.Open()

    # create an SQL command and use the default timeout set in the 
    # database property
    $cmd = $this.Connection.CreateCommand()
    $cmd.CommandText = $Sql
    $cmd.CommandTimeout = $this.QueryTimeout
    $null = $cmd.ExecuteNonQuery()

    # the command object is disposed to free its memory
    $cmd.Dispose()
  }
  #endregion "InvokeSqlNoResult"

  #region "InvokeSql"

  # similar to InvokeSqlNoResult, however this method does return
  # data to the caller
  [System.Data.DataRow[]]InvokeSql([string]$Sql)
  {
    $this.Open()
    $cmd = $this.Connection.CreateCommand()
    $cmd.CommandText = $Sql
    $cmd.CommandTimeout = $this.QueryTimeout
    
    # create a new empty dataset. It will be filled with the
    # results later
    $ds = [System.Data.DataSet]::new() 

    # create a new data adapter based on the sql command
    $da = [System.Data.SQLite.SQLiteDataAdapter]::new($cmd)
    
    # fill the dataset with the results       
    $null = $da.fill($ds)

    # dispose the command to free its memory
    $cmd.Dispose()
    
    # return the table rows received in the dataset
    return $ds.Tables.Rows
  }
  #endregion "InvokeSql"

  [System.Data.DataRow[]]InvokeSql([string]$Sql, [bool]$CaseSensitive)
  {
    # remove all collate statements
    $sql = $sql -replace 'collate\s{1,}(binary|nocase|rtrim)\s{0,}'
    
    # add appropriate
    if ($CaseSensitive)
    {
      $sql += " collate binary"
    }
    else
    {
      $sql += " collate nocase"
    }
    
    return $this.InvokeSql($sql)
  }
  #endregion Invoke Sql Statements

  # explicitly close the database
  # typically, any method acting on the database will open the database
  # and keep it open, so consecutive methods can reuse the open connection
  # the database is closed only when PowerShell ends
  # to explicitly close the database, Close() must be called
  [void]Close()
  {
    # closes the current database connection
    # this is a CRITICAL operation for databases stored solely in memory
    # while file-based databases keep the data, memory-based databases are deleted
    # including all data collected inside of them
    if ($this.IsOpen)
    {
      $this.Connection.Close()

      # dispose the connection to free its memory
      $this.Connection.Dispose()

      # set the property to $null so when a user views the database
      # object, the old connection no longer shows up
      $this.Connection = $null

      # update this state property
      $this.IsOpen = $false
    }
  }

  # whenever a method wants to access the database, it must have an open connection
  [void]Open()
  {
    # if the database connection is already open, bail out:
    if ($this.IsOpen) { return }
    
    # create a new database connection using the path as connection string
        
    $ConnectionString = 'Data Source={0}' -f $this._path
    $this.Connection = [System.Data.SQLite.SQLiteConnection]::new($ConnectionString)

    # set this property to $true to allow UNC paths to work
    $this.Connection.ParseViaFramework = $true 

    # override the default ToString() method so that this object displays a more
    # meaningful string representation
    $this.Connection | Add-Member -MemberType ScriptMethod -Name ToString -Force -Value {
      # display the sqlite server version, the currently used memory in KB, and the state
      '{1:n0} KB,{2},V{0}' -f $this.ServerVersion, ($this.MemoryUsed/1KB),$this.State
    }
     
    # open the database connection           
    Try
    {
      $this.Connection.Open() 
    }
    Catch
    {
      # if the database cannot be opened, throw an exception
      # there are many different reasons why opening the database may fail. Here are some:
      # - the database file does not exist (should be validated by Get-Database)
      # - the user has no write permission to the database file
      #   - it may reside in a restricted place, i.e. the c:\ root folder
      #   - it may be locked by another application
      # - there is not enough free space on the drive left
      #
      # Unfortunately, the internally thrown exception does not provide a clue
      # it just complains that opening the database file did not work
      # so we cannot provide detailed guidance
      $message = "Cannot open database. You may not have sufficient write perission at this location, or the drive is full. Database file: $($this._path). Original error message: $($_.Exception.Message)"
      throw [System.InvalidOperationException]::new($message)
    }

    # set the state property accordingly:
    $this.IsOpen = $true
    
    # there are a number of performance options that a user can specify
    # these options do not take effect until the database is opened
    # so now that the database is open, the requested changes are applied
    # the requests are stored in hidden properties
    if ($this._enableUnsafePerformanceMode) { $this.EnableUnsafePerformanceMode = $true }
    if ($this._lockDatabase) { $this.LockDatabase = $true }
  }

  # returns all tables in the database as an ordered hashtable equivalent
  # a hashtable is used to make it easier to access a table directly via code
  # and also to provide a fast way of looking up tables
  # for example, thanks to the hashtable, code like this is possible:
  # $db.GetTables().masterTable.GetColumns()
  # an ordered hashtable is used to get an ordered list of tables without
  # having to sort anything again
  [System.Collections.Specialized.OrderedDictionary]GetTables()
  {
    $sql = "SELECT * FROM sqlite_master WHERE type='table' ORDER BY name;"
    $tables = $this.InvokeSql($sql)

    # create an empty ordered hashtable which really is a special case of
    # a dictionary
    $hash = [Ordered]@{}

    # add the tables to the hashtable
    foreach($row in $tables)
    {
      # use the table name as key, and create a Table object for the table
      $hash[$row.Name] = [Table]::new($this, $row)
    }
    return $hash
  }
  
  # get a specific table
  [Table]GetTable([string]$TableName)
  {
    # sqlite queries are case-sensitive. Since tables with a given name can exist
    # only once, regardless of casing, the search needs to be case-insensitive
    # for this to happen, add COLLATE NOCASE to the sql statement
    $sql = "SELECT * FROM sqlite_master WHERE type='table' and Name='$TableName' COLLATE NOCASE"
    $tables = $this.InvokeSql($sql)

    # if the table is not present, return $null
    if ($tables -eq $null) { return $null }

    # else return a Table object for the found table
    return [Table]::new($this, $tables[0])
  }
  
  # helper function (TODO make this static)
  # it takes any object and returns an array of ColumnInfo objects describing
  # the properties and their data types
  # this information can be used to construct a table definition based on any
  # object type
  [NewFieldRequest[]]GetFieldNamesFromObject([object]$data)
  {
    # get all members from the object via the hidden PSObject property
    $names = [object[]]$data.psobject.Members | 
    # select properties only 
    # (including dynamicly added properties such as ScriptProperties)
    Where-Object {$_.MemberType -like '*Property'} |
    # determine the appropriate data type and construct the ColumnInfo object
    ForEach-Object {
      $name = $_.Name
      # take the string name of the data type
      $type = $_.TypeNameOfValue
      # if there is no specific type defined, and if the object property
      # contains data, use the type from the actual value of the property
      if (($type -eq 'System.Object' -or $type -like '*#*') -and $_.Value -ne $null) { 
        $type = $_.Value.GetType().FullName
      }

      # remove the System namespace.
      if ($type -like 'System.*') { $type = $type.Substring(7) }
      # any complex and specific type now contains one or more "."
      # since the database supports only basic types, for complex types
      # the string datatype is used instead
      if ($type -like '*.*') { $type = 'String' }
      if ($type -eq 'boolean') { $type = 'Bool' }   
      # create the ColumnInfo object
      [NewFieldRequest]::new($name, $type)
    }

    # return the array of ColumnInfo objects that represent each
    # object property
    return $names
  }

  # add a new index
  [void]AddIndex([string]$Name, [string]$TableName, [string[]]$ColumnName, [bool]$Unique)
  {
    $UniqueString = ('','UNIQUE ')[$Unique]
    $ColumnString = $columnName -join ', '
    $sql = "Create $UniqueString Index $Name On $TableName ($columnString);"
        
    # creating an index may take a long time, so take a look at the table size
    $table = $this.GetTable($TableName)
    if ($table -eq $null)
    {
      throw "Table $table not found."
    }
    elseif ($table.Count -gt 10000)
    {
      Write-Warning "Creating an index on large tables may take considerable time. Please be patient."
    }
        
    try
    {
      $this.InvokeSqlNoResult($sql)
    }
    catch
    {
      if ($Unique -and $_.Exception.InnerException.Message -like '*constraint*')
      {
        throw "There are datasets in your table that share the same values, so a unique index cannot be created. Try a non-unique index instead."
      }
      throw $_.Exception
    }
        
  }

  #endregion dynamic methods (bound to an object instance)

  # backup the database to a file
  # this can also be used to save an in-memory-database to file
  [System.IO.FileInfo]Backup([string]$Path)
  {
    $this.InvokeSqlNoResult("VACUUM INTO '$Path';")
    return Get-Item -LiteralPath $Path 
  }

  [string]ToString()
  {
    
    # show the property name and property value type
    return 'Database,Tables {0} ({1})' -f ($this.GetTables().Keys -join ','),$this.FileSize
  }
  
  #endregion define METHODS
}

# this class represents an index in a database table
class Index
{
  [string]$Name
  [bool]$Unique
  [bool]$IsMultiColumn
  # column contains references to database and table
  [Field[]]$Column
  
  Index([string]$Name, [bool]$Unique, [Field[]]$Column)
  {
    $this.Name = $Name
    $this.Unique = $Unique
    $this.Column = $Column
    $this.IsMultiColumn = $Column.Count -gt 1
  }

  # override the default ToString() method to provide a more
  # meaningful display
  [string]ToString()
  {
    
    # show the property name and property value type
    return '{0} on {1} ({2}, {3})' -f $this.Name, $this.Column.Name, $this.Column.Type, ('NONUNIQUE','UNIQUE')[$this.Unique]
  }
  
  # remove index
  [void]DropIndex()
  {
    $sql = "Drop Index If Exists $($this.Name)"
    $this.Column.Table.Database.InvokeSqlNoResult($sql)
    
  }
}

# this class represents a database table
class Table
{
  # store all important details including the database this table lives in
  [Database]$Database
  [string]$Name
  [bool]$HasErrors
  [string]$RowError
  [System.Data.DataRowState]$RowState
  [string]$Definition
  
  # the constructor takes the database plus the original datarow with the
  # table infos returned by the database
  Table([Database]$Database, [System.Data.DataRow]$TableInfo)
  {
    # translate the original datarow object to the Table object properties:
    $this.Name = $TableInfo.Name
    $this.Definition = $TableInfo.Sql
    $this.Database = $Database
    $this.RowError = $TableInfo.RowError
    $this.RowState = $TableInfo.RowState
    $this.HasErrors = $TableInfo.HasErrors
        
    #region GETTER script properties
    # add scriptproperty "Count" to mimick a getter, and freshly calculate
    # the number of records in this table
    # note that Count is part of the immediately visible properties so when a user
    # dumps a table, this immediately calculates the actual number of records
    # and displays it along with the other details 
    
    # since Count(*) takes a long time on large tables, we output the number of rows
    # this is a good approximation but will not take into account deleted records
    # as the row id is constantly increasing
    $this |
    Add-Member -MemberType ScriptProperty -Name Count -Value {
      #$this.Database.InvokeSql("Select Count(*) from $($this.Name)") |
      $count = $this.Database.InvokeSql("SELECT MAX(_ROWID_) FROM $($this.Name) LIMIT 1;") |
      #Select-Object -ExpandProperty 'Count(*)'
      Select-Object -ExpandProperty 'MAX(_ROWID_)'
      if ($Count -eq [System.DBNull]::Value)
      {
        'EMPTY'
      }
      else
      {
        $count
      }
    }
    #endregion 
  }

  # get the column names and types of this table
  # similar approach as GetTables() in regards to returning an ordered hashtable  
  [System.Collections.Specialized.OrderedDictionary]GetFields()
  {
    # get the detailed table information for this table
    $sql = 'PRAGMA table_info({0});' -f $this.Name
    # and translate each returned record into a Column object  
    $hash = [Ordered]@{}
    foreach($column in $this.Database.InvokeSql($sql))
    {
      $hash[$column.Name] = [Field]::new($this, $column)
    }
    return $hash
  }
  
  
  # override the ToString() method so that this object displays in a more
  # meaningful way
  [string]ToString()
  {
    # return the number of records in this table, left-bound with a minimum of 6 characters,
    # plus a comma-separated list of the table columns
    return '{0,-6}:{1}' -f $this.Count, ($this.GetFields().Keys -join ',')
  }
  
  [int]GetRecordCount()
  {
    return ($this.Database.InvokeSql("Select Count(*) from $($this.Name)") |
    Select-Object -ExpandProperty 'Count(*)') -as [int]
  }
  
  # delete the table from the database
  [void]DropTable()
  {
    # WARNING: the table and all of its data is immediately deleted
    $SQL = "Drop Table $($this.Name);"
    $this.Database.InvokeSQL($SQL) 
  }
  
  # get indices
  [Index[]]GetIndexes()
  {
    $tableName = $this.Name
    $columns = $this.GetFields()
    
    $sql = "PRAGMA index_list('$tableName')"
    $indexes = foreach($index in $this.Database.InvokeSql($sql))
    {
      $indexName = $index.Name
      [bool]$unique = $index.Unique
      $columnName = $this.Database.InvokeSql("PRAGMA index_info('$indexName')").name
      [Index]::new($indexName, $unique, $columns[$columnName])
    }
    return $indexes
  }

  [System.Data.DataRow[]]GetData()
  {
    # dump all table data
    $sql = "select * from {0}" -f $this.Name
    return $this.Database.InvokeSql($sql)
  }

  [System.Data.DataRow[]]GetData([string]$Filter)
  {
    # dump all table data
    $sql = "select * from {0} where $Filter" -f $this.Name
    return $this.Database.InvokeSql($sql)
  }

  [System.Data.DataRow[]]GetData([string]$Filter, [bool]$CaseSensitive)
  {
    # dump all table data
    $sql = "select * from {0} where $Filter" -f $this.Name
    return $this.Database.InvokeSql($sql, $CaseSensitive)
  }
    
  # TODO: add method to query this table
}



#endregion Class Definitions

#region functions



function Get-Database
{
  <#
      .SYNOPSIS
      Returns a database object representing a SQLite database. 
      The database object provides all properties and methods to
      view and manage the database
      Its content (tables, columns, indices, etc) and can execute SQL statements
      Most of the functionality is found in the nested objects.
      To create new tables and store new data in the database, use Import-Database and
      supply the database object to this function

      .EXAMPLE
      $db = Get-Database
      returns a memory-based database

      .EXAMPLE
      $db = Get-Database -Path $env:temp\test.db
      Opens the file-based database. If the file does not exist, a new database file is created

      .EXAMPLE
      $db = Get-Database -Path c:\data\database1.db
      $db.GetTables()
      opens the file-based database and lists the tables found in the database

      .EXAMPLE
      $db = Get-Database -Path c:\data\database1.db
      $db.InvokeSQL('Select * from customers')
      runs the SQL statement and queries all records from the table "customers".
      The table "customers" must exist.
    
  #> 
  param
  (
    # path to the database file. If the file does not yet exist, it will be created
    # this parameter defaults to ":memory:" which creates a memory-based database
    # memory-based databases are very fast but the data is not permanently stored
    # once the database is closed or PowerShell ends, the memory-based database is
    # deleted
    [String]
    [Parameter(Mandatory=$false)]
    $Path = ':memory:'
  )

  # all work is done by the constructor of Database
  return [Database]::new($Path) 
}

function Import-Database
{
  <#
      .SYNOPSIS
      Imports new data to a database table. Data can be added to existing or new tables.
      Use Get-Database to get a database first.
      .DETAILS
      Import-Database automatically examines incoming objects and creates the
      table definition required to store these objects. The first object received
      by Import-Database determines the table layout.
      If the specified table already exists, Import-Database checks whether the existing
      table has fields for all object properties.

      .EXAMPLE
      $db = Get-Database
      Get-Service | Import-Database -Database $db -Table Services
      $db.InvokeSql('Select * From Services') | Out-GridView
      creates a memory-based database, then pipes all services into the database
      and stores them in a new table called "Services"
      Next, the table content is queried via Sql and the result displays in a gridview
      Note that the database content is lost once PowerShell ends

      .EXAMPLE
      $db = Get-Database -Path $env:temp\temp.db
      Get-Service | Import-Database -Database $db -Table Services
      $db.InvokeSql('Select * From Services') | Out-GridView
      opens the file-based database in $env:temp\temp.db, and if the file does not exist,
      a new file is created. All services are piped into the database
      and stored in a table called "Services". 
      If the table "Services" exists already, the data is appended to the table, else
      a new table is created.
      Next, the table content is queried via Sql and the result displays in a gridview
      Since the database is file-based, all content imported to the database is stored
      in the file specified.

      .EXAMPLE
      $db = Get-Database -Path $env:temp\temp.db
      $db.QueryTimeout = 6000
      Get-ChildItem -Path c:\ -Recurse -ErrorAction SilentlyContinue -File | 
      Import-Database -Database $db -Table Files
      Writes all files on drive C:\ to table "Files". Since this operation may take a long
      time, the database "QueryTimeout" property is set to 6000 seconds (100 min)
      A better way is to split up data insertion into multiple chunks that execute
      faster. This can be achieved via -TransactionSet. This parameter specifies the
      chunk size (number of objects) that should be imported before a new transaction
      starts.

      .EXAMPLE
      $db = Get-Database -Path $home\Documents\myDatabase.db
      Get-ChildItem -Path $home -Recurse -File -ErrorAction SilentlyContinue |
      Import-Database -Database $db -Table FileList -UseUnsafePerformanceTricks -LockDatabase -TransactionSet 10000
      $db.InvokeSql('Select * From FileList Where Extension=".log" Order By "Length"') | Out-GridView
      A file-based database is opened. If the file does not yet exist, it is created.
      Next, all files from the current user profile are collected by Get-ChildItem,
      and written to the database table "FileList". If the table exists, the data is
      appended, else the table is created.
      Next, the table "FileList" is queried by Sql, and all files with extension ".log"
      display in a gridview ordered by file size
      To improve performance, Import-Database temporarily locks the database and turns off
      database features that normally improve robustness in the event of a crash.
      By turning off these features, performance is increased considerably at the expense
      of data corruption. 
    
  #> 
  param
  (
    # Database object returned by Get-Database
    [Database]
    [Parameter(Mandatory)]
    $Database,
  
    # Name of table to receive the data. If the table exists, the data appends the table.
    # Else, a new table is created based on the properties of the first received object.
    [String]
    [Parameter(Mandatory)]
    $TableName,
    
    # the data to be written to the database table
    [Object[]]
    [Parameter(Mandatory,ValueFromPipeline)]
    $InputObject,
    
    # to increase performance, transactions are used. To increase robustness and
    # receive progress information, the transaction can be limited to any number of
    # new objects. Once the number of objects have been written to the database table,
    # the transaction is committed, status information and stats are returned,
    # and a new transaction starts. 
    [int]
    # commit data to database at least after these many of new data sets
    $TransactionSet = 20000,
    
    # temporarily turns off cost-intensive security features to increase speed
    # at the expense of a higher risk of data corruption if the database crashes
    # during the operation
    [Switch]
    # speeds up data insertion at the expense of protection against data corruption in case of crashes or unexpected failures
    $UseUnsafePerformanceTricks,

    # temporarily locks access to the database file to increase speed.
    # While the database file is locked, noone else can access the database.    
    [Switch]
    $LockDatabase,

    # takes the first object and defines the table. Does not add any data
    # this can be used to predefine a new table layout based on a sample
    # object
    [Switch]
    $DefineTableOnly,

    # when the type of a field does not match the type of an object property,
    # the type is autoconverted to the existing field type
    [Switch]
    $AllowTypeConversion,
    
    # returns the table object
    [Switch]
    $PassThru
  )
  
  begin 
  {
    # count the incoming objects
    $dataSetCount = 0

    # the first object is examined to figure out the table layout
    $first = $true

    #region Performance Options
    # if performance options were specified, save the current values
    # so they can be restored later, and apply the changes
    $oldSetting1 = $oldSetting2 = $null
    if ($UseUnsafePerformanceTricks)
    {
      $oldSetting1 = $database.EnableUnsafePerformanceMode
      $database.EnableUnsafePerformanceMode = $true
    }
    if ($LockDatabase)
    {
      $oldSetting2 = $database.LockDatabase
      $database.LockDatabase = $true
    }
    #endregion Performance Options

    # make sure the database can store the maximum amount of data
    $database.InvokeSqlNoResult('PRAGMA PAGE_SIZE=65535')
  }
  
  process
  {
    # process any object that is received either via the pipeline
    # or via an array
    foreach($object in $InputObject)
    {
      #region process first incoming object
      # if this is the first data item, we need to find out the 
      # column definition
      if ($first)
      {
        $first = $false
                
        $wmiDatePattern = '^\d{14}\.\d{6}\+\d{3}$'

        # get the requirements for this object
        $Fields = $database.GetFieldNamesFromObject($object)
    
        # keep record of target field types so when data is inserted,
        # it can be converted to the desired type if required
        $fieldTypes = @{}
        $fields | ForEach-Object { $fieldTypes[$_.Name] = $_.Type }
    
        #region get or create table
        # check for the destination table inside the database
        $table = $database.GetTable($TableName)
        if ($table -eq $null)
        {
          # if it does not yet exist, create it based on the requirements
          # of the first object

          # we use the "object field separator" in $ofs to quickly
          # create the sql field string. $Fields contains an array of
          # Column objects. Their ToString() method displays field name and
          # field type separated by a space. The OFS turns the array into
          # a string and uses the string specified in $ofs to concatenate
          # the array elements, thus a comma-separated list is created:
          $ofs = ','
          $fieldstring = "$Fields".TrimEnd(',')

          # create the table based on the fieldstring:
          $query = 'CREATE TABLE {0} ({1})' -f $TableName, $fieldString
          $Database.InvokeSqlNoResult($query)

          # keep an array of field names that is later used to compile the
          # insertion statement
          $columnTable = $fields.Name
          
          # set $foundAny to $true because ALL fields are matching since we created
          # the table based on the object
          $foundAny = $true
        }
        else
        {
          # if the table is present already, check whether the fields in the
          # existing table match the required fields
          # for this, get the column names from the existing table
          $columns = $table.GetFields()
          # test whether columns match
          $foundAny = $false
          $missing = foreach($field in $fields)
          {
            # if the field exists...
            if ($columns.Contains($field.Name))
            {
              $foundAny = $true
              # ...check the field type. Does it match as well?
              $existingType = $columns[$field.Name].Type
              if ($existingType -ne $field.Type)
              { 
                $message = 'Field {0} is of type {1} but you are adding type {2}.' -f $Field.Name, $existingType, $field.Type
                                    
                if ($AllowTypeConversion)
                {
                  Write-Warning $message
                  # update the field type because now the object property
                  # type does not match the table field type
                  $fieldTypes[$field.Name] = $existingType
                }
                else
                {
                  # if the field exists but the field type is different,
                  # there is no way to fix this, and an exception is thrown
                  throw [System.InvalidOperationException]::new($message)
                }
              }
            }
            else
            {
              # if the field does not exist, it is added to the $missing list 
              $field
            }
          }

          
          $missing | ForEach-Object {
            Write-Warning "Table '$($Table.Name)' has no field '$($_.Name)'."
          }
          if ($missing.Count -gt 0)
          {
            Write-Warning "Consider adding data to a new table with a more appropriate design, or adding missing fields to the table."
          }
          if (!$foundAny)
          {
            throw "There are NO matching fields in table '$($table.Name)'. Import to a new table, or use an existing table that matches the object type."
          }
          # keep an array of field names that is later used to compile the
          # insertion statement
          $columnTable = $columns.Keys
        }
        #endregion get or create table
        #region abort pipeline if table prototyping is active
        if ($DefineTableOnly.isPresent -or !$foundAny)
        {
          # abort pipeline
          $p = {Select-Object -First 1}.GetSteppablePipeline()
          $p.Begin($true)
          $p.Process(1)
        }
        #endregion abort pipeline if table prototyping is active

        #region precompile insertion command
        # adding new data via an INSERT INTO sql statement per object
        # would be very slow for large numbers of objects
        # a much faster way uses a precompiled insertion command
        # which is created now:

        # create a comma-separated list of field names
        $fieldNames = '"' + ($columnTable -join '","') + '"'
        # create a comma-separated list of variable names which really are
        # field names prepended with "$"
        $variableNames = foreach($_ in $columnTable) { '${0}' -f $_ }
        $variableNamesString = $variableNames -join ','
                        
        # precompile the insertion command 
        # the insertion command is a default INSERT INTO sql statement except
        # that it does not contain the actual values but instead
        # variable names:
        $command = $database.Connection.CreateCommand()
        $command.CommandText = 'INSERT INTO {0}({1}) VALUES({2});' -f $TableName, $fieldNames, $variableNamesString

        # to be able to later replace the variables with the actual data,
        # parameters need to be created for each variable:
        $parameters = $variableNames | ForEach-Object {
          # create a parameter
          $parameter = $command.CreateParameter()
          $parameter.ParameterName = $_

          # add the parameter to the command
          $null = $command.Parameters.Add($parameter)
          #endregion precompile insertion command

          # add a noteproperty so we can attach the original property name (less "$") for
          # easy retrieval later when the object properties are queried:
          $realName = $_.Substring(1)
          $parameter | 
          Add-Member -MemberType NoteProperty -Name RealName -Value $realName -PassThru |
          Add-Member -MemberType NoteProperty -Name RealType -Value $fieldTypes[$realName] -PassThru
        }
                    
        # bulk-insert groups of objects to improve performance. 
        # This is done by starting a transaction. 
        # While the transaction is active, no data is written to the
        # table. Only when the transaction is committed, the entire collected data
        # is written.
        # use a transaction to insert multiple data sets in one operation
        $transaction = $database.Connection.BeginTransaction()
        
        # remember start time for stats
        $start = $baseStart = Get-Date
      }
      #endregion process first incoming object

      # the remaining code is executed for any object received

      #region add one object to the table
      # increment the counter
      $dataSetCount++

      # submit the actual object property values for each parameter
      # we added to the INSERT INTO command
      foreach($parameter in $parameters)
      {
        # get the property name only
        $propName = $parameter.RealName 
        $value = $object.$propName

        # if the value is an array, turn the array into a comma-separated
        # string
        if ($value -is [Array])
        {
          $parameter.Value = $value -join ','
        }
        else
        {
          # if the data type is DateTime, we must make sure the value is
          # actually a suitable datetime because SQLite will store it anyway,
          # causing problems when the data is queried later and cannot be converted
          if ($parameter.RealType -eq 'DateTime')
          {
            $dateTimeValue = $value -as [DateTime]
            if ($dateTimeValue -ne $null)
            {
              $value = $dateTimeValue.ToString('yyyy-MM-dd HH:mm:ss')
            }
            elseif ($value -match $wmiDatePattern)
            {
              $value = [System.Management.ManagementDateTimeConverter]::ToDateTime($value).ToString('yyyy-MM-dd HH:mm:ss')
            }
            else
            {
              $value = $null
            }
          }
          $parameter.Value = $value
        }
      }

      # add the command to the transaction
      $null = $command.ExecuteNonQuery()
      #endregion add one object to the table

      #region check for transaction size
      # by default, the transaction is committed only when all objects are
      # received. For large numbers of objects, a transactionset size can be
      # specified. When the specified number of objects are received, the
      # current transaction is committed, and the caller gets back some stats.
      if ($TransactionSet -gt 0 -and ($dataSetCount % $TransactionSet -eq 0))
      {
        $chunkTimePassed = ((Get-Date)-$start).TotalSeconds
        $timePassed = ((Get-Date)-$baseStart).TotalMinutes
        $size = '{0:n2} MB' -f ([IO.FileInfo]::new($Database._path).Length/1MB)

        $info = [PSCustomObject]@{
          Processed = $dataSetCount
          ChunkTime = '{0:n1} sec.' -f $chunkTimePassed
          TotalTime = '{0:n1} min.' -f $timePassed
          FileSize = $size
          FilePath = $Database._path
        }
        $start = Get-Date
        Write-Warning -Message ($info | Out-String)
        # commit the current transaction
        $transaction.Commit()
        # start a new transaction
        $Transaction = $database.Connection.BeginTransaction()
        $dataSetCount = 0
      }
      #endregion check for transaction size
    }    
  }
  end
  {
    # commit pending transaction only if new records have been added
    if ($dataSetCount -gt 0)
    {
      $transaction.Commit()
    }
    #region reset temporary database options
    # reset performance settings to default
    if ($UseUnsafePerformanceTricks)
    {
      $Database.EnableUnsafePerformanceMode = $oldSetting1
    }
    if ($LockDatabase)
    {
      $database.LockDatabase = $oldSetting2
    }    
    #endregion reset temporary database options
  
    if ($PassThru)
    {
      $Database.GetTable($TableName)
    }
  }
}



#endregion functions
