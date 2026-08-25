// DopaX production infrastructure — Israel Central.
//
// Israel Central keeps participant health data in-country, which is the same
// reasoning that drove the earlier region choice. Two consequences are baked in
// below and are not accidents:
//
//   1. There is no Archive blob tier in this region. Cold LRS at
//      $0.0045/GB-month is the coldest floor available, so the lifecycle policy
//      ends at Cold rather than Archive.
//   2. Availability-zone support varies. `postgresHighAvailability` defaults to
//      off; turn it on only after confirming zone redundancy is offered on your
//      subscription, because it doubles the database bill.
//
// Deploy with infra/deploy.sh, which is the supported path. See infra/README.md.
//
// This template is the data layer plus the Jenkins build server: everything
// that does not depend on the compute platform. The API and staff console live
// in infra/apps.bicep, which targets App Service because Container Apps is not
// offered in this region. Splitting them is not tidiness — the two have
// different lifecycles. The data layer is created once and then left alone;
// the application layer is redeployed on every release.

targetScope = 'resourceGroup'

@description('Azure region. Israel Central keeps participant data in-country.')
param location string = 'israelcentral'

@description('Short prefix for every resource name. Lowercase alphanumeric.')
@minLength(3)
@maxLength(10)
param namePrefix string = 'dopax'

@description('Deployment environment. Part of resource names and tags.')
@allowed(['prod', 'staging'])
param environment string = 'prod'

@description('PostgreSQL administrator login. Cannot be azure_superuser, admin, or root.')
param postgresAdminLogin string = 'dopaxadmin'

@description('PostgreSQL administrator password.')
@secure()
@minLength(16)
param postgresAdminPassword string

@description('Signing secret for participant access and refresh tokens.')
@secure()
@minLength(32)
param jwtSecret string

@description('Signing secret for staff console sessions. Must differ from jwtSecret.')
@secure()
@minLength(32)
param adminJwtSecret string

// firebaseProjectId, legacyDriveFolderId and bothArch used to live here. They
// configure the running application rather than the data it sits on, so they
// moved to infra/apps.bicep with the apps that read them.

@description('''
PostgreSQL compute SKU. B1ms (1 vCPU / 2 GB, $0.022/hr) is the default because
the write load is metadata only: raw ZIPs go to blob storage, so at study scale
this server takes roughly 30 rows per participant-day. B2s costs 4x for headroom
nothing is asking for yet.

Scale up when either of these is true, both reversible with a restart:
  - the R5 bootstrap import is IOPS-bound and you want it to finish sooner
  - enrolment passes a few hundred participants, or admin queries start queueing
''')
@allowed(['Standard_B1ms', 'Standard_B2s', 'Standard_D2ds_v5'])
param postgresSku string = 'Standard_B1ms'

@description('''
Provisioned database storage in GB, billed per GB provisioned rather than per GB
used, so this starts at the 32 GB floor. autoGrow is on and storage can never
shrink, which is the other reason not to over-provision at the start.

Note that Burstable IOPS scale with size (32 GB ~ 120 IOPS, 64 GB ~ 240). If the
bootstrap import is slow, raising this raises IOPS with it.
''')
@minValue(32)
param postgresStorageGb int = 32

@description('''
Zone-redundant database. Doubles compute and storage cost.

Israel Central does offer this: the capability API reports ZoneRedundantHa as
Enabled with zones 1, 2 and 3 on every Burstable SKU. It stays off by default
on cost grounds, not availability grounds. Note that geo-redundant backup is a
separate capability and is genuinely not offered in this region.
''')
param postgresHighAvailability bool = false

@description('Days before a raw upload moves from Hot to Cool.')
param daysToCool int = 30

@description('Days before a raw upload moves from Cool to Cold.')
param daysToCold int = 90

// ---------------------------------------------------------------------------
// Build server
// ---------------------------------------------------------------------------

@description('Whether to create the Jenkins build server. See infra/ci.bicep.')
param deployJenkins bool = true

// No @minLength here, even though a short password would be bad. The default
// has to be empty so the template still compiles with deployJenkins=false, and
// Bicep rejects a default that violates its own constraint. infra/deploy.sh
// generates 24 characters and is the only supported way in.
@description('Initial Jenkins administrator password. Stored in Key Vault, never output.')
@secure()
param jenkinsAdminPassword string = ''

@description('''
Source addresses allowed to reach Jenkins on 443 and 22, in CIDR form.

There is no default and an empty list denies everyone, deliberately. This box
holds push rights to the registry that serves participant data, so exposing it
to 0.0.0.0/0 has to be something someone types on purpose. infra/deploy.sh
detects the operator address and passes it here.
''')
param jenkinsAllowedSourceIps array = []

