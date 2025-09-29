# Handle module conflicts - ensure clean slate for Beta modules
<#
.SYNOPSIS
    PowerShell implementation of Agent ID management using Microsoft Graph PowerShell SDK

.DESCRIPTION
    This script provides functions to create and manage Agent IDs using Microsoft Graph PowerShell SDK.
    It implements the complete workflow for creating agent blueprints, agent identities, agentic users,
    and handling various authentication scenarios using proper Microsoft Graph cmdlets.

.NOTES
    Author: Anton Staykov
    Date: September 29, 2025
    Requires: Microsoft Graph PowerShell SDK modules
#>

# Environment Variables - Update these with your tenant-specific values
$script:TenantId = "<YOUR-TENANT-ID>"
$script:MSGraphObjectId = "<OBJECT ID OF Microsoft Graph in your tenant>"
$script:ClientId = "<your management app registration client_id (application id) >"
$script:ClientSecret = "<your management app registration client secret>"
$script:AIClientId = "<your ai app registration client id (appliction id)>"
$script:AIClientSecret = "<your ai app registration client secret>"
# Note: Adjust these names in accordance to your tenant 
$script:AgentUserUPN = "asAgentIdBPUserG@YOUR-TENANT.onmicrosoft.com"
$script:AgentUserMailNickName = "asAgentIdBPUserG"

# Dynamic variables populated during execution
$script:AgentBlueprintAppId = $null
$script:AgentBlueprintAppObjectId = $null
$script:AgentBlueprintClientSecret = $null
$script:AgentIdentityClientId = $null
$script:AgentIdentityUserId = $null
$script:Scope = $null

# Authentication state tracking
$script:IsConnectedAsHighPriv = $false
$script:IsConnectedAsBlueprint = $false

# Helper function to connect to Microsoft Graph with high privilege credentials
function Connect-GraphAsHighPrivilege {
    if ($script:IsConnectedAsHighPriv) {
        return
    }
    
    try {
        $secureClientSecret = ConvertTo-SecureString $script:ClientSecret -AsPlainText -Force
        $clientSecretCredential = New-Object System.Management.Automation.PSCredential($script:ClientId, $secureClientSecret)
        
        Connect-MgGraph -ClientSecretCredential $clientSecretCredential -TenantId $script:TenantId -NoWelcome
        $script:IsConnectedAsHighPriv = $true
        Write-Host "Connected to Microsoft Graph Beta endpoint with high privilege credentials" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph Beta endpoint with high privilege credentials: $($_.Exception.Message)"
        throw
    }
}

# Helper function to connect to Microsoft Graph with Agent Blueprint credentials
function Connect-GraphAsBlueprint {
    if ($script:IsConnectedAsBlueprint) {
        return
    }
    
    if (-not $script:AgentBlueprintAppId -or -not $script:AgentBlueprintClientSecret) {
        throw "Agent Blueprint credentials not available. Create blueprint first."
    }
    
    try {
        # Disconnect if already connected with different credentials
        if (Get-MgContext) {
            Disconnect-MgGraph
            $script:IsConnectedAsHighPriv = $false
        }
        
        $secureClientSecret = ConvertTo-SecureString $script:AgentBlueprintClientSecret -AsPlainText -Force
        $clientSecretCredential = New-Object System.Management.Automation.PSCredential($script:AgentBlueprintAppId, $secureClientSecret)
        
        Connect-MgGraph -ClientSecretCredential $clientSecretCredential -TenantId $script:TenantId -NoWelcome
        $script:IsConnectedAsBlueprint = $true
        Write-Host "Connected to Microsoft Graph Beta endpoint with Agent Blueprint credentials" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph Beta endpoint with Agent Blueprint credentials: $($_.Exception.Message)"
        throw
    }
}



<#
.SYNOPSIS
    Creates Agent Blueprint with high privilege credentials
    
.DESCRIPTION
    Implements the "01 Create Agent Blueprint" folder from the Insomnia collection.
    Creates the agent identity blueprint, service principal, exposes API, and adds client secret.
