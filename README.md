# k8s-cluster

!! IMPORTANT !!
Before any action, pay attention in the structure and sequence of the deployments.
FIRST of all, deploy MetalLB Native and PVS-Class that are inside REQUISITES directory.
SECOND step is, finish to deploy MetalLB in metallb deirectory deploying config, and then services

The cluster was build with 6 nodes with 8vCPU and 32Gb RAM each (ETCD+CP+WN) to run below:

Services:
    metallb
    jellyfin
    nextcloud
    Immich
    gitlab
    postgre
    elk
    zabbix
    grafana
    prometheus
    jenkins
    repo
    athena
    webtool

PV-Storage
    media   (personal multimedia for nextcloud, jellyfin, immich)
    elk     (dedicated pv to log centralizer for Linux servers and applications)
    gitlab
    monitor (dedicated pv for zabbix, prometheus and grafana)
    pgsql   (dedicated pv for PostGreSQL Server)
    repo    (dedicated pv to store deb packages for local repository)

    gitlab  (dedicated pv for git local repository)
    immich
    jellyfin
    nextcloud
    pgsql
    elk
    zabbix
    prometheus
    grafana
    repo
    webtool
    athena

All the Persistent VOlumes are stored in a mounted NFS from a TrueNas VM, where all data are replicated from multiple 2Tb NVMe to 2x HDDs 8Tb, and then CloudSynced to GoogleDrive.


sudo groupadd -g 2000 media_access

sudo useradd -u 9999 postgres -G media_access
sudo useradd -u 9998 git -G media_access
sudo useradd -u 9997 elasticsearch -G media_access
sudo useradd -u 9996 nextcloud -G media_access
sudo useradd -u 9995 abc -G media_access
sudo useradd -u 9994 zabbix -G media_access
sudo useradd -u 9993 grafana -G media_access
sudo useradd -u 9991 prometheus -G media_access
sudo useradd -u 9990 jenkins -G media_access
sudo useradd -u 9989 immich -G media_access
sudo useradd -u 9988 jellyfin -G media_access
sudo useradd -u 33 www-data -G media_access

getent group media_access

















