#!/usr/bin/env bash

# Copyright 2018 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

run_wait_tests() {
    set -o nounset
    set -o errexit

    kube::log::status "Testing kubectl wait"

    create_and_use_new_namespace

    ### Wait for deletion using --all flag

    # create test data
    kubectl create deployment test-1 --image=busybox
    kubectl create deployment test-2 --image=busybox

    # Post-Condition: deployments exists
    kube::test::get_object_assert "deployments" "{{range .items}}{{.metadata.name}},{{end}}" 'test-1,test-2,'

    # wait with jsonpath will timout for busybox deployment
    set +o errexit
    # Command: Wait with jsonpath support fields not exist in the first place
    output_message=$(kubectl wait --for=jsonpath=.status.readyReplicas=1 deploy/test-1 2>&1)
    set -o errexit

    # Post-Condition: Wait failed
    kube::test::if_has_string "${output_message}" 'timed out'

    # Delete all deployments async to kubectl wait
    ( sleep 2 && kubectl delete deployment --all ) &

    # Command: Wait for all deployments to be deleted
    output_message=$(kubectl wait deployment --for=delete --all)

    # Post-Condition: Wait was successful
    kube::test::if_has_string "${output_message}" 'test-1 condition met'
    kube::test::if_has_string "${output_message}" 'test-2 condition met'

    # create test data to test timeout error is occurred in correct time
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: dtest
  name: dtest
spec:
  replicas: 3
  selector:
    matchLabels:
      app: dtest
  template:
    metadata:
      labels:
        app: dtest
    spec:
      containers:
      - name: bb
        image: busybox
        command: ["/bin/sh", "-c", "sleep infinity"]
EOF

    set +o errexit
    # wait timeout error because condition is invalid
    start_sec=$(date +"%s")
    output_message=$(time kubectl wait pod --selector=app=dtest --for=condition=InvalidCondition --timeout=1s 2>&1)
    end_sec=$(date +"%s")
    len_sec=$((end_sec-start_sec))
    set -o errexit
    kube::test::if_has_string "${output_message}" 'timed out waiting for the condition '
    kube::test::if_has_string "${len_sec}" '1'

    # Clean deployment
    kubectl delete deployment dtest

    set +o nounset
    set +o errexit
}