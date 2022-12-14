#!/usr/bin/env bash

set -o errexit
set -o pipefail

function usage() {
    echo "Usage:"
    echo "  $0 apply|delete [app] [environment]"
    printf "\n"
    echo "Flags:"
    printf "  --help\t\tPrints usage\n"
    printf "  --dry-run string\tDisplay what will be migrated\n"
    printf "\n"
    echo "Examples:"
    printf "  %s apply config-service dev\n" "$0"
    printf "  %s delete config-service dev\n" "$0"
    printf "  %s apply config-service prod\n" "$0"
    printf "  %s apply config-service dev --dry-run\n" "$0"
    printf "\n"
}

function create_registry_secret() {
  local server="${1}"
  local username="${2}"
  local password="${3}"
  local config_file="${4}"

  if [[ -z $username ]]; then
      echo -n "Enter registry username for $server: "
      read -r username
      echo
  fi

  if [[ -z $password ]]; then
      echo -n "Enter registry password for $server: "
      read -rs password
      echo
  fi

  cat > "${config_file}" <<EOF
{
	"auths": {
		"${server}": {
			"username": "${username}",
			"password": "${password}"
		}
	}
}
EOF
}

function create_git_ssh_key() {
  local name="${1}"
  local path="${2}"
  local private_key="${3}"
  local known_hosts="${4}"
  local namespace="${5}"

  # if kubectl get secret "$name" --namespace="$namespace" &>/dev/null; then
  #   kubectl delete secret "$name" --namespace="$namespace"
  # fi

  kubectl create secret generic "$name" \
      --namespace="$namespace" \
      --from-file=privateKey="${path}/${private_key}" \
      --from-file=known_hosts="${path}/${known_hosts}" \
      --dry-run=client -oyaml > "${path}/secret.yaml"
}

if [[ -z $1 || $1 == "-h" || $1 == "--help" ]]; then
  usage
  exit
fi

ACTION=$1
APP=$2
ENV=$3

if [[ ! "$ACTION" =~ apply|delete ]]; then
  echo "Action 'apply' or 'delete' is required: "
  usage
  exit 1
fi

shift;shift;shift

if [[ -z "${APP}" ]]; then
  echo "Enter app name: "
  read -r APP;
fi

if [[ -z "${ENV}" ]]; then
  echo "Enter environment name: "
  read -r ENV;
fi

while [ "$1" != "" ]; do
    param=$(echo "$1" | awk -F= '{print $1}')
    case $param in
      -h | --help)
        usage
        exit
        ;;
      --dry-run)
        DRY_RUN=true
        ;;
      *)
        echo ""
        echo "Invalid option: [$param]"
        echo ""
        usage
        exit 1
        ;;
    esac
    shift
done

if [[ ! -d apps/$APP ]]; then
    echo "App '${APP}' does not exist in folder: apps/${APP}"
fi

if [[ ! -d apps/$APP/overlays/$ENV ]]; then
    echo "Environment for '${APP}' does not exist in folder: apps/${APP}/overlays/${ENV}"
fi

if [ ! -f "apps/${APP}/overlays/${ENV}/config_server_deploy_key.rsa" ]; then
  ssh-keygen -m PEM -t rsa -b 4096 -f "apps/${APP}/overlays/${ENV}/config_server_deploy_key.rsa"
  printf "Copy your deploy key from %s into github\n" "apps/${APP}/overlays/${ENV}/config_server_deploy_key.rsa.pub"
  read -rp "Press return when finished." -n 1 -r
fi

[ ! -f "apps/${APP}/overlays/${ENV}/known_hosts" ] && ssh-keyscan github.com > "apps/${APP}/overlays/${ENV}/known_hosts" 2>&1

create_registry_secret "${REGISTRY_SERVER}" "${REGISTRY_USERNAME}" "${REGISTRY_PASSWORD}" "apps/${APP}/overlays/${ENV}/dockerconfig.json"
create_git_ssh_key "configserver-git" "apps/${APP}/overlays/${ENV}" "config_server_deploy_key.rsa" "known_hosts" "${ENV}"

if [[ $DRY_RUN ]]; then
    # kustomize build "apps/${APP}/overlays/${ENV}/"
    kubectl --dry-run=client apply -k "apps/${APP}/overlays/${ENV}/" -oyaml
    exit 0
fi

if [[ $ACTION == delete ]]; then
  kubectl delete -k "apps/${APP}/overlays/${ENV}/"
fi

if [[ $ACTION == apply ]]; then
  kubectl apply -k "apps/${APP}/overlays/${ENV}/"
fi