@description('SSH public key for the build server. Password authentication is disabled.')
param jenkinsSshPublicKey string = ''

@description('''
Build server size. 2 vCPU / 4 GB is the floor for a JVM plus a workspace
checkout, and it is enough here because images are built in Container Registry
rather than on this machine. The regional vCPU quota is 4 in total across every
family, so this takes half of it and nothing else in the stack is VM-backed.

Not Standard_B2s, which the access request originally specified. The entire
first-generation B series is capacity-restricted in Israel Central and fails
preflight with SkuNotAvailable — the size is listed for the region but cannot
actually be allocated. Standard_B2ls_v2 is the same 2 vCPU / 4 GB at $34.97 a
month against B2s at $35.04, so this is a rename rather than a trade-off.
Standard_B2als_v2 is the AMD equivalent at $31.32 if the saving matters more
than staying on Intel.
''')
param jenkinsVmSize string = 'Standard_B2ls_v2'

// ---------------------------------------------------------------------------
// Naming
// ---------------------------------------------------------------------------

var suffix = uniqueString(resourceGroup().id)
var baseName = '${namePrefix}-${environment}'
var tags = {
  project: 'dopax'
  environment: environment
  dataClassification: 'phi'
  managedBy: 'bicep'
}

// Storage, registry, and vault names are globally unique and alphanumeric only.
var storageName = take('${namePrefix}${environment}${suffix}', 24)
var registryName = take('${namePrefix}${environment}${suffix}', 50)
var keyVaultName = take('${namePrefix}-${environment}-${suffix}', 24)
var postgresName = '${baseName}-pg-${suffix}'

var uploadsContainerName = 'uploads'
var databaseName = 'dopax'

// Built-in role definition IDs.
//
// Both of these are role assignments, which means they need
// Microsoft.Authorization/roleAssignments/write — the one thing the built-in
// Contributor role excludes. Key Vault used to be a third entry here and is now
// granted through a vault access policy instead, because access policies live
// under Microsoft.KeyVault and a Contributor can therefore create them. See the
// vault below.
var acrPullRole = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var blobContributorRole = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var contributorRole = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
// Jenkins deploys App Service (apps.bicep) but must not become Contributor on
// the resource group: that role includes Microsoft.KeyVault/vaults/write, which
// would let a pipeline add itself to the application vault's access policy.
var websiteContributorRole = 'de139f84-1756-47ae-9be6-808fbbe84772'
var webPlanContributorRole = '2cc479cb-7b4d-49a8-b449-8c00fd0f0a4b'
var monitoringContributorRole = '749f88d5-cbae-40b8-bcfc-e573ddc772fa'

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

// One user-assigned identity for every workload. It pulls images, reads
// secrets, and writes blobs, so no connection string or registry password is
// ever stored in app configuration.
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${baseName}-id'
  location: location
  tags: tags
}

// A second identity for the build server, deliberately separate from the one
// above. Jenkins needs to push images and read the vault; it has no business
// holding Storage Blob Data Contributor on participant uploads. Sharing one
// identity would give a machine that runs arbitrary pipeline code standing
// read-write access to the archive.
//
// It is declared here rather than inside the ci module because the vault's
// access policy list needs its principal ID, and the module needs the vault.
// Creating it at this level breaks what would otherwise be a cycle.
resource ciIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (deployJenkins) {
  name: '${baseName}-ci-id'
  location: location
  tags: tags
}

// ---------------------------------------------------------------------------
// Observability
// ---------------------------------------------------------------------------

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${baseName}-logs'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    // Analytics ingestion is $3.29/GB here, so the cap is the difference between
    // a runaway log loop dropping logs and it arriving as an invoice. At 0.5 GB a
    // day the worst case is bounded near $50/month; this app writes a small
    // fraction of that, and the two workers log per run rather than per request.
    workspaceCapping: { dailyQuotaGb: json('0.5') }
  }
}

// The Basic-tier table that used to live here targeted ContainerAppConsoleLogs,
// which only exists once a Container Apps environment is linked to the
// workspace. The App Service equivalent is AppServiceConsoleLogs and it also
// supports the Basic plan, so the same saving is available — but the table is
// only created once diagnostic settings start writing to it, which happens in
// apps.bicep. It belongs with phase 2, not here.

