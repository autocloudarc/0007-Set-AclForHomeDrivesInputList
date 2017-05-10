#requires -version 4.0
#requires -RunAsAdministrator
#requires -Modules ActiveDirectory
<#
****************************************************************************************************************************************************************************
PROGRAM		: Set-AclForHomeDrivesFromDirectoryListOrUserInput.ps1
DESCIRPTION	: Takes administrative ownership of files and folders from individual users and resets permissions.
              #CONFIG tags are used to indicate which variables you will need to change to reflect own environment during script exectuion. 
              Permissions will be set to individual user and user subfolders based on what is confgiured at the \\<server-fqdn\home level.
PARAMETERS	:
INPUTS		: You will be prompted for the home directory share path for the $TargetPath variables, as well as the log path for the $LogPath variable. You will also be
              whether you prefer to manually enter a comma separated list of userids to fix or target an entire home folder directory. Specifying only a few users will allow easier
              for intial testing instead of targeting the entire directory with potentially hundreds or thousands of users.
OUTPUTS		: A directory structure with a set of pending or processed list of users, and a log of the script execution activities.
EXAMPLES	: Set-AclForHomeDrivesFromDirectoryListOrUserInput.ps1
REQUIREMENTS: PowerShell Version 4.0, Run as administrator, ActiveDirectory module feature installed.
LIMITATIONS	: NA
AUTHOR(S)	: Preston K. Parsard
EDITOR(S)	: 
REFERENCES	: 
1. https://technet.microsoft.com/en-us/magazine/2008.02.powershell.aspx
2. https://gallery.technet.microsoft.com/Reset-User-Home-Folder-d951b343?redir=0

TAGS	    : Directory, files, folders, permissions, Acl, ownership, access

LICENSE:

The MIT License (MIT)
Copyright (c) 2016 Preston K. Parsard

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software. 

DISCLAIMER:

THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, 
INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  We grant You a nonexclusive, 
royalty-free right to use and modify the Sample Code and to reproduce and distribute the Sample Code, provided that You agree: (i) to not use Our name, 
logo, or trademarks to market Your software product in which the Sample Code is embedded; 
(ii) to include a valid copyright notice on Your software product in which the Sample Code is embedded; and (iii) to indemnify, hold harmless, 
and defend Us and Our suppliers from and against any claims or lawsuits, including attorneys’ fees, 
that arise or result from the use or distribution of the Sample Code.
****************************************************************************************************************************************************************************
#>

<# TASK ITEMS
#>

<# 
***************************************************************************************************************************************************************************
REVISION/CHANGE RECORD	
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------
DATE        VERSION    NAME               CHANGE
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------
10 APR 2016 01.29.0000 Preston K. Parsard Initial publication release
23 APR 2016 00.29.0001 Preston K. Parsard Parameterized inputs for target home directory and script log path variables to make script more portable
23 APR 2016 00.29.0002 Preston K. Parsard Specified green and yellow for original and emphases foreground colors during script execution
01 MAY 2016 00.00.0032 Preston K. Parsard Parameterized batch limit so that user executing script can specify how many folders to process per script execution
01 MAY 2016 00.00.0033 Preston K. Parsard Set log size unit from 1kb to 1mb as default value in comments
11 MAY 2016 00.00.0030 Preston K. Parsard Parameterized inputs for target home directory and script log path variables to make script more portable
11 MAY 2016 00.00.0031 Preston K. Parsard Specified green and yellow for original and emphasis foreground colors during script execution
11 MAY 2016 00.00.0032 Preston K. Parsard Parameterized batch limit so that user executing script can specify how many folders to process per script execution
11 MAY 2016 00.00.0033 Preston K. Parsard Special permissions were being applied, the details of which can only be seen in the advanced permissions setting.
                                          ...updated so that full permissions are explecitly defined in users ACE in basic settings. This will reduce complexity and aid in
					  ...better readability and easier troubleshooting.
