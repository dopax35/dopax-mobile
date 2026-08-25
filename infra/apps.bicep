// DopaX application layer — App Service for Containers, Israel Central.
//
// PHASE 2. Nothing here is deployed by `./infra/deploy.sh --data-only`.
//
// This replaces the Container Apps design that used to live in main.bicep.
// Azure Container Apps is not offered in Israel Central — not the environment,
// not `containerApps`, not `jobs` — and the region is fixed by data residency,
// so the compute platform had to change rather than the region. Measured
// against the live provider manifest:
//
//   Microsoft.App/*                    unavailable in israelcentral
//   Microsoft.Web/sites, serverFarms   available, Linux B1 through P2v3
//   Microsoft.ContainerInstance        available
//
// Three things behave differently from Container Apps and are not oversights:
//
//   1. No scale-to-zero. App Service bills the plan, not the request, so the
//      staff console no longer costs nothing while idle. It shares the API's
//      plan instead, which lands in the same place by a different route.
//   2. Revisions become deployment slots, and slots need Standard or better.
//      On Basic, a rollback is a redeploy of the previous tag.
//   3. Jobs have no equivalent. The R5 bootstrap and the nightly reconciler run
//      as on-demand Container Instances driven by scripts, deliberately: a
//      bootstrap that starts because a template was applied is not the
//      "separate, observed step" guardrail R5 asks for. See infra/README.md.

targetScope = 'resourceGroup'

@description('Azure region. Must match the data layer.')
param location string = resourceGroup().location

@description('Short prefix for every resource name. Must match main.bicep.')
param namePrefix string = 'dopax'

@description('Deployment environment. Part of resource names and tags.')
@allowed(['prod', 'staging'])
param environment string = 'prod'

@description('''
App Service plan SKU. B1 (1 vCPU / 1.75 GB) holds both the API and the staff
console at study scale. Two caveats worth knowing before choosing it:

  - Basic has no deployment slots, so there is no warm swap and no instant
    rollback. S1 is the cheapest tier that has them.
  - Both apps share the plan's single instance, so a heavy admin query and an
    upload compete for the same CPU.

P0v3 is the first tier with a meaningfully larger memory ceiling if the Next.js
console turns out to need it.
''')
@allowed(['B1', 'B2', 'B3', 'S1', 'P0v3', 'P1v3'])
param appServicePlanSku string = 'B1'

@description('Container image tag deployed to both apps.')
param imageTag string = 'latest'

@description('Login server of the container registry, e.g. dopaxprod1234.azurecr.io.')
param registryLoginServer string

@description('Resource ID of the user-assigned workload identity.')
param identityResourceId string

@description('Client ID of the same identity. App Service needs this form for registry pulls.')
param identityClientId string

@description('Key Vault secret URI holding the PostgreSQL connection string.')
param databaseUrlSecretUri string

@description('Key Vault secret URI holding the participant token signing secret.')
param jwtSecretUri string

@description('Key Vault secret URI holding the staff console signing secret.')
param adminJwtSecretUri string

@description('Storage account holding the raw upload archive.')
param storageAccountName string

@description('Blob container holding the raw upload archive.')
param uploadsContainerName string = 'uploads'

@description('Firebase project that remains the identity provider. Guardrail R1.')
param firebaseProjectId string = 'dopa-x-app'

@description('Google Drive folder holding the legacy corpus, read-only.')
param legacyDriveFolderId string = ''

@description('''
Dual-architecture switch. Must stay true until 14 consecutive clean
reconciliation runs have passed. Guardrail R3.
''')
param bothArch bool = true

@description('Log Analytics workspace that receives container console logs.')
param logAnalyticsWorkspaceId string

var baseName = '${namePrefix}-${environment}'
var tags = {
  project: 'dopax'
  environment: environment
  dataClassification: 'phi'
  managedBy: 'bicep'
}

var identityConfig = {
  type: 'UserAssigned'
  userAssignedIdentities: {
    '${identityResourceId}': {}
  }
}

