#!/bin/bash

function readVar () {
  # $1: Variable name
  # $2: Default value
  # $3: Message
  # $4: Skip if variable is not empty (send any character to skip)

  # echo "-- Setting: $1"
  source auto-gen/.env
  if [[ -z ${!1} ]] || [[ -z $4 ]]; then
    [[ -z ${!1} ]] && eval "$1=$2"
    echo ">> $3: (Default: ${!1})"
    read INPUT
    [[ $INPUT != "" ]] && eval "$1=$INPUT"
  else
    eval "$1=${!1}"
  fi  
  # Save variable value to .env file
  sed -i.BACKUP "/^$1=/d" auto-gen/.env
  # sed -i.BACKUP 's/^\($1=\)*//' auto-gen/.env
  echo "$1=\"${!1}\"" >> auto-gen/.env
}

function nextip() {
    IP=$1
    IP_HEX=$(printf '%.2X%.2X%.2X%.2X\n' `echo $IP | sed -e 's/\./ /g'`)
    NEXT_IP_HEX=$(printf %.8X `echo $(( 0x$IP_HEX + 1 ))`)
    NEXT_IP=$(printf '%d.%d.%d.%d\n' `echo $NEXT_IP_HEX | sed -r 's/(..)/0x\1 /g'`)
    echo "$NEXT_IP"
}

