#!/bin/bash

####################### VARIABLES #######################
CLUSTER_NAME="<my_cluster>"
ACCOUNT_ID="111122223333"
REGION="ap-southeast-3"
####################### VARIABLES #######################

####################### VARIABLES #######################
CLUSTER_NAME="Prod-MachineLearning-EKSControlPlane"
ACCOUNT_ID="307939290067"
REGION="ap-southeast-3"
####################### VARIABLES #######################

cat <<EOF >cluster-autoscaler-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:ResourceTag/k8s.io/cluster-autoscaler/$CLUSTER_NAME": "owned"
                }
            }
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeAutoScalingGroups",
                "ec2:DescribeLaunchTemplateVersions",
                "autoscaling:DescribeTags",
                "autoscaling:DescribeLaunchConfigurations",
                "ec2:DescribeInstanceTypes"
            ],
            "Resource": "*"
        }
    ]
}
EOF

aws iam create-policy \
    --policy-name AmazonEKSClusterAutoscalerPolicy \
    --policy-document file://cluster-autoscaler-policy.json

eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --region=$REGION \
  --name=cluster-autoscaler \
  --role-name=AmazonEKSClusterAutoscalerRole \
  --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/AmazonEKSClusterAutoscalerPolicy \
  --override-existing-serviceaccounts \
  --approve

curl -O https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml

sed -i "s/<YOUR CLUSTER NAME>/$CLUSTER_NAME/" cluster-autoscaler-autodiscover.yaml 
sed -i 's/cluster-autoscaler:v1.22.2/cluster-autoscaler:v1.23.0/' cluster-autoscaler-autodiscover.yaml

kubectl apply -f cluster-autoscaler-autodiscover.yaml

kubectl annotate serviceaccount cluster-autoscaler \
  -n kube-system \
  eks.amazonaws.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/AmazonEKSClusterAutoscalerRole

kubectl patch deployment cluster-autoscaler \
  -n kube-system \
  -p '{"spec":{"template":{"metadata":{"annotations":{"cluster-autoscaler.kubernetes.io/safe-to-evict": "false"}}}}}'
