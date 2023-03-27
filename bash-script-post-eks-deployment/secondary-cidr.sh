#!/bin/bash

####################### VARIABLES #######################
CLUSTER_NAME="<cluster-name>"
VPC_NAME="<vpc-name>"
SNET_CIDR="<protected-subnet-cidr>" # pilih salah satu subnet saja
####################### VARIABLES #######################

VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=$VPC_NAME --query 'Vpcs[].VpcId' --output text)

aws ec2 associate-vpc-cidr-block --vpc-id $VPC_ID --cidr-block 100.64.0.0/16

export POD_AZS=($(aws ec2 describe-instances --filters "Name=tag-key,Values=eks:cluster-name" "Name=tag-value,Values=$CLUSTER_NAME" --query 'Reservations[*].Instances[*].[Placement.AvailabilityZone]' --output text | sort | uniq))

CGNAT_SNET1=$(aws ec2 create-subnet --cidr-block 100.64.0.0/19 --vpc-id $VPC_ID --availability-zone ${POD_AZS[0]} --query 'Subnet.SubnetId' --output text) 

CGNAT_SNET2=$(aws ec2 create-subnet --cidr-block 100.64.32.0/19 --vpc-id $VPC_ID --availability-zone ${POD_AZS[1]} --query 'Subnet.SubnetId' --output text) 

# CGNAT_SNET3=$(aws ec2 create-subnet --cidr-block 100.64.64.0/19 --vpc-id $VPC_ID --availability-zone ${POD_AZS[2]} --query 'Subnet.SubnetId' --output text) #(uncomment if 3AZ)

SNET1=$(aws ec2 describe-subnets --filters Name=cidr-block,Values=$SNET_CIDR --query 'Subnets[].SubnetId' --output text)

RTASSOC_ID=$(aws ec2 describe-route-tables --filters Name=association.subnet-id,Values=$SNET1 --query 'RouteTables[].RouteTableId' --output text)

aws ec2 associate-route-table --route-table-id $RTASSOC_ID --subnet-id $CGNAT_SNET1
aws ec2 associate-route-table --route-table-id $RTASSOC_ID --subnet-id $CGNAT_SNET2
# aws ec2 associate-route-table --route-table-id $RTASSOC_ID --subnet-id $CGNAT_SNET3 #(uncomment if 3AZ)

kubectl set env ds aws-node -n kube-system AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true

mkdir -p ~/eniconfig
cd ~/eniconfig


cat <<EOF >pod-netconfig.template
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
 name: \${AZ}
spec:
 subnet: \${SUBNET_ID}
 securityGroups: [ \${NETCONFIG_SECURITY_GROUPS} ]
EOF

INSTANCE_IDS=(`aws ec2 describe-instances --query 'Reservations[*].Instances[*].InstanceId' --filters "Name=tag-key,Values=eks:cluster-name" "Name=tag-value,Values=$CLUSTER_NAME" --output text` )

export NETCONFIG_SECURITY_GROUPS=$(for i in "${INSTANCE_IDS[@]}"; do  aws ec2 describe-instances --instance-ids $i | jq -r '.Reservations[].Instances[].SecurityGroups[].GroupId'; done  | sort | uniq | awk -vORS=, '{print $1 }' | sed 's/,$//')

mkdir -p yaml
while IFS= read -r line
do
 arr=($line)
 OUTPUT=`AZ=${arr[0]} SUBNET_ID=${arr[1]} envsubst < pod-netconfig.template | yq eval -P`
 FILENAME=${arr[0]}.yaml
 echo "Creating ENIConfig file:  yaml/$FILENAME"
 cat <<EOF >yaml/$FILENAME
$OUTPUT	
EOF
done < <(aws ec2 describe-subnets  --filters "Name=cidr-block,Values=100.64.*" --query 'Subnets[*].[AvailabilityZone,SubnetId]' --output text)

kubectl apply -f yaml

kubectl set env daemonset aws-node -n kube-system ENI_CONFIG_LABEL_DEF=failure-domain.beta.kubernetes.io/zone

for i in "${INSTANCE_IDS[@]}"
do
	echo "Terminating EC2 instance $i ..."
	aws ec2 terminate-instances --instance-ids $i
done
