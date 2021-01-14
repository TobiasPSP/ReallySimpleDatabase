#region prerequisites (MUST BE FIRST!)


function LoadBinaries
{

    # use API method to load Interop databases from wherever we want
    # (else, the DLL needs to be in the search path or inside the
    # folder the .NET assembly is located in)
    # FreeLibrary allows us to potentially remove the DLL (for temp file cleanup)
    $code = '
        [DllImport("kernel32.dll")]
        public static extern IntPtr LoadLibrary(string dllToLoad);
         [DllImport("kernel32.dll")]
        public static extern bool FreeLibrary(IntPtr hModule);'

    Add-Type -MemberDefinition $code -Namespace Internal -Name Helper

    # check the platform:
    if ([Environment]::Is64BitProcess)
    {
        Write-Verbose "Platform x64"
        $platform = "64"
    }
    else
    {
        Write-Verbose "Platform x86"
        $platform = "86"
    }
  
    # pre-load the platform specific DLL version
    $parentFolder = Split-Path -Path $PSScriptRoot

    $Path = "$PSScriptRoot\binaries\x$platform\SQLite.Interop.dll"
    $null = [Internal.Helper]::LoadLibrary($Path)
    Write-Verbose "Interop assembly loaded"

    # next, load the .NET assembly. Since the Interop DLL is already
    # pre-loaded, all is good:  
    Add-Type -Path "$PSScriptRoot\binaries\System.Data.SQLite.dll"
    Write-Verbose "database assembly loaded"

}

# load SQLite DLLs
LoadBinaries



#endregion prerequisites

