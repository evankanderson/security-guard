#!/usr/bin/env bash

# Copyright 2022 The Knative Authors
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

set -x
export KO_DOCKER_REPO=ko.local

# Knative install using quickstart
kn quickstart kind -n k8s --install-serving

# Install guard resoucres
kubectl apply -Rf ./config/resources/

# create and load queue-proxy image
Q_IMAGE=`ko build ko://knative.dev/security-guard/cmd/queue -B  `
kind load docker-image $Q_IMAGE --name k8s

# create and load guard-service image
GS_IMAGE=`ko build ko://knative.dev/security-guard/cmd/guard-service -B  `
kind load docker-image $GS_IMAGE --name k8s

# create and load guard-webhook image
GW_IMAGE=`ko build ko://knative.dev/security-guard/cmd/guard-webhook -B  `
kind load docker-image $GW_IMAGE --name k8s

# Kind seem to sometime need some extra time
sleep 10

# deploy guard changes to knative
ko apply -Rf ./config/deploy/ -B

# Activate internal encryption
kubectl patch configmap config-network -n knative-serving --type=merge -p '{"data": {"internal-encryption": "true"}}'

# Restart activator pod
kubectl rollout restart deployment activator -n knative-serving

if ! [ -x "$(command -v kn)" ]; then
  echo 'kn is not installed.' >&2
else
    kn service create helloworld-go \
        --image ghcr.io/knative/helloworld-go:latest \
        --env "TARGET=Secured World" \
        --annotation features.knative.dev/queueproxy-podinfo=enabled \
        --annotation qpoption.knative.dev/guard-activate=enable
fi