function _filesGenerationCeph () {
  mkdir -p auto-gen/csi
  # Ceph RBD CSI GitHub: https://github.com/ceph/ceph-csi/tree/release-v3.8/deploy/rbd/kubernetes
  # Ceph RBD CSI Offical: https://docs.ceph.com/en/latest/rbd/rbd-kubernetes/
  if [ ! -f "auto-gen/csi/csi-config-map.yaml" ]; then
    echo "-- At least one of file core ceph-csi files is missing, downloading them now ..."
    git clone --quiet https://github.com/ceph/ceph-csi.git > /dev/null
    # git clone --quiet https://github.com/ceph/ceph-csi.git --branch release-v3.8 > /dev/null
    sed -i.BACKUP -e 's/namespace: default/namespace: kube-system/g' ceph-csi/deploy/rbd/kubernetes/*.yaml
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
  echo "👍 Script executed successfully. Press any key to continue .."
  echo "-------------------------------------------------------------"
  read
}

##############################################################################################################
echo "---------------------------------------------------------------"
echo "Welcome to the Proxmox Ceph K8s HA deployment script"
echo "---------------------------------------------------------------"
echo "Please answer the following questions to create the pve.env"
echo "file and setting the environment variables"
echo "---------------------------------------------------------------"
mkdir -p auto-gen
source auto-gen/.env

readVar PVE1 "192.168.100.10" "Please entre the PVE1 IP" 1
readVar PVE2 "$(nextip $PVE1)" "Please entre the PVE2 IP" 1
readVar PVE3 "$(nextip $PVE2)" "Please entre the PVE3 IP" 1

_PVE_DEFAULT_ID=$PVE_DEFAULT_ID
readVar PVE_DEFAULT_ID "PVE1" "Which PVE is the default PVE server for Proxmox cluster (PVE1, PVE2 or PVE3)" 1
if [ "$_PVE_DEFAULT_ID" != "$PVE_DEFAULT_ID" ]; then
  PVE_DEFAULT=${!PVE_DEFAULT_ID}
  sed -i.BACKUP "/PVE_DEFAULT=/d" auto-gen/.env
  echo "PVE_DEFAULT=\"${PVE_DEFAULT}\"" >> auto-gen/.env
fi

MESSAGE='Please entre the nodes placement in PVE hosts (1, 2 or 3) with a dash between them:
Example: "1-1-1" means deploying three nodes kurbernetes cluster, all in PVE1.
Example: "1-1-2-2-3-3" means deploying six nodes kurbernetes cluster where 2 nodes in PVE1, 2 nodes in PVE2 and 2 nodes in PVE3.
Example: "2" means deploying one node kurbernetes cluster in PVE2'

_VM_PLACEMENT_STRING=$VM_PLACEMENT_STRING
readVar VM_PLACEMENT_STRING '1-2-3' "$MESSAGE" 1
if [ "$_VM_PLACEMENT_STRING" != "$VM_PLACEMENT_STRING" ]; then
  VM_PLACEMENT="${VM_PLACEMENT_STRING//1/"$PVE1"}"
  VM_PLACEMENT="${VM_PLACEMENT//2/"$PVE2"}"
  VM_PLACEMENT="${VM_PLACEMENT//3/"$PVE3"}"
  VM_PLACEMENT="(${VM_PLACEMENT//-/ })"
  sed -i.BACKUP "/VM_PLACEMENT=/d" auto-gen/.env
  echo "VM_PLACEMENT=${VM_PLACEMENT}" >> auto-gen/.env
fi

MESSAGE="Please entre kubernetes cluster's nodes IP prefix ignoring the last digit -to be concatenated with the node ID starting from zero-:
-- Example: "$(nextip $PVE3)" with three nodes cluster means the nodes IPs will be $(nextip $PVE3)1, $(nextip $PVE3)2 and $(nextip $PVE3)3
-- Example: "10.10.4.1" with six nodes cluster means the nodes IPs will be 10.10.4.11, 10.10.4.12, 10.10.4.13, 10.10.4.14, 10.10.4.15, 10.10.4.16"
readVar NODE_IP_PREFIX "$(nextip $PVE3)" "$MESSAGE" 1
MESSAGE="Please entre the CIDR suffix for VM IPs:
-- Example: "24" the nodes IPs will be ${NODE_IP_PREFIX}1/24"
readVar CIDR_SUFFIX "24" "$MESSAGE" 1
readVar LB "${NODE_IP_PREFIX}1" "Please entre the K8s Load Balancer IP or just simply node1 IP" 1
MESSAGE='Please the VM prefix ID where the last digit is ignored -to be concatenated with the node ID starting from 1-):
Example: "100" with three nodes cluster means the VMs IDs will be 1001, 1002 and 1003
Example: "10" with six nodes cluster means the VMs IDs will be 101, 102, 103, 104, 105, 106'
readVar VM_ID_PREFIX "100" "$MESSAGE" 1
readVar SSH_USERNAME "root" "Please entre the SSH username for PVE and VMs" 1
readVar MY_PUBLIC_KEY "/Users/$(echo $USER)/.ssh/id_rsa.pub" "Please entre the path of your public key to SSH into the VMs" 1

if [ "$KUBECONFIG" == "" ]; then
  KUBECONFIG='"~/.kube/config"'
  sed -i.BACKUP "/KUBECONFIG=/d" auto-gen/.env
  echo "KUBECONFIG=${KUBECONFIG}" >> auto-gen/.env
fi
if [ "$VM_DNS" == "" ]; then
  VM_DNS=$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "cat /etc/resolv.conf | grep nameserver | awk '{print \$2}'")
  sed -i.BACKUP "/VM_DNS=/d" auto-gen/.env
  echo "VM_DNS=${VM_DNS}" >> auto-gen/.env
fi
if [ "$SEARCH_DOMAIN" == "" ]; then
  SEARCH_DOMAIN=$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "domainname -d")
  sed -i.BACKUP "/SEARCH_DOMAIN=/d" auto-gen/.env
  echo "SEARCH_DOMAIN=${SEARCH_DOMAIN}" >> auto-gen/.env
fi
if [ "$ISO_STORAGE_ID" == "" ]; then
  ISO_STORAGE_ID=$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "pvesm status --enabled --content iso" | sed -n 2p | awk '{print $1}')
  sed -i.BACKUP "/ISO_STORAGE_ID=/d" auto-gen/.env
  echo "ISO_STORAGE_ID=${ISO_STORAGE_ID}" >> auto-gen/.env
fi
if [ "$DEFAULT_IMAGES_STORAGE_ID" == "" ]; then
  DEFAULT_IMAGES_STORAGE_ID=$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "pvesm status --enabled --content images" | sed -n 2p | awk '{print $1}')
  sed -i.BACKUP "/DEFAULT_IMAGES_STORAGE_ID=/d" auto-gen/.env
  echo "DEFAULT_IMAGES_STORAGE_ID=${DEFAULT_IMAGES_STORAGE_ID}" >> auto-gen/.env
fi
if [ "$ISO_PATH" == "" ]; then
  ISO_PATH=$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "cat /etc/pve/storage.cfg | grep ${ISO_STORAGE_ID} -A 1 | grep path")/template/iso/
  ISO_PATH=${ISO_PATH#*path }
  sed -i.BACKUP "/ISO_PATH=/d" auto-gen/.env
  echo "ISO_PATH=${ISO_PATH}" >> auto-gen/.env
fi
readVar KUBECONFIG KUBECONFIG "Please entre the path for KUBECONFIG" 1
readVar PROXMOX_HOST_PRIVATE_KEY "/etc/ssh/ssh_host_rsa_key" "Please entre the path to the private key for the proxmox host" 1
readVar PROXMOX_HOST_KNOWN_HOSTS "/etc/pve/priv/known_hosts" "Please entre the path to the known_hosts file for the proxmox host" 1
readVar PVE_CPU_CORES "2" "Please entre the number of CPUs for each VM in kubernetes cluster" 1
readVar PVE_MEMORY "2048" "Please entre the amount of RAM for each VM in kubernetes cluster" 1
readVar VM_DNS "$VM_DNS" "Please entre the DNS IP for in kubernetes cluster's VMs" 1
readVar SEARCH_DOMAIN "$SEARCH_DOMAIN" "Please entre the DNS search domain for in kubernetes cluster's VMs" 1
readVar VM_BRIDG "vmbr0" "Please entre the default bridge for the VMs" 1

if [ "$STORAGEID" == "" ]; then
  echo "-----------------------------------"
  echo "-- List of available storage IDs that supports images:"
  echo "-----------------------------------"
  ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "pvesm status --enabled --content images"
  echo "-----------------------------------"
fi
readVar STORAGEID "$DEFAULT_IMAGES_STORAGE_ID" "Please entre the storage ID for in kubernetes cluster's VMs." 1

if [ "$CLOUDINIT_STORAGEID" == "" ]; then
  echo "-----------------------------------"
  echo "-- List of available storage IDs that supports images:"
  echo "-----------------------------------"
  ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "pvesm status --enabled --content images"
  echo "-----------------------------------"
fi
readVar CLOUDINIT_STORAGEID "$DEFAULT_IMAGES_STORAGE_ID" "Please entre the storage ID for cloud-init" 1

readVar DOWNLOAD_FOLDER "/mnt/pve/cephfs/images/000" "Please entre the download folder for raw cloud images" 1
readVar CLOUD_IMAGE_URL "https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.raw" "Please entre the cloud image URL" 1
readVar FILENAME "debian-11-generic-amd64.raw" "Please entre the cloud image file name" 1

_RECLAIM_POLICY=$RECLAIM_POLICY
readVar RECLAIM_POLICY "Delete" "Please enter Ceph reclaim policy (Delete or Retain)" 1
if [ "_$RECLAIM_POLICY" != "$RECLAIM_POLICY" ]; then
  if [[ $RECLAIM_POLICY != "Retain" ]]; then
    STATIC_VOLUME="false"
  else
    STATIC_VOLUME="true"
  fi
  sed -i.BACKUP "/STATIC_VOLUME=/d" auto-gen/.env
  echo "STATIC_VOLUME=${STATIC_VOLUME}" >> auto-gen/.env
fi

readVar K8S_NAMESPACE "homelab" "Please enter Kubernetes namespace" 1
readVar K8S_CLUSTER_IP "10.244.0.0/16" "Please enter Kubernetes cluster IP/CIDR" 1
readVar K8S_SERVICE_IP "192.168.244.0/24" "Please enter Kubernetes service IP/CIDR" 1
readVar POOL_NAME "rbd" "Please enter Ceph pool name" 1
##############################################################################################################
source auto-gen/.env
while true
do
  clear
  echo "-----------------------------------------------------------"
  echo "Welcome to the Proxmox Ceph K8s HA deployment script"
  echo "Please select one of rhe following options:"
  echo "-----------------------------------------------------------"
  echo "(qc)   < QUIT AND CLEAN UP ENVIRONMENT & FILES"
  echo "(q)    < Quit"
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
  echo "(19)...Start Docker LXC Installation Wizard"
  echo "(20)...Start Home Assistant OS VM Installation Wizard"
  echo "(21)...Override VM info baed on auto-gen/override.env"
  pwd
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
      # check if command k9s is installed
      if ! command -v k9s &> /dev/null
      then
          echo "k9s could not be found"
          echo "Do you want to install k9s to monitor K8s cluster? (Y/n)"
          read -r INSTALL_K9S
          if [[ $INSTALL_K9S != "n" ]]; then
            echo "Installing k9s..."
            brew install derailed/k9s/k9s
          fi
      fi
      k9s -A
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
      if ! command -v tree &> /dev/null
      then
          echo "tree comand could not be found"
          echo "Do you want to install tree to monitor auto generated files? (Y/n)"
          read -r INSTALL_TREE
          if [[ $INSTALL_TREE != "n" ]]; then
            echo "Installing tree..."
            brew install tree
          fi
      fi
      watch tree auto-gen
      ;;
    16) # Print environment variables
      clear
      echo "-------------------------------------------------"
      echo "-------------- auto-gen/.env --------------------"
      echo "-------------------------------------------------"
      cat auto-gen/.env
      END_OF_SCRIPT
      ;;
      17) ## ssh into PVE_DEFAULT
          echo "Tip: type exit to exit"
          ssh -t -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} bash
          ;;
      18) ## ssh into node1
          echo "Tip: type exit to exit"
          ssh -t -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${NODE_IP_PREFIX}1 bash
        ;;
      19)
        ssh -t -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} bash -c "$(wget -qLO - https://github.com/tteck/Proxmox/raw/main/ct/docker.sh)"
        echo "Credit goes to tteck"
        END_OF_SCRIPT
        ;;
      20)
        ssh -t -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} bash -c "$(wget -qLO - https://github.com/tteck/Proxmox/raw/main/vm/haos-vm.sh)"
        echo "Credit goes to tteck"
        END_OF_SCRIPT
        ;;
      21) # Override VM info baed on auto-gen/override.env
        if [ ! -f "auto-gen/override.env" ]; then
          echo '# EXAMPLE
# OVERRIVE_VM_NAMES=("docker" "docker-1" "docker-2")
# OVERRIVE_VM_IPs=("10.10.10.1/16" "192.168.1.2/24" "192.168.2.2/24")
# OVERRIVE_VM_GW=("10.10.1.1" "192.168.1.1" "192.168.2.1")
# OVERRIVE_VM_DNS=("10.10.1.1" "192.168.1.1" "192.168.2.1")
# OVERRIVE_VM_DOMAIN=("base.example.com" "sub1.base.example.com" "sub2.base.example.com")
# OVERRIVE_VM_BR=("vmbr0" "vmbr1" "vmbr1")
# OVERRIVE_VM_VLAN=("" "1" "2")' > auto-gen/override.env
        fi
        nano auto-gen/override.env
        source auto-gen/override.env
        ID=1
        INDEX=0
        for PLACEMENT in ${VM_PLACEMENT[@]}
        do
          VM_ID=${VM_ID_PREFIX}${ID}
          ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PLACEMENT} bash << ___EOF___
#!/bin/bash
echo "-- Updating VM ${VM_ID} ..."
qm set ${VM_ID} --name ${OVERRIVE_VM_NAMES[$INDEX]}
qm set ${VM_ID} --net0 model=virtio,bridge=${OVERRIVE_VM_BR[$INDEX]},firewall=0$(if [[ ${OVERRIVE_VM_VLAN[$INDEX]} != "" ]]; then echo ",tag=${OVERRIVE_VM_VLAN[$INDEX]}"; fi)
qm set ${VM_ID} --nameserver "${OVERRIVE_VM_DNS[$INDEX]}"
qm set ${VM_ID} --searchdomain "${OVERRIVE_VM_DOMAIN[$INDEX]}"
qm set ${VM_ID} --ipconfig0 "ip=${OVERRIVE_VM_IPs[$INDEX]},gw=${OVERRIVE_VM_GW[$INDEX]}"
qm cloudinit update ${VM_ID}
echo "-- Rebooting VM ${VM_ID} ..."
qm reboot ${VM_ID}
___EOF___
        ID=$(( ID+1 ))
        INDEX=$(( INDEX+1 ))
        done
        END_OF_SCRIPT
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
        echo "(qc)   < QUIT AND CLEAN UP ENVIRONMENT & FILES"
        echo "(q)    < Back to main menu"
        echo "----------------------------------------------------"
        echo "[1]....Initiate the infrastructure"
        echo "[2]....Download cloud image (libguestfs-tools will be installed)"
        echo "[3]....Build cluster's nodes (VMs creation)"
        echo "[4]....Install k3sup on mac"
        echo "[5]....Deploy Kubernetes cluster (k3s) and Back to main menu"
        echo "[6]....Install Docker on all nodes and Back to main menu"
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
            echo "-- Cleaning ${PVE} keys ..."
            ssh-keygen -f ~/.ssh/known_hosts -R "${PVE}" >> ~/.ssh/known_hosts
            ssh-keyscan -H "${PVE}" >> ~/.ssh/known_hosts
          done
          echo "-- Cleaing kurbenetes keys ..."
          ID=1
          for NODE in ${VM_PLACEMENT[@]}
          do
            echo "-- Cleaning ${NODE} keys ..."
            ssh-keygen -f ~/.ssh/known_hosts -R "${NODE}"  >> ~/.ssh/known_hosts 
            ssh-keygen -f ~/.ssh/known_hosts -R "${NODE_IP_PREFIX}${ID}" >> ~/.ssh/known_hosts
            ID=$((ID+1))
          done

          for PVE in ${PVE1} ${PVE2} ${PVE3}
          do
            echo "-- Authorizing ssh to ${PVE} ..."
            ssh-copy-id -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE} >> ~/.ssh/known_hosts >/dev/null 2>&1
          done 
          for PVE in ${PVE1} ${PVE2} ${PVE3}
          do
          echo "-- Setting up ssh keys on ${PVE} ..."
          ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE} bash << ___EOF___
#!/bin/bash
cp /root/.ssh/id_rsa /tmp/id_rsa.BACKUP.$(date +%Y%m%d%H%M%S) >/dev/null 2>&1
cp /root/.ssh/id_rsa.pub /tmp/id_rsa.pub.BACKUP.$(date +%Y%m%d%H%M%S) >/dev/null 2>&1
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
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE} rm -f ${DOWNLOAD_FOLDER}/$FILENAME
          done
          for PVE in ${PVE1} ${PVE2} ${PVE3}
          do
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE} bash << ___EOF___
#!/bin/bash
mkdir -p ${DOWNLOAD_FOLDER}
cd ${DOWNLOAD_FOLDER}
if [ ! -f "$FILENAME" ]; then
  curl -L ${CLOUD_IMAGE_URL} -o "$FILENAME"
  qemu-img resize -f raw $FILENAME +8G
  apt-get install -y libguestfs-tools
  virt-customize -a $FILENAME --install qemu-guest-agent
  virt-customize -a $FILENAME --install curl
  virt-customize -a $FILENAME --install util-linux
  virt-customize -a $FILENAME --install coreutils
  virt-customize -a $FILENAME --install gnupg
  virt-customize -a $FILENAME --install git
  virt-customize -a $FILENAME --install glusterfs-client
  virt-customize -a $FILENAME --run-command "systemctl enable qemu-guest-agent"
  virt-customize -a $FILENAME --run-command "\
        sed -i '/#PermitRootLogin prohibit-password/c\PermitRootLogin yes' /etc/ssh/sshd_config && \
        sed -i '/PasswordAuthentication no/c\PasswordAuthentication yes' /etc/ssh/sshd_config && \
        sed -i '/#   StrictHostKeyChecking ask/c\    StrictHostKeyChecking no' /etc/ssh/ssh_config && \
        echo 'source /etc/network/interfaces.d/*' > /etc/network/interfaces && \
        sed -i '/#net.ipv4.ip_forward=1/c\net.ipv4.ip_forward=1' /etc/sysctl.conf && \
        sed -i '/#net.ipv6.conf.all.forwarding=1/c\net.ipv6.conf.all.forwarding=1' /etc/sysctl.conf && \
        sed -i '/#DefaultTimeoutStopSec=90s/c\DefaultTimeoutStopSec=10s' /etc/systemd/system.conf && \
        sed -i '/ - update_etc_hosts/c\#  - update_etc_hosts' /etc/cloud/cloud.cfg && \
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"/&usbcore.autosuspend=-1 /' /etc/default/grub && \
        update-grub"
fi
___EOF___
          done
        END_OF_SCRIPT
        ;;
        3) ## Create VMs
          ID=1
          for PLACEMENT in ${VM_PLACEMENT[@]}
          do
            echo "-- Creating VM: node${ID}"
            VM_NAME="node${ID}"
            VM_ID=${VM_ID_PREFIX}${ID}
            FULLNAME=${VM_NAME}.${SEARCH_DOMAIN}
            scp $MY_PUBLIC_KEY ${SSH_USERNAME}@${PLACEMENT}:/tmp/.key
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PLACEMENT} bash << ___EOF___
#!/bin/bash
ssh-keygen -y -f ${PROXMOX_HOST_PRIVATE_KEY} >> /tmp/.key
qm create ${VM_ID} \
    --memory ${PVE_MEMORY} \
    --net0 model=virtio,bridge=${VM_BRIDG},firewall=0 \
    --scsihw virtio-scsi-single \
    --boot c \
    --bootdisk scsi0 \
    --ide2 ${CLOUDINIT_STORAGEID}:cloudinit \
    --ciuser "${SSH_USERNAME}" \
    --sshkey /tmp/.key \
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
    --ipconfig0 "ip=${NODE_IP_PREFIX}${ID}/${CIDR_SUFFIX},gw=${VM_DNS}" \
    --name ${VM_NAME}
qm cloudinit update ${VM_ID}
qm importdisk ${VM_ID} ${DOWNLOAD_FOLDER}/$FILENAME ${STORAGEID} --format raw
qm set ${VM_ID} --scsi0 ${STORAGEID}:vm-${VM_ID}-disk-0,aio=threads,backup=1,cache=writeback,iothread=1,replicate=1,ssd=1 >/dev/null 2>&1
qm set ${VM_ID} --scsi0 ${STORAGEID}:${VM_ID}/vm-${VM_ID}-disk-0.raw,aio=threads,backup=1,cache=writeback,iothread=1,replicate=1,ssd=1 >/dev/null 2>&1
qm start ${VM_ID}
#ha-manager add vm:${VM_ID} --state started --max_relocate 0 --max_restart 5 --group ${VM_NAME}
rm -f /tmp/.key
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
            FQDN=node${ID}.${SEARCH_DOMAIN}
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
                                             --cluster-cidr=${K8S_CLUSTER_IP} \
                                             --service-cidr=${K8S_SERVICE_IP} \
                                             --disable metrics-server" \
                            --cluster                

            else
              k3sup join --user ${SSH_USERNAME} \
                          --ip $IP \
                          --ssh-key $MY_PUBLIC_KEY \
                          --server-user ${SSH_USERNAME} \
                          --server-ip $LB \
                          --k3s-extra-args "--flannel-backend=host-gw \
                                            --cluster-cidr=${K8S_CLUSTER_IP} \
                                            --service-cidr=${K8S_SERVICE_IP} \
                                            --disable metrics-server" \
                          --server
            fi
            
            ID=$(( ID+1 ))
          done
          END_OF_SCRIPT
          break
          ;;
        6) ## Docker
          ID=1
          for PLACMENT in ${VM_PLACEMENT[@]}
          do
            FQDN=node${ID}.${SEARCH_DOMAIN}
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
curl -fsSL https://get.docker.com | sh
____EOF____
            ID=$(( ID+1 ))
          done
          readVar DEPLOY_PORTAINER "n" "Do you want to install Portainer AGENT on all nodes (y/n)" 
          if [[ $DEPLOY_PORTAINER == "y" ]]; then
            ID=1
            for PLACMENT in ${VM_PLACEMENT[@]}
            do
              IP=${NODE_IP_PREFIX}${ID}
              echo "-- Deploying Portainer on node${ID}"
              ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${IP} bash <<'____EOF____'
#!/bin/bash
docker rm -f portainer_agent; docker run -d \
  -p 9001:9001 \
  --name portainer_agent \
  --restart=always \
  -v /docker-volumes:/host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /var/lib/docker/volumes:/var/lib/docker/volumes \
  portainer/agent:2.19.0
____EOF____
            ID=$(( ID+1 ))
          done
          fi
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
k3s-uninstall.sh >/dev/null 2>&1
k3s-agent-uninstall.sh >/dev/null 2>&1
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
                  ssh-keygen -f ~/.ssh/known_hosts -R "node${ID}" 
                  ssh-keygen -f ~/.ssh/known_hosts -R "${NODE_IP_PREFIX}${ID}"
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
        echo "(qc)   < QUIT AND CLEAN UP ENVIRONMENT & FILES"
        echo "(q)    < Back to main menu"
        echo "----------------------------------------------------"
        echo "[1]....Create \"$POOL_NAME\" RBD Pool"
        echo "[2]....Create RBD Images"
        echo "[3]....Mount RBD images"
        echo "[4]....SSH into PVE where the RBD images are mounted"
        echo "[5]....Unmount RBD images"
        echo "[6]....-- Copy files to RBD images -->"
        echo "[7]....<-- Copy files from RBD images --"
        echo "[8]....Permanently mount CephFS inside a Debian VM/CT"
        echo "----------------------------------------------------"
        echo "(test).Test disk speed"
        echo "(ls)...List RBD images and mounts"
        echo "(pg)...Calculate PGs"
        echo "(del)..Delete RBD images"
        echo "(zap)..Zap disks"
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
            readVar RBD_IMAGE "rbd-image" "Please enter the RBD image name to mount in /mnt/rbd:"
            readVar SIZE "rbd-size" "Please enter the size of the RBD image"
            echo "-- Creating ${RBD_IMAGE} RDB with size ${SIZE} at pool \"$POOL_NAME\""
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd create ${RBD_IMAGE} --size=${SIZE} --pool=$POOL_NAME"
            END_OF_SCRIPT
            ;;
        3) # Mount RBD images
            readVar RBD_IMAGE "rbd-image" "Please enter the RBD image name to mount in /mnt/rbd:"
            echo "-- Mapping and mounting ${RBD_IMAGE} RBD to /mnt/rbd/${RBD_IMAGE} folder"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd map ${RBD_IMAGE} --pool $POOL_NAME --id admin --keyring /etc/pve/priv/ceph.client.admin.keyring"
            
            readVar MKFS_RBD_IMAGE "n" "RBD image has been mapped but not mounted yet. Do you want to make filesystem (mkfs.xfs) on the mapped ${RBD_IMAGE} RBD image before mounting? (y/N)"
            if [[ $MKFS_RBD_IMAGE == "y" ]]; then
              ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "mkfs.xfs -f /dev/rbd/$POOL_NAME/${RBD_IMAGE}"
            fi
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "mkdir -p /mnt/rbd/${RBD_IMAGE}"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "mount /dev/rbd/$POOL_NAME/${RBD_IMAGE} /mnt/rbd/${RBD_IMAGE}"
            echo "-------------------------------------------------------------"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "df -h | grep -E 'Filesystem|/mnt/rbd'"
            END_OF_SCRIPT
            ;;
        4) # SSH into PVE where the RBD images are mounted
            ssh -t -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "cd /mnt/rbd/ ; ls -al ; bash --login"
            ;;
        5) # Unmount RBD
            readVar RBD_IMAGE "rbd-image" "Please enter the RBD image name to unmount from /mnt/rbd:"
            echo "-- Unmounting and unmapping ${RBD_IMAGE} .."
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "umount -f /mnt/rbd/${RBD_IMAGE}"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd unmap -o force ${RBD_IMAGE} --pool=$POOL_NAME --id admin --keyring /etc/pve/priv/ceph.client.admin.keyring"
            END_OF_SCRIPT
            ;;
        6) # Copy data to RBD images
            readVar RBD_IMAGE "rbd-image" "Please enter the RBD image name to copy data to:"

            readVar DELETE_DATA_IN_MOUNTED_VOLUMES "n" "Do you want to delete the data in the mounted volumes before copying? (y/n)" 
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
        7) # Copy data from RBD images
            readVar RBD_IMAGE "rbd-image" "Please enter the RBD image name to copy data from:"
            echo "-- Copying ..."
            rsync -r --progress ${SSH_USERNAME}@${PVE_DEFAULT}:/mnt/rbd/$RBD_IMAGE/* rbd/$RBD_IMAGE/
            END_OF_SCRIPT
            ;;
        8)
          readVar "CEPHFS_VM_IP" "${NODE_IP_PREFIX}1" "Please enter the IP address of the VM/CT to mount CephFS inside (make sure you enable \"FUSE\" in the CT options)"
          readVar "CEPHFS_VM_SSH_USERNAME" "$SSH_USERNAME" "What is the SSH username of the VM/CT that you want to mount CephFS on?"
          readVar "CEPHFS_MOUNT_POINT" "/docker-volumes" "Please enter CephFS mount point"
          readVar "CEPHFS_NAME" "cephfs" "Please enter the CephFS name. Listed above"
          readVar "MOUNT_ON_DOCKER_STARTUP" "n" "Do you want to modify /lib/systemd/system/docker.service to mount CephFS on Docker startup? (y/n)"
          readVar "CEPHFS_USER_NAME" "cephfs" "Please enter the CephFS user name"
          readVar "CEPH_SUB_DIR" "/" "Please enter the CephFS subfolder name"

          FSTAB_STRING="none  $CEPHFS_MOUNT_POINT  fuse.ceph  ceph.name=client.$CEPHFS_USER_NAME,ceph.conf=/etc/ceph/ceph.conf,ceph.client_mountpoint=$CEPH_SUB_DIR,_netdev,defaults,nonempty  0  0"
          MOUNT_POINT_CMD_ESCAPED=$(echo $CEPHFS_MOUNT_POINT | sed "s~\(['\"\/]\)~\\\\\1~g")
          MOUNT_POINT_SYSTEMD_ESCAPED=$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} systemd-escape "$CEPHFS_MOUNT_POINT")

          echo "Copying keys and authorising ${CEPHFS_VM_IP} to access PVE1-3 ..."
          ssh-copy-id -f -i ${MY_PUBLIC_KEY} ${CEPHFS_VM_SSH_USERNAME}@${CEPHFS_VM_IP} 
          ssh -i ${MY_PUBLIC_KEY} ${CEPHFS_VM_SSH_USERNAME}@${CEPHFS_VM_IP} '[ ! -f ~/.ssh/id_rsa ] && ssh-keygen -C "$CEPHFS_VM_SSH_USERNAME@$HOSTNAME" -t rsa -b 4096 -f ~/.ssh/id_rsa -q -N "" <<< $'\ny''
          ssh-keygen -f ~/.ssh/known_hosts -R "${CEPHFS_VM_IP}"
          ssh-keyscan -H "${CEPHFS_VM_IP}" >> ~/.ssh/known_hosts
          mkdir -p auto-gen/keys
          scp ${CEPHFS_VM_SSH_USERNAME}@${CEPHFS_VM_IP}:~/.ssh/id_rsa auto-gen/keys/${CEPHFS_VM_IP}.key
          scp ${CEPHFS_VM_SSH_USERNAME}@${CEPHFS_VM_IP}:~/.ssh/id_rsa.pub auto-gen/keys/${CEPHFS_VM_IP}.key.pub
          ssh-copy-id -f -i auto-gen/keys/${CEPHFS_VM_IP}.key ${SSH_USERNAME}@${PVE1}
          ssh-copy-id -f -i auto-gen/keys/${CEPHFS_VM_IP}.key ${SSH_USERNAME}@${PVE2}
          ssh-copy-id -f -i auto-gen/keys/${CEPHFS_VM_IP}.key ${SSH_USERNAME}@${PVE3}
          echo "-- Generating CephFS config and keying files in ${PVE_DEFAULT}"
          ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} bash << __EOF__
echo "-- Keeping a backup copy of /etc/ceph/ceph.conf in /etc/ceph/ceph.conf.BACKUP also in /tmp/"
cp /etc/pve/ceph.conf /etc/ceph/ceph.conf.BACKUP
cp /etc/pve/ceph.conf /tmp/ceph.conf.BACKUP.$(date +%Y%m%d%H%M%S)
if [[ -f /etc/pve/priv/ceph.client.$CEPHFS_USER_NAME.keyring ]]; then
  echo "-- Keeping a backup copy of /etc/pve/priv/ceph.client.$CEPHFS_USER_NAME.keyring in /etc/pve/priv/ceph.client.$CEPHFS_USER_NAME.keyring.BACKUP also in /tmp/"
  cp /etc/pve/priv/ceph.client.$CEPHFS_USER_NAME.keyring /etc/pve/priv/ceph.client.$CEPHFS_USER_NAME.keyring.BACKUP
  cp /etc/pve/priv/ceph.client.$CEPHFS_USER_NAME.keyring /tmp/ceph.client.$CEPHFS_USER_NAME.keyring.BACKUP.$(date +%Y%m%d%H%M%S)
fi
ceph auth rm client.cephfs
ceph fs authorize ${CEPHFS_NAME} client.$CEPHFS_USER_NAME / rw > /etc/pve/priv/ceph.client.$CEPHFS_USER_NAME.keyring
ceph config generate-minimal-conf > /etc/ceph/ceph.minimal.conf
__EOF__
          echo "-- Ceph instlation and configuration in ${CEPHFS_VM_IP}"
          ssh -i ${MY_PUBLIC_KEY} ${CEPHFS_VM_SSH_USERNAME}@${CEPHFS_VM_IP} bash << __EOF__
ssh-keyscan -H ${PVE1} >> ~/.ssh/known_hosts
ssh-keyscan -H ${PVE2} >> ~/.ssh/known_hosts
ssh-keyscan -H ${PVE3} >> ~/.ssh/known_hosts
mkdir -p -m 755 $CEPHFS_MOUNT_POINT
mkdir -p /etc/ceph
rm -f /etc/ceph/ceph.conf && touch /etc/ceph/ceph.conf && chmod 644 /etc/ceph/ceph.conf
rm -f /etc/ceph/ceph.client.$CEPHFS_USER_NAME.keyring && touch /etc/ceph/ceph.client.$CEPHFS_USER_NAME.keyring && chmod 600 /etc/ceph/ceph.client.$CEPHFS_USER_NAME.keyring
echo "-- Installing ceph-common and ceph-fuse"
apt install -y ceph-common ceph-fuse >/dev/null 2>&1
scp ${SSH_USERNAME}@${PVE_DEFAULT}:/etc/ceph/ceph.minimal.conf /etc/ceph/ceph.conf
echo "        client_fs = $CEPHFS_NAME" >> /etc/ceph/ceph.conf
scp ${SSH_USERNAME}@${PVE_DEFAULT}:/etc/pve/priv/ceph.client.$CEPHFS_USER_NAME.keyring /etc/ceph/ceph.client.$CEPHFS_USER_NAME.keyring
sed -i "/$MOUNT_POINT_CMD_ESCAPED/d" /etc/fstab
echo "$FSTAB_STRING" >> /etc/fstab
systemctl daemon-reload 
systemctl start ceph-fuse@$MOUNT_POINT_SYSTEMD_ESCAPED.service
systemctl enable ceph-fuse.target
systemctl enable ceph-fuse@$MOUNT_POINT_SYSTEMD_ESCAPED.service 
umount $CEPHFS_MOUNT_POINT >/dev/null 2>&1
echo "-- Mounting .."
mount -a
echo "-------------------------------------------------------------"
df | grep -E "Filesystem | $CEPHFS_MOUNT_POINT"
__EOF__
            if [ "$MOUNT_ON_DOCKER_STARTUP" == "y" ]; then
              echo "-- Modifying docker service. CEPHFS_MOUNT_POINT: "
              CEPH_FUSE_MOINT_UNIT=$( ssh -i ${MY_PUBLIC_KEY} ${CEPHFS_VM_SSH_USERNAME}@${CEPHFS_VM_IP} "systemctl list-units -t mount" | grep ${CEPHFS_MOUNT_POINT} | awk '{print $1}' )
              CEPH_FUSE_MOINT_UNIT_ESCAPED=$(echo $CEPH_FUSE_MOINT_UNIT | sed "s~\(['\"\/]\)~\\\\\1~g" | sed "s~\(['\"\/]\)~\\\\\1~g")
              GREP_MOINT_POINT_SERVICE="$( ssh -i ${MY_PUBLIC_KEY} ${CEPHFS_VM_SSH_USERNAME}@${CEPHFS_VM_IP} 'cat /lib/systemd/system/docker.service' | grep $CEPH_FUSE_MOINT_UNIT )"
              ssh -i ${MY_PUBLIC_KEY} ${CEPHFS_VM_SSH_USERNAME}@${CEPHFS_VM_IP} bash << __EOF__
if [ "$GREP_MOINT_POINT_SERVICE" == "" ]; then
  echo "-- Making a backup copy of /lib/systemd/system/docker.service in /tmp/"
  cp /lib/systemd/system/docker.service /tmp/docker.service.BACKUP.$(date +%Y%m%d%H%M%S)
  sed -i "s/After=/After=$CEPH_FUSE_MOINT_UNIT_ESCAPED /" /lib/systemd/system/docker.service
  sed -i "s/Requires=/Requires=$CEPH_FUSE_MOINT_UNIT_ESCAPED /" /lib/systemd/system/docker.service
else
  echo "-- \"$CEPH_FUSE_MOINT_UNIT\" exist in /lib/systemd/system/docker.service .. Skipped .."
fi
systemctl daemon-reload
systemctl restart docker
__EOF__
            fi
            END_OF_SCRIPT
            ;;
        test)
            if [ ! -f auto-gen/DISK_SPEED_RESULTS.txt ]; then
              echo "TIME SERVER TARGET WRITE LATENCY READ
            ----------------- ------- ------------------------- ------- ------- -------" | column -t > auto-gen/DISK_SPEED_RESULTS.txt
            fi
            readVar TEST_SERVER ${PVE_DEFAULT} "Please enter the server IP address to test disk speed on"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${TEST_SERVER} "mount | cut -f3 -d' '" > tmp.txt
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${TEST_SERVER} "df -h --output='target,fstype'" >> tmp.txt
            TEST_DIR_MESSAGE="\
Please enter the directory to test write and read speed on.
The script will find the largest file in this directory to use for reading.
Suggestions:
$(cat tmp.txt)
"
            rm -f tmp.txt
            readVar TEST_DIR "/var/lib/pve/local/" "$TEST_DIR_MESSAGE"
            if [[ `ssh ${SSH_USERNAME}@${TEST_SERVER} test -d $TEST_DIR && echo exists` ]]; then
              echo -n "Testing write speed on $TEST_DIR"
              DD_WRITE=$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${TEST_SERVER} "dd if=/dev/zero of=$TEST_DIR/output.img bs=512MB count=2 oflag=dsync 2>&1 | sed 's/ s, /\n/g' | tail -1 | sed -r 's/\s+//g';rm -f $TEST_DIR/output.img")
              echo ": $DD_WRITE"
              echo -n "Testing write latency on $TEST_DIR"
              DD_LATENCY=$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${TEST_SERVER} "dd if=/dev/zero of=$TEST_DIR/output.img bs=512 count=1000 oflag=dsync 2>&1 | sed 's/ s, /\n/g' | tail -1 | sed -r 's/\s+//g';rm -f $TEST_DIR/output.img")
              echo ": $DD_LATENCY"
              echo -n "Testing read speed"
              LARGEST_FILE_FIND_RESULT=$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${TEST_SERVER} "find $TEST_DIR -type f -printf '%s %p\n' -nowarn | sort -nr | head -1")
              LARGEST_FILE_PATH=$(echo $LARGEST_FILE_FIND_RESULT | cut -f2 -d' ')
              LARGEST_FILE_SIZE=$(echo $LARGEST_FILE_FIND_RESULT | cut -f1 -d' ' | awk '{ byte =$1 /1024/1024**2 ; print byte " GB" }')
              ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${TEST_SERVER} "echo 3 | tee /proc/sys/vm/drop_caches > /dev/null"
              echo -n " from $LARGEST_FILE_PATH [$LARGEST_FILE_SIZE]"
              DD_READ=$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${TEST_SERVER} "dd if=$LARGEST_FILE_PATH of=/dev/null bs=8k 2>&1 | sed 's/ s, /\n/g' | tail -1 | sed -r 's/\s+//g'")
              echo ": $DD_READ"
              TEST_DIR_SCAPED=$(echo $TEST_DIR | sed "s~\(['\"\/]\)~\\\\\1~g")
              sed -i.BACKUP "/$TEST_DIR_SCAPED/d" auto-gen/DISK_SPEED_RESULTS.txt
              cp auto-gen/DISK_SPEED_RESULTS.txt tmp.txt
              echo "$(date +'%d-%m-%y-%T') $TEST_SERVER $TEST_DIR $DD_WRITE $DD_LATENCY $DD_READ" >> tmp.txt
              cat tmp.txt | column -t > auto-gen/DISK_SPEED_RESULTS.txt
              rm -f tmp.txt
              cat auto-gen/DISK_SPEED_RESULTS.txt
            else
              echo "ERROR: $TEST_DIR does not exist"
            fi
            END_OF_SCRIPT
            ;;
        ls)
            clear
            echo "-------------------------------------------------------------"
            echo "RBD IMAGES:"
            echo "-------------------------------------------------------------"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd ls --pool $POOL_NAME | grep -v vm-"
            echo "-------------------------------------------------------------"
            echo "CURRENT MOUNTE POINTS FOR RBD IMAGES:"
            echo "-------------------------------------------------------------"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "df -h | grep '/mnt/rbd'"
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
        zap)
            readVar PVE_ZAP $PVE_DEFAULT_ID "In which PVE do you want to zap a disk (PVE1, PVE2 or PVE3)?"
            echo "$PVE_ZAP Disks:"
            PVE_ZAP_IP=${!PVE_ZAP}
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@$PVE_ZAP_IP bash << '___EOF___'
echo "------" && lsblk -e 7,11 -lp -o PATH | grep -v PATH && echo "------" && ls -al /dev/disk/by-id/* | awk '{print $9 " ---> " $11}' && echo "------"
___EOF___
            readVar DISK_PATH "N/A" "Please enter the disk path to zap in PVE${PVE_NUM}: (example: /dev/nvme0n1)"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_ZAP_IP} ceph-volume lvm zap ${DISK_PATH} --destroy

            readVar WIPE_DISK "n" "Do you want to wipe $DISK_PATH"
            if [ "$WIPE_DISK" == "y" ]; then
              ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_ZAP_IP} "dd if=/dev/urandom of=$DISK_PATH bs=1M count=2"
            fi
            END_OF_SCRIPT 
            ;;
        4) # Unmount RBD 
            readVar RBD_IMAGE "rbd-image" "Please enter the RBD image name to mount in /mnt/rbd/"
            echo "-- Unmounting and unmapping ${RBD_IMAGE} .."
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "umount -f /mnt/rbd/${RBD_IMAGE}"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd unmap -o force ${RBD_IMAGE} --pool=$POOL_NAME --id admin --keyring /etc/pve/priv/ceph.client.admin.keyring"
            END_OF_SCRIPT
            ;;
        del) # Delete RBD image
            echo "Listing of current RBD images in \"$POOL_NAME\" pool ..."
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd ls --pool $POOL_NAME | grep -v vm-"
            readVar RBD_IMAGE "rbd-image" "Please enter the RBD image name to delete"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "umount -f /mnt/rbd/${RBD_IMAGE}" >/dev/null 2>&1
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd unmap -o force ${RBD_IMAGE} --pool=$POOL_NAME --id admin --keyring /etc/pve/priv/ceph.client.admin.keyring" >/dev/null 2>&1
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd rm ${RBD_IMAGE} --pool $POOL_NAME"
            END_OF_SCRIPT
            ;;
        nukE)
          if ["$ISO_STORAGE_ID" == ""]; then
            echo "-----------------------------------"
            echo "-- List of available storage IDs that supports images:"
            echo "-----------------------------------"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "pvesm status --enabled --content iso"
            echo "-----------------------------------"
          fi
          readVar ISO_STORAGE_ID $ISO_STORAGE_ID "Please enter the storage ID to download the iso file in"
          readVar ISO_PATH $ISO_PATH "Please enter the iso download location on PVE1 for storage $ISO_STORAGE_ID"
          readVar NUKE_VM_ID "911" "Please enter the nuke VM ID"
          readVar PVE_NUM $PVE_DEFAULT_ID "In which PVE do you want to create the \"ShredOS - Disk Eraser\" VM (PVE1, PVE2 or PVE3)"
          PVE_IP=${!PVE_NUM}
          ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@$PVE_IP bash << '___EOF___'
echo "------" && lsblk -e 7,11 -lp -o PATH | grep -v PATH && echo "------" && ls -al /dev/disk/by-id/* | awk '{print $9 " ---> " $11}' && echo "------"
___EOF___
          readVar PVE_CEPH_DISK "N/A" "Please enter the disk/dev path that you want to wipe (Example /dev/nvme0n1):"
          echo "-- Creating VM ${NUKE_VM_ID} in ${PVE_NUM} and attaching $PVE_CEPH_DISK to it ..."
          ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@$PVE_IP bash << ___EOF___
#!/bin/bash
if [ ! -f "${ISO_PATH}shredos-2021.08.2_23_x86-64_0.34_20221231.iso" ]; then
  curl -L https://github.com/PartialVolume/shredos.x86_64/releases/download/v2021.08.2_23_x86-64_0.34/shredos-2021.08.2_23_x86-64_0.34_20221231.iso -o ${ISO_PATH}shredos-2021.08.2_23_x86-64_0.34_20221231.iso
fi
qm unlock ${NUKE_VM_ID} >/dev/null 2>&1
qm stop ${NUKE_VM_ID} >/dev/null 2>&1
qm destroy ${NUKE_VM_ID} --destroy-unreferenced-disks --purge true --skiplock true >/dev/null 2>&1
qm create ${NUKE_VM_ID} \
    --cdrom ${ISO_STORAGE_ID}:iso/shredos-2021.08.2_23_x86-64_0.34_20221231.iso \
    --name "shredos-disk-eraser" \
    --memory ${PVE_MEMORY} \
    --cpu host \
    --cores ${PVE_CPU_CORES} \
    --ostype l26
qm set ${NUKE_VM_ID} --scsi0 $PVE_CEPH_DISK
qm start ${NUKE_VM_ID}
___EOF___
            PVE_HOST_NAME=$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@$PVE_IP hostname)
            URL='https://'${PVE_IP}':8006/?console=kvm&novnc=1&vmid='${NUKE_VM_ID}'&vmname=shredos-disk-eraser&node='${PVE_HOST_NAME}'&resize=off&cmd='
            echo "VM CONSOLE: $URL"
            open $URL
            echo "Please press any key to continue and delete \"ShredOS - Disk Eraser\" VM .."
            read
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@$PVE_IP bash << ___EOF___
qm unlock ${NUKE_VM_ID}
qm stop ${NUKE_VM_ID}
qm destroy ${NUKE_VM_ID} --destroy-unreferenced-disks --purge true --skiplock true
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
      if [ $FSID == "" ]; then
        FSID=$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "ceph fsid")
        echo "FSID=$FSID" >> auto-gen/ceph.env
      fi
      if [ $ADMIN_USER_KEY == "" ]; then
        ADMIN_USER_KEY="$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} cat /etc/pve/priv/ceph.client.admin.keyring | grep key |  sed 's/.*key = //')"
        echo "ADMIN_USER_KEY=$ADMIN_USER_KEY" >> auto-gen/ceph.env
      fi
      if [ -f $KUBECONFIG ]; then
        echo "-- Getting KUBECONFIG from Kubernetes cluster .. please wait .."
        k3sup install --skip-install --ip $LB --local-path $KUBECONFIG >/dev/null 2>&1
      fi
        
      while true
      do
      clear
      echo "--------------------------------------------------------------"
      echo "------------------------- DEPLOYMENT -------------------------"
      echo "--------------------------------------------------------------"
      echo "CLUSTER ID (FSID): $FSID"
      echo "ADMIN USER KEY   : ***************"
      echo "POOL NAME        : $POOL_NAME"
      echo "RECLAIM POLICY   : $RECLAIM_POLICY"
      echo "K8S NAMESPACE    : $K8S_NAMESPACE"
      echo "LOAD BALANCE IP  : $LB"
      echo "--------------------------------------------------------------"
      echo "Please select one of the following options:"
      echo "--------------------------------------------------------------"
      echo "(qc)  < QUIT AND CLEAN UP ENVIRONMENT & FILES"
      echo "(q)   < Back to main menu"
      echo "--------------------------------------------------------------"
      echo "[1]...Install brew, helm (and add repos), kubectl, Kompose,"
      echo "      and CoreUtils on mac"
      echo "[2]...Create \"$K8S_NAMESPACE\" namespaces"
      echo "[3]...Deploy Ceph CSI          | (r3)..Remove Ceph CSI"
      echo "[4]...Create PV/PVC            | (r4)..Remove a PV/PVC"
      echo "--------------------------------------------------------------"
      echo "(d1)..Deploy manifest 1        | (u1)..Undeploy manifest 1"
      echo "(d2)..Deploy manifest 2        | (u2)..Undeploy manifest 2"
      echo "(d3)..Deploy manifest 3        | (u3)..Undeploy manifest 3"
      echo "(d4)..Deploy Kompose a Compose | (u4)..Undeploy Kompose"
      echo "(d5)..Deploy wordpress         | (u5)..Undeploy wordpress "
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
          if ! command -v brew &> /dev/null
          then
              echo "brew could not be found"
              echo "Do you want to install brew? (Y/n)"
              read -r INSTALL
              if [[ $INSTALL != "n" ]]; then
                echo "Installing brew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
              fi
          fi

          if ! command -v kubectl &> /dev/null
          then
              echo "kubectl could not be found"
              echo "Do you want to install kubectl? (Y/n)"
              read -r INSTALL
              if [[ $INSTALL != "n" ]]; then
                echo "Installing kubectl..."
                brew install kubectl
              fi
          fi

          if ! command -v helm &> /dev/null
          then
              echo "helm could not be found"
              echo "Do you want to install helm? (Y/n)"
              read -r INSTALL
              if [[ $INSTALL != "n" ]]; then
                echo "Installing helm..."
                brew install helm
                helm repo add ceph-csi https://ceph.github.io/csi-charts
                helm repo update
              fi
          fi

          if ! command -v kompose &> /dev/null
          then
              echo "kompose could not be found"
              echo "Do you want to install kompose? (Y/n)"
              read -r INSTALL
              if [[ $INSTALL != "n" ]]; then
                echo "Installing kompose..."
                brew install kompose
              fi
          fi
          echo "Do you want to install CoreUtils? (y/N)"
          read -r INSTALL
          if [[ $INSTALL == "y" ]]; then
            echo "Installing CoreUtils..."
            brew install coreutils
          fi
          END_OF_SCRIPT
          ;;
        2)
          kubectl create namespace $K8S_NAMESPACE
          END_OF_SCRIPT
          ;;
        3)
          source auto-gen/ceph.env
          echo "-- FSID: ${FSID}"
          echo "-- ADMIN_USER_KEY: ***************"
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
          readVar RBD_IMAGE_NAME "rbd-image" "Please enter the volume name (the same as RBD image name)"
          readVar SIZE "1G" "Please enter the volume size (in GB)"
          _filesGenerationPV
          kubectl apply -f auto-gen/pv/$RBD_IMAGE_NAME-pv.yaml
          kubectl apply -n $K8S_NAMESPACE -f auto-gen/pvc/$RBD_IMAGE_NAME-pvc.yaml
          END_OF_SCRIPT
          ;;
        d1)
          nano auto-gen/manifest1.yaml
          kubectl apply -n $K8S_NAMESPACE -f auto-gen/manifest1.yaml
          END_OF_SCRIPT
          ;;
        d2)
          nano auto-gen/manifest2.yaml
          kubectl apply -n $K8S_NAMESPACE -f auto-gen/manifest2.yaml
          END_OF_SCRIPT
          ;;
        d3)
          nano auto-gen/manifest3.yaml
          kubectl apply -n $K8S_NAMESPACE -f auto-gen/manifest3.yaml
          END_OF_SCRIPT
          ;;
        d4)
          nano auto-gen/docker-compose.yaml
          rm -r mkdir -p auto-gen/kompose
          mkdir -p auto-gen/kompose
          cp auto-gen/docker-compose.yaml auto-gen/kompose/docker-compose.yaml
          cd auto-gen/kompose && kompose convert && cd ../../
          rm auto-gen/kompose/docker-compose.yaml
          kubectl apply -n $K8S_NAMESPACE -f auto-gen/kompose/
          END_OF_SCRIPT
          ;;
        d5)
          clear
          readVar MYSQL_RBD_IMAGE_NAME "mysql-rbd-image" "Please enter the volume name (RBD images will have the same name) for My SQL"
          readVar MYSQL_RBD_IMAGE_SIZE "1G" "Please enter the volume size (in GB) for \"$MYSQL_RBD_IMAGE_NAME\""
          ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd info ${MYSQL_RBD_IMAGE_NAME} --pool $POOL_NAME" >/dev/null 2>&1
          if [[ $? == 0 ]]; then
            echo "-- The image \"$MYSQL_RBD_IMAGE_NAME\" is already created in \"$POOL_NAME\" pool"
            echo ""
          else
            echo "-- The image \"$MYSQL_RBD_IMAGE_NAME\" is not created in \"$POOL_NAME\" pool. Creating..."
            echo ""
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd create ${MYSQL_RBD_IMAGE_NAME} --size ${MYSQL_RBD_IMAGE_SIZE} --pool $POOL_NAME"
            if [[ $? != 0 ]]; then
              echo "--?-- Failed to create the image \"$MYSQL_RBD_IMAGE_NAME\" in \"$POOL_NAME\" pool"
              echo ""
              exit 1
            fi
          fi

          readVar WP_RBD_IMAGE_NAME "wp-rbd-image" "Please enter the volume name (the same as RBD image name) for WORDPRESS"
          readVar WP_RBD_IMAGE_SIZE "1G" "Please enter the volume size (in GB) for \"$WP_RBD_IMAGE_NAME\""
          echo ">> Please enter the volume size (in GB) for \"$WP_RBD_IMAGE_NAME\" (Default: 1G)"
          read SIZE
          if [[ $WP_RBD_IMAGE_SIZE == "" ]]; then
            WP_RBD_IMAGE_SIZE="1G"
          fi
          ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd info ${WP_RBD_IMAGE_NAME} --pool $POOL_NAME" >/dev/null 2>&1
          if [[ $? == 0 ]]; then
            echo "-- The image \"$WP_RBD_IMAGE_NAME\" is already created in \"$POOL_NAME\" pool"
            echo ""
          else
            echo "-- The image \"$WP_RBD_IMAGE_NAME\" is not created in \"$POOL_NAME\" pool. Creating..."
            echo ""
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE_DEFAULT} "rbd create ${WP_RBD_IMAGE_NAME} --size ${WP_RBD_IMAGE_SIZE} --pool $POOL_NAME"
            if [[ $? != 0 ]]; then
              echo "--?-- Failed to create the image \"$WP_RBD_IMAGE_NAME\" in \"$POOL_NAME\" pool"
              echo ""
              exit 1
            fi
          fi

          MYSQL_PASSWORD=$(openssl rand -base64 12)
          _filesGenerationExample

          nano auto-gen/manifest-wordpress.yaml
          timeout 5 kubectl apply -n $K8S_NAMESPACE -f auto-gen/manifest-wordpress.yaml
          
          echo "-- Waiting for the Wordpress pod to be ready... waiting for 10 seconds.. "
          sleep 10
          echo "forwarding from the port below to port 80"
          kubectl port-forward deployment/wordpress :80
          END_OF_SCRIPT
          ;;
        u1)
          timeout 5 kubectl delete -n $K8S_NAMESPACE -f auto-gen/manifest1.yaml --force --grace-period=0
          END_OF_SCRIPT
          ;;
        u2)
          timeout 5 kubectl delete -n $K8S_NAMESPACE -f auto-gen/manifest2.yaml --force --grace-period=0
          END_OF_SCRIPT
          ;;
        u3)
          timeout 5 kubectl delete -n $K8S_NAMESPACE -f auto-gen/manifest3.yaml --force --grace-period=0
          END_OF_SCRIPT
          ;;
        u4)
          timeout 5 kubectl delete -n $K8S_NAMESPACE -f auto-gen/kompose --force --grace-period=0
          rm -r auto-gen/kompose
          END_OF_SCRIPT
          ;;
        u5)
          _filesGenerationExample
          timeout 5 kubectl delete -n $K8S_NAMESPACE -f auto-gen/manifest-wordpress.yaml --force --grace-period=0
          END_OF_SCRIPT
          ;;
        r3)
          echo "-- Removing CEPH CSI ..."
          source auto-gen/ceph.env
          echo "-- FSID: ${FSID}"
          echo "-- ADMIN_USER_KEY: ***************"
          echo "-- MON1: ${PVE1}"
          echo "-- MON2: ${PVE2}"
          echo "-- MON3: ${PVE3}"
          _filesGenerationCeph
          timeout 5 kubectl delete -n kube-system -f auto-gen/csi/ --force --grace-period=0
          END_OF_SCRIPT
          ;;
        r4)
          echo "-- List of deployed PVs (PV/PVs):"
          kubectl get pv -n $K8S_NAMESPACE
          readVar RBD_IMAGE "rbd-image" " Please enter the volume name (the same as RBD image name) to remove"
          timeout 5 kubectl delete pvc -n $K8S_NAMESPACE "${RBD_IMAGE}-pvc" --force --grace-period=0
          timeout 5 kubectl delete pv -n $K8S_NAMESPACE $RBD_IMAGE --grace-period=0 --force
          timeout 5 kubectl patch pv -n $K8S_NAMESPACE $RBD_IMAGE -p '{"metadata": {"finalizers": null}}'
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