#>
function New-AgentBlueprint {
    [CmdletBinding()]
    param()
    
    Write-Host "Creating Agent Blueprint..." -ForegroundColor Green
    
    # Connect with high privilege credentials
    Connect-GraphAsHighPrivilege
    
    try {
        # 01.01 Create Agent Id Blueprint
        Write-Host "Creating Agent Identity Blueprint..."
        
        # Use New-MgApplication for creating the Agent Identity Blueprint
        $blueprintParams = @{
            DisplayName = "[ast] agent-id-blueprint $(Get-Date -Format 'yyyyMMdd')"
            AdditionalProperties = @{
                "@odata.type" = "Microsoft.Graph.AgentIdentityBlueprint"
            }
        }
        
        $blueprint = New-MgBetaApplication @blueprintParams
        $script:AgentBlueprintAppId = $blueprint.AppId
        $script:AgentBlueprintAppObjectId = $blueprint.Id
        
        Write-Host "Created blueprint with AppId: $($script:AgentBlueprintAppId)"
        
        # 01.02 Create Agent Id Blueprint Service Principal
        Write-Host "Creating Agent Identity Blueprint Service Principal..."
        
        # This endpoint is specific to agent blueprint service principals and not available in standard SDK
        # Use Invoke-MgRestMethod with relative path for better SDK integration
        $servicePrincipalBody = @{
            appId = $script:AgentBlueprintAppId
        }
        
        $servicePrincipal = Invoke-MgRestMethod -Uri "/beta/serviceprincipals/graph.agentIdentityBlueprintPrincipal" -Method POST -Body ($servicePrincipalBody | ConvertTo-Json) -ContentType "application/json"
        
        # 01.03 Add client secret to the Agent App Reg
        Write-Host "Adding client secret to Agent App Registration..."
        
        $secretParams = @{
            ApplicationId = $script:AgentBlueprintAppObjectId
            PasswordCredential = @{
                DisplayName = "PowerShell Generated Secret"
                EndDateTime = "2026-08-05T23:59:59Z"
            }
        }
        
        $secretResponse = Add-MgBetaApplicationPassword @secretParams
        $script:AgentBlueprintClientSecret = $secretResponse.SecretText
        
        Write-Host "Client secret created successfully"
        Write-Host "Waiting 20 seconds to ensure client secret is fully propagated..." -ForegroundColor Yellow
        Start-Sleep -Seconds 20
        Write-Host "Wait complete. Continuing with API exposure..." -ForegroundColor Green
        
        # 01.04 Expose an API for the blueprint
        Write-Host "Exposing API for the blueprint..."
        $scopeId = [System.Guid]::NewGuid().ToString()
        
        $apiParams = @{
            ApplicationId = $script:AgentBlueprintAppObjectId
            IdentifierUris = @("api://$($script:AgentBlueprintAppId)")
            Api = @{
                Oauth2PermissionScopes = @(
                    @{
                        AdminConsentDescription = "Allow the application to access the agent on behalf of the signed-in user."
                        AdminConsentDisplayName = "Access agent"
                        Id = $scopeId
                        IsEnabled = $true
                        Type = "User"
                        Value = "access_agent"
                    }
                )
            }
        }

        Update-MgBetaApplication @apiParams
        $script:Scope = "api://$($script:AgentBlueprintAppId)/access_agent"
        
        Write-Host "Agent Blueprint created successfully!" -ForegroundColor Green
        return @{
            AppId = $script:AgentBlueprintAppId
            ObjectId = $script:AgentBlueprintAppObjectId
            ClientSecret = $script:AgentBlueprintClientSecret
            Scope = $script:Scope
        }
    }
    catch {
        Write-Error "Failed to create Agent Blueprint: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Creates Agent Identity using Agent Blueprint credentials
    
.DESCRIPTION
    Implements the "02 Create Agent Id" folder from the Insomnia collection.
    Creates the agent identity using the previously created blueprint credentials.
#>
function New-AgentIdentity {
    [CmdletBinding()]
    param()
    
    Write-Host "Creating Agent Identity..." -ForegroundColor Green
    
    if (-not $script:AgentBlueprintAppId -or -not $script:AgentBlueprintClientSecret) {
        throw "Agent Blueprint must be created first. Run New-AgentBlueprint."
    }
    
    try {
        # Connect using Agent Blueprint credentials
        Connect-GraphAsBlueprint
        
        # 02.01 Create Agent Identity
        Write-Host "Creating Agent Identity..."
        
        # This endpoint is specific to agent identities and not available in standard SDK
        # Use Invoke-MgRestMethod with relative path for better SDK integration
        $agentBody = @{
            displayName = "[ast]-from-id-blueprint"
            agentAppId  = $script:AgentBlueprintAppId
        }
        
        $agentIdentity = Invoke-MgRestMethod -Uri "/beta/serviceprincipals/Microsoft.Graph.AgentIdentity" -Method POST -Body ($agentBody | ConvertTo-Json) -ContentType "application/json"
        $script:AgentIdentityClientId = $agentIdentity.appId
        
        Write-Host "Created Agent Identity with ClientId: $($script:AgentIdentityClientId)" -ForegroundColor Green
        Write-Host "Now waiting 15 seconds to make sure changes propagate ..." -ForegroundColor Green
        Start-Sleep -Seconds 15
        return @{
            ClientId = $script:AgentIdentityClientId
        }
    }
    catch {
        Write-Error "Failed to create Agent Identity: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Creates Agentic User (Digital Colleague) with high privilege credentials
    
.DESCRIPTION
    Implements the "03 Create Agentic User" folder from the Insomnia collection.
    Creates the digital colleague user and grants OAuth2 permissions.
#>
function New-AgenticUser {
    [CmdletBinding()]
    param()
    
    Write-Host "Creating Agentic User (Digital Colleague)..." -ForegroundColor Green
    
    if (-not $script:AgentIdentityClientId) {
        throw "Agent Identity must be created first. Run New-AgentIdentity."
    }
    
    try {
        # Connect with high privilege credentials for user creation
        Connect-GraphAsHighPrivilege
        
        # 03.01 Create Agentic User (Digital Colleague)
        Write-Host "Creating Agentic User..."
        
        # Use New-MgUser for creating the Agent User
        $userParams = @{
            DisplayName = "[ast] Agent ID User"
            UserPrincipalName = $script:AgentUserUPN
            MailNickname = $script:AgentUserMailNickName
            AccountEnabled = $true
            AdditionalProperties = @{
                "@odata.type" = "microsoft.graph.agentUser"
                "identityParentId" = $script:AgentIdentityClientId
            }
        }
        
        $agentUser = New-MgBetaUser @userParams
        $script:AgentIdentityUserId = $agentUser.Id
        
        Write-Host "Created Agentic User with UserId: $($script:AgentIdentityUserId)"
        
        # 03.02 Grant OAuth2 permissions to the Agentic User
        Write-Host "Granting OAuth2 permissions to the Agentic User..."
        
        $permissionParams = @{
            ClientId = $script:AgentIdentityClientId
            ConsentType = "Principal"
            PrincipalId = $script:AgentIdentityUserId
            ResourceId = $script:MSGraphObjectId
            Scope = "User.Read groupmember.read.all mail.read"
            StartTime = [DateTime]::Parse("2025-09-24T00:00:00")
            ExpiryTime = [DateTime]::Parse("2026-09-24T00:00:00")
        }
        
        $permissionGrant = New-MgBetaOauth2PermissionGrant @permissionParams
        
        Write-Host "Agentic User created and permissions granted successfully!" -ForegroundColor Green
        Write-Host "Now waiting 15 seconds for permissions to propagate ..." -ForegroundColor Green
        Start-Sleep -Seconds 15

        return @{
            UserId = $script:AgentIdentityUserId
            UserPrincipalName = $script:AgentUserUPN
        }
    }
    catch {
        Write-Error "Failed to create Agentic User: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Authenticates Agent User (Digital Colleague)
    
.DESCRIPTION
    Implements the "04 Authenticate Agent User" folder from the Insomnia collection.
    Handles the complex authentication flow using FIC tokens for the digital colleague.
    Note: This function uses REST API calls as the complex FIC token flows are not available in Graph SDK.
#>
function Connect-AgentUser {
    [CmdletBinding()]
    param()
    
    Write-Host "Authenticating Agent User (Digital Colleague)..." -ForegroundColor Green
    
    if (-not $script:AgentBlueprintAppId -or -not $script:AgentBlueprintClientSecret -or -not $script:AgentIdentityClientId) {
        throw "Agent Blueprint and Identity must be created first."
    }
    
    try {
        # For FIC token flows, we need to use REST API as these are specialized authentication flows
        $tokenUrl = "https://login.microsoftonline.com/$($script:TenantId)/oauth2/v2.0/token"
        
        # 04.01 Request FIC token for Agent Blueprint
        Write-Host "Requesting FIC token for Agent Blueprint..."
        $ficBody = @{
            scope      = "api://AzureADTokenExchange/.default"
            grant_type = "client_credentials"
            fmi_path   = $script:AgentIdentityClientId
        }
        
        $basicAuth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($script:AgentBlueprintAppId):$($script:AgentBlueprintClientSecret)"))
        $headers = @{
            Authorization = "Basic $basicAuth"
            "Content-Type" = "application/x-www-form-urlencoded"
        }
        
        $ficResponse = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body $ficBody -Headers $headers
        $blueprintFicToken = $ficResponse.access_token
        
        # 04.02 Request FIC token for Agent ID using the Blueprint FIC token
        Write-Host "Requesting FIC token for Agent ID..."
        $agentFicBody = @{
            client_id                = $script:AgentIdentityClientId
            scope                   = "api://AzureADTokenExchange/.default"
            grant_type              = "client_credentials"
            client_assertion_type   = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
            client_assertion        = $blueprintFicToken
        }
        
        $agentFicResponse = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body $agentFicBody -ContentType "application/x-www-form-urlencoded"
        $agentFicToken = $agentFicResponse.access_token
        
        # 04.03 Request Agent User token - using both FIC tokens
        Write-Host "Requesting Agent User token..."
        $userTokenBody = @{
            client_id                           = $script:AgentIdentityClientId
            client_assertion_type              = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
            client_assertion                   = $blueprintFicToken
            grant_type                         = "user_fic"
            requested_token_use                = "on_behalf_of"
            scope                              = "https://graph.microsoft.com/.default"
            username                           = $script:AgentUserUPN
            user_federated_identity_credential = $agentFicToken
        }
        
        $userTokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body $userTokenBody -ContentType "application/x-www-form-urlencoded"
        $agentUserAccessToken = $userTokenResponse.access_token
        
        Write-Host "Agent User authenticated successfully!" -ForegroundColor Green
        
        # Test the authentication with sample calls
        Write-Host "Testing authentication with sample Graph calls..."
        
        # For testing with the agent user token, we need to use Invoke-RestMethod since
        # Invoke-MgRestMethod uses the current SDK connection context
        try {
            $tempHeaders = @{ Authorization = "Bearer $agentUserAccessToken" }
            
            # 04.04 Test /me endpoint using beta since we're connected to beta
            $meResponse = Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/me" -Headers $tempHeaders
            Write-Host "Me endpoint test successful: $($meResponse.displayName)"
            Write-Host "Full /me response:" -ForegroundColor Yellow
            Write-Host ($meResponse | ConvertTo-Json -Depth 3) -ForegroundColor Cyan
            
            # 04.05 Test /me/getMemberGroups
            $groupsBody = @{ securityEnabledOnly = $true }
            $groupsHeaders = @{ 
                Authorization = "Bearer $agentUserAccessToken"
                "Content-Type" = "application/json" 
            }
            $groupsResponse = Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/me/getMemberGroups" -Method POST -Body ($groupsBody | ConvertTo-Json) -Headers $groupsHeaders
            Write-Host "Member groups retrieved: $($groupsResponse.value.Count) groups"
            
            # 04.06 Test /me/messages
            $messagesResponse = Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/me/messages" -Headers $tempHeaders
            Write-Host "Messages retrieved: $($messagesResponse.value.Count) messages"
        }
        catch {
            Write-Warning "Authentication test calls failed, but token was obtained successfully: $($_.Exception.Message)"
        }
        
        return @{
            AccessToken = $agentUserAccessToken
            UserInfo = $meResponse
        }
    }
    catch {
        Write-Error "Failed to authenticate Agent User: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Authenticates Agent ID (Autonomous Agent)
    
.DESCRIPTION
    Implements the "05 Authenticate Agent ID" folder from the Insomnia collection.
    Handles authentication for the autonomous agent using FIC tokens.
    Note: This function uses REST API calls as the complex FIC token flows are not available in Graph SDK.
#>
function Connect-AgentID {
    [CmdletBinding()]
    param()
    
    Write-Host "Authenticating Agent ID (Autonomous Agent)..." -ForegroundColor Green
    
    if (-not $script:AgentBlueprintAppId -or -not $script:AgentBlueprintClientSecret -or -not $script:AgentIdentityClientId) {
        throw "Agent Blueprint and Identity must be created first."
    }
    
    try {
        # For FIC token flows, we need to use REST API as these are specialized authentication flows
        $tokenUrl = "https://login.microsoftonline.com/$($script:TenantId)/oauth2/v2.0/token"
        
        # 05.01 Request FIC token for Agent Blueprint
        Write-Host "Requesting FIC token for Agent Blueprint..."
        $ficBody = @{
            scope      = "api://AzureADTokenExchange/.default"
            grant_type = "client_credentials"
            fmi_path   = $script:AgentIdentityClientId
        }
        
        $basicAuth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($script:AgentBlueprintAppId):$($script:AgentBlueprintClientSecret)"))
        $headers = @{
            Authorization = "Basic $basicAuth"
            "Content-Type" = "application/x-www-form-urlencoded"
        }
        
        $ficResponse = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body $ficBody -Headers $headers
        $blueprintFicToken = $ficResponse.access_token
        
        # 05.02 Request Agent ID token using the Blueprint FIC token
        Write-Host "Requesting Agent ID token..."
        $agentTokenBody = @{
            client_id             = $script:AgentIdentityClientId
            scope                 = "https://graph.microsoft.com/.default"
            grant_type            = "client_credentials"
            client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
            client_assertion      = $blueprintFicToken
        }
        
        $agentTokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body $agentTokenBody -ContentType "application/x-www-form-urlencoded"
        $agentIdentityAccessToken = $agentTokenResponse.access_token
        
        Write-Host "Agent ID authenticated successfully!" -ForegroundColor Green
        return @{
            AccessToken = $agentIdentityAccessToken
        }
    }
    catch {
        Write-Error "Failed to authenticate Agent ID: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Initiates End-User authentication (Interactive Agent)
    
.DESCRIPTION
    Implements the "06 Authenticate End-User" folder from the Insomnia collection.
    Provides authorization code flow setup for end-user interactive authentication.
#>
function Start-EndUserAuthentication {
    [CmdletBinding()]
    param()
    
    Write-Host "Initiating End-User Authentication (Interactive Agent)..." -ForegroundColor Green
    
    if (-not $script:Scope) {
        throw "Agent Blueprint must be created first to establish the scope."
    }
    
    try {
        # 06.01 Generate AuthZ Code request URL for end-user authentication
        $state = "rnd-$(Get-Random -Maximum 999999)"
        $redirectUri = "https://jwt.ms"
        $scope = "$($script:Scope) offline_access"
        $authorizationUrl = "https://login.microsoftonline.com/$($script:TenantId)/oauth2/v2.0/authorize"
        
        $authUrl = $authorizationUrl + 
                   "?client_id=$($script:AIClientId)&" +
                   "response_type=code&" +
                   "redirect_uri=$([System.Web.HttpUtility]::UrlEncode($redirectUri))&" +
                   "scope=$([System.Web.HttpUtility]::UrlEncode($scope))&" +
                   "state=$state"
        
        Write-Host "Authorization URL generated:" -ForegroundColor Yellow
        Write-Host $authUrl -ForegroundColor Cyan
        Write-Host ""
        Write-Host "To complete end-user authentication:" -ForegroundColor Yellow
        Write-Host "1. Copy the above URL and open it in a web browser" -ForegroundColor White
        Write-Host "2. Sign in with the end-user credentials" -ForegroundColor White
        Write-Host "3. After consent, you'll be redirected to jwt.ms with the authorization code" -ForegroundColor White
        Write-Host "4. Use the authorization code to exchange for access tokens" -ForegroundColor White
        
        return @{
            AuthorizationUrl = $authUrl
            RedirectUri = $redirectUri
            State = $state
            Scope = $scope
        }
    }
    catch {
        Write-Error "Failed to initiate end-user authentication: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Complete workflow to create and authenticate all agent components
    
.DESCRIPTION
    Executes the complete workflow from creating the agent blueprint to setting up all authentication scenarios.
    Uses Microsoft Graph PowerShell SDK where possible and REST API for specialized agent features.
#>
function Complete-AgentSetup {
    [CmdletBinding()]
    param(
        [switch]$SkipEndUserAuth
    )
    
    Write-Host "Starting complete Agent ID setup workflow..." -ForegroundColor Magenta
    Write-Host "Using Microsoft Graph PowerShell SDK with REST API for specialized features" -ForegroundColor Yellow
    
    try {
        # Step 1: Create Agent Blueprint
        $blueprint = New-AgentBlueprint
        Write-Host "✓ Agent Blueprint created" -ForegroundColor Green
        
        # Step 2: Create Agent Identity
        $identity = New-AgentIdentity
        Write-Host "✓ Agent Identity created" -ForegroundColor Green
        
        # Step 3: Create Agentic User
        $user = New-AgenticUser
        Write-Host "✓ Agentic User created" -ForegroundColor Green
        
        # Step 4: Authenticate Agent User
        $userAuth = Connect-AgentUser
        Write-Host "✓ Agent User authenticated" -ForegroundColor Green
        
        # Step 5: Authenticate Agent ID
        $agentAuth = Connect-AgentID
        Write-Host "✓ Agent ID authenticated" -ForegroundColor Green
        
        # Step 6: Setup End-User Authentication (optional)
        if (-not $SkipEndUserAuth) {
            $endUserAuth = Start-EndUserAuthentication
            Write-Host "✓ End-User authentication initiated" -ForegroundColor Green
        }
        
        Write-Host ""
        Write-Host "Agent ID setup completed successfully!" -ForegroundColor Magenta
        Write-Host "Summary:" -ForegroundColor Yellow
        Write-Host "- Agent Blueprint App ID: $($script:AgentBlueprintAppId)" -ForegroundColor White
        Write-Host "- Agent Identity Client ID: $($script:AgentIdentityClientId)" -ForegroundColor White
        Write-Host "- Agent User UPN: $($script:AgentUserUPN)" -ForegroundColor White
        Write-Host "- Agent User ID: $($script:AgentIdentityUserId)" -ForegroundColor White
        
        # Clean up connections
        if (Get-MgContext) {
            Disconnect-MgGraph
            Write-Host "Disconnected from Microsoft Graph" -ForegroundColor Yellow
        }
        
        return @{
            Blueprint = $blueprint
            Identity = $identity
            User = $user
            UserAuth = $userAuth
            AgentAuth = $agentAuth
            EndUserAuth = if (-not $SkipEndUserAuth) { $endUserAuth } else { $null }
        }
    }
    catch {
        Write-Error "Agent setup failed: $($_.Exception.Message)"
        # Clean up on failure
        if (Get-MgContext) {
            Disconnect-MgGraph
        }
        throw
    }
}

# Export functions
# Export-ModuleMember -Function New-AgentBlueprint, New-AgentIdentity, New-AgenticUser, Connect-AgentUser, Connect-AgentID, Start-EndUserAuthentication, Complete-AgentSetup

Complete-AgentSetup
<#
.EXAMPLE
    # Complete setup workflow using Microsoft Graph PowerShell SDK
    Complete-AgentSetup

.EXAMPLE
    # Step-by-step setup using Microsoft Graph PowerShell SDK
    New-AgentBlueprint
    New-AgentIdentity
    New-AgenticUser
    Connect-AgentUser
    Connect-AgentID
    Start-EndUserAuthentication

.EXAMPLE
    # Setup without end-user authentication
    Complete-AgentSetup -SkipEndUserAuth

.NOTES
    This script properly uses Microsoft Graph PowerShell SDK cmdlets where available:
    - Connect-MgGraph for authentication (Beta endpoint)
    - New-MgApplication for application creation
    - Add-MgApplicationPassword for client secrets
    - Update-MgApplication for API exposure
    - New-MgUser for user creation
    - New-MgOauth2PermissionGrant for permission grants
    - Invoke-MgRestMethod for SDK-compatible Graph REST calls
    - Disconnect-MgGraph for cleanup
    
    Direct REST API calls are used only for specialized endpoints not available in the SDK:
    - AgentIdentityBlueprint service principal creation (specialized beta endpoint)
    - AgentIdentity creation (specialized beta endpoint) 
    - OAuth2/FIC token authentication flows (specialized Azure AD token endpoints)
    - Agent user authentication testing (requires raw access tokens)
    
    All Microsoft Graph connections use the Beta endpoint to ensure compatibility with Agent features.
#>