# Entra Agent ID Developer Onboarding and Deep Dive

## Prerequisites
 * A Microsoft Entra ID tenant that is onboarded to the Entra Agent ID preview
 * „Management“ application registration: to create artefacts with the following (application) permissions
   * AgentApplication.Create – to create Agent Blueprint
   * Application.ReadWrite.OwnedBy – to create client secret for the blueprint and to „expose an API“ for the blueprint
   * User.ReadWrite.All – to create the Agent User Id
   * OAuth2PermissionGrants.ReadWrite.All – to grant admin consent for the Agent User
 * AI application client – this will represent your AI application that you are developing
 * Optional – Insomnia, all requests are provided as Insomnia Collection and PowerShell (Microsoft Graph Beta PowerShell)

## Insomnia setup
Import the provided Insomnia5-AgentID.yaml collection to Insomnia
Open the Agent ID collection

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

```
POST /beta/applications/
host: graph.microsoft.com
OData-Version: 4.0
authorization: Bearer
{
  "@odata.type": "Microsoft.Graph.AgentIdentityBlueprint",
  "displayName": "[as]-agent-identity-blueprint"
}
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
POST /beta/serviceprincipals/graph.agentServicePrincipal
host: graph.microsoft.com
authorization: Bearer
{
  "appId": "{{ _.agent_blueprint_appId }}"
}
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
POST /beta/applications/{{_.agent_blueprint_appObjectId}}/addPassword
host: graph.microsoft.com
authorization: Bearer
{
  "passwordCredential": {
    "displayName": "Dummy Secret",
    "endDateTime": "2026-08-05T23:59:59Z"
  }
}
```

Sample response
```JSON
{
	"@odata.context": "https://xxxx#microsoft.graph.passwordCredential",
	"customKeyIdentifier": null,
	"endDateTime": "2026-08-05T23:59:59Z",
	"keyId": "e6912b08-c00f-46ea-a8a6-6ae04bb50bd3",
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
POST /beta/serviceprincipals/graph.agentServicePrincipal
host: graph.microsoft.com
authorization: Bearer
{
  "identifierUris": ["api://{{ _.agent_blueprint_appId }}"],
  "api": {
    "oauth2PermissionScopes": [
      {
        "adminConsentDescription": "Allow the application to access the agent on behalf of the signed-in user.",
        "adminConsentDisplayName": "Access agent",
        "id": "{% faker 'guid' %}",
        "isEnabled": true,
        "type": "User",
        "value": "access_agent"
      }
    ]
  }
}
``` 

A successful response would carry `HTTP 204` status code with empty response body.

## 02 Creating the Agent Identity

After an Agent Blueprint is created we will need an Agent Identity. This is a special service principal that is linked directly to the Agent Blueprint. An Agent Blueprint may have more than one Agent Identity, but an Agent Identity can only have one parent Agent Blueprint. This Agent Identity can be used in scenario of `Autonomous Agent`. That is when an AI Agent operates under its own security context.

### 02.01. Creating the Agent Identity

```
POST /beta/serviceprincipals/Microsoft.Graph.AgentIdentity
host: graph.microsoft.com
authorization: Bearer <agent blueprint ms graph token>
02. Creating Agent Identity (autonomous agent)
{
    "displayName": "[as]-from-id-blueprint",
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
"displayName": "[as]-from-id-blueprint",
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
POST /beta/users
host: graph.microsoft.com
OData-Version: 4.0
authorization: Bearer
03. Creating Agent User (digital colleague)
{
 "@odata.type":"microsoft.graph.agentUser",
 "displayName": "[as] Agent ID User",
 "userPrincipalName": "{{ _.agent_user_upn }}",
 "mailNickname": "{{ _.agent_user_mailNickName }}",
 "accountEnabled": true,
 "identityParentId":"{{ _.agent_identity_clientId }}"
}

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
POST /beta/oauth2PermissionGrants
host: graph.microsoft.com
authorization: Bearer

{
 "clientId": "{{ _.agent_identity_clientId }}",
 "consentType": "Principal",
 "principalId": "{{ _.agent_identity_userId }}",
 "resourceId": "{{ _.ms_graph_object_id }}",
 "scope":"User.Read groupmember.read.all mail.read",
 "startTime": "2025-09-24T00:00:00",
 "expiryTime":"2026-09-24T00:00:00"
}
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
POST _.token_url
	&scope=api://AzureADTokenExchange/.default
	&grant_type=client_credentials
	&client_id=<agent_blueprint_client_id>
	&client_secret=<agent_blueprint_secret>
	&fmi_path=<agent_id_client_id>
```

 > **Note**: The specific extension here is the additional parameter `fmi_path` which points to the `Agent Identity` for which we want to get the FIC token

