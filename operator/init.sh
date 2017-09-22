#!/bin/bash

#########################################################################################
#components default version
#########################################################################################
GRAFANA_DEFAULT_VERSION=4.5.1
PROMETHEUS_DEFAULT_VERSION=v2.0.0-beta.5
PROMETHEUS_OPERATOR_DEFAULT_VERSION=v0.12.0
ALERT_MANAGER_DEFAULT_VERSION=v0.8.0
NODE_EXPORTER_DEFAULT_VERSION=v0.14.0
KUBE_STATE_METRICS_DEFAULT_VERSION=v1.0.1

#########################################################################################
#environment configuration
#########################################################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
if [ -z "${KUBECONFIG}" ]; then
    export KUBECONFIG=~/.kube/config
fi

if [ -z "${NAMESPACE}" ]; then
    NAMESPACE=monitoring
fi

echo
echo -e "${BLUE}Creating ${ORANGE}'monitoring' ${BLUE}namespace."
tput sgr0
kubectl create namespace "$NAMESPACE"

kctl() {
    kubectl --namespace "$NAMESPACE" "$@"
}

###########################################################################################
#set components version
###########################################################################################
echo "${ORANGE}Setting components version"
tput sgr0

#Prometheus Operator
echo
read -p "Enter Prometheus Operator version [$PROMETHEUS_OPERATOR_DEFAULT_VERSION]: " PROMETHEUS_OPERATOR_VERSION
PROMETHEUS_OPERATOR_VERSION=${PROMETHEUS_OPERATOR_VERSION:-$PROMETHEUS_OPERATOR_DEFAULT_VERSION}

#Prometheus
echo
read -p "Enter Prometheus version [$PROMETHEUS_DEFAULT_VERSION]: " PROMETHEUS_VERSION
PROMETHEUS_VERSION=${PROMETHEUS_VERSION:-$PROMETHEUS_DEFAULT_VERSION}

#Grafana
echo
read -p "Enter Grafana version [$GRAFANA_DEFAULT_VERSION]: " GRAFANA_VERSION
GRAFANA_VERSION=${GRAFANA_VERSION:-$GRAFANA_DEFAULT_VERSION}

#Alertmanager
read -p "Enter Alert Manager version [$ALERT_MANAGER_DEFAULT_VERSION]: " ALERT_MANAGER_VERSION
ALERT_MANAGER_VERSION=${ALERT_MANAGER_VERSION:-$ALERT_MANAGER_DEFAULT_VERSION}

#Node Exporter
echo
read -p "Enter Node Exporter version [$NODE_EXPORTER_DEFAULT_VERSION]: " NODE_EXPORTER_VERSION
NODE_EXPORTER_VERSION=${NODE_EXPORTER_VERSION:-$NODE_EXPORTER_DEFAULT_VERSION}

#Kube State Metrics
echo
read -p "Enter Kube State Metrics version [$KUBE_STATE_METRICS_DEFAULT_VERSION]: " KUBE_STATE_METRICS_VERSION
KUBE_STATE_METRICS_VERSION=${KUBE_STATE_METRICS_VERSION:-$KUBE_STATE_METRICS_DEFAULT_VERSION}

#set prometheus operator version
sed -i -e 's/PROMETHEUS_OPERATOR_VERSION/'"$PROMETHEUS_OPERATOR_VERSION"'/g' manifests/prometheus-operator/prometheus-operator.yaml

#set prometheus version
sed -i -e 's/PROMETHEUS_VERSION/'"$PROMETHEUS_VERSION"'/g' manifests/prometheus-operator/prometheus-operator.yaml
sed -i -e 's/PROMETHEUS_VERSION/'"$PROMETHEUS_VERSION"'/g' manifests/prometheus/prometheus-k8s.yaml

#set grafana version
sed -i -e 's/GRAFANA_VERSION/'"$GRAFANA_VERSION"'/g' manifests/grafana/grafana.de.yaml

#set alertmanager version
sed -i -e 's/ALERT_MANAGER_VERSION/'"$ALERT_MANAGER_VERSION"'/g' manifests/alertmanager/alertmanager.yaml

#set node-exporter version
sed -i -e 's/NODE_EXPORTER_VERSION/'"$NODE_EXPORTER_VERSION"'/g' manifests/node-exporter/node-exporter.ds.yaml

#set node-exporter version
sed -i -e 's/KUBE_STATE_METRICS_VERSION/'"$KUBE_STATE_METRICS_VERSION"'/g' manifests/kube-state-metrics/kube-state-metrics.de.yaml

##########################################################################################################################################
#configure alert channels
##########################################################################################################################################
#SMTP
echo
echo -e "${BLUE}Do you want to set up an SMTP relay?"
tput sgr0
read -p "Y/N [N]: " use_smtp

#if so, fill out this form...
if [[ $use_smtp =~ ^([yY][eE][sS]|[yY])$ ]]; then
  #smtp smarthost
  read -p "SMTP smarthost: " smtp_smarthost
  #smtp from address
  read -p "SMTP from (user@domain.com): " smtp_from
  #smtp to address
  read -p "Email address to send alerts to (user@domain.com): " alert_email_address
  #smtp username
  read -p "SMTP auth username: " smtp_user
  #smtp password
  prompt="SMTP auth password: "
  while IFS= read -p "$prompt" -r -s -n 1 char
  do
      if [[ $char == $'\0' ]]
      then
          break
      fi
      prompt='*'
      smtp_password+="$char"
  done

  #update configmap with SMTP relay info
  sed -i -e 's/your_smtp_smarthost/'"$smtp_smarthost"'/g' assets/alertmanager.yaml
  sed -i -e 's/your_smtp_from/'"$smtp_from"'/g' assets/alertmanager.yaml
  sed -i -e 's/your_smtp_user/'"$smtp_user"'/g' assets/alertmanager.yaml
  sed -i -e 's,your_smtp_pass,'"$smtp_password"',g' assets/alertmanager.yaml
  sed -i -e 's/your_alert_email_address/'"$alert_email_address"'/g' assets/alertmanager.yaml
