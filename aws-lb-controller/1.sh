#!/bin/sh

# CLUSTER_NAME="PoC-ML-Workload-EKSControlPlane"; // change or use environment variable
# ACCOUNT_ID="714270772174"; // change or use environment variable

curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.4/docs/install/iam_policy.json;
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json;

curl -LO "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz";
sudo tar xzvf eksctl_$(uname -s)_amd64.tar.gz -C /usr/local/bin;
sudo yum -y install jq;
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve \
  --override-existing-serviceaccounts;

curl -fsSL -o helm-v3.6.3.tar.gz https://get.helm.sh/helm-v3.6.3-linux-amd64.tar.gz;
tar -zxvf helm-v3.6.3.tar.gz;
sudo mv linux-amd64/helm /usr/local/bin/;
helm repo add eks https://aws.github.io/eks-charts;
helm repo update;

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set image.repository=602401143452.dkr.ecr.ap-southeast-1.amazonaws.com/amazon/aws-load-balancer-controller;

# kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"
