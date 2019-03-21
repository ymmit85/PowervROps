# PowervROPs

## Overview
PowervROps is a module written for PowerShell that can be used to access various elements of the vRealize Operations Manager API via PowerShell functions.
Feature requests are welcome via the issues tracker on the projects page on GitHub.
Currently development has been completed against vROPs 6.7 & 7.0 & Powershell 5.1.

##Latest Updates
The following functions have been added in version 0.5.0, most have been tested but there are a couple that still require modification to allow additonal parameter inputs.

- getAdapterInstances
- setAdapterInMaintenance
- setAdapterEndMaintenance
- setAdapterStartMonitoring
- setAdapterStopMonitoring
- releaseToken
- getAuthSources
- getAuthSource
- getRoles
- getUsers
- getUserGroups
- getCollectorGroups
- getServicesInfo
- getServiceInfo 
- getPakList
- getPakStatus
- getPakDistributionStatus
- getNotificationRules
- addNotificationRule
- deleteReport
- getReports
- getSymptomDefinitions
- addCollecotrToGroup
- deleteCollectorFromGroup
- getCollectorGroup

## Support
This module is not supported by VMware, and comes with no warranties express or implied. Please test and validate its functionality before using this product in a production environment. The module exposes elements of both the public and internal APIs, the latter of these may not be included in future releases of vROps so functionality of this module may be reduced at a later date.
Please note that PowervRops is a work in progress, both in terms of the functions that are available but also some of the filtering methods that can be used via each function. There is an expectation that more functions will be made available, although the likelylihood is that this will not include the API in its entirety.

No testing has been done against PowerShell core at this time and there are a number of known issues (see issues tracker).