// Anything secret is a Key Vault reference resolved by the managed identity at
// start, so no credential is ever stored in application configuration.
var backendAppSettings = [
  { name: 'NODE_ENV', value: 'production' }
  { name: 'PORT', value: '8080' }
  // App Service needs to be told which port the container listens on; it does
  // not read EXPOSE.
  { name: 'WEBSITES_PORT', value: '8080' }
  { name: 'LOG_LEVEL', value: 'info' }
  { name: 'BOTH_ARCH', value: string(bothArch) }
  { name: 'LEGACY_DRIVE_DRAIN', value: string(bothArch) }
  { name: 'LEGACY_DRIVE_FOLDER_ID', value: legacyDriveFolderId }
  { name: 'STORAGE_BACKEND', value: 'azure' }
  { name: 'AZURE_STORAGE_CONTAINER', value: uploadsContainerName }
  { name: 'AZURE_STORAGE_ACCOUNT', value: storageAccountName }
  { name: 'AZURE_CLIENT_ID', value: identityClientId }
  { name: 'FIREBASE_PROJECT_ID', value: firebaseProjectId }
  { name: 'ADMIN_API_ENABLED', value: 'true' }
  { name: 'DATABASE_URL', value: '@Microsoft.KeyVault(SecretUri=${databaseUrlSecretUri})' }
  { name: 'JWT_SECRET', value: '@Microsoft.KeyVault(SecretUri=${jwtSecretUri})' }
  { name: 'ADMIN_JWT_SECRET', value: '@Microsoft.KeyVault(SecretUri=${adminJwtSecretUri})' }
]

// ---------------------------------------------------------------------------
// Plan
// ---------------------------------------------------------------------------

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${baseName}-plan'
  location: location
  tags: tags
  sku: {
    name: appServicePlanSku
  }
  kind: 'linux'
  // `reserved: true` is what makes a plan Linux. Without it the plan is
  // Windows and every container deployment onto it fails confusingly.
  properties: {
    reserved: true
  }
}

// ---------------------------------------------------------------------------
// The API
// ---------------------------------------------------------------------------

resource api 'Microsoft.Web/sites@2023-12-01' = {
  name: '${baseName}-api'
  location: location
  tags: tags
  kind: 'app,linux,container'
  identity: identityConfig
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    // Which identity resolves @Microsoft.KeyVault references. Defaults to the
    // system-assigned identity, which this app does not have.
    keyVaultReferenceIdentity: identityResourceId
    siteConfig: {
      linuxFxVersion: 'DOCKER|${registryLoginServer}/dopax-backend:${imageTag}'
      acrUseManagedIdentityCreds: true
      acrUserManagedIdentityID: identityClientId
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      // /healthz rather than /readyz, deliberately. /readyz reports bootstrap
      // state, and an instance that is up but pending the R5 import should not
      // be restarted in a loop by the platform for saying so.
      healthCheckPath: '/healthz'
      appSettings: backendAppSettings
    }
  }
}

// ---------------------------------------------------------------------------
// The staff console
// ---------------------------------------------------------------------------

resource admin 'Microsoft.Web/sites@2023-12-01' = {
  name: '${baseName}-admin'
  location: location
  tags: tags
  kind: 'app,linux,container'
  identity: identityConfig
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    keyVaultReferenceIdentity: identityResourceId
    siteConfig: {
      linuxFxVersion: 'DOCKER|${registryLoginServer}/dopax-admin:${imageTag}'
      acrUseManagedIdentityCreds: true
      acrUserManagedIdentityID: identityClientId
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      appSettings: [
        { name: 'NODE_ENV', value: 'production' }
        { name: 'PORT', value: '3100' }
        { name: 'WEBSITES_PORT', value: '3100' }
        { name: 'HOSTNAME', value: '0.0.0.0' }
        // Container Apps gave the two apps a shared internal network. App
        // Service does not, so staff traffic to the backend leaves over the
        // public endpoint. It is TLS the whole way and the API authenticates
        // every admin request, but it is a real difference from the previous
        // design. Closing it means VNet integration plus a private endpoint,
        // which is already item 1 in the hardening backlog.
        { name: 'BACKEND_URL', value: 'https://${api.properties.defaultHostName}' }
      ]
    }
  }
}

// ---------------------------------------------------------------------------
// Diagnostics
// ---------------------------------------------------------------------------
//
// Container Apps shipped console output to Log Analytics as part of the
// environment. App Service needs it asked for explicitly, per app.

resource apiDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-log-analytics'
  scope: api
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
      }
    ]
  }
}

resource adminDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-log-analytics'
  scope: admin
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output apiUrl string = 'https://${api.properties.defaultHostName}'
output adminUrl string = 'https://${admin.properties.defaultHostName}'
output apiName string = api.name
output adminName string = admin.name
output planName string = plan.name

// Outbound addresses for the PostgreSQL firewall. App Service outbound IPs are
// stable for the lifetime of the plan, so these can replace the broad
// "Azure services" sentinel rule the data layer currently uses.
output apiOutboundIpAddresses string = api.properties.possibleOutboundIpAddresses
