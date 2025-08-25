<# .SYNOPSIS
    This is a small Powershell script that disables IntelliCode in Visual Studio 2022.

   .DESCRIPTION
   This script writes changes to a .vssettings file that will set various config options that are otherwise hidden from the user. These options will disable Visual Studio's IntelliCode functionality.
   By default, the script will try to auto-detect the location of your .vssettings file by looking for the one that was written most recently in your local application data directory.
   If it can't find one, then you can specify the path explicitly.

   For advanced usage, see the parameter documentation.

   For information on what each of the config options actually does, ask Microsoft. I got most of these from here: https://stackoverflow.com/a/77294217

   .PARAMETER SettingsFilePath
    The path to the .vssettings file to update. If omitted, tries to auto-detect.

   .PARAMETER EnableTemplateIntelliSense
    Pass this switch to set 'EnableTemplateIntelliSense' to true
   
   .PARAMETER EnableSingleFileIntelliSense
    Pass this switch to set 'EnableSingleFileISense' to true

   .PARAMETER EnableSharedIntelliSense   
    Pass this switch to set 'DisableSharedIntelliSense' to false

   .PARAMETER EnableIntelliSenseUpdating
    Pass this switch to set 'DisableIntelliSenseUpdating' to false

   .PARAMETER EnableIntelliSense
    Pass this switch to set 'DisableIntelliSense' to false

   .PARAMETER IntelliSenseProcessMemoryLimit
    Pass an integer that specifies the memory limit of the IntelliSense process.
    I defaulted this to 1, as 0 can often be used to disable a memory limit in similar contexts. I am also not sure if the unit is bytes, kilobytes, megabytes, lb-ft, or something else entirely.
#>
[CmdletBinding(DefaultParameterSetName = 'autodetect')]
param(
  [Parameter(Mandatory = $true, ParameterSetName = 'explicit')]
  [ValidateNotNullOrEmpty()]
  [ValidateScript({ Test-Path -PathType Leaf $_ })]
  [string]$SettingsFilePath,

  [Parameter(Mandatory = $false)]
  [switch]$EnableTemplateIntelliSense,

  [Parameter(Mandatory = $false)]
  [switch]$EnableSingleFileIntelliSense,

  [Parameter(Mandatory = $false)]
  [switch]$EnableSharedIntelliSense,

  [Parameter(Mandatory = $false)]
  [switch]$EnableIntelliSenseUpdating,

  [Parameter(Mandatory = $false)]
  [switch]$EnableIntelliSense,

  [Parameter(Mandatory = $false)]
  [ValidateRange(0, ([int]::MaxValue))]
  [int]$IntelliSenseProcessMemoryLimit = 1
)

$Script:PSNativeCommandUseErrorActionPreference = $true
$EXTENSION = '.vssettings'
# See: https://stackoverflow.com/a/77294217
$SETTINGS = @{
  'EnableTemplateIntelliSense'     = $EnableTemplateIntelliSense.IsPresent
  'EnableSingleFileISense'         = $EnableSingleFileIntelliSense.IsPresent
  'DisableSharedIntelliSense'      = !$EnableSharedIntelliSense.IsPresent
  'DisableIntelliSenseUpdating'    = !$EnableIntelliSenseUpdating.IsPresent
  'DisableIntelliSense'            = !$EnableIntelliSense.IsPresent
  'IntelliSenseProcessMemoryLimit' = $IntelliSenseProcessMemoryLimit
}

$processes = Get-Process 'devenv' -ErrorAction SilentlyContinue
if (($processes | Measure-Object).Count -ne 0)
{
  Write-Error 'Visual Studio is running' `
    -RecommendedAction 'Close Visual Studio before running the script' `
    -TargetObject ($processes | Select-Object -First 1)
}