11 MAY 2016 00.00.0034 Preston K. Parsard Removed duplicate $Processed++ counter which was providing a false indication of twice the number of users processed
17 APR 2017 00.00.0010 Preston K. Parsard Append the leaf component of the target path to construct a new logging sub-directory. 
17 APR 2017 00.00.0011 Preston K. Parsard Added prompt for user to specify a sample of users or all users in directory with $SampleOrAllUsers variable
18 APR 2017 00.00.0012 Preston K. Parsard Added logic to continue processing sample user list even if input files directory to process is empty
18 APR 2017 00.00.0013 Preston K. Parsard Created new input files function to account for the condition if sample users are specified and the input directory already exist but is empty
18 APR 2017 00.00.0014 Preston K. Parsard Validated user folders if a sample user list was supplied before processing and decremented the invalid # of folders from the batch count.
                                          see: $InvalidUserFolders = (Compare-Object -DifferenceObject ($UserIdFolders.Name) -ReferenceObject $UserIdList).Count
18 APR 2017 00.00.0015 Preston K. Parsard Updated the log summary to include a user count and list of users without folders specified from the manual input list
20 APR 2017 00.00.0016 Preston K. Parsard Changed $UserIdFolderPaths.Length to $UserIdFolderPaths.Count to accurately reflect # of folders instead of string length of folder path
20 APR 2017 00.00.0017 Preston K. Parsard Simplified input file creation process by removing $BatchLimitStart variable.
20 APR 2017 00.00.0018 Preston K. Parsard Type casted $UserIdFolderPaths variable to [array] to fix bug with single characters being written to the input files instead of entire folder paths.
20 APR 2017 00.00.0019 Preston K. Parsard Corrected -DifferenceObject parameter sequence in the Compare-Object cmdlet.
30 APR 2017 01.00.0000 Preston K. Parsard Added the <#requires -Modules ActiveDirectory> requires statement to ensure that the Get-ADUser cmdlet will work to determine valid users in the home directory.
#>

#region INITIALIZE VALUES	

$BeginTimer = Get-Date

# Setup script execution environment
Clear-Host 
# Set foreground color 
$OriginalForeground = "Green"
$EmphasisForeground = "Yellow"
$host.ui.RawUI.ForegroundColor = $OriginalForeground

# Create and populate prompts object with property-value pairs
# PROMPTS (PromptsObj)
$PromptsObj = [PSCustomObject]@{
 pAskToOpenLog = "Would you like to open the log now ? [YES/NO]"
} #end $PromptsObj

# Create and populate responses object with property-value pairs
# RESPONSES (ResponsesObj): Initialize all response variables with null value
$ResponsesObj = [PSCustomObject]@{
 pOpenLogNow = $null
} #end $ResponsesObj

# CONFIG: Change the $TargetPath value below to reflect the home drive path you whish to use in your own environment using the format below
# $TargetPath = "\\FileServer.domain.com\home"
Do
{
 $host.ui.RawUI.ForegroundColor = $EmphasisForeground
 Write-Host("Please enter the target path for your user home folders directory, i.e. \\fs1.litware.lab\home ")
 [string] $TargetPath = Read-Host
 $host.ui.RawUI.ForegroundColor = $OriginalForeground
 Write-Host("")
} #end Do
Until (($TargetPath) -ne $null)

$ColumnWidth = 108
$EmptyString = ""
$DoubleLine = ("=" * $ColumnWidth)
$SingleLine = ("-" * $ColumnWidth)
[int]$l= 0

# CONFIG: Change the the $LogPath value below to reflect the log path you whish to use in your own environment using the format below
# $LogPath = "\\FileServer.domain.com\logs"
Do
{
 $host.ui.RawUI.ForegroundColor = $EmphasisForeground
 Write-Host("Please enter the log path where the output for this script will be saved, i.e. \\fs1.litware.lab\logs ")
 [string] $LogPath = Read-Host
 $host.ui.RawUI.ForegroundColor = $OriginalForeground
} #end Do
Until (($LogPath) -ne $null)

