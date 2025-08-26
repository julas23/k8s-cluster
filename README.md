# k3s-cluster
!! IMPORTANT !!
Before any action, pay attention in the structure and sequence of the deployments.

Inside REQUISITES directory: (If you already have a Kubernetes Cluster, jump to Third step and on)

    FIRST of all, deploy k3s cluster:       ansible-playbook -i hosts playbook_k3s_deploy.yml
    SECOND step, obtain the kubeconfig:     ansible-playbook -i hosts playbook_k3s_kubeconfig.yml
    THIRD step, deploy MetalLB Native:      kubectl deploy -f metallb-native.yaml
    FORTH step, deploy PVS-Class:           kubectl deploy -f pvs-class-nfs.yaml

DEPLOY SERVICES:
Services            PV-Storage                  Description

    nextcloud       /mnt/k8s-data/nextcloud     (personal multimedia for nextcloud)
    immich          /mnt/k8s-data/immich        (personal multimedia for immich)
    jellyfin        /mnt/k8s-data/jellyfin      (personal multimedia for jellyfin)
    gitlab          /mnt/k8s-data/gitlab        (dedicated pv for git local repository)
    postgre         /mnt/k8s-data/postgre       (dedicated pv for PostGreSQL Server)
    elk             /mnt/k8s-data/elk           (dedicated pv to log centralizer for Linux servers and applications)
    zabbix          /mnt/k8s-data/zabbix        (dedicated pv for zabbix)
    grafana         /mnt/k8s-data/grafana       (dedicated pv for grafana)
    prometheus      /mnt/k8s-data/prometheus    (dedicated pv for prometheus)
    jenkins         /mnt/k8s-data/jenkins       (dedicated pv for jenkins pipelines)
    repo            /mnt/k8s-data/repo          (dedicated pv to store deb packages for local repository)

All the Persistent VOlumes are stored in a mounted NFS from a TrueNas VM, where all data are replicated from multiple 2Tb NVMe to 2x HDDs 8Tb, and then CloudSynced to GoogleDrive.


