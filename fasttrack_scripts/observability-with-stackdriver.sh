#!/usr/bin/env bash

# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# TASK: This script completes the deploy application section of ASM workshop.

#!/bin/bash

# Verify that the scripts are being run from Linux and not Mac
if [[ $OSTYPE != "linux-gnu" ]]; then
    echo "ERROR: This script and consecutive set up scripts have only been tested on Linux. Currently, only Linux (debian) is supported. Please run in Cloud Shell or in a VM running Linux".
    exit;
fi

# Export a SCRIPT_DIR var and make all links relative to SCRIPT_DIR
export SCRIPT_DIR=$(dirname $(readlink -f $0 2>/dev/null) 2>/dev/null || echo "${PWD}/$(dirname $0)")
export LAB_NAME=observability-with-stackdriver

# Create a logs folder and file and send stdout and stderr to console and log file 
mkdir -p ${SCRIPT_DIR}/../logs
export LOG_FILE=${SCRIPT_DIR}/../logs/ft-${LAB_NAME}-$(date +%s).log
touch ${LOG_FILE}
exec 2>&1
exec &> >(tee -i ${LOG_FILE})

source ${SCRIPT_DIR}/../scripts/functions.sh

# Lab: Observability with Stackdriver

# Set speed
bold=$(tput bold)
normal=$(tput sgr0)

color='\e[1;32m' # green
nc='\e[0m'

echo -e "\n"
title_no_wait "*** Lab: Observability with Stackdriver ***"
echo -e "\n"

# https://codelabs.developers.google.com/codelabs/anthos-service-mesh-workshop/#6
title_no_wait "Install the istio to stackdriver config file in the ops clusters."
title_and_wait "Recall that the Istio controlplane (including istio-telemetry) is installed in the ops clusters only."
print_and_execute "cd ${WORKDIR}/k8s-repo/gke-asm-1-r1-prod/istio-telemetry"
print_and_execute "kustomize edit add resource istio-telemetry.yaml"
print_and_execute " "
print_and_execute "cd ${WORKDIR}/k8s-repo/gke-asm-2-r2-prod/istio-telemetry"
print_and_execute "kustomize edit add resource istio-telemetry.yaml"

title_and_wait "Commit the changes to to k8s-repo."
print_and_execute "cd ${WORKDIR}/k8s-repo"
print_and_execute "git add . && git commit -am \"Install istio to stackdriver configuration\""
print_and_execute "git push"
 
echo -e "\n"
title_no_wait "View the status of the Ops project Cloud Build in a previously opened tab or by clicking the following link: "
echo -e "\n"
title_no_wait "https://console.cloud.google.com/cloud-build/builds?project=${TF_VAR_ops_project_name}"
title_no_wait "Waiting for Cloud Build to finish..."

BUILD_STATUS=$(gcloud builds describe $(gcloud builds list --project ${TF_VAR_ops_project_name} --format="value(id)" | head -n 1) --project ${TF_VAR_ops_project_name} --format="value(status)")
while [[ "${BUILD_STATUS}" == "WORKING" ]]
  do
      title_no_wait "Still waiting for cloud build to finish. Sleep for 10s"
      sleep 10
      BUILD_STATUS=$(gcloud builds describe $(gcloud builds list --project ${TF_VAR_ops_project_name} --format="value(id)" | head -n 1) --project ${TF_VAR_ops_project_name} --format="value(status)")
  done
echo -e "\n"
 
title_and_wait "Verify the Istio → Stackdriver integration. Get the Stackdriver Handler CRD."
print_and_execute "kubectl --context ${OPS_GKE_1} get handler -n istio-system"

# actually validate the existence of the stackdriver handler
NUM_SD=`kubectl --context ${OPS_GKE_1} get handler -n istio-system | grep "stackdriver" | wc -l`
if [[ $NUM_SD -eq 0 ]]
then 
    error_no_wait "Stackdriver handler is not deployed in the ops-1 cluster."  
    error_no_wait "Verify the istio-telemetry.yaml file is in the k8s-repo. Exiting script..."
    exit 1
else 
    title_no_wait "Stackdriver handler is deployed in the ops-1 cluster. Continuing..."
