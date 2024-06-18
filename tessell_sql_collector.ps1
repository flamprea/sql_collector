# TESSELL SQL SERVER COLLECTION SCRIPT
# v1.0 - June 2024

# Collect Parameters
param (
    [string]$serverInstance,
    [string]$database,
    [int]$queryTimeout,
    [string]$username,
    [string]$password,
    [string]$performanceLogFile,
    [string]$outputLogFile,
    [int]$durationMinutes,
    [int]$sampleRate
)

function Show-Help {
    Write-Host "Usage: tessell_sql_collector.ps1 -serverInstance <server_instance> -database <database_name> -queryTimeout <query_timeout> -username <username> -password <password> -performanceLogFile <performance_log_file_path> -outputLogFile <output_log_file_path> -durationMinutes <duration_in_minutes> -sampleRate <sample_rate_in_seconds>"
    Write-Host "Example: tessell_sql_collector.ps1 -serverInstance 'localhost\Tessellserver' -database 'master' -queryTimeout 120 -username 'your_sql_username' -password 'your_sql_password' -performanceLogFile 'C:\PerformanceLogs\server_performance_log.csv' -outputLogFile 'C:\PerformanceLogs\output_log.txt' -durationMinutes 1440 -sampleRate 60"
    Write-Host "Tessell recommends a minimum duration of 7 days (1440 minutes) and a sample rate of 60 seconds."
    exit
}

# Check if all required arguments are provided
if (-not $serverInstance -or -not $database -or -not $queryTimeout -or -not $username -or -not $password -or -not $performanceLogFile -or -not $outputLogFile -or -not $durationMinutes -or -not $sampleRate) {
    Show-Help
}

#### NO NEED TO MODIFY ANYTHING BELOW THIS LINE.... ###
# Load SQL Server module
Import-Module SqlServer

# SQL Server instance name
$instanceName = $serverInstance.Split('\')[1]

# Secure the credential
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)

# Get hostname and current date/time
$hostname = $env:COMPUTERNAME
$currentDateTime = Get-Date -Format "yyyyMMdd-HHmmss"

# Create log files and write headers if necessary
if (-not (Test-Path $performanceLogFile)) {
    "Timestamp,CPUUsage,MemoryAvailableKB,DiskTime,DiskIdleTime,DiskAvgQueueLength,DiskCurrentQueue,DiskCurrentReads,DiskCurrentWrites,DiskAvgReads,DiskAvgWrites,ProcessorQueueLength,NetworkBytesPerSec,TargetServerMemoryKB,TotalServerMemoryKB,TotalFreeMemoryKB" | Out-File -FilePath $performanceLogFile -Encoding utf8
}

# Add header to output log file
"$hostname - $currentDateTime" | Out-File -FilePath $outputLogFile -Encoding utf8

# Function to capture performance data
function Capture-PerformanceData {
    # OS Counters
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $cpuUsage = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
    $memoryAvailableKB = (Get-Counter '\Memory\Available KBytes').CounterSamples.CookedValue
    $diskTime = (Get-Counter '\PhysicalDisk(_Total)\% Disk Time').CounterSamples.CookedValue
    $diskIdleTime = (Get-Counter '\PhysicalDisk(_Total)\% Idle Time').CounterSamples.CookedValue
    $diskAvgQueueLength = (Get-Counter '\PhysicalDisk(_Total)\Avg. Disk Queue Length').CounterSamples.CookedValue
    $diskCurrentQueue = (Get-Counter '\PhysicalDisk(_Total)\Current Disk Queue Length').CounterSamples.CookedValue
    $diskCurrentReads = (Get-Counter '\PhysicalDisk(_Total)\Disk Reads/sec').CounterSamples.CookedValue
    $diskCurrentWrites = (Get-Counter '\PhysicalDisk(_Total)\Disk Writes/sec').CounterSamples.CookedValue
    $diskAvgReads = (Get-Counter '\PhysicalDisk(_Total)\Avg. Disk sec/Read').CounterSamples.CookedValue
    $diskAvgWrites = (Get-Counter '\PhysicalDisk(_Total)\Avg. Disk sec/Write').CounterSamples.CookedValue
    $processorQueueLength = (Get-Counter '\System\Processor Queue Length').CounterSamples.CookedValue
    $networkBytesPerSec = (Get-Counter '\Network Interface(*)\Bytes Total/sec').CounterSamples.CookedValue | Measure-Object -Sum | Select-Object -ExpandProperty Sum

    # Construct the SQL Counters
    $targetServerMemoryKBPath = "\MSSQL`$$instanceName`:Memory Manager\Target Server Memory (KB)"
    $totalServerMemoryKBPath = "\MSSQL`$$instanceName`:Memory Manager\Total Server Memory (KB)"
    $totalFreeMemoryKBPath = "\MSSQL`$$instanceName`:Memory Manager\Free Memory (KB)"
    #Write-Host "Debug: $targetServerMemoryKBPath"
    #Write-Host "Debug: $totalServerMemoryKBPath"
    #Write-Host "Debug: $totalFreeMemoryKBPath"

    # Collect the Data
    $targetServerMemoryKB = (Get-Counter $targetServerMemoryKBPath).CounterSamples.CookedValue
    $totalServerMemoryKB = (Get-Counter $totalServerMemoryKBPath).CounterSamples.CookedValue
    $totalFreeMemoryKB = (Get-Counter $totalFreeMemoryKBPath).CounterSamples.CookedValue

    "$timestamp,$cpuUsage,$memoryAvailableKB,$diskTime,$diskIdleTime,$diskAvgQueueLength,$diskCurrentQueue,$diskCurrentReads,$diskCurrentWrites,$diskAvgReads,$diskAvgWrites,$processorQueueLength,$networkBytesPerSec,$targetServerMemoryKB,$totalServerMemoryKB,$totalFreeMemoryKB" | Add-Content -Path $performanceLogFile -Encoding utf8
}