We will call the resulting `access_token` as `agent_blueprint_fic-token` to easily recognize its usage in the following calls.

### 04.02. Obtain a Federated Identity Credential (FIC) for the Agent Identity 
```
POST _.token_url
	&scope=api://AzureADTokenExchange/.default
	&grant_type=client_credentials
	&client_id=<agent_id_client_id>
	&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer
	&client_assertion=agent_blueprint_fic-token
```

We will call the resulting `access_token` as `agent_id_fic-token` to easily recognize its usage in the following calls.

### 04.03. Obtain an Agentic User token for MS Graph using the agent_blueprint_fic-token and agent_id_fic-token
```
POST _.token_url
	&scope=https://graph.microsoft.com/.default
	&grant_type=user_fic
	&requested_token_use=on_behalf_of
	&client_id=<agent_id_client_id>
	&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer
	&client_assertion=<agent_blueprint_fic-token>
	&user_federated_identity_credential=<agent_id_fic-token>
	&username=<agent_user_upn>
```

We will call the resulting `access_token` as `agent-user-token` for the following calls

### 04.04. Use the agent-user-token to call MS Graph /me endpoint
```
GET /v1.0/me
	Host: graph.microsoft.com
	authorization: Bearer <agent-user-token>
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

## 05 Authenticate the Agent Identity (Autonomous Agent)

### 05.01. Obtain the Agent Blueprint FIC token
 > **Warning**: In this sample we use client credentials (client id and client secret) to authenticate the Agent Blueprint. It is recommended to use Managed Identity for production environments. 

```
POST _.token_url
	&scope=api://AzureADTokenExchange/.default
	&grant_type=client_credentials
	&client_id=<agent_blueprint_client_id>
	&client_secret=<agent_blueprint_secret>
	&fmi_path=<agent_id_client_id>
```

 > **Note**: The specific extension here is the additional parameter `fmi_path` which points to the `Agent Identity` for which we want to get the FIC token

We will call the resulting `access_token` as `agent_blueprint_fic-token` to easily recognize its usage in the following calls.

### 05.02. Obtain the Agent Identity MS Graph access token
```
POST _.token_url
	&scope=https://graph.microsoft.com/.default
	&grant_type=client_credentials
	&client_id=<agent_id_client_id>
	&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer
	&client_assertion=<agent_blueprint_fic-token>
```

We can now use the resulting access token to access any resource the Agent Identity is authorized to access.

## 06. Authenticate end-user to access the AI Agent and send commands
In this use case the AI Agent will act `on-behlf-of` the user carrying all the security context of the calling user.

For this scenario we will use authorization code folw. We will use the `client id` of the `AI Application` and will be targeting (in our `scope`) the **Agent Blueprint**.

### 06.01 Obtain authorzation code for the user accessing the AI Agent

Open browser and navigate to:
```
https://login.microsoftonline.com/8e9ff323-8255-4620-8bc3-06637b146e51/oauth2/v2.0/authorize?client_id=<AI_APP_CLIENT_ID>&response_type=code&redirect_uri=https%3a%2f%2fjwt.ms&scope=api%3a%2f%2f<AGENT_ID_CLIENT_ID>%2faccess_agent+offline_access&state=rnd-463866&response_mode=query
```

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
POST _.token_url

	&client_id=<AI_APP_CLIENT_ID>
	&scope=api%3a%2f%2f<AGENT_ID_CLIENT_ID>%2faccess_agent+offline_access
	&code=OAAABAAAAiL9Kn2Z27UubvWFPbm0gLWQJVzCTE9UkP3pSx1aXxUjq3n8b2JRLk4OxVXr...
	&redirect_uri=http%3A%2F%2Fjwt.ms%2F
	&grant_type=authorization_code
	&client_secret=<AI_APP_CLIENT_SECRET> 
```