fi
 
title_and_wait "Verify that the Istio metrics export to Stackdriver is working. Click the link output from this command:"
echo "https://console.cloud.google.com/monitoring/metrics-explorer?cloudshell=false&project=${TF_VAR_ops_project_name}"
echo ""
echo ""
title_and_wait ""

title_no_wait "Add a pre-canned metrics dashboard using the Dashboard API."
title_no_wait "This is typically done as part of a deployment pipeline."
title_no_wait "For this workshop, create the dashboard interacting with the API directly (via curl)."

print_and_execute "cd ${WORKDIR}/asm/k8s_manifests/prod/app-telemetry/"
print_and_execute "sed -i 's/OPS_PROJECT/'${TF_VAR_ops_project_name}'/g'  services-dashboard.json"
print_and_execute "OAUTH_TOKEN=$(gcloud auth application-default print-access-token)"
print_and_execute "curl -X POST -H \"Authorization: Bearer $OAUTH_TOKEN\" -H \"Content-Type: application/json\" \
                        https://monitoring.googleapis.com/v1/projects/${TF_VAR_ops_project_name}/dashboards \
                        -d @services-dashboard.json "

title_and_wait "Navigate to the output link below to view the newly added dashboard."
echo "https://console.cloud.google.com/monitoring/dashboards/custom/servicesdash?cloudshell=false&project=${TF_VAR_ops_project_name}"
echo ""
echo ""
title_and_wait ""

title_and_wait "Add a new Chart using the API. \
    To accomplish this, get the latest version of the Dashboard. \
    Apply edits directly to the downloaded Dashboard json.\
    And upload the patched json (with the new Chart) using the HTTP PATCH method. \
    Get the existing dashboard that was just added:"

print_and_execute "curl -X GET -H \"Authorization: Bearer $OAUTH_TOKEN\" -H \"Content-Type: application/json\" \
    https://monitoring.googleapis.com/v1/projects/${TF_VAR_ops_project_name}/dashboards/servicesdash > sd-services-dashboard.json"
 
title_and_wait "Add a new Chart for 50th %ile latency to the Dashbaord. \
    Use jq to patch the downloaded Dashboard json in the previous step with the new Chart."
print_and_execute "jq --argjson newChart \"\$(<new-chart.json)\" '.gridLayout.widgets += [\$newChart]' sd-services-dashboard.json > patched-services-dashboard.json"
 
title_and_wait "Update the Dashboard with the new patched json."
print_and_execute "curl -X PATCH -H \"Authorization: Bearer $OAUTH_TOKEN\" -H \"Content-Type: application/json\" \
     https://monitoring.googleapis.com/v1/projects/${TF_VAR_ops_project_name}/dashboards/servicesdash \
     -d @patched-services-dashboard.json"
 
title_and_wait "View the updated dashboard by navigating to the following output link:"
echo "https://console.cloud.google.com/monitoring/dashboards/custom/servicesdash?cloudshell=false&project=${TF_VAR_ops_project_name}"
 
title_and_wait "View project logs."
echo "https://console.cloud.google.com/logs/viewer?cloudshell=false&project=${TF_VAR_ops_project_name}"
title_and_wait "Refer to the Logging section in the Observability Lab in the workshop for further details."

title_and_wait "View project traces:"
echo "https://console.cloud.google.com/traces/overview?cloudshell=false&project=${TF_VAR_ops_project_name}"
title_and_wait "Refer to the Tracing section in the Observability Lab in the workshop for further details."

title_and_wait "Expose Grafana in ops-1 cluster. Grafana is an open source metrics dashboarding tool. \
    This is used later in the workshop in the Istio control plane monitoring and troubleshooting sections. \
    To learn more about Grafana, visit https://grafana.io"
print_and_execute "kubectl --context ${OPS_GKE_1} -n istio-system port-forward svc/grafana 3000:3000 >> /dev/null & "

echo "https://ssh.cloud.google.com/devshell/proxy?authuser=0&port=3000&environment_id=default"

title_no_wait "Congratulations! You have successfully completed the Observability with Stackdriver lab."
echo -e "\n"