// ---------------------------------------------------------------------------
// Container registry
// ---------------------------------------------------------------------------

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: {
    // Managed-identity pulls only. An admin user would be a shared credential
    // with no audit trail.
    adminUserEnabled: false
  }
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, identity.id, acrPullRole)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRole)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Object storage — the raw ZIP archive
// ---------------------------------------------------------------------------

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    // Entra ID only. Shared keys are a standing credential that cannot be
    // attributed to a person after the fact.
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Enabled'
    encryption: {
      keySource: 'Microsoft.Storage'
      services: {
        blob: { enabled: true }
        file: { enabled: true }
      }
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    // Once phones start expiring their local copies, this container holds the
    // only copy of irreplaceable study data. Versioning plus soft delete means
    // a bad deploy overwriting a blob is recoverable.
    isVersioningEnabled: true
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 30
    }
  }
}

resource uploads 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: uploadsContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource lifecycle 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          name: 'age-raw-uploads'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['${uploadsContainerName}/']
            }
            actions: {
              // No delete action anywhere in this policy, deliberately. Study
              // data is retained indefinitely; tiering is a cost control, not
              // a retention policy. Cold is the floor because Israel Central
              // has no Archive tier.
              baseBlob: {
                tierToCool: { daysAfterModificationGreaterThan: daysToCool }
                tierToCold: { daysAfterModificationGreaterThan: daysToCold }
              }
              version: {
                tierToCool: { daysAfterCreationGreaterThan: daysToCool }
                tierToCold: { daysAfterCreationGreaterThan: daysToCold }
              }
            }
          }
        }
      ]
    }
  }
}

resource blobAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, identity.id, blobContributorRole)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobContributorRole)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// PostgreSQL — the system of record
// ---------------------------------------------------------------------------

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: postgresName
  location: location
  tags: tags
  sku: {
    name: postgresSku
    tier: startsWith(postgresSku, 'Standard_B') ? 'Burstable' : 'GeneralPurpose'
  }
  properties: {
    version: '16'
    administratorLogin: postgresAdminLogin
    administratorLoginPassword: postgresAdminPassword
    storage: {
      storageSizeGB: postgresStorageGb
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: 35
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: postgresHighAvailability ? 'ZoneRedundant' : 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: postgres
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// The 0.0.0.0-0.0.0.0 range is Azure's sentinel for "Azure services only", not
// a wildcard. Consumption Container Apps have no stable outbound IP to pin, so
// this is the narrowest rule available without moving to a VNet-integrated
// environment. See the hardening section in infra/README.md.
resource allowAzureServices 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: postgres
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// ---------------------------------------------------------------------------
// Secrets
// ---------------------------------------------------------------------------

// Access policies rather than RBAC, deliberately.
//
// RBAC is the modern choice and would be the default preference, but granting
// `Key Vault Secrets User` is a role assignment, and a Contributor cannot create
// role assignments. An access policy achieves the same least-privilege result —
// this identity can read secret values and do nothing else — through
// Microsoft.KeyVault/vaults/write, which Contributor does have.
//
// This is a substitution, not a compromise: the effective permission granted is
// identical. Reversing it later means setting enableRbacAuthorization to true and
// restoring the roleAssignment, which requires whoever holds Owner.
//
// Note that the policy list is declared inline, so it is authoritative: a
// deployment replaces the whole list rather than appending to it. Anything added
// by hand in the portal will be removed on the next deploy.
resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
    // The build server is deliberately absent from this list.
    //
    // A vault access policy grants verbs over the whole vault, not over
    // individual secrets: there is no way to say "get, but only
    // jenkins-admin-password". Adding the CI identity here to let cloud-init
    // fetch one password would also let any Jenkins job read jwt-secret, and
    // whoever holds that can mint a token for any participant. Guardrail R1
    // treats that secret as the thing you never touch.
    //
    // So the build server gets its own vault instead, in infra/ci.bicep. Two
    // vaults cost nothing extra and the boundary is then structural rather
    // than a rule someone has to remember.
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: identity.properties.principalId
        // `get` only. The workloads read three secrets at start and never
        // write, list, or delete. Writing them is a control-plane operation
        // the deployment does through ARM, which needs no data-plane
        // permission here.
        permissions: {
          secrets: ['get']
        }
      }
    ]
  }
}

var databaseUrl = 'postgresql://${postgresAdminLogin}:${uriComponent(postgresAdminPassword)}@${postgres.properties.fullyQualifiedDomainName}:5432/${databaseName}?sslmode=require'

resource databaseUrlSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: vault
  name: 'database-url'
  properties: {
    value: databaseUrl
  }
}

