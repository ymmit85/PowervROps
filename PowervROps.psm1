<#
.SYNOPSIS  
    PowerShell module that enables the use of the vROPs API via PowerShell cmdlets 
.DESCRIPTION
.NOTES
    Version:        0.5.0
	Author:         Andy Davies (andyd@vmware.com)
	Github:         andyvmware
	
	Author:         Tim Willimas (tim@ymmit.net)
    Twitter:        @ymmit85
	Github:         ymmit85

.LINK
    https://github.com/andydvmware/PowervROps
    https://github.com/ymmit85/PowervROps
#>

################################################
# Adding certificate exception to prevent API errors
################################################
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = `
[Net.SecurityProtocolType]::Tls12,
[Net.SecurityProtocolType]::Tls11,
[Net.SecurityProtocolType]::Ssl3

function getTimeSinceEpoch {
	<#
		.SYNOPSIS
			Function to obtain the current time in milliseconds since the Unix epoch
		.DESCRIPTION
			Function used by other functions in the module to convert either the current date/time
			or a previous date/time into milliseconds since the Unix epoch which is what vROps uses
			for all of its time calculations
		.EXAMPLE
			getTimeSinceEpoch
		.EXAMPLE
			getTimeSinceEpoch -date (get-date -day 12 -month 06 -year 2016 -hour 14 -minute 50 -second 30)
		.EXAMPLE
			getTimeSinceEpoch -date $somepreviousvariable
		.PARAMETER date
			PowerShell date object
		.NOTES
			Added in version 0.1
			Updated to include date argument in 0.3.5
	#>
	Param	(
		[parameter(Mandatory=$false)]$date,
		[parameter(Mandatory=$false)]$hourstoadd
		)
	process {
		$epoch = (get-date -Date "01/01/1970").ToUniversalTime()
		if ($date -eq $null) {
			$referencetime = ((get-date).AddHours($hourstoadd)).ToUniversalTime()
			write-host ((get-date).AddHours($hourstoadd)).ToUniversalTime()
			write-host (get-date).ToUniversalTime()
		}
		else {
			$referencetime = $date.ToUniversalTime()
		}
		$timesinceepoch = [math]::floor(($referencetime - $epoch).TotalMilliseconds)
		return $timesinceepoch
	}
}

function convertEpoch {
	<#
		.SYNOPSIS
			Function to convert epoch time to normal
		.DESCRIPTION
			Function to convert epoch time to normal
		.EXAMPLE
			convertEpoch
		.EXAMPLE
			convertEpoch -epochTime 1537615930

		.PARAMETER epochTime
			Epoch Time object
		.NOTES
	#>
	Param	(
		[parameter(Mandatory=$false)]$epochTime
		)
	process {
		$convertedDate = (Get-Date 01.01.1970)+([System.TimeSpan]::FromMilliseconds($epochTime))
		$convertedDate = $convertedDate.ToString("HH:mm:ss dd-MM-yyyy")
		return $convertedDate
	}
}

function setRestHeaders {
	<#
		.SYNOPSIS
			Function to set the rest headers to allow rest methods to be executed
		.DESCRIPTION
			To enable standardisation of execution, all of the functions that are performing
			tasks on the vROps instance use standard means of performing that execution.
			These functions (invokeRestMethod & invokeWebRequest) need certain headers setting
			based on the format that requests and responses are executed but also because there
			certain calls which require a special header value to be set
		.EXAMPLE
			setRestHeaders -accept json -token $token -contenttype json
		.EXAMPLE
			setRestHeaders -accept json -contenttype json -useinternalapi $true
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER contenttype
			Analogous to the header parameter 'Content-Type' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER useinternalapi
			Used only by functions that are accessing vROps internal api. This sets the value of the header
			parameter 'X-vRealizeOps-API-use-unsupported' to 'true'.
		.NOTES
			Added in version 0.3
	#>
	Param	(
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',	
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$contenttype = 'json',
		[parameter(Mandatory=$false)][ValidateSet($true,$false)][string]$useinternalapi = $false
		
		)
	Process {
		$restheaders = @{}
		$restheaders.Add('Accept','application/'+$accept)
		if ($contenttype -ne $null) {
			$restheaders.Add('Content-Type','application/'+$contenttype)
		}
		if ($token -ne $null) {
			$restheaders.Add('Authorization',('vRealizeOpsToken ' + $token))
		}
		if ($useinternalapi -eq $true) {
			$restheaders.Add("X-vRealizeOps-API-use-unsupported","true")
		}		
		return $restheaders
	}
}
function invokeRestMethod {
	<#
		.SYNOPSIS
			Function to invoke the rest method, from other functions within the module
		.DESCRIPTION
			To standardise the module, all functions use the invokeRestMethod for the actual
			rest call.
		.EXAMPLE
			invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		.EXAMPLE
			invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		.EXAMPLE
			invokeRestMethod -method 'POST' -url $url -accept $accept -token $token -contenttype $contenttype -body $body
		.EXAMPLE
			invokeRestMethod -method 'POST' -url $url -accept $accept -credentials $credentials -contenttype $contenttype -body $body
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER url
			The url against which the request will be performed. This will be passed to the cmdlet by the originating
			request and does not need any user modification.
		.PARAMETER method
			The request type, valid values are (currently) 'GET', 'PUT', 'POST', 'DELETE'
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER contenttype
			Analogous to the header parameter 'Content-Type' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER useinternalapi
			Used only by functions that are accessing vROps internal api. This sets the value of the header
			parameter 'X-vRealizeOps-API-use-unsupported' to 'true'.
		.PARAMETER timeoutsec
			Number of seconds to wait before timing out the request
		.NOTES
			Added in version 0.3
	#>
	Param (
		[parameter(Mandatory=$false)]$credentials,	
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)]$url,
		[parameter(Mandatory=$false)][ValidateSet('GET','PUT','POST','DELETE')][string]$method,
		[parameter(Mandatory=$false)]$body,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',	
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$contenttype = 'json',
		[parameter(Mandatory=$false)][ValidateSet($true,$false)][string]$useinternalapi = $false,
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$false)][int]$timeoutsec = 30
	)
	Process {
		if (($credentials -eq $null) -and ($token -eq $null)) {
			Write-Host ("ERROR: ") -ForegroundColor red -nonewline; Write-Host 'No credentials or bearer token supplied' -ForegroundColor White;
			return
		}
		elseif ($token -ne $null) {
			if ($useinternalapi -eq $true) {
				$restheaders = setRestHeaders -accept $accept -token $token -contenttype $contenttype -useinternalapi $true
			}
			else {
				$restheaders = setRestHeaders -accept $accept -token $token -contenttype $contenttype
			}
		}
		else {
			if ($useinternalapi -eq $true) {
				$restheaders = setRestHeaders -accept $accept -contenttype $contenttype -useinternalapi $true
			}
			else {
				$restheaders = setRestHeaders -accept $accept -contenttype $contenttype
			}
		}
		if ($body -ne $null) {
			if ($token -ne $null) {
				Try {

				
					$response = Invoke-RestMethod -Method $method -Uri $url -Headers $restheaders -body $body -timeoutsec $timeoutsec -ErrorAction Stop

				
					return $response
				}
				Catch {
					
			return $_.Exception
				}	
			}
			else {
				Try {

			
					$response = Invoke-RestMethod -Method $method -Uri $url -Headers $restheaders -body $body -credential $credentials -timeoutsec $timeoutsec -ErrorAction Stop

				
					return $response
				}
				Catch {

			return $_.Exception.Message	
				}
			}
		}
		else {
			if ($token -ne $null) {
				Try {

		
					$response = Invoke-RestMethod -Method $method -Uri $url -Headers $restheaders -timeoutsec $timeoutsec -ErrorAction Stop

			
					return $response
				}
				Catch {

			return $_.Exception.Message
				}	
			}
			else {
				Try {

			
					$response = Invoke-RestMethod -Method $method -Uri $url -Headers $restheaders -credential $credentials -timeoutsec $timeoutsec -ErrorAction Stop

				
					return $response
				}
				Catch {
			return $_.Exception.Message
				}
			}
		}
	}
}

function connectvROpsServer { # TBC
}

#/api/audit -------------------------------------------------------------------------------------------------------

function getSystemAudit {
	<#
		.SYNOPSIS
			Get system audit report.
		.DESCRIPTION
			Get system audit report.
		.EXAMPLE
			getSystemAudit -token $validtoken -resthost 'fqdn of vROps instance' -accept json
		.EXAMPLE
			getSystemAudit -credentials $validpscredentials -resthost 'fqdn of vROps instance' -accept xml
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/audit/system'
		if ($token -ne $null) {
			$getSystemAuditresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getSystemAuditresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getSystemAuditresponse
	}
}

#/api/product -------------------------------------------------------------------------------------------------------

function getProductEdition {
	<#
		.SYNOPSIS
			Get edition of product licensing.
		.DESCRIPTION
			Get edition of product licensing.
		.EXAMPLE
			getProductEdition -token $validtoken -resthost 'fqdn of vROps instance' -accept json
		.EXAMPLE
			getProductEdition -credentials $validpscredentials -resthost 'fqdn of vROps instance' -accept xml
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/audit/system'
		if ($token -ne $null) {
			$getProductEditionResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getProductEditionResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getProductEditionResponse
	}
}

#/api/actiondefinitions -------------------------------------------------------------------------------------------------------

function getAllActions {
	<#
		.SYNOPSIS
			Look up all Action Definitions in the system.
		.DESCRIPTION
			Executing will query for all available Actions defined in the system.
			This includes the data needed to populate an Action in the system.
		.EXAMPLE
			getAllActions -token $validtoken -resthost 'fqdn of vROps instance' -accept json
		.EXAMPLE
			getAllActions -credentials $validpscredentials -resthost 'fqdn of vROps instance' -accept xml
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
			Added in version 0.3
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/actiondefinitions'
		if ($token -ne $null) {
			$getAllActionsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getAllActionsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getAllActionsresponse
	}
}

# /api/actions ----------------------------------------------------------------------------------------------------------------

# /api/adapterkinds -----------------------------------------------------------------------------------------------------------

function getResourcesWithAdapterAndResourceKind {
	<#
		.SYNOPSIS
			Query for Resources within a particular Adapter Kind and Resource Kind.
		.DESCRIPTION
			Optionally filter these resources based on resource name. The resource name (specified as a query parameter) will be used for doing a partial match.
			However, if the resource identifiers and their values are specified, name is ignored and the API enforces all the mandatory (both uniquely identifying and required) identifiers are specified. This allows for looking up a single resource using a ResourceKey and allows the translation between a ResourceKey and a Resource UUID
		.EXAMPLE
			getResourcesWithAdapterAndResourceKind -resthost $h -credentials $cred -adapterKindKey vmware -resourceKind virtualmachine -identifiers [VMEntityObjectID]=vm-2162
		.EXAMPLE
			getResourcesWithAdapterAndResourceKind -resthost $h -credentials $cred -adapterKindKey vmware -resourceKind Datastore -identifiers [VMEntityName]=Local_R0
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.

		.PARAMETER resourceKind
			The resourceKind of the objects to query. This will return multiple objects. Examples of resourceKind are:
				eg: ClusterComputeResource
				eg: VirtualMachine

		.PARAMETER adapterKindKey
			The adapterKind to query.
				eg: VMWARE
		.PARAMETER identifiers
			Resource Identifiers where the Key represents the Resource Identifier Key and the Value represents the Resource Identifier value
				eg: [VMEntityObjectID]=vm-2162
				eg: [VMEntityName]=vcsa
				eg: [VMEntityVCID]=41da59b4-64e7-4e83-85e0-1b194d9a08e4
		.NOTES
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][String]$name,
		[parameter(Mandatory=$false)][String]$resourceKind,
		[parameter(Mandatory=$false)][string]$adapterKindKey,
		[parameter(Mandatory=$false)][string]$identifiers
		)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/adapterkinds/'

		if ($adapterKindKey -ne "") {
			$url += $adapterKindKey
		}
		if ($resourceKind -ne "") {
			$url += '/resourcekinds/' + $resourceKind + '/resources'
		}
		if ($identifiers -ne "") {
			$url += '?identifiers' + $identifiers
		}
		$url
		if ($token -ne $null) {
			$getResourcesWithAdapterAndResourceKindResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getResourcesWithAdapterAndResourceKindResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}
		return $getResourcesWithAdapterAndResourceKindResponse.resourcelist
	}
}

# /api/adapters ---------------------------------------------------------------------------------------------------------------

function enumerateAdapterInstances {
	<#
		.SYNOPSIS
			Returns all the adapter instance resources in the system.
		.DESCRIPTION
			Returns all the adapter instance resources in the system.
		.EXAMPLE
			enumerateAdapterInstances -resthost $resthost -token $token
		.EXAMPLE
			enumerateAdapterInstances -resthost $resthost -token $token -adapterKindKey VMWARE
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER adapterKindKey
			The name of the adapter type to filter
		.NOTES
			Added in version 0.2
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$false)]$adapterKindKey
		)
	Process {
		if ($adapterKindKey -ne $null) {
			$url = 'https://' + $resthost + '/suite-api/api/adapters?adapterKindKey=' + $adapterKindKey
		}
		else {
			$url = 'https://' + $resthost + '/suite-api/api/adapters'
		}
		if ($token -ne $null) {
			$enumerateAdapterInstancesresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$enumerateAdapterInstancesresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $enumerateAdapterInstancesresponse
	}
}

function getAdapterInstances {
	<#
		.SYNOPSIS
			Look up a single adapter instance using an identifier.
		.DESCRIPTION
			Look up a single adapter instance using an identifier.
			Returns a specific adapter instance identified by the specified UUID. 
		.EXAMPLE
			getAdapterInstances -resthost $resthost -token $token -adapterID
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER adapterID
			The name of the adapter ID to filter.
		.NOTES
			
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$false)]$adapterID
		)
	Process {

			$url = 'https://' + $resthost + '/suite-api/api/adapters/' + $adapterID

		if ($token -ne $null) {
			$getAdapterInstancesresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getAdapterInstancesresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getAdapterInstancesresponse
	}
}

function deleteAdapterInstance {
	<#
		.SYNOPSIS
			Deletes an adapter instance using an identifier.
		.DESCRIPTION
			Deletes an adapter instance using an identifier.
		.EXAMPLE
			deleteAdapterInstances -resthost $resthost -token $token -adapterID
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER adapterID
			The name of the adapter ID to delete.
		.NOTES
			
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$false)]$adapterID
		)
	Process {

			$url = 'https://' + $resthost + '/suite-api/api/adapters/' + $adapterID

		if ($token -ne $null) {
			$deleteAdapterInstancesresponse = invokeRestMethod -method 'DELETE' -url $url -accept $accept -token $token
		}
		else {
			$deleteAdapterInstancesresponse = invokeRestMethod -method 'DELETE' -url $url -accept $accept -credentials $credentials
		}	
		return $deleteAdapterInstancesresponse
	}
}


function setAdapterInMaintenance {
	<#
		.SYNOPSIS
			Place specified Adapter into maintenance.
		.DESCRIPTION
			Marks the adapter instance as being 'maintained' for the given duration.
			After the duration expires, the adapter instance state is automatically set to 'STARTED'		 
		.EXAMPLE
			setAdapterInMaintenance -resthost $resthost -token $token -adapterID 300fd432-9975-4aaa-ac3e-0438b28cf58e -duration '5'
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER adapterID
			The name of the adapter type to filter
		.PARAMETER minutes
			Duration of maintenance window in mintes,
		.NOTES
			
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$true)]$adapterID,
		[parameter(Mandatory=$true)]$minutes

		)
	Process {
			$url = 'https://' + $resthost + '/suite-api/api/adapters/' + $adapterID + '/maintained/?duration=' + $minutes

		if ($token -ne $null) {
			$setAdapterInMaintenanceResponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -token $token
		}
		else {
			$setAdapterInMaintenanceResponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -credentials $credentials
		}	
		return $setAdapterInMaintenanceResponse
	}
}


function setAdapterEndMaintenance {
	<#
		.SYNOPSIS
			Removes specified Adapter from maintenance.
		.DESCRIPTION
			Marks the adapter instance as being 'started'. 
			Removes the adapter instance from being in an maintenance window. The adapter instance will be notified to start collection process immediately.		 
		.EXAMPLE
			setAdapterEndMaintenance -resthost $resthost -token $token -adapterID 300fd432-9975-4aaa-ac3e-0438b28cf58e
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER adapterID
			The name of the adapter type to filter
		.NOTES
			
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$true)]$adapterID
		)
	Process {
			$url = 'https://' + $resthost + '/suite-api/api/adapters/' + $adapterID + '/maintained'

		if ($token -ne $null) {
			$setAdapterEndMaintenanceResponse = invokeRestMethod -method 'DELETE' -url $url -accept $accept -token $token
		}
		else {
			$setAdapterEndMaintenanceResponse = invokeRestMethod -method 'DELETE' -url $url -accept $accept -credentials $credentials
		}	
		return $setAdapterEndMaintenanceResponse
	}
}

function setAdapterStartMonitoring {
	<#
		.SYNOPSIS
			Starts the adapter instance from monitoring its resources.
		.DESCRIPTION
			Starts the adapter instance from monitoring its resources.		
		.EXAMPLE
			setAdapterStartMonitoring -resthost $resthost -token $token -adapterID 300fd432-9975-4aaa-ac3e-0438b28cf58e
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER adapterID
			The name of the adapter type to filter
		.NOTES

		#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$true)]$adapterID
		)

	Process {
			$url = 'https://' + $resthost + '/suite-api/api/adapters/' + $adapterId + '/monitoringstate/start'

		if ($token -ne $null) {
			$setAdapterStartMonitoringResponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -token $token
		}
		else {
			$setAdapterStartMonitoringResponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -credentials $credentials
		}	
		return $setAdapterStartMonitoringResponse
	}
}

function setAdapterStopMonitoring {
	<#
		.SYNOPSIS
			Stops the adapter instance from monitoring its resources.
		.DESCRIPTION
			Stops the adapter instance from monitoring its resources.
		.EXAMPLE
			setAdapterStopMonitoring -resthost $resthost -token $token -adapterID 300fd432-9975-4aaa-ac3e-0438b28cf58e
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER adapterID
			The name of the adapter type to filter
		.NOTES

		#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$true)]$adapterID
		)
	Process {
			$url = 'https://' + $resthost + '/suite-api/api/adapters/' + $adapterId + '/monitoringstate/stop'

		if ($token -ne $null) {
			$setAdapterStopMonitoringResponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -token $token
		}
		else {
			$setAdapterStopMonitoringResponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -credentials $credentials
		}	
		return $setAdapterStopMonitoringResponse
	}
}

# /api/alertdefinitions -------------------------------------------------------------------------------------------------------
	
function getAlertDefinitionById {
	<#
		.SYNOPSIS
			Gets Alert Definition using the identifier specified.
		.DESCRIPTION
			Gets Alert Definition using the identifier specified.
		.EXAMPLE
			getAlertDefinitionById -resthost $resthost -token $token -alertdefinitionid $alertdefinitionid
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER alertdefinitionid
			The vROps ID of the alert definition
		.NOTES
			Added in version 0.2
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$true)][String]$alertdefinitionid
		)
	$url = 'https://' + $resthost + '/suite-api/api/alertdefinitions/' + $alertdefinitionid		

	if ($token -ne $null) {
		$getAlertDefinitionByIdresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
	}
	else {
		$getAlertDefinitionByIdresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
	}	
	return $getAlertDefinitionByIdresponse

}	

function getAlertDefinitions {
	<#
		.SYNOPSIS
			Returns a collection of Alert Definitions matching the search criteria specified.
		.DESCRIPTION
			Returns a collection of Alert Definitions matching the search criteria specified.
		.EXAMPLE
			getAlertDefinitions -resthost $resthost -token $token
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER alertdefinitionid
			The identifier(s) of the Alert Definitions to search for.
			Do not specify adapterKind or resourceKind if searching by the identifier
		.PARAMETER adapterkind
			Adapter Kind key of the Alert Definitions to search for
		.PARAMETER resourcekind
			Resource Kind key of the Alert Definitions to search for
		.NOTES
			Added in version 0.2
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][String]$alertdefinitionid,
		[parameter(Mandatory=$false)][String]$adapterkind,
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$false)][String]$resourcekind
		)
	Process {
		if (($alertdefinitionid -ne "") -and (($adapterkind -ne "") -or ($resourcekind -ne ""))) {
			write-host "alertdefinition" $alertdefintion
			write-host "WARNING - When specifying an alert definition ID, an adapterkind or resourcekind are not necessary"
			return
		}
		else {
			if ($alertdefinitionid -ne "") {
				$url = 'https://' + $resthost + '/suite-api/api/alertdefinitions/?id=' + $alertdefinitionid
			}
			elseif ($adapterkind -ne "") {
				if ($resourcekind -ne "") {
					$url = 'https://' + $resthost + '/suite-api/api/alertdefinitions/?adapterKind=' + $adapterkind + '&resourceKind=' + $resourcekind 
				}
				else {
					$url = 'https://' + $resthost + '/suite-api/api/alertdefinitions/?adapterKind=' + $adapterkind
				}
			}
			elseif ($resourcekind -ne "") {
				$url = 'https://' + $resthost + '/suite-api/api/alertdefinitions/?resourceKind=' + $resourcekind 
			}
			else {
				$url = 'https://' + $resthost + '/suite-api/api/alertdefinitions'
			}
			if ($token -ne $null) {
				$getAlertDefinitionsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
			}
			else {
				$getAlertDefinitionsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
			}	
			return $getAlertDefinitionsresponse
		}
	}
}

# /api/alertplugins -----------------------------------------------------------------------------------------------------------
	
# /api/alerts -----------------------------------------------------------------------------------------------------------------

function getAlert {
	<#
		.SYNOPSIS
			Look up an Alert by its identifier.
		.DESCRIPTION
			Look up an Alert by its identifier.
		.EXAMPLE
			getAlerts -token $validtoken -resthost 'fqdn of vROps instance' -accept json -alertid 3014d718-18e4-42d5-b264-66f6b4ff4d8e
		.EXAMPLE
			getAlerts -credentials $validpscredentials -resthost 'fqdn of vROps instance' -accept xml -alertid 3014d718-18e4-42d5-b264-66f6b4ff4d8e
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER alertid
			The vROps ID of the alert to query.
		.NOTES
			Added in version 0.2
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][String]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$true)][String]$alertid
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/alerts/' + $alertid
		if ($token -ne $null) {
			$getAlertresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getAlertresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getAlertresponse
	}
}
function getAlerts {
	<#
		.SYNOPSIS
			Look up Alerts by their identifiers or using the identifiers of the Resources they are associated with.
		.DESCRIPTION
			Look up Alerts by their identifiers or using the identifiers of the Resources they are associated with.
		.EXAMPLE
			getAlerts -token $validtoken -resthost 'fqdn of vROps instance' -accept json
		.EXAMPLE
			getAlerts -credentials $validpscredentials -resthost 'fqdn of vROps instance' -accept xml
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
			Added in version 0.2
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/alerts'
		if ($token -ne $null) {
			$getAlertsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getAlertsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getAlertsresponse
	}
}

# /api/auth -------------------------------------------------------------------------------------------------------------------

function acquireToken {
	<#
		.SYNOPSIS
			Acquire a token to perform REST API calls.
		.DESCRIPTION
			Performing this request would yield a response object that includes token and its validity.
		.EXAMPLE
			acquireToken -resthost 'fqdn of vROps instance' -accept json -username 'admin' -password 'somepassword' -authSource 'local'
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER username
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER authSource
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER password
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER contenttype
			Analogous to the header parameter 'Content-Type' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
			Added in version 0.2
	#>
	Param	(
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$contenttype = 'json',
		[parameter(Mandatory=$false)][string]$username,
		[parameter(Mandatory=$false)][string]$authSource,
		[parameter(Mandatory=$false)][string]$password
	)
	Process {
		$restheaders = @{}
		$restheaders.Add('Accept','application/'+$accept)
		$restheaders.Add('Content-Type','application/'+$contenttype)
		$url = 'https://' + $resthost + '/suite-api/api/auth/token/acquire'
		if ($contenttype -eq 'json') {
			$body = @{
				'username' = $username
				'authSource' = $authSource
				'password' = $password
				'others' = @()
				'otherAttributes' = @{}
				} | convertto-json
		}
		Try {
			$response = Invoke-RestMethod -Method 'POST' -Uri $url -Headers $restheaders -body $body -ErrorAction Stop
			return $response.token
		}
		Catch {
			Write-Host ("ERROR: ") -ForegroundColor red -nonewline; Write-Host 'Token not generated' -ForegroundColor White;
			Write-Host $response
			Write-Host $Error[0].Exception

		}		
	}
}

function releaseToken {
	<#
		.SYNOPSIS
			Call this URL to terminate the current sessionId.  
		.DESCRIPTION
			Call this URL to terminate the current sessionId.  
		.EXAMPLE
			releaseToken -resthost $resthost -token $token
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.

		.NOTES
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/auth/token/release' 
		$getAuthSourceResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		return $getAuthSourceResponse
	}
}


function getAuthSources {
	<#
		.SYNOPSIS
			Lists all the available auth sources in the system.
		.DESCRIPTION
			Lists all the available auth sources in the system.
		.EXAMPLE
			getAuthSources -resthost $resthost -credentials $credentials
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.NOTES
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/auth/sources'
		if ($token -ne $null) {
			$getAuthSourcesResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getAuthSourcesResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getAuthSourcesResponse
	}
}

function getAuthSource {
	<#
		.SYNOPSIS
			Retrieve information about a particular authentication source. 
		.DESCRIPTION
			Retrieve information about a particular authentication source. 
		.EXAMPLE
			getAuthSource -resthost $resthost -credentials $credentials -sourceID $sourceID
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER sourceID
			Source ID of the Authentication Source.

		.NOTES
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$true)][String]$sourceID,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/auth/sources/' + $sourceID
		if ($token -ne $null) {
			$getAuthSourceResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getAuthSourceResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getAuthSourceResponse
	}
}

function getRoles {
	<#
		.SYNOPSIS
			Query for a list of application roles using the role names. 
		.DESCRIPTION
			Query for a list of application roles using the role names. 
		.EXAMPLE
			getRoles -resthost $resthost -credentials $credentials
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.NOTES
			Need to add in additioanl request params

	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/auth/roles/'
		if ($token -ne $null) {
			$getRolesResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getRolesResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getRolesResponse
	}
}

function getUsers {
	<#
		.SYNOPSIS
			Look up a list of users using the user identifiers or their role names. 
		.DESCRIPTION
			Look up a list of users using the user identifiers or their role names. 
			If both ids and roleNames are not specified, information about all the local users are returned. 
 		.EXAMPLE
			getUser -resthost $resthost -credentials $credentials
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.NOTES
			Need to add in additioanl request params
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/auth/users/'
		if ($token -ne $null) {
			$getUserResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getUserResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getUserResponse
	}
}

function getUserGroups {
	<#
		.SYNOPSIS
			Retrieve a list of local user groups using identifiers or names or all. 
		.DESCRIPTION
			Retrieve a list of local user groups using identifiers or names or all. 
			If none of the parameters are specified, all the user groups in the system are returned.  
		.EXAMPLE
			getUserGroups -resthost $resthost -credentials $credentials
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.NOTES
			Need to add in additioanl request params

	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/auth/usergroups/'
		if ($token -ne $null) {
			$getUserGroupsResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getUserGroupsResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getUserGroupsResponse
	}
}

# /api/collectorgroups --------------------------------------------------------------------------------------------------------

function getCollectorGroups {
		<#
		.SYNOPSIS
			Enumerates all the Collector Groups defined in the system.
		.DESCRIPTION
			Enumerates all the Collector Groups defined in the system.
		.EXAMPLE
			getCollectorGroups -resthost $resthost -token $token
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
	#>
Param	(
	[parameter(Mandatory=$false)]$credentials,
	[parameter(Mandatory=$true)][String]$resthost,
	[parameter(Mandatory=$false)]$token,
	[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)

$url = 'https://' + $resthost + '/suite-api/api/collectorgroups'

if ($token -ne $null) {
	$getCollectorGroups = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
}
else {
	$getCollectorGroups = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
}	
return $getCollectorGroups
}

function getCollectorGroup {
		<#
		.SYNOPSIS
			Gets details of a particular Collector Group in the system.
		.DESCRIPTION
			Gets details of a particular Collector Group in the system.
		.EXAMPLE
			getCollectorGroup -resthost $resthost -token $token -id $id
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER id
			ID of the collector group to retrieve.
		.NOTES
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)]$id
	)
	
	$url = 'https://' + $resthost + '/suite-api/api/collectorgroups/' + $id
	
	if ($token -ne $null) {
		$getCollectorGroupresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
	}
	else {
		$getCollectorGroupresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
	}	
	return $getCollectorGroupresponse
	}

	function deleteCollectorGroup {
		<#
			.SYNOPSIS
				Deletes Collector Group from the system using its identifier..
			.DESCRIPTION
				Deletes Collector Group from the system using its identifier..
			.EXAMPLE
				deleteCollecotrGroup -resthost $resthost -token $token -id $id
			.PARAMETER credentials
				A set of PS Credentials used to authenticate against the vROps endpoint.
			.PARAMETER token
				If token based authentication is being used (as opposed to credential based authentication)
				then the token returned from the acquireToken cmdlet should be used.
			.PARAMETER resthost
				FQDN of the vROps instance or cluster to operate against.
			.PARAMETER accept
				Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
				However, the module has only been tested against json.
			.PARAMETER id
				ID of the collector to fromve group.
			.PARAMETER collectorid
				ID of the collector group to remove collector from.
			.NOTES
		#>
		Param	(
			[parameter(Mandatory=$false)]$credentials,
			[parameter(Mandatory=$true)][String]$resthost,
			[parameter(Mandatory=$false)]$token,
			[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
			[parameter(Mandatory=$true)]$collectorid
		)
		$url = 'https://' + $resthost + '/suite-api/api/collectorgroups/' + $id
		if ($token -ne $null) {
			$deleteCollectorfromGroupresponse = invokeRestMethod -method 'DELETE' -url $url -accept $accept -token $token
		}
		else {
			$deleteCollectorfromGroupresponse = invokeRestMethod -method 'DELETE' -url $url -accept $accept -credentials $credentials
		}	
		return $deleteCollectorfromGroupresponse
	}

	function addCollectortoGroup {
		<#
			.SYNOPSIS
				Adds Collector Group from the system using its identifier..
			.DESCRIPTION
				Adds Collector Group from the system using its identifier..
			.EXAMPLE
				addCollectortoGroup -resthost $resthost -token $token -id $id -collectorid $collectorid
			.PARAMETER credentials
				A set of PS Credentials used to authenticate against the vROps endpoint.
			.PARAMETER token
				If token based authentication is being used (as opposed to credential based authentication)
				then the token returned from the acquireToken cmdlet should be used.
			.PARAMETER resthost
				FQDN of the vROps instance or cluster to operate against.
			.PARAMETER accept
				Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
				However, the module has only been tested against json.
			.PARAMETER id
				ID of the collector to add to collector group.
			.PARAMETER collector
				ID of the collector group to add collector into.
			.NOTES
		#>
		Param	(
			[parameter(Mandatory=$false)]$credentials,
			[parameter(Mandatory=$true)][String]$resthost,
			[parameter(Mandatory=$false)]$token,
			[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
			[parameter(Mandatory=$true)]$collectorid,
			[parameter(Mandatory=$true)]$id
		)
		$url = 'https://' + $resthost + '/suite-api/api/collectorgroups/' + $id + '/collector/' + $collectorid
		if ($token -ne $null) {
			$addCollectorToGroupresponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -token $token
		}
		else {
			$addCollectorToGroupresponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -credentials $credentials
		}	
		return $addCollectorToGroupresponse
	}

# /api/collectors -------------------------------------------------------------------------------------------------------------

function getAdaptersOnCollector {
	<#
		.SYNOPSIS
			Gets all the Adapters registered (bound) to a specific Collector.
		.DESCRIPTION
			Gets all the Adapters registered (bound) to a specific Collector.
		.EXAMPLE
			getAdaptersOnCollector -resthost $resthost -token $token -collectorid $collectorsid
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER collectorid
			ID of the collector to query
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)]$collectorid
	)
	$url = 'https://' + $resthost + '/suite-api/api/collectors/' + $collectorid + '/adapters'
	if ($token -ne $null) {
		$getAdaptersOnCollectorresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
	}
	else {
		$getAdaptersOnCollectorresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
	}	
	return $getAdaptersOnCollectorresponse
}
function getCollectors {
	<#
		.SYNOPSIS
			Gets all the Collectors registered with the vRealize Operations Manager system.
		.DESCRIPTION
			Gets all the Collectors registered with the vRealize Operations Manager system.
		.EXAMPLE
			getCollectors -resthost $resthost -token $token
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
		# need to add in host as a parameter
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/collectors'
		if ($token -ne $null) {
			$getCollectorsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getCollectorsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getCollectorsresponse
	}
}

# /api/credentialkinds --------------------------------------------------------------------------------------------------------

function getCredentialKinds {
	<#
		.SYNOPSIS
			Get all Credential Kinds defined in the system. Gets all the Credential Kinds defined in the system. 
		.DESCRIPTION
			Get all Credential Kinds defined in the system. Gets all the Credential Kinds defined in the system.
		.EXAMPLE
			getCredentialKinds -resthost $resthost -token $token
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
			Added in version 0.3
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/credentialkinds'
		
		if ($token -ne $null) {
			$getCredentialKindsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getCredentialKindsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getCredentialKindsresponse
	}
}

# /api/credentials ------------------------------------------------------------------------------------------------------------

function getCredentials {
	<#
		.SYNOPSIS
			Get all Credential Instances in the system. Gets all the Credential Instances in the system. Optionally filter by adapter kind keys or credential instance identifiers.
		.DESCRIPTION
			Get all Credential Instances in the system. Gets all the Credential Instances in the system. Optionally filter by adapter kind keys or credential instance identifiers.
		.EXAMPLE
			getCredentials -resthost $resthost -token $token -accept json
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
			Added in version 0.3
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
		# ID
		# AdapterKind
	)
	$url = 'https://' + $resthost + '/suite-api/api/credentials'
	if ($token -ne $null) {
		$getCredentialsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
	}
	else {
		$getCredentialsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
	}	
	return $getCredentialsresponse
}

# /api/deployment -------------------------------------------------------------------------------------------------------------
function getServicesInfo {
	<#
		.SYNOPSIS
			Gets the health of all Services.
		.DESCRIPTION
			Gets the health of all Services.
		.EXAMPLE
			getServicesInfo -resthost $resthost -credentials $vropscreds
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
			
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/deployment/node/services/info'
		if ($token -ne $null) {
			$getServicesInfoResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getServicesInfoResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getServicesInfoResponse
	}
}

function getServiceInfo {
	<#
		.SYNOPSIS
			Gets information about a specific Service that is part of the vRealize Operations Manager stack.
		.DESCRIPTION
			Gets information about a specific Service that is part of the vRealize Operations Manager stack.
		.EXAMPLE
			getServiceInfo -resthost $resthost -credentials $vropscreds -service
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER name
			Name of service to recieve details for.
		.NOTES
			
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$name,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/deployment/node/services/' + $name + '/info'
		if ($token -ne $null) {
			$getServiceInfoResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getServiceInfoResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getServiceInfoResponse
	}
}

function getLicenceKeysForProduct {
	<#
		.SYNOPSIS
			Gets all the License Details associated with a vRealize Operations Manager instance.
		.DESCRIPTION
			Gets all the License Details associated with a vRealize Operations Manager instance.
		.EXAMPLE
			getLicenceKeysForProduct -resthost $resthost -token cac9cdc1-c2b3-487c-a51f-4ccb45e2b246::5e0ab7fa-f401-497a-acce-e2429791fe98
		.EXAMPLE
			getLicenceKeysForProduct -resthost $resthost -credentials $credentials
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
			Added in version 0.3
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/deployment/licenses'
		if ($token -ne $null) {
			$getLicenceKeysForProductresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getLicenceKeysForProductresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getLicenceKeysForProductresponse
	}
}

function getNodeStatus {
	<#
		.SYNOPSIS
			get the status of the node
		.DESCRIPTION
			If the status is ONLINE if all the services are running and responsive. else status is OFFLINE 
		.EXAMPLE
			getNodeStatus -resthost $resthost -credentials $vropscreds
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
			Added in version 0.3.5
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/deployment/node/status'
		if ($token -ne $null) {
			$getNodeStatusresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getNodeStatusresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getNodeStatusresponse
	}
}

function getGlobalsettings {
	<#
		.SYNOPSIS
			get the global settings configured within vROPs
		.DESCRIPTION
			get the global settings configured within vROPs
		.EXAMPLE
			getGlobalsettings -resthost $resthost -credentials $vropscreds
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/deployment/config/globalsettings'
		if ($token -ne $null) {
			$getGlobalsettingsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getGlobalsettingsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getGlobalsettingsresponse
	}
}
# /casa -------------------------------------------------------------------------------------------------------------
function getPakList {
	<#
		.SYNOPSIS
			Get list of Pak files deployed to nodes.
		.DESCRIPTION
			Get list of Pak files deployed to nodes.
			Used when following process on https://kb.vmware.com/s/article/2127895
		.EXAMPLE
			getPakList -resthost $resthost -credentials $vropscreds
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
			
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/casa/upgrade/cluster/pak/reserved/list'
		if ($token -ne $null) {
			$getPakListResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getPakListResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getPakListResponse
	}
}

function getPakStatus {
	<#
		.SYNOPSIS
			Gets status of Pak file deployed to nodes in cluster..
		.DESCRIPTION
			Gets status of Pak file deployed to nodes in cluster.
			Used when following process on https://kb.vmware.com/s/article/2127895
		.EXAMPLE
			getPakStatus -resthost $resthost -credentials $vropscreds
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER pakId
			Name of pak ID to search for.
		.NOTES
			
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$pakID,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/casa/upgrade/cluster/pak/' + $pakID + '/status'
		if ($token -ne $null) {
			$getPakStatusResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getPakStatusResponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getPakStatusResponse
	}
}

function getPakDistributionStatus {
		<#
		.SYNOPSIS
			Gets distribution status of pak file on nodes in cluster from function getPakstatus
		.DESCRIPTION
			Gets distribution status of pak file on nodes in cluster from function getPakstatus
			Used when following process on https://kb.vmware.com/s/article/2127895
		.EXAMPLE
			getPakDistributionStatus -pakStatusResponse $pakStatusResponse
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.NOTES
	#>

	Param (
		[parameter(Mandatory=$true)]$pakStatusResponse
	)
	Process {
		Foreach ($slice in $pakStatusResponse.slices) {
			$slice.slice_address
			$slice.document
		}
	}
}
# /api/events -----------------------------------------------------------------------------------------------------------------

# /api/maintenanceschedules ---------------------------------------------------------------------------------------------------

# /api/notifications ----------------------------------------------------------------------------------------------------------
function getNotificationRules {
	<#
		.SYNOPSIS
			Returns all the Notification Rules defined in the system
		.DESCRIPTION
			Returns all the Notification Rules defined in the system
		.EXAMPLE
			getNotificationRules -resthost $resthost -credentials $vropscreds
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
			
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/notifications/rules'
		if ($token -ne $null) {
			$getNotificationRulesresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getNotificationRulesresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getNotificationRulesresponse
	}
}

function createNotificationRule {
	<#
		.SYNOPSIS
			Creates a new Notification Rule for a Notification Plugin Instance.
			The Notification Plugin with which the Rule needs to be associated must be specified as part of the request.  
		.DESCRIPTION
			Creates a new Notification Rule for a Notification Plugin Instance.
			The Notification Plugin with which the Rule needs to be associated must be specified as part of the request.  
		.EXAMPLE
			createNotificationRule -resthost $resthost -token $token -body $body
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER contenttype
			Analogous to the header parameter 'Content-Type' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER body
			Body content that describes the property/properties being added to the object
		.NOTES
			
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][ValidateSet('xml','json')]$contenttype = 'json',
		[parameter(Mandatory=$true)][String]$body
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/notifications/rules'
		if ($token -ne $null) {
			$addNotificationRulesresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -token $token -body $body -contenttype $contenttype
		}
		else {
			$addNotificationRulesresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -credentials $credentials -body $body -contenttype $contenttype
		}
		return $addNotificationRulesresponse
	}
}

# /api/recommendations --------------------------------------------------------------------------------------------------------

# /api/reportdefinitions ------------------------------------------------------------------------------------------------------

function getReportDefinitions { # No test currently
	<#
		.SYNOPSIS
			TBC
		.DESCRIPTION
			TBC
		.EXAMPLE
			TBC
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER name
			TBC
		.PARAMETER owner
			TBC
		.PARAMTER duration
			TBC
		.NOTES
			Added in version 0.3.7
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][String]$name,
		[parameter(Mandatory=$false)][String]$owner,
		[parameter(Mandatory=$false)][String]$subject
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/reportdefinitions'
		if ($name -ne "") {
			$url += '?name=' + $name
			if ($owner -ne ""){
				$url += '&owner=' + $owner
			}
			if ($subject -ne "") {
				$url += '&subject' + $subject
			}
		}
		elseif ($owner -ne ""){
			$url += '?owner=' + $owner
			if ($subject -ne "") {
				$url += '&subject' + $subject
			}
		}
		elseif ($subject -ne "") {
			$url += '?subject' + $subject
		}
		if ($token -ne $null) {
			$getReportDefinitionsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getReportDefinitionsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getReportDefinitionsresponse
	}
}

# /api/reports ----------------------------------------------------------------------------------------------------------------

function createReport {
	<#
		.SYNOPSIS
			Generate (create) a Report using the specified Report Definition and for the specified Resource.
		.DESCRIPTION
			Generate (create) a Report using the specified Report Definition and for the specified Resource.
		.EXAMPLE
			createReport -token $token -resthost vrops-01a.cloudkindergarten.local -reportdefinitionid 4eaae8d7-c57a-4e0a-a2bc-e103d63d1aaf -objectid f44eae09-b99a-4e85-9b8f-457739789ba1
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			The vROps ID of the subject that the report will be run against.
		.PARAMETER reportid
			The vROps ID of the report to be generated.
		.NOTES
			Added in version 0.3
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)][String]$objectid,
		[parameter(Mandatory=$true)][String]$reportdefinitionid
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/reports'
		$body = @{
			'id'=$null
			'resourceId'=$objectid
			'reportDefinitionId'=$reportdefinitionid
			'traversalSpec'=@{
				'name'='Custom Groups'
				'rootAdapterKindKey'='?'
				'rootResourceKindKey'='?'
				'adapterInstanceAssociation'=$false
				'others'=@()
				'otherAttributes'=@{}
				}
			'subject'=@()
			'others'=@()
			'otherAttributes'=@{}
		} | convertto-json -depth 5
		if ($token -ne $null) {
			$getCredentialKindsresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -token $token -body $body
		}
		else {
			$getCredentialKindsresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -credentials $credentials -body $body
		}	
		return $getCredentialKindsresponse
	}
}
function downloadReport {
	<#
		.SYNOPSIS
			Download the Report given its identifier.
		.DESCRIPTION
			Download the Report given its identifier. The supported formats for Reports are:
				pdf
				csv
			If the format is not specified the downloaded report will be in PDF format.
		.EXAMPLE
			downloadReport -token $token -resthost $resthost -reportid $reportid -format 'csv' -outputfile 'c:\somedirectory\somefile.csv'
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER reportid
			The vROps ID of the report to be generated.
		.PARAMETER format
			TBC
		.PARAMETER outputfile
			Location to download the report to
		.NOTES
			Added in version 0.3.7
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][ValidateSet('pdf','csv')][string]$format = 'pdf',
		[parameter(Mandatory=$false)]$outputfile,
		[parameter(Mandatory=$true)][String]$reportid
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/reports/' + $reportid + '/download?format=' + $format
		if ($token -ne $null) {
			$restheaders = @{}
			$restheaders.add('Authorization',('vRealizeOpsToken ' + $token))
			$downloadReportresponse = invoke-webrequest -uri $url -header $restheaders -outfile $outputfile -method 'GET'
		}
		else {
			$downloadReportresponse = invoke-webrequest -uri $url -credential $credentials -outfile $outputfile -method 'GET'

		}	
		return $downloadReportresponse
	}
}
function deleteReport {
	<#
		.SYNOPSIS
			Deletes report by it's identifier.
		.DESCRIPTION
			Deletes report by it's identifier.
		.EXAMPLE
			deleteReport -token $token -resthost $resthost -reportid $reportid 
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER reportid
			The vROps ID of the report to be generated.
		.NOTES
			Requires full testing and cleaner output validating deletion of report.
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)][String]$reportid
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/reports/' + $reportid
		if ($token -ne $null) {
			$restheaders = @{}
			$restheaders.add('Authorization',('vRealizeOpsToken ' + $token))
			$deleteReportresponse = invoke-webrequest -uri $url -header $restheaders -method 'DELETE'
		}
		else {
			$deleteReportresponse = invoke-webrequest -uri $url -credential $credentials -method 'DELETE'

		}	
		return $deleteReportresponse
	}
}

function getReport {
	<#
		.SYNOPSIS
			Gets the detail of a Report given its identifier.
		.DESCRIPTION
			Gets the detail of a Report given its identifier.
		.EXAMPLE
			getReport -token $token -resthost $resthost -reportid $reportid
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER reportid
			The vROps ID of the report to be generated.
		.NOTES
			Added in version 0.3.7
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)][String]$reportid
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/reports/' + $reportid
		if ($token -ne $null) {
			$getReportresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getReportresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getReportresponse
	}
}

function getReports {
	<#
		.SYNOPSIS
			Gets the Reports based on the Report Query Spec provided. 
			If the query spec is not provided, all Reports present in the system are returned.
		.DESCRIPTION
			Gets all reports created in system
		.EXAMPLE
			getReports -token $token -resthost $resthost
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
			Requires update to allow additional params.
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/reports'
		if ($token -ne $null) {
			$getReportsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getReportsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getReportsresponse
	}
}
# /api/resources -------------------------------------------------------------------------------------------------------------- 

function addGroupType {
	<#
		.SYNOPSIS
			Add a new group type.
		.DESCRIPTION
			Add a new group type.
		.EXAMPLE
			addGroupType -resthost $resthost -token $token -name 'NewGroup'
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			Group Type name.
		.NOTES

		#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)]$name
	)
	Process {

		$body = @{
			'name' = $objectid
			'others' = @()
			'otherAttributes' = @()
			} | ConvertTo-Json

			$url = 'https://' + $resthost + '/suite-api/api/resources/groups/types'

		if ($token -ne $null) {
			$addGroupTyperesponse = invokeRestMethod -method 'POST' -url $url -accept $accept -token $token -body $body
		}
		else {
			$addGroupTyperesponse = invokeRestMethod -method 'POST' -url $url -accept $accept -credentials $credentials -body $body
		}
		return $addGroupTyperesponse
	}
}

function addProperties {
	<#
		.SYNOPSIS
			Adds Properties to a Resource. 
		.DESCRIPTION
			Adds Properties to a Resource. 
		.EXAMPLE
			addProperties -resthost $resthost -token $token -objectid 8014d795-18e4-42d5-a264-89f6b47f4d8e -body $body
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER contenttype
			Analogous to the header parameter 'Content-Type' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			The vROps ID of the object for which the properties are being added.
		.PARAMETER body
			Body content that describes the property/properties being added to the object
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][ValidateSet('xml','json')]$contenttype = 'json',
		[parameter(Mandatory=$true)][String]$body,
		[parameter(Mandatory=$true)][String]$objectid
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources/' + $objectid + '/properties/'
		if ($token -ne $null) {
			$addPropertiesresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -token $token -body $body -contenttype $contenttype
		}
		else {
			$addPropertiesresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -credentials $credentials -body $body -contenttype $contenttype
		}
		return $addPropertiesresponse
	}
}
function addRelationship {
	<#
		.SYNOPSIS
			Add relationships of given type to the resource with specified resourceId. 
		.DESCRIPTION
			Add relationships of given type to the resource with specified resourceId.
			NOTE: Adding relationship is not synchronous. As a result, the add operation may not happen immediately.
			It is recommended to query the relationships of the specific Resource back to ensure that the operation was indeed successful. 
		.EXAMPLE
			addRelationship -resthost $resthost -token $token -objectid 6434d795-1bc4-42d5-a264-89f6b47f4d8e -relationship children -body $body
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			The vROps ID of the object for which the relationship is being configured
		.PARAMETER body
			Body content that describes the relationship being created
		.PARAMETER relationship
			The relationship that is being defined, valid values are 'parent' or 'children'
		.PARAMETER contenttype
			Analogous to the header parameter 'Content-Type' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][ValidateSet('xml','json')]$contenttype = 'json',
		[parameter(Mandatory=$true)]$body,
		[parameter(Mandatory=$true)][String]$objectid,
		[parameter(Mandatory=$true)][ValidateSet('children','parent')][String]$relationship
		)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources/' + $objectid + '/relationships/' + $relationship
		if ($token -ne $null) {
			$addRelationshipresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -token $token -body $body -contenttype $contenttype
		}
		else {
			$addRelationshipresponse = invokeRestMethod -method 'POST' -url $url -credentials $credentials -body $body -contenttype $contenttype
		}	
		return $addRelationshipresponse
	}
}
function addStats {
	<#
		.SYNOPSIS
			Adds Stats to a Resource.
		.DESCRIPTION
			It is recommended (though not required) to use this API when the resource was created using the API POST /api/resources/{id}/adapters/{adapterInstanceId}.
			Otherwise an additional adapter instance might be created. 
		.EXAMPLE
			addStats -resthost $resthost -token $token -objectid 8014d795-18e4-42d5-a264-89f6b47f4d8e -body $body
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			The vROps ID of the object to add stats to
		.PARAMETER body
			The body payload that contains the details of the metrics and values to add
		.PARAMETER contenttype
			Analogous to the header parameter 'Content-Type' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][ValidateSet('xml','json')]$contenttype = 'json',
		[parameter(Mandatory=$true)]$body,
		[parameter(Mandatory=$true)][String]$objectid
		)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources/' + $objectid + '/stats'
		if ($token -ne $null) {
			$addStatsresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -token $token -body $body -contenttype $contenttype
		}
		else {
			$addStatsresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -credentials $credentials -body $body -contenttype $contenttype
		}	
		return $addStatsresponse
	}
}
function addStatsforResources {
	<#
		.SYNOPSIS
			Adds Stats to a group of resources.
		.DESCRIPTION
			It is recommended (though not required) to use this API when the resource was created using the API POST /api/resources/{id}/adapters/{adapterInstanceId}.
			Otherwise an additional adapter instance might be created. 
		.EXAMPLE
			addStatstoResources -resthost $resthost -token $token -body $body
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER body
			The body payload that contains the details of the IDs, metrics and values to add
		.PARAMETER contenttype
			Analogous to the header parameter 'Content-Type' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
			Added in version 0.4
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][ValidateSet('xml','json')]$contenttype = 'json',
		[parameter(Mandatory=$true)]$body
		)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources/stats'
		if ($token -ne $null) {
			$addStatsforResourcesresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -token $token -body $body -contenttype $contenttype
		}
		else {
			$addStatsforResourcesresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -credentials $credentials -body $body -contenttype $contenttype
		}	
		return $addStatsforResourcesresponse
	}
}



function createResourceUsingAdapterKind {
	<#
		.SYNOPSIS
			Creates a new Resource in the system associated with an existing adapter instance.
		.DESCRIPTION
			The API will create the missing Adapter Kind and Resource Kind contained within the ResourceKey of the Resource if they do not exist.
			The API will return an error if the adapter instance specified does not exist.
		.EXAMPLE
			createResourceUsingAdapterKind -resthost $resthost -token $token -body $body -adapterID $adapterid
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER body
			Body content that describes the new resource being created
		.PARAMETER adapterID
			The ID of the adapter instance on which the new resource should be created
		.PARAMETER contenttype
			Analogous to the header parameter 'Content-Type' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.	
		.NOTES
			Added in version 0.2
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][ValidateSet('xml','json')]$contenttype = 'json',
		[parameter(Mandatory=$true)]$body,
		[parameter(Mandatory=$true)]$adapterID
		)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources/adapters/' + $adapterID

		if ($token -ne $null) {
			$createResourceUsingAdapterKindresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -token $token -contenttype $contenttype -body $body
		}
		else {
			$createResourceUsingAdapterKindresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -credentials $credentials -contenttype $contenttype -body $body
		}	
		return $createResourceUsingAdapterKindresponse
	}
}
function deleteRelationship {
	<#
		.SYNOPSIS
			Deletes (removes) a Resource as RelationshipType of a specific Resource.
		.DESCRIPTION
			Deletes (removes) a Resource as RelationshipType of a specific Resource.
			If either of the Resources that are part of the path parameters are invalid/non-existent then the API returns a 404 error.
			NOTE: Removing a relationship is not synchronous. As a result, the delete operation may not happen immediately.
			It is recommended to query the relationships of the specific Resource back to ensure that the operation was indeed successful. 
		.EXAMPLE
			deleteRelationship -resthost $resthost -token $token -objectid 8014d795-18e4-42d5-a264-89f6b47f4d8e -relatedid 6434d795-1bc4-42d5-a264-89f6b47f4d8e -relationship children
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			The vROps ID of the object to delete the relationship from
		.PARAMETER relatedid
			The vROps ID of the related object
		.PARAMETER relationship
			The vROps relationship between the primary object (objectid) and secondary object (relatedid)
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)][String]$objectid,
		[parameter(Mandatory=$true)][String]$relatedid,
		[parameter(Mandatory=$true)][ValidateSet('children','parent')][String]$relationship
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources/' + $objectid + '/relationships/' + $relationship + '/' + $relatedid	
		if ($token -ne $null) {
			$deleteRelationshipresponse = invokeRestMethod -method 'DELETE' -url $url -accept $accept -token $token
		}
		else {
			$deleteRelationshipresponse = invokeRestMethod -method 'DELETE' -url $url -accept $accept -credentials $credentials
		}	
		return $deleteRelationshipresponse
	}
}
function deleteResource {
	<#
		.SYNOPSIS
			Deletes a Resource with the given identifier. 
		.DESCRIPTION
			Deletes a Resource with the given identifier.
			NOTE: Deletion of a Resource is not synchronous. As a result, the delete operation may not happen immediately.
			It is recommended to query back the system with the resource identifier and ensure that the system returns a 404 error. 
		.EXAMPLE
			deleteResource -resthost $resthost -token $token -objectid 80133295-18e4-42d5-a264-8af6b47f4d8e
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			The vROps ID of the resource to delete
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][ValidateSet('xml','json')]$contenttype = 'json',
		[parameter(Mandatory=$true)][String]$objectid
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources/' + $objectid
		if ($token -ne $null) {
			$deleteResourceresponse = invokeRestMethod -method 'DELETE' -url $url -accept $accept -token $token -contenttype $contenttype
		}
		else {
			$deleteResourceresponse = invokeRestMethod -method 'DELETE' -url $url -accept $accept -credentials $credentials -contenttype $contenttype
		}	
		return $deleteResourceresponse
	}
}

function getLatestStatsofResources {
	<#
		.SYNOPSIS
			Gets Latest stats of resources using the query spec that is specified.
		.DESCRIPTION
			Gets Latest stats of resources using the query spec that is specified.
		.EXAMPLE
			getLatestStatsofResources -resthost $resthost -token $token -objectid 80133295-18e4-42d5-a264-8af6b47f4d8e -statkey 'PowervROPsTesting|TestStat'
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			The vROps ID of the object for which the latest stats should be returned
		.PARAMETER statkey
			If supplied the response will be limited to the vROps statkey supplied
		.NOTES
			Added in version 0.2
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)][string]$objectid,	
		[parameter(Mandatory=$true)]$statkey
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources/stats/latest?resourceId=' + $objectid + '&statKey=' + $statkey
		if ($token -ne $null) {
			$getLatestStatsofResourcesresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getLatestStatsofResourcesresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}
		return $getLatestStatsofResourcesresponse
	}
}

function getLatestPropertiesofResources {
	<#
		.SYNOPSIS
			Gets Latest properties of resources using the query spec that is specified.
		.DESCRIPTION
			Gets Latest properties of resources using the query spec that is specified.
		.EXAMPLE
			getLatestPropertiesofResources -resthost $resthost -token $token -objectid 80133295-18e4-42d5-a264-8af6b47f4d8e -statkey 'PowervROPsTesting|TestStat'
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			The vROps ID of the object for which the latest stats should be returned
		.PARAMETER statkey
			If supplied the response will be limited to the vROps statkey supplied
		.NOTES

		#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)][string]$objectid,	
		[parameter(Mandatory=$true)]$statkey
	)
	Process {

		$body = @{
			'resourceIds' = @($objectid)
			'propertyKeys' = @($statkey)
			'others' = @()
			'otherAttributes' = @()
			} | ConvertTo-Json

			$url = 'https://' + $resthost + '/suite-api/api/resources/properties/latest/query'
		if ($token -ne $null) {
			$getLatestPropertiesofResourcesresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -token $token -body $body
		}
		else {
			$getLatestPropertiesofResourcesresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -credentials $credentials -body $body
		}
		return $getLatestPropertiesofResourcesresponse
	}
}

function getLatestStatsofResources {
	<#
		.SYNOPSIS
			Gets Latest stats of resources using the query spec that is specified.
		.DESCRIPTION
			Gets Latest stats of resources using the query spec that is specified.
		.EXAMPLE
			getLatestPropertiesofResources -resthost $resthost -token $token -objectid 80133295-18e4-42d5-a264-8af6b47f4d8e -statkey 'PowervROPsTesting|TestStat'
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			The vROps ID of the object for which the latest stats should be returned
		.PARAMETER statkey
			If supplied the response will be limited to the vROps statkey supplied
		.NOTES

		#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)][string]$objectid,	
		[parameter(Mandatory=$true)]$statkey
	)
	Process {

		$body = @{
			'resourceId' = @($objectid)
			'statKey' = @($statkey)
			'metrics' = 'false'
  			'currentOnly' = 'false'
  			'maxSamples' = 1
			} | ConvertTo-Json

			$url = 'https://' + $resthost + '/suite-api/api/resources/stats/latest/query'
		if ($token -ne $null) {
			$getLatestStatsofResourcesresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -token $token -body $body
		}
		else {
			$getLatestStatsofResourcesresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -credentials $credentials -body $body
		}
		return $getLatestStatsofResourcesresponse
	}
}

function getRelationship {	
	<#
		.SYNOPSIS
			Gets the related resources of a particular Relationship Type for a Resource.
		.DESCRIPTION
			Gets the related resources of a particular Relationship Type for a Resource.
		.EXAMPLE
			getRelationship -resthost $resthost -token $token -objectid 80133295-18e4-42d5-a264-8af6b47f4d8e -relationship children
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			vROps ID of the object to query
		.PARAMETER relationship
			Relationship type to query, valid values are 'parent' and 'children'.
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)][string]$objectid,	
		[parameter(Mandatory=$true)][ValidateSet('children','parents')][String]$relationship
	)	
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources/' + $objectid + '/relationships/' + $relationship
		if ($token -ne $null) {
			$getRelationshipresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getRelationshipresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getRelationshipresponse
	}
}
function getResource {
	<#
		.SYNOPSIS
			Gets the Resource for the specified identifier.
		.DESCRIPTION
			Gets the Resource for the specified identifier.
		.EXAMPLE
			getResource -resthost $resthost -token $token -objectid 3014d793-18e4-42d5-a264-66f6b47f4d8e
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			The vROps ID of the object to query.
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)][string]$objectid	
		)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources/' + $objectid
		if ($token -ne $null) {
			$getResourceresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getResourceresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getResourceresponse
	}
}
function getResourceProperties {
	<#
		.SYNOPSIS
			Get all the properties for the specified Resource.
		.DESCRIPTION
			Get all the properties for the specified Resource.
		.EXAMPLE
			getResourceProperties -resthost $resthost -token $token -objectid 80133295-18e4-42d5-a264-8af6b47f4d8e
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			vROps ID of the object to query
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][string]$objectid	
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources/' + $objectid + '/properties'
		if ($token -ne $null) {
			$getResourcePropertiesresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getResourcePropertiesresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getResourcePropertiesresponse
	}
}
function getResources { # Need additional tests for pagesize and pagenumber
	<#
		.SYNOPSIS
			Gets a listing of resources based on the query spec specified.
		.DESCRIPTION
			Currently the function only permits querying for resources via the following filters:
				Name
				ResourceKind
				ObjectId
		.EXAMPLE
			getResources -resthost $resthost -token $token -name NameofObject
		.EXAMPLE
			getResources -resthost $resthost -token $token -resourceKind 'ClusterComputeResource'
		.EXAMPLE
			getResources -resthost $resthost -token $token -objectid 8014d795-18e4-42d5-a264-89f6b47f4d8e
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER name
			The name of the vROps object to query.
		.PARAMETER resourceKind
			The resourceKind of the objects to query. This will return multiple objects. Examples of resourceKind are:
				ClusterComputeResource
				VirtualMachine
		.PARAMETER objectid
			The vROps ID of the object to query.
		.PARAMETER pagesize
			The number of records to return as part of the query
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][String]$name,
		[parameter(Mandatory=$false)][String]$resourceKind,
		[parameter(Mandatory=$false)][Int]$pagesize = 1000,
		[parameter(Mandatory=$false)][Int]$pagetoview = 0,
		[parameter(Mandatory=$false)][string]$objectid	
		)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources?'
		if ($name -ne "") {
			$url += 'name=' + $name + '&'
		}
		if ($resourceKind -ne "") {
			$url += 'resourceKind=' + $resourceKind + '&'
		}
		if ($objectid -ne "") {
			$url += 'resourceId=' + $objectid + '&'
		}
		$url = $url.Substring(0,$url.Length-1)
		$url += '&pageSize=' + $pagesize + '&page=' + $pagetoview
		
		if ($token -ne $null) {
			$getResourcesresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getResourcesresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}
		return $getResourcesresponse
	}
}

function getStatsForResources { # No test, and no documentation
	<#
		.SYNOPSIS
			TBC
		.DESCRIPTION
			TBC
		.EXAMPLE
			TBC
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			TBC
		.NOTES
			Added in version 0.4.0
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$true)]$body,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources/stats/query'
		if ($token -ne $null) {
			$getStatsForResourcesresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -token $token -body $body
		}
		else {
			$getStatsForResourcesresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -credentials $credentials -body $body
		}	
		return $getStatsForResourcesresponse
	}
}
function markResourceAsBeingMaintained { # only single test for manual mode and documentation incomplete. Need tests for duration and end
	<#
		.SYNOPSIS
			Put the specific Resource in Maintenance.
		.DESCRIPTION
			The Resource can end up in two maintenance states - MAINTAINED OR MAINTAINED_MANUAL - depending upon the inputs specified.
				If duration/end time is specified, the resource will be placed in MAINTAINED state and after the duration/end time expires, the resource state is automatically set to the state it was in before entering the maintenance window.
				If duration/end time is not specified, the resource will be placed in MAINTAINED_MANUAL state. Callers have to execute DELETE /suite-api/api/resources/{id}/maintained API to set the Resource back to whatever state it was in.
				If both duration and end time are specified, end time takes preference over duration. 
		.EXAMPLE
			TBC
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			The vROps ID of the object to query.
		.PARAMETER duration
			The number of minutes that the object should be put into maintenance mode
		.PARAMTER end
			The date/time in Unix epoch format (number of milliseconds since 01/01/1970 00:00:00)
			Use the getTimeSinceEpoch function and pass a date to the function to retrieve the required value
		.NOTES
			Added in version 0.3.5
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)][string]$objectid,
		[parameter(Mandatory=$false)][int]$duration,
		[parameter(Mandatory=$false)][string]$end
		)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources/' + $objectid + '/maintained'
		
		if ($end -ne $null) {
			$url += ('?end=' + $end)
		}
		elseif ($duration -ne $null) {
			$url += ('?duration=' + $duration)
		}
		
		if ($token -ne $null) {
			$markResourceAsBeingMaintainedresponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -token $token
		}
		else {
			$markResourceAsBeingMaintainedresponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -credentials $credentials
		}	
		return $markResourceAsBeingMaintainedresponse
	}
}
function setRelationship {
	<#
		.SYNOPSIS
			Set (Replace) Resources as RelationshipType of a specific Resource.
		.DESCRIPTION
			This API exposes replace semantics. Therefore, all the existing relationships of the specified
			relationshipType will be removed and replaced with the resources specified as part of the request body. 
		.EXAMPLE
			setRelationship -resthost $resthost -token $token -objectid 80133295-18e4-42d5-a264-8af6b47f4d8e -relationship children -body $body
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER contenttype
			Analogous to the header parameter 'Content-Type' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER body
			Body payload used to set the relationship
		.PARAMETER objectid
			The vROps ID of the object to set the relationship on
		.PARAMETER relationship
			The relationship type to set between the two objects. Valid values are parent or children.
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)]$body,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')]$contenttype = 'json',
		[parameter(Mandatory=$true)][String]$objectid,
		[parameter(Mandatory=$true)][ValidateSet('children','parent')][String]$relationship
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources/' + $objectid + '/relationships/' + $relationship
		if ($token -ne $null) {
			$setRelationshipresponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -token $token -body $body -contenttype $contenttype
		}
		else {
			$setRelationshipresponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -credentials $credentials -body $body -contenttype $contenttype
		}	
		return $setRelationshipresponse	
	}
}
function startMonitoringResource {
	<#
		.SYNOPSIS
			Inform one or more or all Adapters to start monitoring this Resource.
		.DESCRIPTION
			Inform one or more or all Adapters to start monitoring this Resource.
		.EXAMPLE
			startMonitoringResource -resthost $resthost -token $token -objectid 8014d795-18e4-42d5-a264-89f6b47f4d8e
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			The vROps ID of the object to start monitoring
		.NOTES
			Added in version 0.2
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)][String]$objectid
		)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources/' + $objectid + '/monitoringstate/start'
		if ($token -ne $null) {
			$startMonitoringResourceresponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -token $token
		}
		else {
			$startMonitoringResourceresponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -credentials $credentials
		}	
		return $startMonitoringResourceresponse
	}
}
function stopMonitoringResource {
	<#
		.SYNOPSIS
			Inform one or more or all Adapters to stop monitoring this Resource.
		.DESCRIPTION
			Inform one or more or all Adapters to stop monitoring this Resource.
		.EXAMPLE
			stopMonitoringResource -resthost $resthost -token $token -objectid 8014d795-18e4-42d5-a264-89f6b47f4d8e
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			The vROps ID of the object to stop monitoring
		.NOTES
			Added in version 0.2
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)][String]$objectid
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources/' + $objectid + '/monitoringstate/stop'	
		if ($token -ne $null) {
			$stopMonitoringResourceresponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -token $token
		}
		else {
			$stopMonitoringResourceresponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -credentials $credentials
		}	
		return $stopMonitoringResourceresponse
	}
}
function unmarkResourceAsBeingMaintained {
	<#
		.SYNOPSIS
			Bring the Resource out of Maintenance manually.
		.DESCRIPTION
			Bring the Resource out of Maintenance manually.
		.EXAMPLE
			unmarkResourceAsBeingMaintained -resthost $resthost -token $token -objectid $resourceid
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			The vROps ID of the object to query.
		.NOTES
			Added in version 0.3.5
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)][string]$objectid
		)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/resources/' + $objectid + '/maintained'
		if ($token -ne $null) {
			$unmarkResourceAsBeingMaintainedresponse = invokeRestMethod -method 'DELETE' -url $url -accept $accept -token $token
		}
		else {
			$unmarkResourceAsBeingMaintainedresponse = invokeRestMethod -method 'DELETE' -url $url -accept $accept -credentials $credentials
		}	
		return $unmarkResourceAsBeingMaintainedresponse
	}
}		

# /api/solutions --------------------------------------------------------------------------------------------------------------

# /api/supermetrics -----------------------------------------------------------------------------------------------------------

function getSuperMetric {
	<#
		.SYNOPSIS
			Get a SuperMetric with the given id.
		.DESCRIPTION
			Get a SuperMetric with the given id.
		.EXAMPLE
			getSuperMetric -resthost $resthost -token $token -supermetricid 3014d718-18e4-42d5-b264-66f6b4ff4d8e
		.EXAMPLE
			getSuperMetric -resthost $resthost -credentials $credentials -supermetricid 3014d718-18e4-42d5-b264-66f6b4ff4d8e
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER supermetricid
			ID of the supermetric, can be obtained either manually via the UI or via the getSuperMetrics
			cmdlet
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$false)][string]$supermetricid	
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/supermetrics/' + $supermetricid
		if ($token -ne $null) {
			$getSuperMetricresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getSuperMetricresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getSuperMetricresponse	
	}
}
function getSuperMetrics {
	<#
		.SYNOPSIS
			Gets a collection of SuperMetrics based on search parameters.
		.DESCRIPTION
			Gets a collection of SuperMetrics based on search parameters. Possible methods for filltering are:
			name
			supermetricid (not yet implemented)
		.EXAMPLE
			getSuperMetrics -resthost $resthost -token $token
		.EXAMPLE
			getSuperMetrics -resthost $resthost -credentials $credentials -name MyFirstSupermetric
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER name
			The name of the supermetric to query
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$false)][string]$name	
		)
	Process {
		if (($name -eq $null) -or ($name -eq "")) {
			$url = 'https://' + $resthost + '/suite-api/api/supermetrics'
		}
		else {
			$url = 'https://' + $resthost + '/suite-api/api/supermetrics?name=' + $name
		}		
		if ($token -ne $null) {
			if ($ignoressl) {
				$getSuperMetricsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token -ignoressl
			}
			else {
				$getSuperMetricsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
			}
		}
		else {
			if ($ignoressl) {
				$getSuperMetricsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials -ignoressl
			}
			else {
				$getSuperMetricsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
			}	
		}	
		return $getSuperMetricsresponse		
	}
}

# /api/symptomdefinitions -----------------------------------------------------------------------------------------------------
function getSymptomDefinitions {
	<#
		.SYNOPSIS
			Returns a collection of Symptom Definitions matching the search criteria specified.
		.DESCRIPTION
			Returns a collection of Symptom Definitions matching the search criteria specified.
		.EXAMPLE
			getSymptomDefinitions -resthost $resthost -token $token -resourcekind $resourcekind
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER alertdefinitionid
			The identifier(s) of the Alert Definitions to search for.
			Do not specify adapterKind or resourceKind if searching by the identifier
		.PARAMETER adapterkind
			Adapter Kind key of the Alert Definitions to search for
		.PARAMETER resourcekind
			Resource Kind key of the Alert Definitions to search for
		.PARAMETER symptomdefinitionid
			The identifier(s) of the symptom definitions to search for
		.NOTES
			
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][String]$symptomdefinitionid,
		[parameter(Mandatory=$false)][String]$adapterkind,
		[parameter(Mandatory=$false)][switch]$ignoressl,
		[parameter(Mandatory=$false)][String]$resourcekind
		)
	Process {
		if (($symptomdefinitionid -ne "") -and (($adapterkind -ne "") -or ($resourcekind -ne ""))) {
			write-host "symptomdefinition" $alertdefintion
			write-host "WARNING - When specifying an symptom definition ID, an adapterkind or resourcekind are not necessary"
			return
		}
		else {
			if ($symptomdefinitionid -ne "") {
				$url = 'https://' + $resthost + '/suite-api/api/symptomdefinitions/?id=' + $symptomdefinitionid
			}
			elseif ($adapterkind -ne "") {
				if ($resourcekind -ne "") {
					$url = 'https://' + $resthost + '/suite-api/api/symptomdefinitions/?adapterKind=' + $adapterkind + '&resourceKind=' + $resourcekind 
				}
				else {
					$url = 'https://' + $resthost + '/suite-api/api/symptomdefinitions/?adapterKind=' + $adapterkind
				}
			}
			elseif ($resourcekind -ne "") {
				$url = 'https://' + $resthost + '/suite-api/api/symptomdefinitions/?resourceKind=' + $resourcekind 
			}
			else {
				$url = 'https://' + $resthost + '/suite-api/api/symptomdefinitions'
			}
			if ($token -ne $null) {
				$getSymptomDefinitionsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
			}
			else {
				$getSymptomDefinitionsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
			}	
			return $getSymptomDefinitionsresponse
		}
	}
}

# /api/symptoms ---------------------------------------------------------------------------------------------------------------

# /api/tasks ------------------------------------------------------------------------------------------------------------------

# /api/versions ---------------------------------------------------------------------------------------------------------------

function getVersions {
		<#
		.SYNOPSIS
			Gets the current version of the Service.
		.DESCRIPTION
			Gets the current version of the Service.
		.EXAMPLE
			getVersions -credentials $creds -resthost $resthost
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/api/versions/current/'	
		if ($token -ne $null) {
			$getVersionsupresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token
		}
		else {
			$getVersionsupresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials
		}	
		return $getVersionsupresponse	
	}

}

# /internal/resources ---------------------------------------------------------------------------------------------------------

function getCustomGroup {
	<#
		.SYNOPSIS
			Retrieve a custom group definition using its identifier.
		.DESCRIPTION
			Retrieve a custom group definition using its identifier.
		.EXAMPLE
			getCustomGroup -resthost $resthost -token $token -objectid $customgroupid
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			The vROps ID of the custom group to query
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)][string]$objectid		
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/internal/resources/groups/' + $objectid	
		if ($token -ne $null) {
			$getcustomgroupresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token -useinternalapi $true
		}
		else {
			$getcustomgroupresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials -useinternalapi $true
		}	
		return $getcustomgroupresponse	
	}
}
function getCustomGroups {
	<#
		.SYNOPSIS
			Query for custom groups based on groupId and whether they are dynamic or static.
		.DESCRIPTION
			Query for custom groups based on groupId and whether they are dynamic or static.
		.EXAMPLE
			getCustomGroups -resthost $resthost -token $token
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json'
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/internal/resources/groups'
		if ($token -ne $null) {
			$getCustomGroupsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token -useinternalapi $true
		}
		else {
			$getCustomGroupsresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials -useinternalapi $true
		}	
		return $getCustomGroupsresponse
	}
}
function createCustomGroup {
	<#
		.SYNOPSIS
			Create a new custom group definition
		.DESCRIPTION
			The new group can be created with one of the following definitions:
				Metric Key
				Property Key
				Relationship Condition
				Resource Name
		.EXAMPLE
			createCustomGroup -resthost $resthost -token $token -body $body
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER body
			Body content to be used when creating the custom group
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][ValidateSet('xml','json')]$contenttype = 'json',
		[parameter(Mandatory=$true)][String]$body
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/internal/resources/groups'
		if ($token -ne $null) {
			$createCustomGroupresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -token $token -useinternalapi $true -contenttype $contenttype -body $body
		}
		else {
			$createCustomGroupresponse = invokeRestMethod -method 'POST' -url $url -accept $accept -credentials $credentials -useinternalapi $true -contenttype $contenttype -body $body
		}	
		return $createCustomGroupresponse
	}
}
function getMembersOfGroup {
	<#
		.SYNOPSIS
			Get the list of (computed/static) members of the group. 
		.DESCRIPTION
			Get the list of (computed/static) members of the group. 
		.EXAMPLE
			getMembersOfGroup -resthost $resthost -credentials $credentials -objectid $customgroupID
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			The vROps ID of the group to get the members of
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)][String]$objectid
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/internal/resources/groups/' + $objectid + '/members'
		if ($token -ne $null) {
			$getMembersOfGroupresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -token $token -useinternalapi $true
		}
		else {
			$getMembersOfGroupresponse = invokeRestMethod -method 'GET' -url $url -accept $accept -credentials $credentials -useinternalapi $true
		}	
		return $getMembersOfGroupresponse
	}
}
function deleteCustomGroup {
	<#
		.SYNOPSIS
			Delete a custom group. 
		.DESCRIPTION
			Delete a custom group. 
		.EXAMPLE
			deleteCustomGroup -resthost $resthost -token $token -objectid $customgroupID
		.EXAMPLE
			deleteCustomGroup -resthost $resthost -credentials $credentials -objectid $customgroupID
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			Analogous to the header parameter 'Accept' used in REST calls, valid values are xml or json.
			However, the module has only been tested against json.
		.PARAMETER objectid
			The vROps ID of the custom group to delete
		.NOTES
			Added in version 0.1
	#>
	Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$true)][String]$objectid
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/internal/resources/groups/' + $objectid

		if ($token -ne $null) {
			$deleteCustomGroupresponse = invokeRestMethod -method 'DELETE' -url $url -accept $accept -token $token -useinternalapi $true
		}
		else {
			$deleteCustomGroupresponse = invokeRestMethod -method 'DELETE' -url $url -accept $accept -credentials $credentials -useinternalapi $true
		}	
		return $deleteCustomGroupresponse
	}
}

function modifyCustomGroup {
	<#
		.SYNOPSIS
			Modified a custom group. 
		.DESCRIPTION
			Modified a custom group. 
		.EXAMPLE
			TBC
		.EXAMPLE
			TBC
		.PARAMETER credentials
			A set of PS Credentials used to authenticate against the vROps endpoint.
		.PARAMETER token
			If token based authentication is being used (as opposed to credential based authentication)
			then the token returned from the acquireToken cmdlet should be used.
		.PARAMETER resthost
			FQDN of the vROps instance or cluster to operate against.
		.PARAMETER accept
			TBC
		.PARAMETER objectid
			The vROps ID of the custom group to delete
		.NOTES
			Added in version 0.4.0
	#>
Param	(
		[parameter(Mandatory=$false)]$credentials,
		[parameter(Mandatory=$false)]$token,
		[parameter(Mandatory=$true)][String]$resthost,
		[parameter(Mandatory=$false)][ValidateSet('xml','json')][string]$accept = 'json',
		[parameter(Mandatory=$false)][ValidateSet('xml','json')]$contenttype = 'json',
		[parameter(Mandatory=$true)][String]$body
	)
	Process {
		$url = 'https://' + $resthost + '/suite-api/internal/resources/groups'
		if ($token -ne $null) {
			$modifyCustomGroupresponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -token $token -useinternalapi $true -contenttype $contenttype -body $body
		}
		else {
			$modifyCustomGroupresponse = invokeRestMethod -method 'PUT' -url $url -accept $accept -credentials $credentials -useinternalapi $true -contenttype $contenttype -body $body
		}	
		return $modifyCustomGroupresponse
}
}

export-modulemember -function 'get*'
export-modulemember -function 'Create*'
export-modulemember -function 'add*'
export-modulemember -function 'set*'
export-modulemember -function 'delete*'
export-modulemember -function 'download*'
export-modulemember -function 'start*'
export-modulemember -function 'stop*'
export-modulemember -function 'acquire*'
export-modulemember -function 'enumerate*'
export-modulemember -function 'update*'
export-modulemember -function 'mark*'
export-modulemember -function 'unmark*'
export-modulemember -function 'modify*'
export-modulemember -function 'convert*'