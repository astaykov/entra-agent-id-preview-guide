# Entra Agent ID developer onboarding and deep dive

## Prerequisites
 * A Microsoft Entra ID tenant that is onboarded to the Entra Agent ID preview
 * „Management“ application registration: to create artefacts with the following (application) permissions
   * AgentApplication.Create – to create Agent Blueprint
   * Application.ReadWrite.OwnedBy – to create client secret for the blueprint and to „expose an API“ for the blueprint
   * User.ReadWrite.All – to create the Agent User Id
   * OAuth2PermissionGrants.ReadWrite.All – to grant admin consent for the Agent User
 * AI application client – this will represent your AI application that you are developing
 * Optional – Insomnia, all requests are provided as [Insomnia](https://insomnia.rest/) Collection ([Insomnia5-AgentID.yaml](./Insomnia5-AgentID.yaml)) and PowerShell ([AgentID-PowerShell.ps1](./AgentID-PowerShell.ps1))

 > **Note on the permissions**
 > - `Application.ReadWrite.OwnedBy` permission is only requirement for scripting in this guide to work. The script exposes an API on the Agent Blueprint - section 01.03, and adds client credential - section 01.04.
  > - `User.ReadWrite.All` permission is a temporary requirement during preview. This is required to create the `Agentic User` (Digital Colleague), which is a `User` object with some special properties.
 > - `OAuth2PermissionGrants.ReadWrite.All` permission is a temporary requirement during preview. This is required for the script to grant admin consent for the digital colleague (Agentic User) to access data. Check section (4) for more details.

## Insomnia setup
Import the provided Insomnia5-AgentID.yaml collection to [Insomnia](https://insomnia.rest/) and open the Agent ID collection.

### Update the Base environment with the values for your tenant
 `token_url`: "https://login.microsoftonline.com/YOUR-TENANT-ID/oauth2/v2.0/token",  
 `authorization_url`: "https://login.microsoftonline.com/YOUR-TENANT-ID/oauth2/v2.0/authorize",  
 `ms_graph_object_id`: "find the object ID for MS Graph in your tenant",  
 `client_id` "the client id for your management app with granted application permissions",  
 `client_secret`: "client secret for the management app",  
 `ai_client_id`: "client id for app registration representing the AI app you are developing",  
 `ai_client_secret`: "client secret for the AI app"  
 `agent_user_upn`: "agenticDigitalColleague@yourtenant.onmicrosoft.com",  
 `agent_user_mailNickName`: "agenticDigitalColleague"  

The Agent ID environment variables will be populated automatically.

 > **Note:** Required authentication for each REST call in insomnia is configured at the „Authentication“ section of the request or the folder for the request

## The following artefacts will be created
TODO: Insert graphic

## 01 Creating the Agent ID Blueprint

### 01.01. Create the Agent Identity Blueprint (application)

```bash
curl -X POST "https://graph.microsoft.com/beta/applications/" \
  -H "Content-Type: application/json" \
  -H "OData-Version: 4.0" \
  -H "Authorization: Bearer {{ ACCESS_TOKEN_FROM_OAUTH2_CLIENT_CREDENTIALS }}" \
  -d '{
    "@odata.type": "Microsoft.Graph.AgentIdentityBlueprint",
    "displayName": "[as]-agent-id-blueprint 20250926"
  }'
```

Sample response
```JSON
{
	"@odata.context": "https://graph.microsoft.com/beta/$metadata#applications/$entity",
	"@odata.type": "#microsoft.graph.agentIdentityBlueprint",
	"id": "929afb83-2c25-43f5-85a0-33a8299e3148",
	"deletedDateTime": null,
	"appId": "fe2433e7-1fd8-4d26-a4e4-6dfb62aa41b2",
	"applicationTemplateId": null,
	"identifierUris": [],
	"createdByAppId": "c7070528-2e77-48fb-bad8-2644cd74a151",
	"createdDateTime": "2025-09-24T08:27:46.5462298Z",
	"tags": [],
	....
}
```


### 01.02. Create the Agent Blueprint Service Principal

```
curl -X POST "https://graph.microsoft.com/beta/serviceprincipals/graph.agentIdentityBlueprintPrincipal" \
  -H "Content-Type: application/json" \
  -H "OData-Version: 4.0" \
  -H "Authorization: Bearer {{ ACCESS_TOKEN_FROM_OAUTH2_CLIENT_CREDENTIALS }}" \
  -d '{
    "appId": "{{ _.agent_blueprint_appId }}"
  }'
```

Sample response:
```JSON
{
	"@odata.context": "<shortened>/microsoft.graph.agentServicePrincipal/$entity",
	"id": "b7d1b414-b5fc-4ce8-ad68-8113678d0d31",
	"accountEnabled": true,
	"createdByAppId": "c7070528-2e77-48fb-bad8-2644cd74a151",
	"appDisplayName": "[as]-agent-identity-blueprint",
	"appId": "fe2433e7-1fd8-4d26-a4e4-6dfb62aa41b2",
	"appOwnerOrganizationId": "8e9ff323-8255-4620-8bc3-06637b146e51",
	"appRoleAssignmentRequired": false,
	"servicePrincipalNames": [
		"fe2433e7-1fd8-4d26-a4e4-6dfb62aa41b2„
	],
	"servicePrincipalType": "Application",
	"signInAudience": "AzureADMyOrg",
}
```

### 01.03. Add Password credential (client secret) to the Agent Blueprint 

 > **Warning** This step is for illustrational and demo purposes only. Do not use client secrets in production environments.
 It is recommended to use managed identity in production environment!

```
curl -X POST "https://graph.microsoft.com/beta/applications/{{ _.agent_blueprint_appObjectId }}/addPassword" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {{ ACCESS_TOKEN_FROM_OAUTH2_CLIENT_CREDENTIALS }}" \
  -d '{
    "passwordCredential": {
      "displayName": "Dummy Secret",
      "endDateTime": "2026-08-05T23:59:59Z"
    }
  }'
```

Sample response
```JSON
{
	"@odata.context": "https://xxxx#microsoft.graph.passwordCredential",
	"customKeyIdentifier": null,
	"endDateTime": "2026-08-05T23:59:59Z",
	"keyId": "e6912b08-c00f-1234-a8a6-6ae04bb50bd3",
	"startDateTime": "2025-09-26T08:00:42.4974553Z",
	"secretText": "ntu*******",
	"hint": "ntu",
	"displayName": "Dummy Secret"
}
```

 > **Note**: A post-response script in Insomnia will update the environment variable with the provided client secret

 > **Warning**: Please wait at least 30 seconds before moving to next steps, to allow time for the credential to be fully replicated.

### 01.04. Exponsing API (scope) for the Agent Blueprint
We will need this for the scenario where the AI Agent is performing tasks *on-behalf* of the end-user and carrying the end-user security context.

```
curl -X PATCH "https://graph.microsoft.com/beta/applications/{{ _.agent_blueprint_appObjectId }}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {{ ACCESS_TOKEN_FROM_OAUTH2_CLIENT_CREDENTIALS }}" \
  -d '{
    "identifierUris": ["api://{{ _.agent_blueprint_appId }}"],
    "api": {
      "oauth2PermissionScopes": [
        {
          "adminConsentDescription": "Allow the application to access the agent on behalf of the signed-in user.",
          "adminConsentDisplayName": "Access agent",
          "id": "{{ GENERATED_GUID }}",
          "isEnabled": true,
          "type": "User",
          "value": "access_agent"
        }
      ]
    }
  }'
``` 

A successful response would carry `HTTP 204` status code with empty response body.

## 02 Creating the Agent Identity

After an Agent Blueprint is created we will need an Agent Identity. This is a special service principal that is linked directly to the Agent Blueprint. An Agent Blueprint may have more than one Agent Identity, but an Agent Identity can only have one parent Agent Blueprint. This Agent Identity can be used in scenario of `Autonomous Agent`. That is when an AI Agent operates under its own security context.

### 02.01. Creating the Agent Identity

```
curl -X POST "https://graph.microsoft.com/beta/serviceprincipals/Microsoft.Graph.AgentIdentity" \
  -H "Content-Type: application/json" \
  -H "OData-Version: 4.0" \
  -H "Authorization: Bearer {{ ACCESS_TOKEN_FROM_AGENT_BLUEPRINT_OAUTH2 }}" \
  -d '{
    "displayName": "[as] from-id-blueprint",
    "agentAppId": "{{ _.agent_blueprint_appId }}"
  }
```
Sample response
```JSON
{
  "@odata.context": ".../$metadata#servicePrincipals/microsoft.graph.agentIdentity/$entity",
  "id": "c81ab79b-fe7f-4e19-b1a3-b527f48622f4",
  "accountEnabled": true,
  "alternativeNames": [],
  "createdByAppId": "5d674406-dba3-4dee-afbd-de1887403dff",
  "appId": "c81ab79b-fe7f-4e19-b1a3-b527f48622f4",
"appOwnerOrganizationId": null,
  "appRoleAssignmentRequired": false,
"displayName": "[as] from-id-blueprint",
  "agentAppId": "5d674406-dba3-4dee-afbd-de1887403dff",
  ...
}
```

 > **Note**: Please wait about 20 seconds before creating the Agentic User (step 03). The Agentic User will refer to this identity as its parent.

## 03. Creating Agent User Identity
This is a special User object that will represent an Agentic User - `Digital Colleague`. This type of AI Agent will not only operate with its own identity, but it will also have its own e-mail, teams, onedrive, etc. 

### 03.01. Create the agentic user

 > *Credentials*: an MS Graph access token obtained via the management app credentials

```
curl -X POST "https://graph.microsoft.com/beta/users" \
  -H "Content-Type: application/json" \
  -H "OData-Version: 4.0" \
  -H "Authorization: Bearer {{ ACCESS_TOKEN_FROM_OAUTH2_CLIENT_CREDENTIALS }}" \
  -d '{
    "@odata.type":"microsoft.graph.agentUser",
    "displayName": "[as] Agent ID User",
    "userPrincipalName": "{{ _.agent_user_upn }}",
    "mailNickname": "{{ _.agent_user_mailNickName }}",
    "accountEnabled": true,
    "identityParentId":"{{ _.agent_identity_clientId }}"
  }'
```

Sample repsonse
```JSON
{
 "@odata.context": "https://..../$metadata#users/$entity",
 "@odata.type": "#microsoft.graph.agentUser",
 "id": "4274f09f-b3ea-4005-b377-e0ec77736a4f",
 "deletedDateTime": null,
 "accountEnabled": true,
 "displayName": "[as] Agent ID User",
 "mailNickname": "asAgentIdBPUser",
 "userType": "Member",
 "identityParentId": "c81ab79b-fe7f-4e19-b1a3-b527f48622f4",
 "identityParent": {
 	"id": "c81ab79b-fe7f-4e19-b1a3-b527f48622f4"
 }
}
```

 > **Note**: Wait about 10-15 seconds for changes to be fully replicated before granting permissions to the user

### 03.02. Grant (consent) permissions for the Agentic User

Following the principle of least privilege, an Agentic User does not have any permissions to any resources by default. For this identity to access any information, a consent must be explicitly granted. In this example we will grant permissions to be able to sign-in and read its own user data, read e-mails and read its own group memberships.

```
curl -X POST "https://graph.microsoft.com/beta/oauth2PermissionGrants" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {{ ACCESS_TOKEN_FROM_OAUTH2_CLIENT_CREDENTIALS }}" \
  -d '{
    "clientId": "{{ _.agent_identity_clientId }}",
    "consentType": "Principal",
    "principalId": "{{ _.agent_identity_userId }}",
    "resourceId": "{{ _.ms_graph_object_id }}",
    "scope":"User.Read groupmember.read.all mail.read",
    "startTime": "2025-09-24T00:00:00",
    "expiryTime":"2026-09-24T00:00:00"
  }'
``` 

Sample response
```JSON
{
 "@odata.context": „..#oauth2PermissionGrants/$entity",
 "clientId": "c81ab79b-fe7f-4e19-b1a3-b527f48622f4",
 "consentType": "Principal",
 "expiryTime": "2026-09-24T00:00:00Z",
 "id": "m7cayH_xxxxx",
 "principalId": "4274f09f-b3ea-4005-b377-e0ec77736a4f",
 "resourceId": "1a8127b0-1874-4400-9468-5ca9c9f4f0eb",
 "scope": "User.Read groupmember.read.all mail.read",
 "startTime": "2025-09-24T00:00:00Z"
}
```

## 04 Authenticate the Agentic User (Digital Colleague)

Authentication of the digital colleague follows an extension to the OAuth 2.0 authorization framework and may change in the future. This is custom implementation by Microsoft Entra to support secure, reliable authentication and authorization of AI Agents acting as digital colleagues.

### 04.01. Obtain a Federated Identity Credetial (FIC) for the Agent Blueprint
 > **Warning**: In this sample we use client credentials (client id and client secret) to authenticate the Agent Blueprint. It is recommended to use Managed Identity for production environments. 
```
curl -X POST "{{ _.token_url }}" \
  -H "Content-Type: multipart/form-data" \
  -u "{{ _.agent_blueprint_appId }}:{{ _.agent_blueprint_clientSecret }}" \
  -F "scope=api://AzureADTokenExchange/.default" \
  -F "grant_type=client_credentials" \
  -F "fmi_path={{ _.agent_identity_clientId }}"
```

 > **Note**: The specific extension here is the additional parameter `fmi_path` which points to the `Agent Identity` for which we want to get the FIC token

We will call the resulting `access_token` as `agent_blueprint_fic-token` to easily recognize its usage in the following calls.

### 04.02. Obtain a Federated Identity Credential (FIC) for the Agent Identity 
```
curl -X POST "{{ _.token_url }}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id={{ _.agent_identity_clientId }}&scope=api://AzureADTokenExchange/.default&grant_type=client_credentials&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion={{ _.agent_blueprint_ficToken }}"

```

We will call the resulting `access_token` as `agent_id_fic-token` to easily recognize its usage in the following calls.

### 04.03. Obtain an Agentic User token for MS Graph using the agent_blueprint_fic-token and agent_id_fic-token

```
curl -X POST "{{ _.token_url }}" \
  -H "Content-Type: multipart/form-data" \
  -F "client_id={{ _.agent_identity_clientId }}" \
  -F "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -F "client_assertion={{ _.agent_blueprint_ficToken }}" \
  -F "grant_type=user_fic" \
  -F "requested_token_use=on_behalf_of" \
  -F "scope=https://graph.microsoft.com/.default" \
  -F "username={{ _.agent_user_upn }}" \
  -F "user_federated_identity_credential={{ _.agent_identity_ficToken }}"
```

We will call the resulting `access_token` as `agent-user-token` for the following calls

### 04.04. Use the agent-user-token to call MS Graph /me endpoint
```
curl -X GET "https://graph.microsoft.com/v1.0/me" \
  -H "Authorization: Bearer {{ _.agent_user_accessToken }}"
```

Sample response
```JSON
{
	"@odata.context": "https://graph.microsoft.com/v1.0/$metadata#users/$entity",
	"businessPhones": [],
	"displayName": "[as] Agent ID User",
	"givenName": null,
	"jobTitle": null,
	"mail": null,
	"mobilePhone": null,
	"officeLocation": null,
	"preferredLanguage": null,
	"surname": null,
	"userPrincipalName": "asAgentIdUser@wrytercorp.onmicrosoft.com",
	"id": "bea9b72b-105a-46c8-9fbd-0bb09b1e7803"
}
```

### 04.05. Get the groups the Agentic User (Digital Colleague) is member of

In this example we will use MS Graph to get the groups for which the agent user is member of.
To effectively test this functionality, you may want to manually add the agent user to some security groups in the Entra admin center.

```
curl -X POST "https://graph.microsoft.com/v1.0/me/getMemberGroups" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {{ _.agent_user_accessToken }}" \
  -d '{
    "securityEnabledOnly": true
  }'
```

## 05 Authenticate the Agent Identity (Autonomous Agent)

### 05.01. Obtain the Agent Blueprint FIC token
 > **Warning**: In this sample we use client credentials (client id and client secret) to authenticate the Agent Blueprint. It is recommended to use Managed Identity for production environments. 

```
curl -X POST "{{ _.token_url }}" \
  -H "Content-Type: multipart/form-data" \
  -u "{{ _.agent_blueprint_appId }}:{{ _.agent_blueprint_clientSecret }}" \
  -F "scope=api://AzureADTokenExchange/.default" \
  -F "grant_type=client_credentials" \
  -F "fmi_path={{ _.agent_identity_clientId }}"
```

 > **Note**: The specific extension here is the additional parameter `fmi_path` which points to the `Agent Identity` for which we want to get the FIC token

We will call the resulting `access_token` as `agent_blueprint_fic-token` to easily recognize its usage in the following calls.

### 05.02. Obtain the Agent Identity MS Graph access token

```
curl -X POST "{{ _.token_url }}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id={{ _.agent_identity_clientId }}&scope=https://graph.microsoft.com/.default&grant_type=client_credentials&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion={{ _.agent_blueprint_ficToken }}"
```

We can now use the resulting access token to access any resource the Agent Identity is authorized to access.

## 06. Authenticate end-user to access the AI Agent and send commands
In this use case the AI Agent will act `on-behlf-of` the user carrying all the security context of the calling user.

For this scenario we will use authorization code folw. We will use the `client id` of the `AI Application` and will be targeting (in our `scope`) the **Agent Blueprint**.

### 06.01 Obtain authorzation code for the user accessing the AI Agent

Open browser and navigate to:
```
https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/authorize?client_id=<AI_APP_CLIENT_ID>&response_type=code&redirect_uri=https%3a%2f%2fjwt.ms&scope=api%3a%2f%2f<AGENT_ID_CLIENT_ID>%2faccess_agent+offline_access&state=rnd-463866&response_mode=query
```
 > **Note:** This is an OAuth2 authorization code flow that requires user interaction.  
 > The final request to https://jwt.ms is just to decode the JWT token


Here all the specific parameters for better readibility:

`client_id`=<AI_APP_CLIENT_ID>  
&`response_type`=code  
&`redirect_uri`=https%3a%2f%2fjwt.ms  
&`scope`=api%3a%2f%2f<AGENT_ID_CLIENT_ID>%2faccess_agent+offline_access  
&`state`=rnd-463866  
&`response_mode`=query  

After authenticating you will be redirected to the default reply url with a `code`.

### Redeem the authorization code (Insomnia will do this automatically)

Note that the `scope` and `redirect_uri` must exactly match the values provided during the authorization code request flow. We use `https://jwt.ms` as redirect uri for demo purposes.

```
curl -X POST "{{ _.token_url }}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id={{ _.ai_client_id }}&client_secret={{ _.ai_client_secret }}&grant_type=authorization_code&code={{ AUTHORIZATION_CODE }}&redirect_uri=https://jwt.ms&scope={{ _.scope }}%20offline_access"
```
