#!/usr/bin/env bash
#
# Create or update the "dopax-deploy" Jenkins job and a read-only GitHub
# deploy key for the jenkins user. Intended to run on the build VM.
#
#   sudo bash infra/jenkins/install-deploy-job.sh
#
set -euo pipefail

JOB_NAME='dopax-deploy'
JOB_XML="${1:-}"
JENKINS_HOME="${JENKINS_HOME:-/var/lib/jenkins}"
SSH_DIR="${JENKINS_HOME}/.ssh"
CLI_JAR='/opt/dopax/jenkins-cli.jar'

if [[ -z "${JOB_XML}" ]]; then
  echo "usage: $0 /path/to/dopax-deploy-job.xml" >&2
  exit 2
fi
[[ -f "${JOB_XML}" ]] || { echo "error: missing ${JOB_XML}" >&2; exit 1; }

if [[ ! -f /etc/jenkins/admin.env ]]; then
  echo "error: /etc/jenkins/admin.env is missing; cloud-init has not finished" >&2
  exit 1
fi
# shellcheck disable=SC1091
source /etc/jenkins/admin.env
: "${JENKINS_ADMIN_PASSWORD:?}"

install -d -m 0700 -o jenkins -g jenkins "${SSH_DIR}"

if [[ ! -f "${SSH_DIR}/id_ed25519" ]]; then
  sudo -u jenkins ssh-keygen -t ed25519 -N '' -f "${SSH_DIR}/id_ed25519" -C 'dopax-prod-ci-jenkins'
fi

if [[ ! -f "${SSH_DIR}/known_hosts" ]] || ! grep -q github.com "${SSH_DIR}/known_hosts"; then
  ssh-keyscan -t ed25519,rsa github.com >> "${SSH_DIR}/known_hosts"
  chown jenkins:jenkins "${SSH_DIR}/known_hosts"
  chmod 0644 "${SSH_DIR}/known_hosts"
fi

cat > "${SSH_DIR}/config" <<'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
EOF
chown jenkins:jenkins "${SSH_DIR}/config"
chmod 0600 "${SSH_DIR}/config"

curl -fsS http://127.0.0.1:8080/jnlpJars/jenkins-cli.jar -o "${CLI_JAR}"

cli() {
  java -jar "${CLI_JAR}" -s http://127.0.0.1:8080 -auth "admin:${JENKINS_ADMIN_PASSWORD}" "$@"
}

if cli get-job "${JOB_NAME}" >/dev/null 2>&1; then
  cli update-job "${JOB_NAME}" < "${JOB_XML}"
  echo "updated Jenkins job ${JOB_NAME}"
else
  cli create-job "${JOB_NAME}" < "${JOB_XML}"
  echo "created Jenkins job ${JOB_NAME}"
fi

echo
echo "Add this public key to GitHub as a read-only deploy key on covivi243/dopax-mobile:"
echo
cat "${SSH_DIR}/id_ed25519.pub"
echo
