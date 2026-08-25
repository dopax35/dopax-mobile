// DopaX build server — Jenkins on a single Linux VM, Israel Central.
//
// Deployments run from here rather than from a hosted CI service, so there is
// no service principal secret and no federated credential anywhere: the VM
// authenticates with `az login --identity` against a user-assigned identity
// created by the caller.
//
// Two decisions worth reading before changing anything here.
//
// **No Docker on this box.** Images build server-side with `az acr build`.
// That removes the arm64-versus-amd64 trap that catches every Apple Silicon
// laptop pushing to Container Registry, keeps a 4 GB VM from having to build a
// Next.js image locally, and means the disk holds build history instead of a
// layer cache.
//
// **A second Key Vault, not the main one.** A vault access policy grants verbs
// across the whole vault, so letting this machine read its own admin password
// out of the main vault would also let any pipeline read jwt-secret. Vaults are
// free; the isolation is not negotiable.

targetScope = 'resourceGroup'

@description('Azure region. Must match the data layer.')
param location string

@description('Resource name prefix, e.g. dopax-prod.')
param baseName string

@description('Deterministic suffix shared with the data layer, for globally unique names.')
param nameSuffix string

@description('Tags applied to every resource.')
param tags object

@description('Resource ID of the CI managed identity, created by the caller.')
param ciIdentityResourceId string

@description('Principal ID of the CI managed identity.')
param ciIdentityPrincipalId string

@description('Client ID of the CI managed identity. cloud-init needs this form for az login.')
param ciIdentityClientId string

@description('Initial Jenkins administrator password. Written to the CI vault, never output.')
@secure()
param adminPassword string

@description('Source addresses allowed to reach Jenkins, in CIDR form. Empty denies everyone.')
param allowedSourceIps array

@description('SSH public key for the VM. Password authentication is disabled.')
param sshPublicKey string

@description('VM size. Standard_B2ls_v2 is 2 vCPU / 4 GB. See the note in main.bicep on why not B2s.')
param vmSize string = 'Standard_B2ls_v2'

@description('OS disk size in GB. Holds the Jenkins home directory and build history.')
@minValue(32)
param osDiskSizeGb int = 64

@description('Local administrator account on the VM.')
param adminUsername string = 'dopaxadmin'

@description('VNet address space. Sized to leave room for the hardening backlog.')
param vnetAddressPrefix string = '10.20.0.0/16'

@description('Subnet holding the build server.')
param ciSubnetPrefix string = '10.20.1.0/24'

// ---------------------------------------------------------------------------
// Naming
// ---------------------------------------------------------------------------

var vmName = '${baseName}-ci'
var dnsLabel = '${baseName}-ci-${nameSuffix}'
var jenkinsFqdn = '${dnsLabel}.${location}.cloudapp.azure.com'
var ciVaultName = take('${baseName}-ci-${nameSuffix}', 24)
var adminPasswordSecretName = 'jenkins-admin-password'

// An address that cannot appear as a real source, so an empty allowlist fails
// closed rather than failing to deploy. Reaching Jenkins then requires someone
// to add their address on purpose, which is the intended friction for a machine
// holding push rights to the registry.
var effectiveSourceIps = empty(allowedSourceIps) ? ['255.255.255.255/32'] : allowedSourceIps

// ---------------------------------------------------------------------------
// Secrets
// ---------------------------------------------------------------------------

resource ciVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: ciVaultName
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
    softDeleteRetentionInDays: 7
    // Purge protection is deliberately off here, unlike the main vault. This
    // holds one recoverable credential rather than anything protecting
    // participant data, and leaving it off means tearing the build server down
    // and rebuilding it does not block the name for 90 days.
    publicNetworkAccess: 'Enabled'
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: ciIdentityPrincipalId
        permissions: {
          secrets: ['get']
        }
      }
    ]
  }
}

resource adminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: ciVault
  name: adminPasswordSecretName
  properties: {
    value: adminPassword
  }
}

// ---------------------------------------------------------------------------
// Network
// ---------------------------------------------------------------------------

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${baseName}-ci-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-https-from-allowlist'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefixes: effectiveSourceIps
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'allow-ssh-from-allowlist'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefixes: effectiveSourceIps
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        // Belt and braces. The platform's own DenyAllInbound sits at 65500 and
        // would cover this, but an explicit rule means a later addition at a
        // careless priority cannot silently open the box.
        name: 'deny-all-inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// Subnets are declared inline rather than as child resources on purpose: a
// separate Microsoft.Network/virtualNetworks/subnets resource races with the
// parent VNet on redeploy and intermittently wipes sibling subnets.
//
// 10.20.2.0/24, 10.20.3.0/24 and 10.20.4.0/24 are left unallocated for App
// Service regional integration, private endpoints, and Container Instances
// respectively. Reserving the space now means the hardening backlog does not
// have to re-address anything later.
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: '${baseName}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: 'snet-ci'
        properties: {
          addressPrefix: ciSubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: '${baseName}-ci-ip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    // Static, because the address is written into a PostgreSQL firewall rule.
    // A dynamic address would silently lock Jenkins out of the database on the
    // first deallocate.
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: dnsLabel
    }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: '${baseName}-ci-nic'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// The build server
// ---------------------------------------------------------------------------

// cloud-init is templated here rather than parameterised at runtime so the
// rendered file is a deployment artifact and can be diffed.
var cloudInit = replace(
  replace(
    replace(
      replace(loadTextContent('cloud-init/jenkins.yaml'), '__VAULT_NAME__', ciVaultName),
      '__CLIENT_ID__',
      ciIdentityClientId
    ),
    '__JENKINS_FQDN__',
    jenkinsFqdn
  ),
  '__SECRET_NAME__',
  adminPasswordSecretName
)

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${ciIdentityResourceId}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        name: '${vmName}-osdisk'
        createOption: 'FromImage'
        diskSizeGB: osDiskSizeGb
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        deleteOption: 'Delete'
      }
    }
    osProfile: {
      computerName: 'dopax-ci'
      adminUsername: adminUsername
      customData: base64(cloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
        patchSettings: {
          patchMode: 'AutomaticByPlatform'
          assessmentMode: 'AutomaticByPlatform'
        }
      }
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      // Serial console output. This is how you find out why cloud-init failed
      // on a box you cannot SSH into yet.
      bootDiagnostics: {
        enabled: true
      }
    }
  }
  // The password has to exist in the vault before first boot, because
  // cloud-init reads it there rather than receiving it in customData — anyone
  // with VM read access can fetch customData back out.
  dependsOn: [adminPasswordSecret]
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output publicIpAddress string = publicIp.properties.ipAddress
output fqdn string = jenkinsFqdn
output vmName string = vm.name
output vaultName string = ciVault.name
output adminUsername string = adminUsername
output secretName string = adminPasswordSecretName
