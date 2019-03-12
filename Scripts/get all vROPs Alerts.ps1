$alerts = getAlerts -resthost $resthost -token $token
$activealerts = $alerts.alerts 
    $alertHashTable =@()

foreach ($alert in $activealerts) {
    #$alertHashTable =@()
    $alertObject = $r = getResource -resthost $resthost -token $token -objectid $alert.resourceId
    $alertHashTable += [PSCustomObject]@{
        'Name' = $alert.alertDefinitionName
        'status' = $alert.status
        'alertLevel' = $alert.alertLevel
        'Effected Object' = $alertObject.resourceKey.name
        'Start Time' = (Get-Date 01.01.1970)+([System.TimeSpan]::FromMilliseconds($alert.startTimeUTC))
        'Updated Time' = (Get-Date 01.01.1970)+([System.TimeSpan]::FromMilliseconds($alert.updateTimeUTC))
    }
}
$alertHashTable | ogv