# If the target path is in a UNC format, filter out the double slashes prefix and return only the leaf component of the path
If ($TargetPath -match '\\')
{
 $TargetPathFiltered = $TargetPath.Replace('\\','\')
 $TargetPathLeaf = $TargetPathFiltered | Split-Path -Leaf
} #end if
else
{
 # Otherwise if the target path uses a drive letter and colon (i.e. "D:\" format), proceed to splitting the leaf component as well to create the logging sub-directory
 $TargetPathLeaf = $TargetPath | Split-Path -Leaf
} #end else

$TargetPathLeaf
# Append the leaf component of the target path to construct a new logging sub-directory
$LogPath = $LogPath + "\" + $TargetPathLeaf

If (-not(Test-Path -Path $LogPath))
{
 New-Item -Path $LogPath -ItemType Directory
} #end if

$InputFilePendingFolder = "InputFiles-PENDING"
$InputFilePendingPath = Join-Path $LogPath -ChildPath $InputFilePendingFolder
$InputFileProcessedFolder = "InputFiles-PROCESSED"
$InputFileProcessedPath = Join-Path $LogPath -ChildPath $InputFileProcessedFolder

$BatchLimit = $null
# CONFIG: Specify wether to [1] supply a sample set of users or [2]target the home directory for a users. 
Do
{
 $host.ui.RawUI.ForegroundColor = $EmphasisForeground
 Write-Host(" ")
 Write-Host("[1] Specify a comma-separated list of userids to process")
 Write-Host("[2] Process ALL USERS in the target directory")
 Write-Host(" ")
 Write-Host("Please make a numeric selection [1] or [2] from the options shown above")
 [int] $SampleOrAllUsers = Read-Host
 $host.ui.RawUI.ForegroundColor = $OriginalForeground
} #end Do
Until (($SampleOrAllUsers -eq 1) -or ($SampleOrAllUsers -eq 2))

If ($SampleOrAllUsers -eq 1)
{
 Do
 {
  Write-Host("Please specify in comma separated format, without quotes, the list of userids [home folders] to process, i.e: usr.gn1.sn1, usr.gn2.sn2, usr.gn3.sn3, etc. ")
  [string]$UserIdList = Read-Host
  [array]$UserIdList = $UserIdList.Split(",").Replace(" ","")
  # Count number of users specified for the batch limit
  [int]$BatchLimit = $UserIdList.Count
 } #end do
 Until ($BatchLimit -gt 0)
} #end if
else
{
 # CONFIG: Specify the batch limit, which is the total number of users this script will process per session of execution. 
 Do
 {
  $host.ui.RawUI.ForegroundColor = $EmphasisForeground
  Write-Host("Specify the number of user home folders that will be processed per script execution, i.e. 3")
  Write-Host("During testing of less than 20 folders, a batch limit of 3 is recommended, however in production you may increase this limit as appropriate")
  [int]$BatchLimit = Read-Host
  $host.ui.RawUI.ForegroundColor = $OriginalForeground
 } #end Do
 Until (($BatchLimit) -ne $null)
} #end if

$StartTime = (((get-date -format u).Substring(0,16)).Replace(" ", "-")).Replace(":","")

Function Script:New-Log
{
  [int]$Script:l++
  # Create log file with a "u" formatted time-date stamp
  $LogFile = "Set-AclForHomeDrives" + "-" + $StartTime + "-" + [int]$Script:l + ".log"
  $Script:Log = Join-Path -Path $LogPath -ChildPath $LogFile
  New-Item -Path $Script:Log -ItemType File -Force
} #end function

New-Log

Function Get-LogSize
{
 $LogObj = Get-ChildItem -Path $Log 
 # CONIFIG: Use 1mb for production, 1kb for testing. Default value will be [1mb]
 $LogSize = ([System.Math]::Round(($LogObj.Length/1mb)))
 If ($LogSize -gt 10)
 {
  ShowAndLog("")
  ShowAndLog("------------------------")
  ShowAndLog("Creating new log file...")
  ShowAndLog("------------------------")
  # Create a new log with new index and timestamp
  $LogSize = 0
  New-Log
 } #end if
} #end function

$DelimDouble = ("=" * 100 )
$DelimSingle = ("-" * 50 )
$Header = "RESET ACL AND OWNERSHIP PERMISSION FOR HOME DIRECTORIES: " + $StartTime

# Index to uniquely identify each line when logging using the LogWithIndex function
$Index = 0
# Number of users to process during task scheduled execution of this script
# Populate Summary Display Object
# Add properties and values
# Make all values upper-case
 $SummObj = [PSCustomObject]@{
  TARGETPATH = $TargetPath.ToUpper()
  LOGFILE = $Log
 } #end $SummObj

# Send output to both the console and log file
Function ShowAndLog
{
[CmdletBinding()] Param([Parameter(Mandatory=$True)]$Output)
$Output | Tee-Object -FilePath $Log -Append
} #end ShowAndLog

# Send output to both the console and log file and include a time-stamp
Function LogWithTime
{
[CmdletBinding()] Param([Parameter(Mandatory=$True)]$LogEntry)
# Construct log time-stamp for indexing log entries
# Get only the time stamp component of the date and time, starting with the "T" at position 10
$TimeIndex = (get-date -format o).ToString().Substring(10)
$TimeIndex = $TimeIndex.Substring(0,17)
"{0}: {1}" -f $TimeIndex,$LogEntry 
} #end LogWithTime

# Send output to both the console and log file and include an index
Function Script:LogWithIndex
{
[CmdletBinding()] Param([Parameter(Mandatory=$True)]$LogEntry)
# Increment QA index counter to uniquely identify this item being inspected
$Script:Index++
"{0}`t{1}" -f $Script:Index,$LogEntry | Tee-Object -FilePath $Log -Append
} #end LogWithIndex

# Send output to log file only
Function LogToFile
{
[CmdletBinding()] Param([Parameter(Mandatory=$True)]$LogData)
$LogData | Out-File -FilePath $Log -Append
} #end LogToFile

#endregion INITIALIZE VALUES


#region MAIN	

# Clear-Host 

# Display header
ShowAndLog($DelimDouble)
ShowAndLog($Header)
ShowAndLog($DelimDouble)

# If the input file path does already exist...
If (Test-Path("$InputFilePendingPath"))
{
 ShowAndLog("Input files directory does exist...")
 # ...and there are no input files in the directory, then we can assume that all files have already been processed unless a sample list of users were specified
 If (((Get-ChildItem -Path $InputFilePendingPath).Count -eq 0) -and ($SampleOrAllUsers -eq 2))
 {
  ShowAndLog("No input files are available to process. Exiting script...")
  $ParentLogPath = ($LogPath | Split-Path -Parent)
  $host.ui.RawUI.ForegroundColor = $EmphasisForeground
  ShowAndLog("If you would still like to process all users at $TargetPath, first move or delete all log files at: $ParentLogPath, then re-run this script.")
  pause
  $host.ui.RawUI.ForegroundColor = $OriginalForeground
  exit
 } #end if
} #end if

ShowAndLog("Processing directories...")
# Index for each user
$UserCount = 0
# Number of users processed
$Processed = 0
# Base ACL reference to use for applying to subfolders and files for administrative access
$AclPreSet = Get-Acl $TargetPath

# Get all user folders
If ($SampleOrAllUsers -eq 1)
{
 $UserIdFolders = Get-ChildItem -Path $TargetPath -Include $UserIdList
 # Validate that specified user have a directory beneath the target path
 $InvalidUserFolders = (Compare-Object -ReferenceObject $UserIdList -DifferenceObject $UserIdFolders.Name)
 [int]$BatchLimit = $UserIdFolders.Count
} #end if
else
{
 $InvalidUserFolders = $null
 $UserIdFolders = Get-ChildItem -Path $TargetPath
} #end if

[array]$UserIdFolderPaths = $UserIdFolders.FullName
# Split user folders based on batch limit
ShowAndLog("Creating input files for batch processing of user home folders")
$TotalUserFolders = $UserIdFolderPaths.Count
$TotalInputFiles = [int]($TotalUserFolders / $BatchLimit)
# If there are leftover paths less than the batch limit, add an extra file as the last one
If ($TotalUserFolders % $BatchLimit)
{
 $TotalInputFiles++
} #end 

# If the input path has not yet been created, this must be the first time the script is run, so create the path and populate all input files
If (!(Test-Path("$InputFilePendingPath")))
{
 # Create pending directory
 ShowAndLog("Input files directory to process does not already exists. Creating $InputFilePendingPath ...")
 New-Item -Path $InputFilePendingPath -ItemType Directory -Force 
} #end test-path
# Create processed directory if it doesn't already exist
If (!(Test-Path("$InputFileProcessedPath")))
{
 # Create processed directory
 ShowAndLog("Input files which have been processed directory does not already exists. Creating $InputFileProcessedPath ...")
 New-Item -Path $InputFileProcessedPath -ItemType Directory -Force 
} #end if

# Create all input files
for ($y = 0; $y -lt $TotalInputFiles; $y++)
{
 $InputFile = "UserFoldersBatch" + "-" + $StartTime + "-" + ($y+1) + ".txt"
 $NewInputFile = Join-Path -Path $InputFilePendingPath -ChildPath $InputFile
 New-Item -Path $NewInputFile -ItemType File -Force
 If ($BatchLimit -gt $TotalUserFolders)
 { 
  $BatchLimit = $TotalUserFolders
 } #end if
 For ($fi = 0; $fi -lt ($BatchLimit); $fi++)
 {
  $UserIdFolderPaths[$fi] | Out-File -FilePath $NewInputFile -Append
 } #end for
} #end for

$TargetAcl = Get-Acl $TargetPath
# Netbios domain name
$Domain = (Get-ADDomain).NetBiosName
# Level of access for each user to their own home folders
$Right = "FullControl"
 
$CurrentInputfile = (Get-ChildItem -Path $InputFilePendingPath | Sort-Object $_ | Select-Object -first 1).FullName
If ($CurrentInputfile)
{
 [array]$HomeFolderPaths = Get-Content -Path $CurrentInputfile -ErrorAction SilentlyContinue
} #end if
else 
{
 [array]$HomeFolderPaths = $null
} #end else

$HomeFolderPaths | Select-Object {
 takeown /f $_ /r /a /d y >> $Log
 . Get-LogSize
} #end select-object

. Get-LogSize 

# For netapps CIFS file server objects, the takeown command will be necessary to taking ownership from the root home level and supress prompts
# Fix permissions for administrative access (which temporarily removes user access)
Function FixPermissions
{
 ShowAndLog("Reseting administrative permissions on user files and folders...")
 $FixPermsError = $null
 ForEach ($HomeFolderPath in $HomeFolderPaths)
 {
  Get-ChildItem -Path $HomeFolderPath -Recurse -Force | Set-Acl -AclObject $TargetAcl -Passthru -ErrorVariable $FixPermsError
  While ($FixPermsError) 
   {
    # If the FixPermissions function failed, continue to attempt resetting administrative permissions on user files and folders until succesfull
    ForEach ($HomeFolderPath in $HomeFolderPaths)
    { 
     Get-ChildItem -Path $HomeFolderPath -Recurse -Force | Set-Acl -AclObject $TargetAcl -Passthru
    } #end foreach
   } #end while
  } #end foreach
} #end function

FixPermissions

. Get-LogSize

# Calculate last \ separator in homefolder path to separate just the home folder name
$HomeFolderIndex = (($HomeFolderPaths[0] -split "\\").Count - 1)

# Re-add users to ACL for their home folder and all subfolders
 for ($q = 0; $q -lt $BatchLimit; $q++)
 {
  $FullHomeFolderPath = $HomeFolderPaths[$q]
  $CurrentHomeFolder = $FullHomeFolderPath.Split("\\").Item($HomeFolderIndex)
  $User = Get-ADUser -Filter {sAMAccountName  -eq $CurrentHomeFolder}
  If ($User)
  {
   ShowAndLog($DoubleLine)
   LogWithIndex("Processing ACL for user $CurrentHomeFolder")
   $Principal = "$Domain\$CurrentHomeFolder"
   # Reset user rights as full NTFS permissions recursively to their home folder and all subfolders and files below it, while not modifying any other ACEs
   icacls ("$FullHomeFolderPath") /grant ("$Principal" + ':(OI)(CI)F') /T
   $Processed++
 } #end If
 else
 {
  ShowAndLog("User: $CurrentHomeFolder was not found in AD")
 } #end else
} #end for

. Get-LogSize

ShowAndLog("")
ShowAndLog("Last user processed: $CurrentHomeFolder")
#endregion MAIN

#region FOOTER		

If (Test-Path("$InputFileProcessedPath"))
{
 # Move completed input file from pending to processed folder
 ShowAndLog("Completed input file will now be moved to: $InputFileProcessedPath ...")
 Move-Item -Path $CurrentInputFile -Destination $InputFileProcessedPath -Force
} #end if

# Calculate elapsed time
ShowAndLog("Calculating script execution time...")
$StopTimer = Get-Date
$EndTime = (((Get-Date -format u).Substring(0,16)).Replace(" ", "-")).Replace(":","")
$ExecutionTime = New-TimeSpan -Start $BeginTimer -End $StopTimer

$Footer = "SCRIPT COMPLETED AT: "
[int]$TotalUsers = $Processed

ShowAndLog($DelimDouble)
ShowAndLog($Footer + $EndTime)
ShowandLog("# of users processed: $Processed")
ShowAndLog("Total # of users evaluated: $TotalUsers")
ShowAndLog("Total # of invalid users [no user folder found]: $($InvalidUserFolders.Count)")
ShowAndLog("-"*50)
ShowAndLog("List of invalid user folders:")
ShowAndLog("-"*50)
If ($InvalidUserFolders.Count -gt 0)
{
 ShowAndLog($InvalidUserFolders)
} #end 
ShowAndLog("TOTAL SCRIPT EXECUTION TIME: $ExecutionTime")
ShowAndLog($DelimDouble)

# Prompt to open log
# CONFIG: Comment out the entire prompt below (Do...Until loop) after testing is completed and you are ready to schedule this script. This is just added as a convenience during testing.

Do 
{
 $ResponsesObj.pOpenLogNow = read-host $PromptsObj.pAskToOpenLog
 $ResponsesObj.pOpenLogNow = $ResponsesObj.pOpenLogNow.ToUpper()
}
Until ($ResponsesObj.pOpenLogNow -eq "Y" -OR $ResponsesObj.pOpenLogNow -eq "YES" -OR $ResponsesObj.pOpenLogNow -eq "N" -OR $ResponsesObj.pOpenLogNow -eq "NO")

# Exit if user does not want to continue
if ($ResponsesObj.pOpenLogNow -eq "Y" -OR $ResponsesObj.pOpenLogNow -eq "YES") 
{
 Start-Process notepad.exe $Log
} #end if


# End of script
LogWithTime("END OF SCRIPT!")

#endregion FOOTER

# CONFIG: Remove pause statement below for production run in your environment. This has only been added as a convenience during testing so that the powershell console isn't lost after the script completes.
Pause
Exit