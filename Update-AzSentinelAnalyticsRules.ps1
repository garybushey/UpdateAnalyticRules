#requires -version 6.2
<#
    .SYNOPSIS
        This command will update all the Analytic rules that come from a rule template that has been updated.
    .DESCRIPTION
        This command will update all the Analytic rules that come from a rule template that has been updated.
    .PARAMETER WorkSpaceName
        Enter the Log Analytics workspace name, this is a required parameter
    .PARAMETER ResourceGroupName
        Enter the Log Analytics workspace name, this is a required parameter
    .NOTES
        AUTHOR: Gary Bushey
        LASTEDIT: 7 July 2022
    .EXAMPLE
        Update-AzSentinelAnalyticsRules -WorkspaceName "workspacename" -ResourceGroupName "rgname"
        In this example you will update all the rules that come from a rule template that has been updated.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$WorkSpaceName,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName

)

Function Update-AzSentinelAnalyticsRules ($workspaceName, $resourceGroupName) {
    #Set up the authentication header
    $context = Get-AzContext
    $azureProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
    $profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($azureProfile)
    $token = $profileClient.AcquireAccessToken($context.Subscription.TenantId)
    $authHeader = @{
        'Content-Type'  = 'application/json' 
        'Authorization' = 'Bearer ' + $token.AccessToken 
    }
    
    $SubscriptionId = $context.Subscription.Id

    #Load all the rule templates so we can copy the information as needed.
    $url = "https://management.azure.com/subscriptions/$($subscriptionId)/resourceGroups/$($ResourceGroupName)/providers/Microsoft.OperationalInsights/workspaces/$($WorkspaceName)/providers/Microsoft.SecurityInsights/alertruletemplates?api-version=2021-10-01-preview"
    $ruleTemplates = (Invoke-RestMethod -Method "Get" -Uri $url -Headers $authHeader ).value

    #Load all the rules that habve been enabled
    $url = "https://management.azure.com/subscriptions/$($subscriptionId)/resourceGroups/$($ResourceGroupName)/providers/Microsoft.OperationalInsights/workspaces/$($WorkspaceName)/providers/Microsoft.SecurityInsights/alertrules?api-version=2021-10-01-preview"
    $rules = (Invoke-RestMethod -Method "Get" -Uri $url -Headers $authHeader ).value


    #Iterate through all rules
    foreach ($rule in $rules) {
        #Does this rule have a template version
        if ($null -ne $rule.properties.templateVersion) {
            #Is the version number lower than the version number from the template?
            $templateID = $rule.properties.alertRuleTemplateName
            $template = $ruleTemplates | Where-Object { $_.name -eq $templateID }
            $templateVersion = $template.properties.version
            #We are comparing using not equal for the comparison since the only way the rule version number will change is during an update, unless it is updated
            #via the REST API in which case, buyer beware!
            if ($rule.properties.templateVersion -ne $templateVersion) {
                $displayName = $rule.properties.displayName
                #Update those fields that the rule template would have.  These are NOT all the fields in the rule itself
                $body = @{
                    "kind"       = "Scheduled"
                    "properties" = @{
                        "displayName"           = $template.properties.displayName
                        "description"           = $template.properties.description
                        "severity"              = $template.properties.severity
                        "tactics"               = $template.properties.tactics
                        "techniques"            = $template.properties.techniques
                        "query"                 = $template.properties.query
                        "queryFrequency"        = $template.properties.queryFrequency
                        "queryPeriod"           = $template.properties.queryPeriod
                        "triggerOperator"       = $template.properties.triggerOperator
                        "triggerThreshold"      = $template.properties.triggerThreshold
                        "entityMappings"        = $template.properties.entityMappings
                        "fieldMappings"         = $template.properties.fieldMappings
                        "enabled"               = $rule.properties.enabled
                        "eventGroupingSettings" = $rule.properties.eventGroupingSettings
                        "alertRuleTemplateName" = $rule.properties.alertRuleTemplateName
                        "suppressionDuration"   = $rule.properties.suppressionDuration
                        "suppressionEnabled"    = $rule.properties.suppressionEnabled
                        "incidentConfiguration" = $rule.properties.incidentConfiguration
                    }
                }
                $guid = $rule.name

                #Create the URI we need to update the alert.
                $uri = "https://management.azure.com/subscriptions/$($subscriptionId)/resourceGroups/$($resourceGroupName)/providers/Microsoft.OperationalInsights/workspaces/$($workspaceName)/providers/Microsoft.SecurityInsights/alertRules/$($guid)?api-version=2021-10-01-preview"
                try {
                    Write-Host "Attempting to update rule $($displayName)"
                    $verdict = Invoke-RestMethod -Uri $uri -Method Put -Headers $authHeader -Body ($body | ConvertTo-Json -EnumsAsStrings -Depth 5)
                    Write-Output -ForegroundColor Green "Succeeded"
                }
                catch {
                    #Output any error
                    $errorReturn = $_
                    Write-Error $errorReturn
                }
                #This pauses for 5 second so that we don't overload the workspace.
                Start-Sleep -Seconds 5
            }
        }
    }
}
Write-Host -ForegroundColor Red "Warning!  By running this script you will update ALL analytic rules that have a template with changes in it"
Write-Host -ForegroundColor Red "You will not be able to see the changes being made."
$answer = Read-Host -Prompt "Type in 'Yes' to continue"

if ($answer -eq 'Yes')
{
    Update-AzSentinelAnalyticsRules $WorkSpaceName $ResourceGroupName
}