# OS Version and Machine Shape for the Output Log
function Capture-Inventory {
    # Capture hardware shape information
    $osInfoOutput = "Instance Inventory Capture"
    $osInfoOutput | Add-Content -Path $outputLogFile -Encoding utf8
    $osInfo = Get-WmiObject -Class Win32_OperatingSystem
    $cpuInfo = Get-WmiObject -Class Win32_Processor
    $cpuCount = (Get-WmiObject -Class Win32_Processor).NumberOfLogicalProcessors
    $physicalCoreCount = (Get-WmiObject -Class Win32_Processor | Measure-Object -Property NumberOfCores -Sum).Sum
    $memoryInfo = Get-WmiObject -Class Win32_PhysicalMemory | Measure-Object Capacity -Sum
    $systemInfo = @{
        OSVersion = $osInfo.Caption
        CPUs = $cpuInfo.Name
        LogicalCPUCount = $cpuCount
        PhysicalCoreCount = $physicalCoreCount
        TotalMemoryGB = [Math]::Round($memoryInfo.Sum / 1Gb, 2)
    }
    $systemInfoOutput = $systemInfo | Out-String
    $systemInfoOutput | Add-Content -Path $outputLogFile -Encoding utf8

    # Mount Points
    $diskInfoOutput = Get-WmiObject -Class Win32_Volume | Select-Object Name, @{
        Name = "Capacity(GB)"; Expression ={
            [math]::Round($_.Capacity/1GB, 2)
        }
    }, @{
        Name = "FreeSpace(GB)"; Expression ={
        [math]::Round($_.FreeSpace/1GB, 2)
        }
    } | Format-Table -AutoSize | Out-String
    $diskInfoOutput | Add-Content -Path $outputLogFile -Encoding utf8

    # Check if Failover Cluster feature is installed
    $failoverClusterInstalled = Get-WindowsFeature Failover-Clustering -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    if ($failoverClusterInstalled.Installed) {
        $clusterStatusOutput = if ((Get-ClusterResource -ErrorAction SilentlyContinue -WarningAction SilentlyContinue).Count -gt 0) {
        "Is windows Failover cluster used? : The system is part of a Failover Cluster."
    } else {
        "Is windows Failover cluster used? : The system has Failover Cluster feature installed but is not part of a cluster."
    }
    } else {
        $clusterStatusOutput = "Is windows Failover cluster used? : Failover Cluster feature is not installed."
    }
    $clusterStatusOutput | Add-Content -Path $outputLogFile -Encoding utf8

    # SQL Server specific queries
    $sqlInfoOutput = "Gathering SQL Server information..."
    $sqlInfoOutput | Add-Content -Path $outputLogFile -Encoding utf8
    $sqlQueries = @{
        Edition = "SELECT SERVERPROPERTY('Edition')"
        ProductVersion = "SELECT SERVERPROPERTY('ProductVersion')"
        NumberOfDatabases = "SELECT count(1) FROM sys.databases WHERE database_id > 4"
        SSISInstalled = "USE msdb; IF EXISTS (SELECT 1 FROM syssubsystems WHERE subsystem = 'SSIS') SELECT 'SSIS is installed.' ELSE SELECT 'SSIS is not installed.'"
        SSRSInstalled = "USE msdb; IF EXISTS (SELECT 1 FROM syssubsystems WHERE subsystem = 'SSRS') SELECT 'SSRS is installed.' ELSE SELECT 'SSRS is not installed.'"
        CombinedSizeofAlldatabasesGB = "SELECT SUM(size * 8.0 / 1024)/1024 FROM sys.master_files WHERE type = 0 OR type = 1"
    }
    foreach ($query in $sqlQueries.GetEnumerator()) {
        $result = Invoke-Sqlcmd -ServerInstance $serverInstance -Database $database -Query $query.Value -QueryTimeout $queryTimeout -Credential $credential -TrustServerCertificate
        $sqlQueryOutput = "$($query.Key) : $($result.Column1)"
        $sqlQueryOutput | Add-Content -Path $outputLogFile -Encoding utf8
    }
}

# Run the inventory collection and rename the log file to include hostname and date. We will close out this file now since the subsequent step can run for a very long period of time
Capture-Inventory
$outputLogFileDir = Split-Path -Parent $outputLogFile
$finalOutputLogFile = Join-Path $outputLogFileDir "$hostname-$currentDateTime-output_log.txt"
Move-Item -Path $outputLogFile -Destination $finalOutputLogFile
Write-Host "Inventory log file has been renamed to include hostname and date."

# Run performance data capture every minute for a specified number of minutes. This can run for many days!
$startTime = Get-Date
$endTime = $startTime.AddMinutes($durationMinutes)

while ($true) {
    $currentTime = Get-Date
    if ($currentTime -gt $endTime) {
        break
    }
    Capture-PerformanceData
    Write-Host "Running Performance Capture at $currentTime. Estimated Completion at $endTime"
    Start-Sleep -Seconds $sampleRate
}

# Rename the log files to include hostname and date
$performanceLogFileDir = Split-Path -Parent $performanceLogFile
$finalPerformanceLogFile = Join-Path $performanceLogFileDir "$hostname-$currentDateTime-server_performance_log.csv"
Move-Item -Path $performanceLogFile -Destination $finalPerformanceLogFile
Write-Host "Performance log file has been renamed to include hostname and date."

# Wrap up
Write-Host "Collection Complete."
Write-Host " Please provide $finalOutputLogFile and $finalPerformanceLogFile to your Tessell representative."
exit