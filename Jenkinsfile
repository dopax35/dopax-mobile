// DopaX server deploy. Runs on the Azure build VM.
//
// Images are built in the registry with `az acr build` — there is no Docker
// daemon on this box. Authentication is `az login --identity`; there is no
// service principal secret.
//
// This job does not run the R5 bootstrap. That stays a separate, observed
// step. It also does not apply main.bicep, so it never needs JWT_SECRET or
// the PostgreSQL admin password.

pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  parameters {
    choice(
      name: 'ENVIRONMENT',
      choices: ['prod', 'staging'],
      description: 'Target environment. Names the resource group dopax-<env>-rg.'
    )
    string(
      name: 'IMAGE_TAG',
      defaultValue: '',
      description: 'Image tag. Leave empty to use the git short SHA.'
    )
    booleanParam(
      name: 'DEPLOY_APPS',
      defaultValue: true,
      description: 'After pushing images, deploy the API and staff console.'
    )
    string(
      name: 'LEGACY_DRIVE_FOLDER_ID',
      defaultValue: '',
      description: 'Read-only Drive folder for the legacy corpus. Optional.'
    )
    string(
      name: 'NEXT_PUBLIC_FIREBASE_API_KEY',
      defaultValue: '',
      description: 'Inlined into the admin client bundle at build time. Public identifier, not a credential.'
    )
  }

  environment {
    AZURE_LOCATION = 'israelcentral'
  }

  stages {
    stage('Azure login') {
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail
          az login --identity --output none
          az account show --query '{name:name, id:id, user:user.name}' -o json
        '''
      }
    }

    stage('Resolve names') {
      steps {
        script {
          env.DOPAX_ENVIRONMENT = params.ENVIRONMENT
          env.RESOURCE_GROUP = "dopax-${params.ENVIRONMENT}-rg"
          env.IMAGE_TAG = params.IMAGE_TAG?.trim() ? params.IMAGE_TAG.trim() : sh(
            script: 'git rev-parse --short HEAD',
            returnStdout: true
          ).trim()
        }
        sh '''#!/usr/bin/env bash
          set -euo pipefail
          REGISTRY_SERVER="$(az deployment group show \
            --resource-group "${RESOURCE_GROUP}" --name main \
            --query properties.outputs.registryLoginServer.value -o tsv)"
          REGISTRY_NAME="$(az deployment group show \
            --resource-group "${RESOURCE_GROUP}" --name main \
            --query properties.outputs.registryName.value -o tsv)"
          echo "REGISTRY_SERVER=${REGISTRY_SERVER}" > "${WORKSPACE}/.dopax-deploy.env"
          echo "REGISTRY_NAME=${REGISTRY_NAME}" >> "${WORKSPACE}/.dopax-deploy.env"
          echo "Resolved ${REGISTRY_SERVER}  tag=${IMAGE_TAG}"
        '''
      }
    }

    stage('Build backend') {
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail
          # shellcheck disable=SC1091
          source "${WORKSPACE}/.dopax-deploy.env"
          az acr build \
            --registry "${REGISTRY_NAME}" \
            --platform linux/amd64 \
            --target runtime \
            --image "dopax-backend:${IMAGE_TAG}" \
            --image dopax-backend:latest \
            --file backend/Dockerfile \
            backend
        '''
      }
    }

    stage('Build backend release task') {
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail
          # shellcheck disable=SC1091
          source "${WORKSPACE}/.dopax-deploy.env"
          az acr build \
            --registry "${REGISTRY_NAME}" \
            --platform linux/amd64 \
            --target release \
            --image "dopax-backend-release:${IMAGE_TAG}" \
            --image dopax-backend-release:latest \
            --file backend/Dockerfile \
            backend
        '''
      }
    }

    stage('Build admin') {
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail
          # shellcheck disable=SC1091
          source "${WORKSPACE}/.dopax-deploy.env"
          az acr build \
            --registry "${REGISTRY_NAME}" \
            --platform linux/amd64 \
            --target runtime \
            --image "dopax-admin:${IMAGE_TAG}" \
            --image dopax-admin:latest \
            --build-arg "NEXT_PUBLIC_FIREBASE_API_KEY=${NEXT_PUBLIC_FIREBASE_API_KEY:-}" \
            --file admin/Dockerfile \
            admin
        '''
      }
    }

    stage('Deploy applications') {
      when { expression { return params.DEPLOY_APPS } }
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail
          # shellcheck disable=SC1091
          source "${WORKSPACE}/.dopax-deploy.env"

          output() {
            az deployment group show \
              --resource-group "${RESOURCE_GROUP}" --name main \
              --query "properties.outputs.${1}.value" -o tsv
          }

          az deployment group create \
            --resource-group "${RESOURCE_GROUP}" \
            --name apps \
            --template-file infra/apps.bicep \
            --parameters \
              location="${AZURE_LOCATION}" \
              environment="${DOPAX_ENVIRONMENT}" \
              imageTag="${IMAGE_TAG}" \
              registryLoginServer="${REGISTRY_SERVER}" \
              identityResourceId="$(output identityResourceId)" \
              identityClientId="$(output identityClientId)" \
              databaseUrlSecretUri="$(output databaseUrlSecretUri)" \
              jwtSecretUri="$(output jwtSecretUri)" \
              adminJwtSecretUri="$(output adminJwtSecretUri)" \
              storageAccountName="$(output storageAccountName)" \
              uploadsContainerName="$(output uploadsContainerName)" \
              logAnalyticsWorkspaceId="$(output logAnalyticsWorkspaceId)" \
              legacyDriveFolderId="${LEGACY_DRIVE_FOLDER_ID:-}" \
            --output none

          API="$(az deployment group show -g "${RESOURCE_GROUP}" -n apps \
            --query properties.outputs.apiUrl.value -o tsv)"
          ADMIN="$(az deployment group show -g "${RESOURCE_GROUP}" -n apps \
            --query properties.outputs.adminUrl.value -o tsv)"
          echo "API_URL=${API}" >> "${WORKSPACE}/.dopax-deploy.env"
          echo "ADMIN_URL=${ADMIN}" >> "${WORKSPACE}/.dopax-deploy.env"
          echo "API ${API}"
          echo "admin ${ADMIN}"
        '''
      }
    }

    stage('Verify') {
      when { expression { return params.DEPLOY_APPS } }
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail
          # shellcheck disable=SC1091
          source "${WORKSPACE}/.dopax-deploy.env"
          for attempt in $(seq 1 20); do
            if curl -fsS --max-time 10 "${API_URL}/healthz" > /dev/null; then
              echo "healthy after ${attempt} attempt(s)"
              curl -fsS "${API_URL}/readyz" || true
              echo
              exit 0
            fi
            sleep 15
          done
          echo "error: ${API_URL}/healthz never responded" >&2
          exit 1
        '''
      }
    }
  }

  post {
    always {
      sh 'rm -f "${WORKSPACE}/.dopax-deploy.env" || true'
    }
  }
}
