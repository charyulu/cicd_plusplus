#!/bin/sh
# Step -1: Install Gitlab Runner
# View the over all kube config
kubectl config view
# Get the available clusters
kubectl config get-clusters
# clean-up unnecessary clusters
kubectl config delete-cluster <ClusterName>
# Get the list of available contexts
kubectl config get-contexts
# clean-up contexts related to above deleted clusters
kubectl config delete-context <ContextName>
# Clean-up unnecessary users
kubectl config get-users
kubectl config delete-user <UserName>

# Get the current context and make sure kube is pointing to right one.
kubectl config current-context

# If kube is not pointing to required context, List the contexts available in .kube/conf
kubectl config get-contexts
# Point kube to right context
#kubectl config use-context docker-desktop
kubectl config set current-context dev

# Deploy Gitlab runnuer using Helm charts
helm repo add gitlab https://charts.gitlab.io
helm repo update
helm install --namespace gitlab gitlab-runner -f <CONFIG_VALUES_FILE> gitlab/gitlab-runner

#Download sample maven project
git clone git@github.com:charyulu/java-maven-sample.git
cd java-maven-sample/