resource jwtSecretEntry 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: vault
  name: 'jwt-secret'
  properties: {
    value: jwtSecret
  }
}

resource adminJwtSecretEntry 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: vault
  name: 'admin-jwt-secret'
  properties: {
    value: adminJwtSecret
  }
}

// ---------------------------------------------------------------------------
// Build server
// ---------------------------------------------------------------------------

// Contributor, scoped to the registry resource and nothing wider.
//
// AcrPush on its own is not enough. `az acr build` also needs
// registries/scheduleRun/action and registries/listBuildSourceUploadUrl/action,
// which no built-in ACR data role carries. The alternatives were a custom role
// definition or this; Contributor at this scope can at worst destroy a registry
// that is rebuilt by rerunning the deployment, so the blast radius is a
// rebuildable artifact store rather than anything holding participant data.
resource ciRegistryAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployJenkins) {
  name: guid(registry.id, '${baseName}-ci-id', contributorRole)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRole)
    principalId: ciIdentity!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Enough to apply infra/apps.bicep (plan + sites + diagnostic settings) and
// nothing else. Website Contributor includes Microsoft.Resources/deployments/*,
// so the pipeline can create the `apps` deployment without being able to read
// jwt-secret or Storage Blob Data.
resource ciWebsiteAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployJenkins) {
  name: guid(resourceGroup().id, '${baseName}-ci-id', websiteContributorRole)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', websiteContributorRole)
    principalId: ciIdentity!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource ciWebPlanAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployJenkins) {
  name: guid(resourceGroup().id, '${baseName}-ci-id', webPlanContributorRole)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', webPlanContributorRole)
    principalId: ciIdentity!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource ciMonitoringAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployJenkins) {
  name: guid(resourceGroup().id, '${baseName}-ci-id', monitoringContributorRole)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringContributorRole)
    principalId: ciIdentity!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

module ci 'ci.bicep' = if (deployJenkins) {
  name: 'ci'
  params: {
    location: location
    baseName: baseName
    nameSuffix: suffix
    tags: tags
    ciIdentityResourceId: ciIdentity!.id
    ciIdentityPrincipalId: ciIdentity!.properties.principalId
    ciIdentityClientId: ciIdentity!.properties.clientId
    adminPassword: jenkinsAdminPassword
    allowedSourceIps: jenkinsAllowedSourceIps
    sshPublicKey: jenkinsSshPublicKey
    vmSize: jenkinsVmSize
  }
}

// Jenkins reaches PostgreSQL from its static address, so a pipeline can run
// db:migrate. Note this is reachability, not an instruction: no pipeline runs
// the R5 bootstrap, which guardrail R5 keeps as a deliberate, observed step.
//
// dependsOn is load-bearing rather than decorative. PostgreSQL Flexible Server
// serialises firewall changes, and two rules created in parallel fail the
// second one with a conflicting-operation error.
resource allowJenkins 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = if (deployJenkins) {
  parent: postgres
  name: 'AllowJenkins'
  properties: {
    startIpAddress: ci!.outputs.publicIpAddress
    endIpAddress: ci!.outputs.publicIpAddress
  }
  dependsOn: [allowAzureServices]
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output registryLoginServer string = registry.properties.loginServer
output registryName string = registry.name
output postgresFqdn string = postgres.properties.fullyQualifiedDomainName
output storageAccountName string = storage.name
output uploadsContainerName string = uploadsContainerName
output keyVaultName string = vault.name
output logAnalyticsWorkspaceId string = logs.id
output resourceGroupName string = resourceGroup().name

// The workload identity, consumed by infra/apps.bicep in phase 2.
output identityResourceId string = identity.id
output identityClientId string = identity.properties.clientId

// Secret URIs rather than secret values. App Service resolves these at start
// through the identity above, so no secret is ever written into application
// configuration or into a deployment output.
output databaseUrlSecretUri string = databaseUrlSecret.properties.secretUri
output jwtSecretUri string = jwtSecretEntry.properties.secretUri
output adminJwtSecretUri string = adminJwtSecretEntry.properties.secretUri

// Build server. The admin password is deliberately not here: it lives in the
// CI vault and is read with `az keyvault secret show`.
output jenkinsUrl string = deployJenkins ? 'https://${ci!.outputs.fqdn}' : ''
output jenkinsPublicIp string = deployJenkins ? ci!.outputs.publicIpAddress : ''
output jenkinsVaultName string = deployJenkins ? ci!.outputs.vaultName : ''
output ciIdentityClientId string = deployJenkins ? ciIdentity!.properties.clientId : ''
