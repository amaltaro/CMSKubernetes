#!/bin/bash
set -x

namespace=CMSRucio
tmpl=cmsrucio-1909

# large template
#openstack --os-project-name "$namespace" coe cluster template create $tmpl --labels cern_tag=qa --labels master_lb_enabled="true" --labels keystone_auth_enabled="true" --labels influx_grafana_dashboard_enabled="true" --labels ingress_controller="nginx" --labels tiller_enabled=true --labels kube_csi_enabled="true" --labels kube_csi_version="v0.3.2" --labels kube_tag="v1.13.3-12" --labels container_infra_prefix="gitlab-registry.cern.ch/cloud/atomic-system-containers/" --labels manila_enabled="true" --labels cgroup_driver="cgroupfs" --labels cephfs_csi_enabled="true" --labels cvmfs_csi_version="v0.3.0" --labels admission_control_list="NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota,Priority" --labels flannel_backend="vxlan" --labels manila_version="v0.3.0" --labels cvmfs_csi_enabled="true" --labels cvmfs_tag="qa" --labels cephfs_csi_version="v0.3.0" --labels cern_enabled="true" 
#--coe kubernetes --image 26666ca8-bda9-4356-982f-4a92845ec361 --external-network CERN_NETWORK --fixed-network CERN_NETWORK --network-driver flannel --dns-nameserver 137.138.17.5 --flavor m2.large --master-flavor m2.medium --docker-storage-driver overlay2 --server-type vm

openstack --os-project-name "$namespace" coe cluster template delete $tmpl

openstack --os-project-name "$namespace" coe cluster template create $tmpl \
--labels influx_grafana_dashboard_enabled=true \
--labels ingress_controller=nginx \
--labels tiller_enabled=true \
--labels kube_csi_enabled=true \
--labels kube_csi_version=cern-csi-1.0-1 \
--labels kube_tag=v1.14.6 \
--labels container_infra_prefix=gitlab-registry.cern.ch/cloud/atomic-system-containers/ \
--labels manila_enabled=true \
--labels cgroup_driver=cgroupfs \
--labels cephfs_csi_enabled=false \
--labels cvmfs_csi_version=v1.0.0 \
--labels admission_control_list=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota,Priority \
--labels flannel_backend=vxlan \
--labels manila_version=v0.3.0 \
--labels cvmfs_csi_enabled=false \
--labels heat_container_agent_tag=stein-dev-1 \
--labels cephfs_csi_version=cern-csi-1.0-1 \
--coe kubernetes --image 26666ca8-bda9-4356-982f-4a92845ec361 \
--external-network CERN_NETWORK --fixed-network CERN_NETWORK --network-driver flannel --dns-nameserver 137.138.17.5 \
--flavor m2.medium --master-flavor m2.small --docker-storage-driver overlay2 --server-type vm

# list tempaltes
openstack --os-project-name "$namespace" coe cluster template list