fi

#Do you want to set up slack?
echo
echo -e "${BLUE}Do you want to set up slack alerts?"
tput sgr0
read -p "Y/N [N]: " use_slack

#if so, fill out this form...
if [[ $use_slack =~ ^([yY][eE][sS]|[yY])$ ]]; then

  read -p "Slack api token: " slack_api_token
  read -p "Slack channel: " slack_channel

  #again, our sed is funky due to slashes appearing in slack api tokens
  sed -i -e 's,your_slack_api_token,'"$slack_api_token"',g' assets/alertmanager.yaml
  sed -i -e 's/your_slack_channel/'"$slack_channel"'/g' assets/alertmanager.yaml
fi

######################################################################################################
#deploy all the components
######################################################################################################

#prometheus-operator
echo
echo -e "${ORANGE}Deploying Prometheus Operator"
tput sgr0
kctl apply -f manifests/prometheus-operator

printf "${ORANGE}Waiting for Operator to register custom resource definitions..."
tput sgr0
until kctl get customresourcedefinitions servicemonitors.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
until kctl get customresourcedefinitions prometheuses.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
until kctl get customresourcedefinitions alertmanagers.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
until kctl get servicemonitors.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
until kctl get prometheuses.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
until kctl get alertmanagers.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
echo "done!"

#alertmanager
echo
echo -e "${ORANGE}Deploying Alertmanager"
tput sgr0
./scripts/generate-alertmanager-config-secret.sh
kctl apply -f manifests/alertmanager

#prometheus node-exporter
echo
echo -e "${ORANGE}Deploying node-exporter"
tput sgr0
kctl apply -f manifests/node-exporter

#kube-state-metrics
echo
echo -e "${ORANGE}Deploying Kube State Metrics exporter"
tput sgr0
kctl apply -f manifests/kube-state-metrics
echo

#grafana
echo
echo -e "${ORANGE}Deploying Grafana"
tput sgr0

#grafana administrator username
read -p "Enter Grafana administrator username [admin]: " GRAFANA_ADMIN_USERNAME
GRAFANA_ADMIN_USERNAME=${GRAFANA_ADMIN_USERNAME:-admin}

#grafana administrator password
prompt="Enter Grafana administrator password: "
while IFS= read -p "$prompt" -r -s -n 1 char
do
    if [[ $char == $'\0' ]]
    then
        break
    fi
    prompt='*'
    grafana_admin_password+="$char"
done

echo

#create grafana credentials secret
kctl create secret generic grafana-credentials --from-literal=user=$GRAFANA_ADMIN_USERNAME --from-literal=password=$grafana_admin_password

#generate grafana dashboards configmap
./scripts/generate-dashboards-configmap.sh

kctl apply -f manifests/grafana

#prometheus
echo
echo -e "${ORANGE}Deploying Prometheus"
tput sgr0
kctl apply -f manifests/prometheus


#if-self-hosted
echo
echo -e "${ORANGE}Self hosted"
tput sgr0
kctl apply -f manifests/k8s/self-hosted


#echo
##cleanup
#echo -e "${BLUE}Removing local changes"
#echo
##remove  "sed" generated files
#rm k8s/prometheus/*.yaml-e && rm k8s/grafana/*.yaml-e && rm grafana/*-e && rm k8s/kube-state-metrics/*.yaml-e 2> /dev/null
#./cleanup.sh
#
#echo -e "${BLUE}Done"
#echo
#tput sgr0
#
#
##Check if the Grafana pod is ready
#
#while :
#do
#   echo -e "${BLUE}Waiting for Grafana pod to become ready"
#   tput sgr0
#   sleep 2
#   echo
#   if kubectl get pods -n monitoring | grep grafana | grep Running
#   then
#   break
#else
#   echo
#   tput sgr0
#   fi
#done
#
#
#GRAFANA_POD=$(kubectl get pods --namespace=monitoring | grep grafana | cut -d ' ' -f 1)
#
##import prometheus datasource in grafana using Grafana API.
##proxy grafana to localhost to import datasource using Grafana API.
#
#kubectl port-forward $GRAFANA_POD --namespace=monitoring 3000:3000 > /dev/null 2>&1 &
#
#echo
#echo -e "${ORANGE}Importing Prometheus datasource."
#tput sgr0
#sleep 2
#curl 'http://admin:admin@127.0.0.1:3000/api/datasources' -X POST -H 'Content-Type: application/json;charset=UTF-8' --data-binary '{"name":"prometheus.monitoring.svc.cluster.local","type":"prometheus","url":"http://prometheus.monitoring.svc.cluster.local:9090","access":"proxy","isDefault":true}' 2> /dev/null 2>&1
#echo
#
##check datasources
#echo
#echo -e "${GREEN}Checking datasource"
#tput sgr0
#curl 'http://admin:admin@127.0.0.1:3000/api/datasources' 2> /dev/null 2>&1
#echo
## kill the backgrounded proxy process
#kill $!

# set up proxy for the user
echo
echo -e "${GREEN}Done"