if ($PSCmdlet.ParameterSetName -eq 'explicit')
{
  $file = Get-Item $SettingsFilePath
}
elseif ($PSCmdlet.ParameterSetName -eq 'autodetect')
{
  if ($PSVersionTable.PSVersion.Major -lt 7)
  {
    # Nested Join-Path for PSv5
    $vsLocalAppDataRootPath = Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft') 'VisualStudio'
  }
  else
  {
    $vsLocalAppDataRootPath = Join-Path $env:LOCALAPPDATA 'Microsoft' 'VisualStudio'
  }
  
  Write-Verbose ('Autodetect mode -- using root settings directory path: {0}' -f $vsLocalAppDataRootPath)
  try
  {
    $vsLocalAppDataRootDir = Get-Item -Path $vsLocalAppDataRootPath -ErrorAction Stop
    Write-Debug ('Found root dir at {0}' -f $vsLocalAppDataRootPath)
    $vsCurrentVersionAppDataRootDir = Get-ChildItem $vsLocalAppDataRootDir.FullName -Directory |
      Where-Object { [regex]::IsMatch($PSItem.Name, '^\d{2}\.\d+_') } |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if ($null -eq $vsCurrentVersionAppDataRootDir)
    {
      throw New-Object System.Management.Automation.ItemNotFoundException('No valid Visual Studio settings subdirectory was found under "{0}"' -f $vsLocalAppDataRootDir.FullName)
    }
    
    Write-Verbose ('Using directory "{0}" with most recent write time of "{1}"' -f $vsCurrentVersionAppDataRootDir.FullName, $vsCurrentVersionAppDataRootDir.LastWriteTime)
    # It's almost certainly going to be called CurrentSettings.vssettings, but in case something changes in future...
    $file = Get-ChildItem (Join-Path $vsCurrentVersionAppDataRootDir.FullName 'Settings') -Filter ('*{0}' -f $EXTENSION) |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1

    if ($null -eq $file)
    {
      throw New-Object System.Management.Automation.ItemNotFoundException('No valid "{0}" file was found under "{1}"' -f $EXTENSION, $vsCurrentVersionAppDataRootDir.FullName)
    }
  }
  catch [System.Management.Automation.ItemNotFoundException]
  {
    Write-Error -Message ('Couldn''t find a Visual Studio "{0}" file under "{1}"' -f $EXTENSION, $vsLocalAppDataRootPath) `
      -TargetObject $_.TargetObject `
      -Exception $_.Exception `
      -RecommendedAction ('Try specifying the path to your "{0}" file explicitly using the "SettingsFilePath" parameter.' -f $EXTENSION)
  }
}
else
{
  Write-Error 'Unknown/unsupported parameter set?'
}

if ($null -ne $file)
{
  Write-Verbose ('File path is "{0}"' -f $file.FullName)
  $content = Get-Content $file.FullName
  $xml = [System.Xml.XmlDocument]::new()
  $xml.LoadXml($content)

  if ($null -ne $xml)
  {
    # There are much simpler, more efficient ways of doing this with an XPath expression I'm sure
    $elements = $xml.GetElementsByTagName('PropertyValue') | Where-Object { $SETTINGS.Keys -contains $PSItem.Name }
    $changed = $false
    foreach ($element in $elements)
    {
      Remove-Variable requiredValue -ErrorAction SilentlyContinue
      $requiredValue = $SETTINGS[$element.Name].ToString().ToLowerInvariant()
      if ($element.InnerText -ne $requiredValue)
      {
        Write-Verbose ('Updating config item "{0}" from "{1}" to "{2}"' -f $element.Name, $element.InnerText, $requiredValue)
        $element.InnerText = $requiredValue
        $changed = $true
      }
      else
      {
        Write-Verbose ('Config item "{0}" is already set to the required value of "{1}"' -f $element.Name, $requiredValue)
      }
    }

    if ($changed)
    {
      $backupPath = $file.FullName -replace ('\{0}$' -f $file.Extension), ('__disable_intellicode_{0}{1}.backup' -f ([DateTime]::Now.ToString('ddMMyyyy-HHmmss')), $file.Extension)
      Write-Verbose ('We made some changes -- backing up existing settings file to "{0}" before we write them' -f $backupPath)
      $backup = Copy-Item $file.FullName $backupPath -PassThru
      if ($null -ne $backup)
      {
        Write-Verbose ('Successfully created backup. Overwriting file with our changes at "{0}"' -f $file.FullName)
        $xml.Save($file.FullName)
      }
      else
      {
        Write-Warning 'An error occurred trying to create a backup. No changes have been saved.'
      }
    }
  }
}