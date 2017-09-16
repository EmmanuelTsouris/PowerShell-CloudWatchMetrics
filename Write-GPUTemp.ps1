Import-Module AWSPowerShell

Function Get-MetaData {
    <#
    .DESCRIPTION
    Gets metadata from the local instance using the path extention provided
    .PARAMETER metaDataUrlPathExtention
    The URL suffix of the metadata that you want to gathered
    .EXAMPLE
    [string]$instanceId = $(Get-MetaDataObject -metaDataUrlPathExtention "instance-id")
    #>
    Param (

        [string]$Path
    )

    if ($Path.Length -eq 0) {
        Write-Warning "Unable to get meta data because the Path is undefined."
        Throw "MetaData Path is Undefined"
    }

    if ($Path.StartsWith("/")) {
        Write-Debug "Filtering out the extra slash from the meta data path ($Path)."
        $Path = $Path.Substring(1)
    }

    [string]$metaDataBaseUrl = "http://169.254.169.254/latest/meta-data/"
    [string]$metaDataFullUrl = $metaDataBaseUrl + $Path
    Write-Debug "Formed url to query meta data $metaDataFullUrl"

    try {
        [string]$metaDataValue = (New-Object Net.WebClient).DownloadString($metaDataFullUrl)
        Write-Debug "Meta data returned a value of $metaDataValue"

        if ($metaDataValue.Length -gt 0) {
            return $metaDataValue
        }
        else {
            Write-Warning "The returned meta data value appears to be empty."
            Throw "MetaData is Null"
        }
    }
    catch [exception] {
        Write-Warning "Can't get meta data from $metaDataFullUrl"
        Throw
    }
}

Function Get-InstanceId {
    <#
    .DESCRIPTION
    Get the local instanceId from the metadata service
    #>

    return Get-MetaData -Path "instance-id"
}

Function Get-InstanceType {
    return Get-MetaData -Path "instance-type"
}

$InstanceId = Get-InstanceId

$namespace = "root\CIMV2\NV"
$classname = "ThermalProbe"
$probes = Get-WmiObject -Class $classname -Namespace $namespace

$dims = New-Object Collections.Generic.List[Amazon.Cloudwatch.Model.Dimension]

$dimInstanceType = New-Object Amazon.CloudWatch.Model.Dimension
$dimInstanceType.Name = "InstanceType"
$dimInstanceType.Value = Get-InstanceType

$dims.Add($dimInstanceType)

$dimInstance = New-Object Amazon.CloudWatch.Model.Dimension
$dimInstance.Name = "InstanceId"
$dimInstance.Value = Get-InstanceId

$dims.Add($dimInstance)

foreach ($probe in $probes) {
    $probeDims = New-Object Collections.Generic.List[Amazon.Cloudwatch.Model.Dimension]
    $probeDims = $dims

    $dimCounter = New-Object Amazon.CloudWatch.Model.Dimension
    $dimCounter.Name = "GPU"
    $dimCounter.Value = $($probe.id)

    $probeDims.Add($dimCounter)

    $res = $probe.InvokeMethod("info", $Null)

    $dat = New-Object Amazon.CloudWatch.Model.MetricDatum
    $dat.Timestamp = (Get-Date).ToUniversalTime()
    $dat.MetricName = "Temperature"
    $dat.Unit = "Count"
    $dat.Value = $probe.temperature
    $dat.Dimensions = $probeDims
    
    Write-CWMetricData -Namespace "GPU-Temperature"  -MetricData $dat
}
