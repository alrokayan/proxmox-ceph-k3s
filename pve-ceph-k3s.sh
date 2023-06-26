#!/bin/bash
function _filesGenerationCeph () {
  mkdir -p auto-gen/csi
  # Ceph RBD CSI GitHub: https://github.com/ceph/ceph-csi/tree/release-v3.8/deploy/rbd/kubernetes
  # Ceph RBD CSI Offical: https://docs.ceph.com/en/latest/rbd/rbd-kubernetes/

  if [ ! -f "auto-gen/csi/csi-config-map.yaml" ]; then
    echo "-- At least one of file core ceph-csi files is missing, downloading them now ..."
    git clone --quiet https://github.com/ceph/ceph-csi.git --branch release-v3.8 > /dev/null
    sed -i.original -e 's/namespace: default/namespace: kube-system/g' ceph-csi/deploy/rbd/kubernetes/*.yaml
    mv ceph-csi/deploy/rbd/kubernetes/* auto-gen/csi
  else
    echo "-- All core ceph-csi files are present, skipping download ..."
  fi

  if [ ! -f "auto-gen/csi/ceph-config-map.yaml" ]; then
    echo "-- ceph-config-map.yaml is missing, generating it now ..."
    cat > auto-gen/csi/ceph-config-map.yaml << __EOF__
---
apiVersion: v1
kind: ConfigMap
data:
  ceph.conf: |
    [global]
    auth_cluster_required = cephx
    auth_service_required = cephx
    auth_client_required = cephx

  # keyring is a required key and its value should be empty
  keyring: |
metadata:
  name: ceph-config
__EOF__
  else
    echo "-- ceph-config-map.yaml is present, skipping generation ..."
  fi

  if [ ! -f "auto-gen/csi/csi-config-map.yaml" ]; then
    echo "-- csi-config-map.yaml is missing, generating it now ..."
    cat > auto-gen/csi/csi-config-map.yaml << __EOF__
---
apiVersion: v1
kind: ConfigMap
data:
  config.json: |-
    [
      {
        "clusterID": "$FSID",
        "monitors": [
          "$PVE1:6789",
          "$PVE2:6789",
          "$PVE3:6789"
        ]
      }
    ]
metadata:
  name: ceph-csi-config
__EOF__
  else
    echo "-- csi-config-map.yaml is present, skipping generation ..."
  fi

  if [ ! -f "auto-gen/csi/csi-rbd-secret.yaml" ]; then
    echo "-- csi-rbd-secret.yaml is missing, generating it now ..."
    cat > auto-gen/csi/csi-rbd-secret.yaml << __EOF__
---
apiVersion: v1
kind: Secret
metadata:
  name: csi-rbd-secret
  namespace: kube-system
stringData:
  userID: admin
  userKey: $ADMIN_USER_KEY
__EOF__
  else
    echo "-- csi-rbd-secret.yaml is present, skipping generation ..."
  fi

  if [ ! -f "auto-gen/csi/csi-rbd-sc.yaml" ]; then
    echo "-- csi-rbd-sc.yaml is missing, generating it now ..."
    cat > auto-gen/csi/csi-rbd-sc.yaml << __EOF__
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-rbd-sc
provisioner: rbd.csi.ceph.com
parameters:
  clusterID: "$FSID"
  pool: $POOL_NAME
  imageFeatures: "layering"
  tryOtherMounters: "true"
  csi.storage.k8s.io/provisioner-secret-name: csi-rbd-secret
  csi.storage.k8s.io/provisioner-secret-namespace: kube-system
  csi.storage.k8s.io/controller-expand-secret-name: csi-rbd-kube-system
  csi.storage.k8s.io/controller-expand-secret-namespace: kube-system
  csi.storage.k8s.io/node-stage-secret-name: csi-rbd-secret
  csi.storage.k8s.io/node-stage-secret-namespace: kube-system
  csi.storage.k8s.io/fstype: xfs
  cephLogStrategy: remove
  encrypted: "false"
reclaimPolicy: $RECLAIM_POLICY
allowVolumeExpansion: true
mountOptions:
  - discard
__EOF__
  else
    echo "-- csi-rbd-sc.yaml is present, skipping generation ..."
  fi

  if [ ! -f "auto-gen/csi/csi-kms-config-map.yaml" ]; then
    echo "-- csi-kms-config-map.yaml is missing, generating it now ..."
    cat > auto-gen/csi/csi-kms-config-map.yaml << __EOF__
---
apiVersion: v1
kind: ConfigMap
data:
  config.json: |-
    {}
metadata:
  name: ceph-csi-encryption-kms-config
__EOF__
  else
    echo "-- csi-kms-config-map.yaml is present, skipping generation ..."
  fi
}


function _filesGenerationPV () {
  mkdir -p auto-gen/pv
  mkdir -p auto-gen/pvc

  # STATIC RBD: https://github.com/ceph/ceph-csi/blob/release-v3.8/docs/static-pvc.md
  if [ ! -f "auto-gen/pv/$RBD_IMAGE_NAME-pv.yaml" ]; then
    echo "-- $RBD_IMAGE_NAME-pv.yaml is missing, generating it now ..."
    cat > auto-gen/pv/$RBD_IMAGE_NAME-pv.yaml << __EOF__
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $RBD_IMAGE_NAME
spec:
  storageClassName: csi-rbd-sc
  accessModes:
  - ReadWriteOnce
  capacity:
    storage: $SIZE
  csi:
    driver: rbd.csi.ceph.com
    fsType: xfs
    nodeStageSecretRef:
      name: csi-rbd-secret
      namespace: kube-system
    volumeAttributes:
      "clusterID": "$FSID"
      "pool": "$POOL_NAME"
      "staticVolume": "$STATIC_VOLUME"
      "imageFeatures": "layering"
    volumeHandle: $RBD_IMAGE_NAME
  persistentVolumeReclaimPolicy: $RECLAIM_POLICY
  volumeMode: Filesystem
__EOF__
  else
    echo "-- $RBD_IMAGE_NAME-pv.yaml is present, skipping generation ..."
  fi

  if [ ! -f "auto-gen/pvc/$RBD_IMAGE_NAME-pvc.yaml" ]; then
    echo "-- $RBD_IMAGE_NAME-pvc.yaml is missing, generating it now ..."
    cat > auto-gen/pvc/$RBD_IMAGE_NAME-pvc.yaml << __EOF__
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $RBD_IMAGE_NAME-pvc
spec:
  storageClassName: csi-rbd-sc
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: $SIZE
  volumeMode: Filesystem
  volumeName: $RBD_IMAGE_NAME
__EOF__
  else
    echo "-- $RBD_IMAGE_NAME-pvc.yaml is present, skipping generation ..."
  fi

}

function _filesGenerationExample () {
mkdir -p auto-gen

if [ ! -f "auto-gen/manifest-wordpress.yaml" ]; then
  echo "-- auto-gen/manifest-wordpress.yaml is missing, generating it now ..."
  cat > auto-gen/manifest-wordpress.yaml << __EOF__
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $MYSQL_RBD_IMAGE_NAME
spec:
  storageClassName: csi-rbd-sc
  accessModes:
  - ReadWriteOnce
  capacity:
    storage: $MYSQL_RBD_IMAGE_SIZE
  csi:
    driver: rbd.csi.ceph.com
    fsType: xfs
    nodeStageSecretRef:
      name: csi-rbd-secret
      namespace: kube-system
    volumeAttributes:
      "clusterID": "$FSID"
      "pool": "$POOL_NAME"
      "staticVolume": "$STATIC_VOLUME"
      "imageFeatures": "layering"
    volumeHandle: $MYSQL_RBD_IMAGE_NAME
  persistentVolumeReclaimPolicy: $RECLAIM_POLICY
  volumeMode: Filesystem
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $MYSQL_RBD_IMAGE_NAME-pvc
spec:
  storageClassName: csi-rbd-sc
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: $MYSQL_RBD_IMAGE_SIZE
  volumeMode: Filesystem
  volumeName: $MYSQL_RBD_IMAGE_NAME

---
apiVersion: v1
kind: Secret
metadata:
  name: mysql-pass
type: Opaque
data:
  password: $MYSQL_PASSWORD
---
apiVersion: v1
kind: Service
metadata:
  name: wordpress-mysql
  labels:
    app: wordpress
spec:
  ports:
    - port: 3306
  selector:
    app: wordpress
    tier: mysql
  clusterIP: None
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress-mysql
  labels:
    app: wordpress
spec:
  selector:
    matchLabels:
      app: wordpress
      tier: mysql
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: wordpress
        tier: mysql
    spec:
      containers:
      - image: mysql:8.0
        name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-pass
              key: password
        - name: MYSQL_DATABASE
          value: wordpress
        - name: MYSQL_USER
          value: wordpress
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-pass
              key: password
        ports:
        - containerPort: 3306
          name: mysql
        volumeMounts:
        - name: mysql-persistent-storage
          mountPath: /var/lib/mysql
      volumes:
      - name: mysql-persistent-storage
        persistentVolumeClaim:
          claimName: $MYSQL_RBD_IMAGE_NAME-pvc
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $WP_RBD_IMAGE_NAME
spec:
  storageClassName: csi-rbd-sc
  accessModes:
  - ReadWriteOnce
  capacity:
    storage: $WP_RBD_IMAGE_SIZE
  csi:
    driver: rbd.csi.ceph.com
    fsType: xfs
    nodeStageSecretRef:
      name: csi-rbd-secret
      namespace: kube-system
    volumeAttributes:
      "clusterID": "$FSID"
      "pool": "$POOL_NAME"
      "staticVolume": "$STATIC_VOLUME"
      "imageFeatures": "layering"
    volumeHandle: $WP_RBD_IMAGE_NAME
  persistentVolumeReclaimPolicy: $RECLAIM_POLICY
  volumeMode: Filesystem
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $WP_RBD_IMAGE_NAME-pvc
spec:
  storageClassName: csi-rbd-sc
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: $WP_RBD_IMAGE_SIZE
  volumeMode: Filesystem
  volumeName: $WP_RBD_IMAGE_NAME
---
apiVersion: v1
kind: Service
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  ports:
    - port: 80
  selector:
    app: wordpress
    tier: frontend
  type: LoadBalancer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  selector:
    matchLabels:
      app: wordpress
      tier: frontend
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: wordpress
        tier: frontend
    spec:
      containers:
      - image: wordpress:6.2.1-apache
        name: wordpress
        env:
        - name: WORDPRESS_DB_HOST
          value: wordpress-mysql
        - name: WORDPRESS_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-pass
              key: password
        - name: WORDPRESS_DB_USER
          value: wordpress
        ports:
        - containerPort: 80
          name: wordpress
        volumeMounts:
        - name: wordpress-persistent-storage
          mountPath: /var/www/html
      volumes:
      - name: wordpress-persistent-storage
        persistentVolumeClaim:
          claimName: $WP_RBD_IMAGE_NAME-pvc
__EOF__
  else
    echo "-- auto-gen/manifest-wordpress.yaml is present, skipping generation ..."
  fi
}

function END_OF_SCRIPT () {
  echo "-------------------------------------------------------------"
  echo "🐳 Script executed successfully. Press any key to continue .."
  echo "-------------------------------------------------------------"
  read
}

##############################################################################################################
echo "---------------------------------------------------------------"
echo "---------------------------------------------------------------"
echo "Welcome to the Proxmox Ceph K8s HA deployment script"
echo "---------------------------------------------------------------"
echo "Please answer the following questions to create the pve.env"
echo "file and setting the environment variables"
echo "---------------------------------------------------------------"
echo "---------------------------------------------------------------"
echo "---------------------------------------------------------------"

if [ ! -f "auto-gen/pve.env" ]; then
  mkdir -p auto-gen
  echo "-- auto-gen/pve.env file not found .."
  echo "-- Createing auto-gen/pve.env .. please wait .."
  touch auto-gen/pve.env

  echo ">> Please entre the PVE1 IP (default: 10.10.1.10)"
  read PVE1
  if [[ $PVE1 == "" ]]; then
    PVE1=10.10.1.10
  fi
  echo "PVE1=${PVE1}" >> auto-gen/pve.env

  echo ">> Please entre the PVE2 IP (default: 10.10.1.11)"
  read PVE2
  if [[ $PVE2 == "" ]]; then
    PVE2=10.10.1.11
  fi
  echo "PVE2=${PVE2}" >> auto-gen/pve.env

  echo ">> Please entre the PVE3 IP (default: 10.10.1.12)"
  read PVE3
  if [[ $PVE3 == "" ]]; then
    PVE3=10.10.1.12
  fi
  echo "PVE3=${PVE3}" >> auto-gen/pve.env

  echo "Which PVE is the default PVE server for Proxmox cluster (1, 2 or 3)? (Default: 1)"
  echo "1 means PVE1, 2 means PVE2, 3 means PVE3"
  read PVE_DEFAULT_NUM
  if [[ $PVE_DEFAULT_NUM == "" ]]; then
    PVE_DEFAULT_NUM="1"
  fi
  if [[ $PVE_DEFAULT_NUM == "1" ]]; then
    PVE_DEFAULT=${PVE1}
  fi
  if [[ $PVE_DEFAULT_NUM == "2" ]]; then
    PVE_DEFAULT=${PVE2}
  fi
  if [[ $PVE_DEFAULT_NUM == "3" ]]; then
    PVE_DEFAULT=${PVE3}
  fi
  echo "PVE_DEFAULT=${PVE_DEFAULT}" >> auto-gen/pve.env

  echo ">> Please entre the nodes placement in PVE hosts (1, 2 or 3) with a space between them (default: 1 2 3): "
  echo 'Example: "1 1 1" means deploying three nodes kurbernetes cluster, all in PVE1.'
  echo 'Example: "1 1 2 2 3 3" means deploying six nodes kurbernetes cluster where 2 nodes in PVE1, 2 nodes in PVE2 and 2 nodes in PVE3.'
  echo 'Example: "2" means deploying one node kurbernetes cluster in PVE1'
  read VM_PLACEMENT
  if [[ $VM_PLACEMENT == "" ]]; then
    VM_PLACEMENT="1 2 3"
  fi
  PVE_ID=1
  VM_PLACEMENT="${VM_PLACEMENT//$PVE_ID/"$PVE1"}"
  PVE_ID=2
  VM_PLACEMENT="${VM_PLACEMENT//$PVE_ID/"$PVE2"}"
  PVE_ID=3
  VM_PLACEMENT="${VM_PLACEMENT//$PVE_ID/"$PVE3"}"
  VM_PLACEMENT="(${VM_PLACEMENT})"
  echo "VM_PLACEMENT=${VM_PLACEMENT}" >> auto-gen/pve.env

  echo ">> Please entre the nodes IP prefix where the last digital is omitiied to be concatenated with the node ID starting from zero (default: 10.10.100.20):"
  echo "-- Example: "192.168.1.1" with three nodes cluster means the nodes IPs will be 192.168.1.11, 192.168.1.12 and 192.168.1.13"
  echo "-- Example: "10.10.4.10" with six nodes cluster means the nodes IPs will be 10.10.4.101, 10.10.4.102, 10.10.4.103, 10.10.4.104, 10.10.4.105, 10.10.4.106"
  read NODE_IP_PREFIX
  if [[ $NODE_IP_PREFIX == "" ]]; then
    NODE_IP_PREFIX="10.10.100.20"
  fi
  echo "NODE_IP_PREFIX=${NODE_IP_PREFIX}" >> auto-gen/pve.env

  echo ">> Please entre the K8s Load Balancer IP or just simply node1 IP (default: ${NODE_IP_PREFIX}1):"
  read LB
  if [[ $LB == "" ]]; then
    LB=${NODE_IP_PREFIX}1
  fi
  echo "LB=${LB}" >> auto-gen/pve.env

  echo ">> Please the VM prefix ID where the last digital is omitiied to be concatenated with the node ID starting from 1 (default: 100):"
  echo 'Example: "100" with three nodes cluster means the VMs IDs will be 1001, 1002 and 1003'
  echo 'Example: "10" with six nodes cluster means the VMs IDs will be 101, 102, 103, 104, 105, 106'
  read VM_ID_PREFIX
  if [[ $VM_ID_PREFIX == "" ]]; then
    VM_ID_PREFIX=100
  fi
  echo "VM_ID_PREFIX=${VM_ID_PREFIX}" >> auto-gen/pve.env

  echo ">> Please entre the SSH username for PVE and VMs (default: root):"
  read SSH_USERNAME
  if [[ $SSH_USERNAME == "" ]]; then
    SSH_USERNAME=root
  fi
  echo "SSH_USERNAME=${SSH_USERNAME}" >> auto-gen/pve.env

  echo "-- >> Please entre the path for KUBECONFIG (default: ~/.kube/config):"
  read KUBECONFIG
  if [[ $KUBECONFIG == "" ]]; then
    KUBECONFIG=~/.kube/config
  fi
  echo "KUBECONFIG=${KUBECONFIG}" >> auto-gen/pve.env

  echo ">> Please entre the path of your public key to SSH into the VMs (default: ~/.ssh/id_rsa.pub)"
  read MY_PUBLIC_KEY
  if [[ $MY_PUBLIC_KEY == "" ]]; then
    MY_PUBLIC_KEY=~/.ssh/id_rsa.pub
  fi
  echo "MY_PUBLIC_KEY=${MY_PUBLIC_KEY}" >> auto-gen/pve.env

  echo ">> Please entre the path to the private key for the proxmox host (default: /etc/ssh/ssh_host_rsa_key):"
  read PROXMOX_HOST_PRIVATE_KEY
  if [[ $PROXMOX_HOST_PRIVATE_KEY == "" ]]; then
    PROXMOX_HOST_PRIVATE_KEY=/etc/ssh/ssh_host_rsa_key
  fi
  echo "PROXMOX_HOST_PRIVATE_KEY=${PROXMOX_HOST_PRIVATE_KEY}" >> auto-gen/pve.env

  echo ">> Please entre the number of CPUs for each VM (default: 2)"
  read PVE_CPU_CORES
  if [[ $PVE_CPU_CORES == "" ]]; then
    PVE_CPU_CORES=2
  fi
  echo "PVE_CPU_CORES=${PVE_CPU_CORES}" >> auto-gen/pve.env

  echo ">> Please entre the amount of RAM for each VM (default: 2048)"
  read PVE_MEMORY
  if [[ $PVE_MEMORY == "" ]]; then
    PVE_MEMORY=2048
  fi
  echo "PVE_MEMORY=${PVE_MEMORY}" >> auto-gen/pve.env

  echo ">> Please entre the DNS IP for VMs (default: 10.10.1.1)"
  read VM_DNS
  if [[ $VM_DNS == "" ]]; then
    VM_DNS="10.10.1.1"
  fi
  echo "VM_DNS=${VM_DNS}" >> auto-gen/pve.env

  echo ">> Please entre the DNS search domain for VMs (default: ha.ousaimi.com)"
  read SEARCH_DOMAIN
  if [[ $SEARCH_DOMAIN == "" ]]; then
    SEARCH_DOMAIN="ha.ousaimi.com"
  fi
  echo "SEARCH_DOMAIN=${SEARCH_DOMAIN}" >> auto-gen/pve.env

  echo ">> Please entre the storage ID for VMs (default: local-btrfs)"
  read STORAGEID
  if [[ $STORAGEID == "" ]]; then
    STORAGEID="local-btrfs"
  fi
  echo "STORAGEID=${STORAGEID}" >> auto-gen/pve.env

  echo ">> Please entre the storage ID for cloud-init (default: rbd)"
  read CLOUDINIT_STORAGEID
  if [[ $CLOUDINIT_STORAGEID == "" ]]; then
    CLOUDINIT_STORAGEID="rbd"
  fi
  echo "CLOUDINIT_STORAGEID=${CLOUDINIT_STORAGEID}" >> auto-gen/pve.env

  echo ">> Please entre the download folder for raw images (default: /mnt/pve/cephfs/raw/):"
  read DOWNLOAD_FOLDER
  if [[ $DOWNLOAD_FOLDER == "" ]]; then
    DOWNLOAD_FOLDER=/mnt/pve/cephfs/raw/
  fi
  echo "DOWNLOAD_FOLDER=${DOWNLOAD_FOLDER}" >> auto-gen/pve.env

  echo ">> Please entre the cloud image URL (default: https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.raw):"
  read CLOUD_IMAGE_URL
  if [[ $CLOUD_IMAGE_URL == "" ]]; then
    CLOUD_IMAGE_URL=https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.raw
  fi
  echo "CLOUD_IMAGE_URL=${CLOUD_IMAGE_URL}" >> auto-gen/pve.env
  
  echo ">> Please enter Ceph pool name (default: rbd):"
  read POOL_NAME
  if [[ $POOL_NAME == "" ]]; then
    POOL_NAME="rbd"
  fi
  echo "POOL_NAME=${POOL_NAME}" >> auto-gen/pve.env

  echo ">> Please enter Ceph reclaim policy (Delete or Retain) (default: Delete):"
  read RECLAIM_POLICY
  if [[ $RECLAIM_POLICY != "Retain" ]]; then
    RECLAIM_POLICY="Delete"
    STATIC_VOLUME="false"
  else
    RECLAIM_POLICY="Retain"
    STATIC_VOLUME="true"
  fi
  echo "RECLAIM_POLICY=${RECLAIM_POLICY}" >> auto-gen/pve.env
  echo "STATIC_VOLUME=${STATIC_VOLUME}" >> auto-gen/pve.env

  echo ">> Please enter Kubernetes namespace (default: homelab):"
  read K8S_NAMESPACE
  if [[ $K8S_NAMESPACE == "" ]]; then
    K8S_NAMESPACE="homelab"
  fi
  echo "K8S_NAMESPACE=${K8S_NAMESPACE}" >> auto-gen/pve.env

  END_OF_SCRIPT
fi

##############################################################################################################
source auto-gen/pve.env

while true
do
  clear
  echo "-----------------------------------------------------------"
  echo "Welcome to the Proxmox Ceph K8s HA deployment script"
  echo "Please select one of rhe following options:"
  echo "-----------------------------------------------------------"
  echo "(qc)  < Exit and CLEAN UP"
  echo "(q)   < Exit"
  echo "----------------------------------------------------"
  echo "[i]....INFRASTRUCTURE"
  echo "[s]....STORAGE"
  echo "[d]....DEPLOYMENT"
  echo "----------------------------------------------------"
  echo "(10)...Monitor VMs status"
  echo "(11)...Monitor K8s cluster status (k9s)"
  echo "(12)...Monitor Ceph cluster status"
  echo "(13)...Monitor RBD images list"
  echo "(14)...Monitor Ceph pool list"
  echo "(15)...Monitor auto generated files (tree)"
  echo "(16)...Print environment variables"
  echo "(17)...SSH into default Proxmox node (${PVE_DEFAULT})"
  echo "(18)...SSH into K8s first master (${NODE_IP_PREFIX}1)"
  echo "-----------------------------------------------------------"
  read OPTION
  case $OPTION in
    qc)
      echo "Cleaning up..."
      rm -rf auto-gen/
      rm -rf ceph-csi
      exit 0
      ;;
    q)
      exit 0
      ;;
    10) # Monitor VMs status
      ssh -i ${MY_PUBLIC_KEY} -t ${SSH_USERNAME}@${PVE_DEFAULT} "watch pvesh get /cluster/resources --type vm"
      ;;
    11) # Monitor K8s cluster status (k9s)
      k9s -A
      echo "Do you want to install k9s to monitor K8s cluster? (y/N)"
      read -r INSTALL_K9S
      if [[ $INSTALL_K9S == "y" ]]; then
        brew install derailed/k9s/k9s
      fi
      ;;
    12)
      # Ceph Status
      ssh -i ${MY_PUBLIC_KEY} -t ${SSH_USERNAME}@${PVE_DEFAULT} "watch ceph -s"
      ;;
    13) # Monitor Ceph cluster status
      ssh -i ${MY_PUBLIC_KEY} -t ${SSH_USERNAME}@${PVE_DEFAULT} "watch rbd ls -p ${POOL_NAME}"
      ;;
    14) # Monitor Ceph pool list
      ssh -i ${MY_PUBLIC_KEY} -t ${SSH_USERNAME}@${PVE_DEFAULT} "watch ceph osd pool ls"
      ;;
    15) # Monitor auto generated files (tree)
      watch tree auto-gen
      echo ">> Do you want to install tree to monitor auto generated files? (y/N)"
      read -r INSTALL_TREE
      if [[ $INSTALL_TREE == "y" ]]; then
        brew install tree
      fi
      ;;
    16) # Print environment variables
      clear
      echo "----------------------------------------------------"
      echo "-------------- auto-gen/pve.env --------------------"
      echo "----------------------------------------------------"
      cat auto-gen/pve.env
      if [[ -f auto-gen/ceph.env ]]; then
        echo "----------------------------------------------------"
        echo "-------------- auto-gen/ceph.env -------------------"
        echo "----------------------------------------------------"
        cat auto-gen/ceph.env
      fi
      END_OF_SCRIPT
      ;;
      17) ## ssh into PVE_DEFAULT
          ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT}
          ;;
      18) ## ssh into node1
          ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${NODE_IP_PREFIX}1
        ;;
##############################################################
##############################################################
# INFRASTRUCTURE
##############################################################
##############################################################
    i)
        while true; do
        clear
        echo "----------------------------------------------------"
        echo "---------------- INFRASTRUCTURE --------------------"
        echo "----------------------------------------------------"
        echo "DEFAULT PVE   : $PVE_DEFAULT"
        echo "DNS           : $VM_DNS"
        echo "SEARCH DOMAIN : $SEARCH_DOMAIN"
        echo "VM SPECS      : $PVE_CPU_CORES CORES and $PVE_MEMORY RAM"
        echo "STORAGE       : $STORAGEID for VM Disks,"
        echo "                $CLOUDINIT_STORAGEID for CloudInit,"
        echo "                $DOWNLOAD_FOLDER for cloud image"
        echo "----------------------------------------------------"
        echo "Please select one of the following options:"
        echo "----------------------------------------------------"
        echo "(qc)  < Exit and CLEAN UP"
        echo "(q)   < Back"
        echo "----------------------------------------------------"
        echo "[1]....Initiate the infrastructure"
        echo "[2]....Download cloud image"
        echo "[3]....Create VMs"
        echo "[4]....Install k3sup on mac"
        echo "[5]....Deploy Kubernetes cluster (k3s)"
        echo "----------------------------------------------------"
        echo "(wipE).Wipe clean Kubernetes cluster's nodes"
        echo "(nukE).Delete all VMs"
        echo "----------------------------------------------------"
        read INFRA_OPTION
        case $INFRA_OPTION in
        qc)
          echo "Cleaning up..."
          rm -rf auto-gen/
          rm -rf ceph-csi
          exit 0
          ;;
        q)
          break
          ;;
        1) ## Initiate the infrastructure
          echo "-- Cleaning PVE keys ..."
          for PVE in ${PVE1} ${PVE2} ${PVE3}
          do
            ssh-keygen -f ~/.ssh/known_hosts -R "${PVE}" &>/dev/null
          done
          echo "-- Cleaing kurbenetes keys ..."
          ID=1
          for NODE in ${VM_PLACEMENT[@]}
          do
            ssh-keygen -f ~/.ssh/known_hosts -R "${NODE}" &>/dev/null
            ssh-keygen -f ~/.ssh/known_hosts -R "${NODE_IP_PREFIX}${ID}" &>/dev/null
            ID=$((ID+1))
          done

          for PVE in ${PVE1} ${PVE2} ${PVE3}
          do
            ssh-copy-id -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE}
          done

          echo ">> Do you want to copy the groups.cfg to the default PVE host (${PVE_DEFAULT})? (y/N)"
          read COPY_GROUPS_CFG
          if [[ $COPY_GROUPS_CFG == "y" ]]; then
            scp config/groups.cfg ${SSH_USERNAME}@${PVE_DEFAULT}:/etc/pve/
          fi
          for PVE in ${PVE1} ${PVE2} ${PVE3}
          do
          ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE} bash << ___EOF___
#!/bin/bash
cp ${PROXMOX_HOST_PRIVATE_KEY} /root/.ssh/id_rsa
cp ${PROXMOX_HOST_PRIVATE_KEY}.pub /root/.ssh/id_rsa.pub
chmod 600 /root/.ssh/id_rsa
chmod 644 /root/.ssh/id_rsa.pub
___EOF___
          done
          END_OF_SCRIPT
          ;;
        2) ## Download cloud image
          echo "--- Deleting old raw images in ${DOWNLOAD_FOLDER} on all PVE nodes ..."
          for PVE in ${PVE1} ${PVE2} ${PVE3}
          do
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE} rm -f ${DOWNLOAD_FOLDER}/cloud-image.raw
          done

          for PVE in ${PVE1} ${PVE2} ${PVE3}
          do
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE} bash << ___EOF___
#!/bin/bash
mkdir -p ${DOWNLOAD_FOLDER}
cd ${DOWNLOAD_FOLDER}
if [ ! -f "cloud-image.raw" ]; then
  curl -L ${CLOUD_IMAGE_URL} -o "cloud-image.raw"
  qemu-img resize -f raw cloud-image.raw +8G
  apt-get install -y libguestfs-tools
  virt-customize -a cloud-image.raw --install qemu-guest-agent
  virt-customize -a cloud-image.raw --install curl
  virt-customize -a cloud-image.raw --install util-linux
  virt-customize -a cloud-image.raw --install coreutils
  virt-customize -a cloud-image.raw --install gnupg
  virt-customize -a cloud-image.raw --install git
  virt-customize -a cloud-image.raw --run-command "systemctl enable qemu-guest-agent"
  virt-customize -a cloud-image.raw --run-command "\
        sed -i '/#PermitRootLogin prohibit-password/c\PermitRootLogin yes' /etc/ssh/sshd_config && \
        sed -i '/PasswordAuthentication no/c\PasswordAuthentication yes' /etc/ssh/sshd_config && \
        sed -i '/#   StrictHostKeyChecking ask/c\    StrictHostKeyChecking no' /etc/ssh/ssh_config && \
        echo 'source /etc/network/interfaces.d/*' > /etc/network/interfaces && \
        sed -i '/#net.ipv4.ip_forward=1/c\net.ipv4.ip_forward=1' /etc/sysctl.conf && \
        sed -i '/#net.ipv6.conf.all.forwarding=1/c\net.ipv6.conf.all.forwarding=1' /etc/sysctl.conf && \
        sed -i '/#DefaultTimeoutStopSec=90s/c\DefaultTimeoutStopSec=10s' /etc/systemd/system.conf"
fi
___EOF___
          done
        END_OF_SCRIPT
        ;;
        3) ## Create VMs
          ID=1
          for VM_PLACEMENT in ${VM_PLACEMENT[@]}
          do
            echo "-- Creating VM: node${ID}"
            VM_NAME="node${ID}"
            VM_ID=${VM_ID_PREFIX}${ID}
            FULLNAME=${VM_NAME}.${SEARCH_DOMAIN}
            SSH_FILE=.${RANDOM}
            MY_PUBLIC_KEY_VAR=$(cat ${MY_PUBLIC_KEY})
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${VM_PLACEMENT} bash << ___EOF___
#!/bin/bash
ssh-keygen -y -f ${PROXMOX_HOST_PRIVATE_KEY} > /tmp/${SSH_FILE}
echo $MY_PUBLIC_KEY_VAR >> /tmp/${SSH_FILE}
qm create ${VM_ID} \
    --memory ${PVE_MEMORY} \
    --net0 model=virtio,bridge=vmbr0,firewall=0 \
    --scsihw virtio-scsi-single \
    --boot c \
    --bootdisk scsi0 \
    --ide2 ${CLOUDINIT_STORAGEID}:cloudinit \
    --ciuser "${SSH_USERNAME}" \
    --sshkey /tmp/${SSH_FILE} \
    --serial0 socket \
    --vga serial0 \
    --cpu host \
    --cores ${PVE_CPU_CORES} \
    --agent enabled=1 \
    --autostart 1 \
    --onboot 1 \
    --ostype l26 \
    --nameserver "${VM_DNS}" \
    --searchdomain "${SEARCH_DOMAIN}" \
    --ipconfig0 "ip=${NODE_IP_PREFIX}${ID}/16,gw=10.10.1.1" \
    --name ${VM_NAME}
qm cloudinit update ${VM_ID}
qm importdisk ${VM_ID} ${DOWNLOAD_FOLDER}cloud-image.raw ${STORAGEID} --format raw 
qm set ${VM_ID} --scsi0 ${STORAGEID}:vm-${VM_ID}-disk-0,aio=threads,backup=0,cache=writeback,iothread=1,replicate=0,ssd=1 &>/dev/null
qm set ${VM_ID} --scsi0 ${STORAGEID}:${VM_ID}/vm-${VM_ID}-disk-0.raw,aio=threads,backup=0,cache=writeback,iothread=1,replicate=0,ssd=1 &>/dev/null
ha-manager add vm:${VM_ID} --state started --max_relocate 0 --max_restart 5 --group ${VM_NAME}
rm -f /tmp/${SSH_FILE}
___EOF___
          ID=$(( ID+1 ))
          done
        END_OF_SCRIPT
        ;;
        4) ## Install k3sup on mac
        echo "-- Installing k3s"
        curl -sLS https://get.k3sup.dev | sh
        install k3sup /usr/local/bin/
        END_OF_SCRIPT
        ;;
        5) ## Deploy Kubernetes cluster (k3s)
          ID=1
          for PLACMENT in ${VM_PLACEMENT[@]}
          do
            FQDN=node${ID}.ha.ousaimi.com
            IP=${NODE_IP_PREFIX}${ID}
            echo "-- Fixing iptables-legacy on node${ID}"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${IP} bash <<'____EOF____'
#!/bin/bash
iptables-save > /tmp/iptables-save.txt
ip6tables-save > /tmp/ip6tables-save.txt
iptables-legacy-save > /tmp/iptables-legacy-save.txt
ip6tables-legacy-save > /tmp/ip6tables-legacy-save.txt
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -F
iptables -X
ip6tables -P INPUT ACCEPT
ip6tables -P FORWARD ACCEPT
ip6tables -P OUTPUT ACCEPT
ip6tables -t nat -F
ip6tables -t nat -X
ip6tables -t mangle -F
ip6tables -t mangle -X
ip6tables -F
ip6tables -X
iptables-legacy -P INPUT ACCEPT
iptables-legacy -P FORWARD ACCEPT
iptables-legacy -P OUTPUT ACCEPT
iptables-legacy -t nat -F
iptables-legacy -t nat -X
iptables-legacy -t mangle -F
iptables-legacy -t mangle -X
iptables-legacy -F
iptables-legacy -X
ip6tables-legacy -P INPUT ACCEPT
ip6tables-legacy -P FORWARD ACCEPT
ip6tables-legacy -P OUTPUT ACCEPT
ip6tables-legacy -t nat -F
ip6tables-legacy -t nat -X
ip6tables-legacy -t mangle -F
ip6tables-legacy -t mangle -X
ip6tables-legacy -F
ip6tables-legacy -X
for x in _raw _mangle _security _nat _filter; do
  modprobe -r "iptable${x}"
  modprobe -r "ip6table${x}"
done
iptables-restore < /tmp/iptables-save.txt
ip6tables-restore < /tmp/ip6tables-save.txt
update-alternatives --remove iptables /usr/sbin/iptables-legacy
____EOF____
            if [[ $ID -eq 1 ]]; then
              k3sup install --user ${SSH_USERNAME} \
                            --ip $IP \
                            --ssh-key $MY_PUBLIC_KEY \
                            --local-path $KUBECONFIG \
                            --k3s-extra-args "--flannel-backend=host-gw \
                                             --cluster-cidr=10.244.0.0/16 \
                                             --service-cidr=192.168.244.0/24 \
                                             --disable metrics-server" \
                            --cluster                

            else
              k3sup join --user ${SSH_USERNAME} \
                          --ip $IP \
                          --ssh-key $MY_PUBLIC_KEY \
                          --server-user ${SSH_USERNAME} \
                          --server-ip $LB \
                          --k3s-extra-args "--flannel-backend=host-gw \
                                            --cluster-cidr=10.244.0.0/16 \
                                            --service-cidr=192.168.244.0/24 \
                                            --disable metrics-server" \
                          --server
            fi
            
            ID=$(( ID+1 ))
          done
          END_OF_SCRIPT
          break
          ;;
        wipE) ## Wipe clean Kubernetes cluster's nodes
          ID=1
          for PLACEMENT in ${VM_PLACEMENT[@]}
          do
            echo "-- Removing k3s in node${ID}"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${NODE_IP_PREFIX}${ID} bash <<'____EOF____'
#!/bin/bash
k3s-uninstall.sh &>/dev/null
k3s-agent-uninstall.sh &>/dev/null
____EOF____
            ID=$(( ID+1 ))
          done
          END_OF_SCRIPT
          ;;
        nukE) ## Destroy all VMs in all PVEs
          for PVE in ${PVE1} ${PVE2} ${PVE3}
          do
            echo "-- Removing VMs in PVE: ${PVE} ..."
            QM_LIST=$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE} qm list)
            ID=1
            for PLACEMENT in ${VM_PLACEMENT[@]}
            do
              NODE_ID=${VM_ID_PREFIX}${ID}
              QM_LIST_GREPD=$( echo $QM_LIST | grep $NODE_ID )
              echo "-- Checking VM: $NODE_ID"
              if [[ $QM_LIST_GREPD != "" ]]; then
                ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE} bash <<____EOF____
#!/bin/bash
qm unlock ${NODE_ID}
ha-manager remove vm:${NODE_ID}
qm stop ${NODE_ID}
qm destroy ${NODE_ID} --destroy-unreferenced-disks --purge true --skiplock true
____EOF____
                  ssh-keygen -f ~/.ssh/known_hosts -R "node${ID}" &>/dev/null
                  ssh-keygen -f ~/.ssh/known_hosts -R "${NODE_IP_PREFIX}${ID}" &>/dev/null
                fi
             ID=$(( ID+1 ))
             done
           done
        END_OF_SCRIPT
          ;;
        *)
          echo "--?-- Invalid option"
          sleep 1
          ;;
        esac
      done
      ;;
##############################################################
##############################################################
# STORAGE
##############################################################
##############################################################
    s)
      while true; do
        clear
        echo "----------------------------------------------------"
        echo "------------------- STORAGE ------------------------"
        echo "----------------------------------------------------"
        echo "POOL NAME   : $POOL_NAME"
        echo "PVE DEFAULT : $PVE_DEFAULT"
        echo "----------------------------------------------------"
        echo "Please select one of the following options:"
        echo "----------------------------------------------------"
        echo "(qc)   < Exit and CLEAN UP"
        echo "(q)    < Exit"
        echo "----------------------------------------------------"
        echo "[1]....Create \"$POOL_NAME\" RBD Pool"
        echo "[2]....Create RBD Images"
        echo "[3]....Mount RBD images"
        echo "[4]....-- Copy files to RBD images -->"
        echo "[5]....<-- Copy files from RBD images --"
        echo "----------------------------------------------------"
        echo "(pg)...Calculate PGs"
        echo "(z1)...Zap disks in PVE1"
        echo "(z2)...Zap disks in PVE2"
        echo "(z3)...Zap disks in PVE3"
        echo "(um)...Unmount RBD images"
        echo "(del)..Delete RBD images"
        echo "(nukE).ShredOS (USB Disk Eraser)"
        echo "----------------------------------------------------"
        read STORAGE_OPTION
        case $STORAGE_OPTION in
        qc)
          echo "-- Cleaning up..."
          rm -rf auto-gen/ 
          rm -rf ceph-csi
          exit 0
          ;;
        q)
          break
          ;;
        1)
            echo "-- Creating RBD pool $POOL_NAME ..."
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} pveceph pool create $POOL_NAME --application rbd --pg_autoscale_mode on
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} pveceph lspools
            END_OF_SCRIPT
            ;;
        2)
            echo ">> Please enter the RBD image name to mount in /mnt/rbd: (Default: rbd-image)"
            read RBD_IMAGE
            if [[ $RBD_IMAGE == "" ]]; then
              RBD_IMAGE="rbd-image"
            fi
            echo ">> Please enter the size of the RBD image (Default 1G):"
            read SIZE
            if [[ $SIZE == "" ]]; then
              SIZE=1G
            fi
            echo "-- Creating ${RBD_IMAGE} RDB with size ${SIZE} at pool \"$POOL_NAME\""
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd create ${RBD_IMAGE} --size=${SIZE} --pool=$POOL_NAME"
            END_OF_SCRIPT
            ;;
        3) # Mount RBD images
            echo ">> Please enter the RBD image name to mount in /mnt/rbd: (Default: rbd-image)"
            read RBD_IMAGE
            if [[ $RBD_IMAGE == "" ]]; then
              RBD_IMAGE="rbd-image"
            fi
            echo "-- Mapping and mounting ${RBD_IMAGE} RBD to /mnt/rbd/${RBD_IMAGE} folder"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd map ${RBD_IMAGE} --pool $POOL_NAME  --id admin --keyring /etc/pve/priv/ceph.client.admin.keyring"
            
            echo ">> RBD image has been mapped but not mounted yet. Do you want to make filesystem (mkfs.xfs) on the mapped $RBD_IMAGE RBD image before mounting? (y/N)"
            read MKFS_RBD_IMAGE
            if [[ $MKFS_RBD_IMAGE == "y" ]]; then
              MKFS_RBD_IMAGE=true
            else
              MKFS_RBD_IMAGE=false
            fi
            if [ $MKFS_RBD_IMAGE == "true" ]; then
              ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "mkfs.xfs /dev/rbd/$POOL_NAME/${RBD_IMAGE}"
            fi

            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "mkdir -p /mnt/rbd/${RBD_IMAGE}"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "mount /dev/rbd/$POOL_NAME/${RBD_IMAGE} /mnt/rbd/${RBD_IMAGE}"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} df -h
            END_OF_SCRIPT
            ;;
        4) # Copy data to RBD images
            echo ">> Please enter the RBD image name (Default: rbd-image)"
            read RBD_IMAGE
            if [[ $RBD_IMAGE == "" ]]; then
              RBD_IMAGE="rbd-image"
            fi

            echo ">> Do you want to delete the data in the mounted volumes before copying? (y/N)"
            read DELETE_DATA_IN_MOUNTED_VOLUMES
            if [[ $DELETE_DATA_IN_MOUNTED_VOLUMES == "y" ]]; then
              echo "-- Deleting/Cleaning ..."
              ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} rm -rf /mnt/rbd/$RBD_IMAGE/*
            fi
            mkdir -p rbd/$RBD_IMAGE
            echo ">> Please put your files in "rbd/$RBD_IMAGE" folder (rbd/$RBD_IMAGE folder just created in your computer if not exist"
            echo "Press any key to continue ..."
            read
            echo "-- Copying ..."
            rsync -r --progress rbd/$RBD_IMAGE/* ${SSH_USERNAME}@${PVE_DEFAULT}:/mnt/rbd/$RBD_IMAGE/
            END_OF_SCRIPT
            ;;
        5) # Copy data from RBD images
            echo ">> Please enter the RBD image name to mount in /mnt/rbd/$RBD_IMAGE (Default: rbd-image)"
            read RBD_IMAGE
            if [[ $RBD_IMAGE == "" ]]; then
              RBD_IMAGE="rbd-image"
            fi

            echo "-- Copying ..."
            rsync -r --progress ${SSH_USERNAME}@${PVE_DEFAULT}:/mnt/rbd/$RBD_IMAGE/* rbd/$RBD_IMAGE/
            END_OF_SCRIPT
            ;;
        pg)
            # Laurent Barbe
            # Credit: http://cephnotes.ksperis.com/blog/2015/02/23/get-the-number-of-placement-groups-per-osd
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} bash << '__EOF__'
ceph pg dump | awk '
BEGIN { IGNORECASE = 1 }
/^PG_STAT/ { col=1; while($col!="UP") {col++}; col++ }
/^[0-9a-f]+\.[0-9a-f]+/ { match($0,/^[0-9a-f]+/); pool=substr($0, RSTART, RLENGTH); poollist[pool]=0;
up=$col; i=0; RSTART=0; RLENGTH=0; delete osds; while(match(up,/[0-9]+/)>0) { osds[++i]=substr(up,RSTART,RLENGTH); up = substr(up, RSTART+RLENGTH) }
for(i in osds) {array[osds[i],pool]++; osdlist[osds[i]];}
}
END {
printf("\n");
printf("pool :\t"); for (i in poollist) printf("%s\t",i); printf("| SUM \n");
for (i in poollist) printf("--------"); printf("----------------\n");
for (i in osdlist) { printf("osd.%i\t", i); sum=0;
  for (j in poollist) { printf("%i\t", array[i,j]); sum+=array[i,j]; sumpool[j]+=array[i,j] }; printf("| %i\n",sum) }
for (i in poollist) printf("--------"); printf("----------------\n");
printf("SUM :\t"); for (i in poollist) printf("%s\t",sumpool[i]); printf("|\n");
}'
__EOF__
            END_OF_SCRIPT
            ;;
        z1)
            # Zap disk in PVE1
            echo "PVE1 Disks:"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} "find /dev/disk/by-id/ -type l|xargs -I{} ls -l {}|grep -v -E '[0-9]$' |sort -k11|cut -d' ' -f9,10,11,12"
            echo ">> Please enter the disk name to zap in PVE1:"
            read PVE1_CEPH_DISK
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} ceph-volume lvm zap ${PVE1_CEPH_DISK} --destroy
            END_OF_SCRIPT 
            ;;
        z2)
            # Zap disk in PVE2
            echo "PVE2 Disks:"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE2} "find /dev/disk/by-id/ -type l|xargs -I{} ls -l {}|grep -v -E '[0-9]$' |sort -k11|cut -d' ' -f9,10,11,12"
            echo ">> Please enter the disk name to zap in PVE2:"
            read PVE2_CEPH_DISK
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE2} ceph-volume lvm zap ${PVE2_CEPH_DISK} --destroy
            END_OF_SCRIPT 
            ;;
        z3)
            # Zap disk in PVE3
            echo "PVE3 Disks:"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE3} "find /dev/disk/by-id/ -type l|xargs -I{} ls -l {}|grep -v -E '[0-9]$' |sort -k11|cut -d' ' -f9,10,11,12"
            echo ">> Please enter the disk name to zap in PVE3:"
            read PVE3_CEPH_DISK
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE3} ceph-volume lvm zap ${PVE3_CEPH_DISK} --destroy
            END_OF_SCRIPT 
            ;;
        um) # Unmount RBD 
            echo ">> Please enter the RBD image name to mount in /mnt/rbd/ (Default: rbd-image)"
            read RBD_IMAGE
            if [[ $RBD_IMAGE == "" ]]; then
              RBD_IMAGE="rbd-image"
            fi

            echo "-- Unmounting and unmapping ${RBD_IMAGE} .."
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "umount /mnt/rbd/${RBD_IMAGE}"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd unmap -o force ${RBD_IMAGE} --pool=$POOL_NAME --id admin --keyring /etc/pve/priv/ceph.client.admin.keyring"
            END_OF_SCRIPT
            ;;
        del) # Delete RBD image            
            echo "-- List of current RBD images in \"$POOL_NAME\" pool:"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd ls --pool $POOL_NAME"

            echo ">> Please enter the RBD image name to delete (Default: rbd-image)"
            read RBD_IMAGE
            if [[ $RBD_IMAGE == "" ]]; then
              RBD_IMAGE="rbd-image"
            fi
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd rm ${RBD_IMAGE} --pool $POOL_NAME"
            ;;
        nukE)
          echo "Please enter the storage ID to store the iso files in (Default: cephfs)"
          read ISO_STORAGE_ID
          if [[ $ISO_STORAGE_ID == "" ]]; then
            ISO_STORAGE_ID="cephfs"
          fi
          echo "Please enter the iso download location on PVE1 (Default: /mnt/pve/cephfs/template/iso/)"
          read ISO_DOWNLOAD_LOCATION
          if [[ $ISO_DOWNLOAD_LOCATION == "" ]]; then
            ISO_DOWNLOAD_LOCATION="/mnt/pve/cephfs/template/iso/"
          fi
          echo "Please enter the VM ID (Default: 911)"
          read VM_ID
          if [[ $VM_ID == "" ]]; then
            VM_ID="911"
          fi
          echo "In which PVE do you want to create the \"ShredOS - Disk Eraser\" VM (1, 2 or 3)? (Default: 2)"
          read PVE_NUM
          if [[ $PVE_NUM == "" ]]; then
            PVE_NUM="2"
          fi
          if [[ $PVE_NUM == "1" ]]; then
            PVE_IP=${PVE1}
          fi
          if [[ $PVE_NUM == "2" ]]; then
            PVE_IP=${PVE2}
          fi
          if [[ $PVE_NUM == "3" ]]; then
            PVE_IP=${PVE3}
          fi
          ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@$PVE_IP lsusb
          echo ">> Please enter the disk ID to attach to \"ShredOS - Disk Eraser\" VM (Example abcd:1234):"
          read PVE_CEPH_DISK
          echo "-- Creating VM: ${VM_ID} in PVE${PVE_NUM}: .."
          ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@$PVE_IP bash << ___EOF___
#!/bin/bash
if [ ! -f "${ISO_DOWNLOAD_LOCATION}shredos-2021.08.2_23_x86-64_0.34_20221231.iso" ]; then
  curl -L https://github.com/PartialVolume/shredos.x86_64/releases/download/v2021.08.2_23_x86-64_0.34/shredos-2021.08.2_23_x86-64_0.34_20221231.iso -o ${ISO_DOWNLOAD_LOCATION}shredos-2021.08.2_23_x86-64_0.34_20221231.iso
fi

qm unlock ${VM_ID} &>/dev/null
qm stop ${VM_ID} &>/dev/null
qm destroy ${VM_ID} --destroy-unreferenced-disks --purge true --skiplock true &>/dev/null

qm create ${VM_ID} \
    --cdrom ${ISO_STORAGE_ID}:iso/shredos-2021.08.2_23_x86-64_0.34_20221231.iso \
    --name "shredos-disk-eraser" \
    --memory ${PVE_MEMORY} \
    --cpu host \
    --cores ${PVE_CPU_CORES} \
    --ostype l26
qm set ${VM_ID} -usb0 host=${PVE_CEPH_DISK}
qm start ${VM_ID}
___EOF___
            PVE_HOST_NAME=$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@$PVE_IP hostname)
            URL='https://'${PVE_IP}':8006/?console=kvm&novnc=1&vmid='${VM_ID}'&vmname=shredos-disk-eraser&node='${PVE_HOST_NAME}'&resize=off&cmd='
            echo "VM CONSOLE: $URL"
            open $URL
            echo "Please press any key to continue and delete \"ShredOS - Disk Eraser\" VM .."
            read
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@$PVE_IP bash << ___EOF___
qm unlock ${VM_ID}
qm stop ${VM_ID}
qm destroy ${VM_ID} --destroy-unreferenced-disks --purge true --skiplock true
___EOF___
            END_OF_SCRIPT
            ;;
        *)
          echo "--?-- Invalid option"
          sleep 1
          ;;
        esac
      done
      ;;
##############################################################
##############################################################
# DEPLOYMENT
##############################################################
##############################################################
    d)
      if [ ! -f "auto-gen/ceph.env" ] || [[ $FSID == "" ]] || [[ $ADMIN_USER_KEY == "" ]] || [[ $KUBECONFIG == "" ]]; then
        mkdir -p auto-gen
        echo "-- auto-gen/ceph.env file not found or environment variables not set .."
        echo "-- Getting FSID and ADMIN_USER_KEY from Proxmox cluster .. please wait .."
        echo "FSID="$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "ceph fsid") > auto-gen/ceph.env
        echo "ADMIN_USER_KEY="$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} cat /etc/pve/priv/ceph.client.admin.keyring | grep key |  sed 's/.*key = //') >> auto-gen/ceph.env
        echo "MON1=${PVE1}" >> auto-gen/ceph.env
        echo "MON2=${PVE2}" >> auto-gen/ceph.env
        echo "MON3=${PVE3}" >> auto-gen/ceph.env
        echo "-- Getting KUBECONFIG from Kubernetes cluster .. please wait .."
        k3sup install --skip-install --ip $LB --local-path $KUBECONFIG &>/dev/null
      fi
      source auto-gen/ceph.env
      echo "-- FSID: ${FSID}"
      echo "-- MON1: ${PVE1}"
      echo "-- MON2: ${PVE2}"
      echo "-- MON3: ${PVE3}"
      while true
      do
      clear
      echo "--------------------------------------------------------------"
      echo "------------------------- DEPLOYMENT -------------------------"
      echo "--------------------------------------------------------------"
      echo "CLUSTER ID (FSID): $FSID"
      echo "ADMIN USER KEY   : ***********"
      echo "POOL NAME        : $POOL_NAME"
      echo "RECLAIM POLICY   : $RECLAIM_POLICY"
      echo "K8S NAMESPACE    : $K8S_NAMESPACE"
      echo "LOAD BALANCE IP  : $LB"
      echo "--------------------------------------------------------------"
      echo "Please select one of the following options:"
      echo "--------------------------------------------------------------"
      echo "(qc)  < Exit and CLEAN UP"
      echo "(q)   < Exit"
      echo "--------------------------------------------------------------"
      echo "[1]...Install brew, helm (and add repos), kubectl, Kompose,"
      echo "      and CoreUtils on mac"
      echo "[2]...Create \"$K8S_NAMESPACE\" namespaces"
      echo "[3]...Deploy Ceph CSI          | (d3)...Delete Ceph CSI"
      echo "[4]...Create PV/PVC            | (d4)...Delete a PV/PVC"
      echo "--------------------------------------------------------------"
      echo "(5)...Deploy manifest 1        | (d5)...Undeploy manifest 1"
      echo "(6)...Deploy manifest 2        | (d6)...Undeploy manifest 2"
      echo "(7)...Deploy manifest 3        | (d7)...Undeploy manifest 3"
      echo "(8)...Deploy Kompose a Compose | (d8)...Undeploy Kompose"
      echo "(9)...Deploy wordpress         | (d9)...Undeploy wordpress "
      echo "--------------------------------------------------------------"
      read DEPLOYMENT_OPTION
      case $DEPLOYMENT_OPTION in
        qc)
          echo "-- Cleaning up..."
          rm -rf auto-gen/
          rm -rf ceph-csi
          exit 0
          ;;
        q)
          break
          ;;
        1)
          /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
          brew install helm
          brew install kubectl
          brew install coreutils
          helm repo add ceph-csi https://ceph.github.io/csi-charts
          helm repo update
          END_OF_SCRIPT
          ;;
        2)
          kubectl create namespace $K8S_NAMESPACE
          END_OF_SCRIPT
          ;;
        3)
          source auto-gen/ceph.env
          echo "-- FSID: ${FSID}"
          echo "-- ADMIN_USER_KEY: ${ADMIN_USER_KEY}"
          echo "-- MON1: ${PVE1}"
          echo "-- MON2: ${PVE2}"
          echo "-- MON3: ${PVE3}"
          _filesGenerationCeph
          kubectl apply -n kube-system -f auto-gen/csi/csidriver.yaml
          kubectl apply -n kube-system -f auto-gen/csi/csi-provisioner-rbac.yaml
          kubectl apply -n kube-system -f auto-gen/csi/csi-nodeplugin-rbac.yaml
          kubectl apply -n kube-system -f auto-gen/csi/csi-kms-config-map.yaml
          kubectl apply -n kube-system -f auto-gen/csi/csi-config-map.yaml
          kubectl apply -n kube-system -f auto-gen/csi/csi-rbd-secret.yaml
          kubectl apply -n kube-system -f auto-gen/csi/ceph-config-map.yaml
          kubectl apply -n kube-system -f auto-gen/csi/csi-rbdplugin-provisioner.yaml
          kubectl apply -n kube-system -f auto-gen/csi/csi-rbdplugin.yaml
          kubectl apply -n kube-system -f auto-gen/csi/csi-rbd-sc.yaml

          END_OF_SCRIPT
          ;;
        4)
          echo ">> Please enter the volume name (the same as RBD image name) (Default: rbd-image)"
          read RBD_IMAGE_NAME
          if [[ $RBD_IMAGE_NAME == "" ]]; then
            RBD_IMAGE_NAME="rbd-image"
          fi
          echo ">> Please enter the volume size (in GB) (Default: 1G)"
          read SIZE
          if [[ $SIZE == "" ]]; then
            SIZE="1G"
          fi
          _filesGenerationPV
          kubectl apply -f auto-gen/pv/$RBD_IMAGE_NAME-pv.yaml
          kubectl apply -n $K8S_NAMESPACE -f auto-gen/pvc/$RBD_IMAGE_NAME-pvc.yaml
          END_OF_SCRIPT
          ;;
        5)
          nano auto-gen/manifest1.yaml
          kubectl apply -n $K8S_NAMESPACE -f auto-gen/manifest1.yaml
          END_OF_SCRIPT
          ;;
        6)
          nano auto-gen/manifest2.yaml
          kubectl apply -n $K8S_NAMESPACE -f auto-gen/manifest2.yaml
          END_OF_SCRIPT
          ;;
        7)
          nano auto-gen/manifest3.yaml
          kubectl apply -n $K8S_NAMESPACE -f auto-gen/manifest3.yaml
          END_OF_SCRIPT
          ;;
        8)
          mkdir -p auto-gen/kompose
          nano auto-gen/kompose/docker-compose.yaml
          cd auto-gen/kompose
          kompose convert
          kubectl apply -n $K8S_NAMESPACE -f auto-gen/kompose/
          cd ../../
          END_OF_SCRIPT
          ;;
        9)
          clear
          echo "-- List of current RBD images in \"$POOL_NAME\" pool:"
          ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd ls --pool $POOL_NAME"
          
          echo ">> Please enter the volume name (the same as RBD image name) for My SQL (Default: mysql-rbd-image)"
          read MYSQL_RBD_IMAGE_NAME
          if [[ $MYSQL_RBD_IMAGE_NAME == "" ]]; then
            MYSQL_RBD_IMAGE_NAME="mysql-rbd-image"
          fi
          echo ">> Please enter the volume size (in GB) for \"$MYSQL_RBD_IMAGE_NAME\" (Default: 1G)"
          read SIZE
          if [[ $MYSQL_RBD_IMAGE_SIZE == "" ]]; then
            MYSQL_RBD_IMAGE_SIZE="1G"
          fi
          ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd info ${MYSQL_RBD_IMAGE_NAME} --pool $POOL_NAME" &>/dev/null
          if [[ $? == 0 ]]; then
            echo "-- The image \"$MYSQL_RBD_IMAGE_NAME\" is already created in \"$POOL_NAME\" pool"
          else
            echo "-- The image \"$MYSQL_RBD_IMAGE_NAME\" is not created in \"$POOL_NAME\" pool. Creating..."
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd create ${MYSQL_RBD_IMAGE_NAME} --size ${MYSQL_RBD_IMAGE_SIZE} --pool $POOL_NAME"
            if [[ $? != 0 ]]; then
              echo "--?-- Failed to create the image \"$MYSQL_RBD_IMAGE_NAME\" in \"$POOL_NAME\" pool"
              exit 1
            fi
          fi

          echo ">> Please enter the volume name (the same as RBD image name) for WORD PRESS (Default: wp-rbd-image)"
          read WP_RBD_IMAGE_NAME
          if [[ $WP_RBD_IMAGE_NAME == "" ]]; then
            WP_RBD_IMAGE_NAME="wp-rbd-image"
          fi
          echo ">> Please enter the volume size (in GB) for \"$WP_RBD_IMAGE_NAME\" (Default: 1G)"
          read SIZE
          if [[ $WP_RBD_IMAGE_SIZE == "" ]]; then
            WP_RBD_IMAGE_SIZE="1G"
          fi
          ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd info ${WP_RBD_IMAGE_NAME} --pool $POOL_NAME" &>/dev/null
          if [[ $? == 0 ]]; then
            echo "-- The image \"$WP_RBD_IMAGE_NAME\" is already created in \"$POOL_NAME\" pool"
          else
            echo "-- The image \"$WP_RBD_IMAGE_NAME\" is not created in \"$POOL_NAME\" pool. Creating..."
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd create ${WP_RBD_IMAGE_NAME} --size ${WP_RBD_IMAGE_SIZE} --pool $POOL_NAME"
            if [[ $? != 0 ]]; then
              echo "--?-- Failed to create the image \"$WP_RBD_IMAGE_NAME\" in \"$POOL_NAME\" pool"
              exit 1
            fi
          fi

          MYSQL_PASSWORD=$(openssl rand -base64 12)
          echo "-- MYSQL_PASSWORD: $MYSQL_PASSWORD"
          _filesGenerationExample

          nano auto-gen/manifest-wordpress.yaml
          timeout 5 kubectl apply -n $K8S_NAMESPACE -f auto-gen/manifest-wordpress.yaml
          END_OF_SCRIPT
          ;;
        d5)
          echo "-- DELETEING LAST CREATED MANIFEST ..."
          timeout 5 kubectl delete -n $K8S_NAMESPACE -f auto-gen/manifest1.yaml --force --grace-period=0
          END_OF_SCRIPT
          ;;
        d6)
          echo "-- DELETEING LAST CREATED MANIFEST ..."
          timeout 5 kubectl delete -n $K8S_NAMESPACE -f auto-gen/manifest2.yaml --force --grace-period=0
          END_OF_SCRIPT
          ;;
        d7)
          echo "-- DELETEING LAST CREATED MANIFEST ..."
          timeout 5 kubectl delete -n $K8S_NAMESPACE -f auto-gen/manifest3.yaml --force --grace-period=0
          END_OF_SCRIPT
          ;;
        d8)
          echo "-- DELETEING LAST CREATED MANIFEST ..."
          timeout 5 kubectl delete -n $K8S_NAMESPACE -f auto-gen/docker-compose.yaml --force --grace-period=0
          END_OF_SCRIPT
          ;;
        d9)
          echo "-- DELETEING LAST CREATED MANIFEST ..."
          _filesGenerationExample
          timeout 5 kubectl delete -n $K8S_NAMESPACE -f auto-gen/manifest-wordpress.yaml --force --grace-period=0
          END_OF_SCRIPT
          ;;
        d3)
          echo "-- DELETEING CEPH CSI ..."
          source auto-gen/ceph.env
          echo "-- FSID: ${FSID}"
          echo "-- ADMIN_USER_KEY: ${ADMIN_USER_KEY}"
          echo "-- MON1: ${PVE1}"
          echo "-- MON2: ${PVE2}"
          echo "-- MON3: ${PVE3}"
          _filesGenerationCeph
          timeout 5 kubectl delete -n kube-system -f auto-gen/csi/ --force --grace-period=0
          END_OF_SCRIPT
          ;;
        d4)
          echo "-- List of deployed PVs (PV/PVs):"
          kubectl get pv -n $K8S_NAMESPACE
          echo ">> Please enter the volume name (the same as RBD image name) to delete (Default: rbd-image)"
          read RBD_IMAGE_NAME
          if [[ $RBD_IMAGE_NAME == "" ]]; then
            RBD_IMAGE_NAME="rbd-image"
          fi
          timeout 5 kubectl delete pvc -n $K8S_NAMESPACE "${RBD_IMAGE_NAME}-pvc" --force --grace-period=0
          timeout 5 kubectl delete pv -n $K8S_NAMESPACE $RBD_IMAGE_NAME --grace-period=0 --force
          timeout 5 kubectl patch pv -n $K8S_NAMESPACE $RBD_IMAGE_NAME -p '{"metadata": {"finalizers": null}}'
          END_OF_SCRIPT
          ;;
        *)
          echo "--?-- Invalid option"
          sleep 1
          ;;
        esac
      done
      ;;
    *)
      echo "--?-- Invalid option"
      sleep 1
     ;;
  esac
done