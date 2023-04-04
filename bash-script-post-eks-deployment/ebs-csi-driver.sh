#!/bin/bash

####################### VARIABLES #######################
CLUSTER_NAME="<my_cluster>"
ACCOUNT_ID="111122223333"
EBS_KMS_KEY_ARN="custom-key-id"
####################### VARIABLES #######################

cat <<EOF > ebs-csi-driver-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:RevokeGrant"
      ],
      "Resource": ["$EBS_KMS_KEY_ARN"],
      "Condition": {
        "Bool": {
          "kms:GrantIsForAWSResource": "true"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": ["$EBS_KMS_KEY_ARN"]
    }
  ]
}
EOF
aws iam create-policy \
  --policy-name EBS_KMS_policy \
  --policy-document file://ebs-csi-driver-policy.json

eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --region=$REGION \
  --cluster $CLUSTER_NAME \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/EBS_KMS_policy \
  --approve \
  --role-only \
  --role-name AmazonEKS_EBS_CSI_DriverRole

eksctl create addon --name aws-ebs-csi-driver --cluster $CLUSTER_NAME --service-account-role-arn arn:aws:iam::${ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole --force
