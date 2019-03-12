$tags = @()
$tags = Import-Csv .\tags.csv

foreach ($tag in $tags) {
    #If item already has resource ID then skip
    if ($tag.identifier -ne "") {
        Continue
    } else {
    
    write-host "Creating group " $tag.groupname

    $body = @{ # Create the json payload
        'resourceKey' = @{
        'name' = $tag.groupname
        'adapterKindKey' = 'Container'
        'resourceKindKey' = $tag.resourceKindKey
        'resourceIdentifiers' = @()
        }
        'membershipDefinition' = @{
        'includedResources' = @()
        'excludedResources' = @()
        'rules' = @(@{
                'resourceKindKey' = @{
                'resourceKind' = $tag.resourceKind
                'adapterKind' = 'VMWARE'
            }
            'attributeRules' = @(@{
                'type' = 'PROPERTY_CONDITION'
                'compareOperator' = 'CONTAINS'
                'stringValue' = $tag.stringValue
                'key' = $tag.key
            })
            'resourceNameRules' = @()
            'relationshipRules' = @()
            }
            )
        }
    }

$newbody = $body | convertto-json -depth 8 -Compress
$createCustomGroup = createCustomGroup -resthost $resthost -token $token -body $newbody

if (($createCustomGroup.identifier).length -eq 36) {

    $groupcreated = $true
    
    $teststate = 'SUCCESS'
    #write-host ($testname + ": " + $teststate) -foregroundcolor green 
    } else {
    write-host ($testname + ": " + $teststate) -foregroundcolor red
    }
    
    $testname = 'getCustomGroup'
    $teststate = 'FAIL'
        
    if ($token -ne "") {
        $getCustomGroup = getCustomGroup -resthost $resthost -token $token -objectid ($createCustomGroup.identifier)
    }
    elseif ($credentials -ne "") {
        $getCustomGroup = getCustomGroup -resthost $resthost -credentials $credentials -objectid ($createCustomGroup.identifier)
    }
    
    if (($createCustomGroup.identifier) -eq ($getCustomGroup.identifier)) {
    
    $teststate = 'SUCCESS'
    #write-host ($testname + ": " + $teststate) -foregroundcolor green 
    write-host "vROPs Group identifier = " $createCustomGroup.identifier
    #update input list wite identifier
    $tag.identifier = $createCustomGroup.identifier
    }
    else {
    write-host ($testname + ": " + $teststate) -foregroundcolor red
    }
    $tags += $tag
    }
}
$tags | Export-Csv .\tags.csv -NoTypeInformation -Force