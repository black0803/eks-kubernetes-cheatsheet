#!/bin/bash

####################### VARIABLES #######################
CLUSTER_NAME="<my_cluster>"
ACCOUNT_ID="111122223333"
REGION="ap-southeast-3"
EFS_ID="fs-92107410"
####################### VARIABLES #######################

curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-efs-csi-driver/master/docs/iam-policy-example.json

aws iam create-policy \
    --policy-name AmazonEKS_EFS_CSI_Driver_Policy \
    --policy-document file://iam-policy-example.json

eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --namespace kube-system \
    --name efs-csi-controller-sa \
    --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AmazonEKS_EFS_CSI_Driver_Policy \
    --approve \
    --region=$REGION

helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update
helm upgrade -i aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
    --namespace kube-system \
    --set image.repository=602401143452.dkr.ecr.ap-southeast-1.amazonaws.com/eks/aws-efs-csi-driver \
    --set controller.serviceAccount.create=false \
    --set controller.serviceAccount.name=efs-csi-controller-sa

cat <<EOF >efs-sc.yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: $EFS_ID
  directoryPerms: "700"
EOF

kubectl apply -f efs-sc.yaml