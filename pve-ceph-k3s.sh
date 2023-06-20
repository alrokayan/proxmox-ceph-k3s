#!/bin/bash
function _filesGenerationCeph () {
  mkdir -p auto-gen/csi
  # Ceph RBD CSI GitHub: https://github.com/ceph/ceph-csi/tree/release-v3.8/deploy/rbd/kubernetes
  # Ceph RBD CSI Offical: https://docs.ceph.com/en/latest/rbd/rbd-kubernetes/
  if [ ! -f "auto-gen/csi/csi-config-map.yaml" ]; then
    git clone https://github.com/ceph/ceph-csi.git --branch release-v3.8
    mv ceph-csi/deploy/rbd/kubernetes/* auto-gen/csi
  fi

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
reclaimPolicy: Retain
allowVolumeExpansion: true
mountOptions:
  - discard
__EOF__

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

  sed -i.original -e 's/namespace: default/namespace: kube-system/g' auto-gen/csi/*.yaml
  rm -rf auto-gen/csi/*.original
}

function _filesGenerationPV () {
  mkdir -p auto-gen/pv
  mkdir -p auto-gen/pvc

  # STATIC RBD: https://github.com/ceph/ceph-csi/blob/release-v3.8/docs/static-pvc.md
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
      "staticVolume": "true"
      "imageFeatures": "layering"
    volumeHandle: $RBD_IMAGE_NAME
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem
__EOF__

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

}

function END_OF_SCRIPT () {
  echo "-----------------------------"
  echo "🐳 Script executed successfully. Press any key to continue .."
  read
}

##############################################################################################################

if [ ! -f "auto-gen/pve.env" ]; then
  mkdir -p auto-gen
  echo "auto-gen/pve.env file not found .."
  echo "Createing auto-gen/pve.env .. please wait .."
  touch auto-gen/pve.env

  echo "Please entre the PVE1 IP (default: 10.10.1.10)"
  read PVE1
  if [[ $PVE1 == "" ]]; then
    PVE1=10.10.1.10
  fi
  echo "PVE1=${PVE1}" >> auto-gen/pve.env

  echo "Please entre the PVE2 IP (default: 10.10.1.11)"
  read PVE2
  if [[ $PVE2 == "" ]]; then
    PVE2=10.10.1.11
  fi
  echo "PVE2=${PVE2}" >> auto-gen/pve.env

  echo "Please entre the PVE3 IP (default: 10.10.1.12)"
  read PVE3
  if [[ $PVE3 == "" ]]; then
    PVE3=10.10.1.12
  fi
  echo "PVE3=${PVE3}" >> auto-gen/pve.env

  echo "Please entre the nodes placement in PVE hosts (1, 2 or 3) with a space between them (default: 1 2 3): "
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

  echo "Please entre the nodes IP prefix where the last digital is omitiied to be concatenated with the node ID starting from zero (default: 10.10.100.20):"
  echo "Example: "192.168.1.1" with three nodes cluster means the nodes IPs will be 192.168.1.11, 192.168.1.12 and 192.168.1.13"
  echo "Example: "10.10.4.10" with six nodes cluster means the nodes IPs will be 10.10.4.101, 10.10.4.102, 10.10.4.103, 10.10.4.104, 10.10.4.105, 10.10.4.106"
  read NODE_IP_PREFIX
  if [[ $NODE_IP_PREFIX == "" ]]; then
    NODE_IP_PREFIX="10.10.100.20"
  fi
  echo "NODE_IP_PREFIX=${NODE_IP_PREFIX}" >> auto-gen/pve.env

  echo "Please entre the K8s Load Balancer IP or just simply node1 IP (default: ${NODE_IP_PREFIX}1):"
  read LB
  if [[ $LB == "" ]]; then
    LB=${NODE_IP_PREFIX}1
  fi
  echo "LB=${LB}" >> auto-gen/pve.env

  echo "Please the VM prefix ID where the last digital is omitiied to be concatenated with the node ID starting from 1 (default: 100):"
  echo 'Example: "100" with three nodes cluster means the VMs IDs will be 1001, 1002 and 1003'
  echo 'Example: "10" with six nodes cluster means the VMs IDs will be 101, 102, 103, 104, 105, 106'
  read VM_ID_PREFIX
  if [[ $VM_ID_PREFIX == "" ]]; then
    VM_ID_PREFIX=100
  fi
  echo "VM_ID_PREFIX=${VM_ID_PREFIX}" >> auto-gen/pve.env

  echo "Please entre the SSH username for PVE and VMs (default: root):"
  read SSH_USERNAME
  if [[ $SSH_USERNAME == "" ]]; then
    SSH_USERNAME=root
  fi
  echo "SSH_USERNAME=${SSH_USERNAME}" >> auto-gen/pve.env

  echo "Please entre the path for KUBECONFIG (default: ~/.kube/config):"
  read KUBECONFIG
  if [[ $KUBECONFIG == "" ]]; then
    KUBECONFIG=~/.kube/config
  fi
  echo "KUBECONFIG=${KUBECONFIG}" >> auto-gen/pve.env

  echo "Please entre the path of your public key to SSH into the VMs (default: ~/.ssh/id_rsa.pub)"
  read MY_PUBLIC_KEY
  if [[ $MY_PUBLIC_KEY == "" ]]; then
    MY_PUBLIC_KEY=~/.ssh/id_rsa.pub
  fi
  echo "MY_PUBLIC_KEY=${MY_PUBLIC_KEY}" >> auto-gen/pve.env

  echo "Please entre the path to the private key for the proxmox host (default: /etc/ssh/ssh_host_rsa_key):"
  read PROXMOX_HOST_PRIVATE_KEY
  if [[ $PROXMOX_HOST_PRIVATE_KEY == "" ]]; then
    PROXMOX_HOST_PRIVATE_KEY=/etc/ssh/ssh_host_rsa_key
  fi
  echo "PROXMOX_HOST_PRIVATE_KEY=${PROXMOX_HOST_PRIVATE_KEY}" >> auto-gen/pve.env

  echo "Please entre the number of CPUs for each VM (default: 2)"
  read PVE_CPU_CORES
  if [[ $PVE_CPU_CORES == "" ]]; then
    PVE_CPU_CORES=2
  fi
  echo "PVE_CPU_CORES=${PVE_CPU_CORES}" >> auto-gen/pve.env

  echo "Please entre the amount of RAM for each VM (default: 2048)"
  read PVE_MEMORY
  if [[ $PVE_MEMORY == "" ]]; then
    PVE_MEMORY=2048
  fi
  echo "PVE_MEMORY=${PVE_MEMORY}" >> auto-gen/pve.env

  echo "Please entre the DNS IP for VMs (default: 10.10.1.1)"
  read VM_DNS
  if [[ $VM_DNS == "" ]]; then
    VM_DNS="10.10.1.1"
  fi
  echo "VM_DNS=${VM_DNS}" >> auto-gen/pve.env

  echo "Please entre the DNS search domain for VMs (default: ha.ousaimi.com)"
  read SEARCH_DOMAIN
  if [[ $SEARCH_DOMAIN == "" ]]; then
    SEARCH_DOMAIN="ha.ousaimi.com"
  fi
  echo "SEARCH_DOMAIN=${SEARCH_DOMAIN}" >> auto-gen/pve.env

  echo "Please entre the storage ID for VMs (default: local-btrfs)"
  read STORAGEID
  if [[ $STORAGEID == "" ]]; then
    STORAGEID="local-btrfs"
  fi
  echo "STORAGEID=${STORAGEID}" >> auto-gen/pve.env

  echo "Please entre the storage ID for cloud-init (default: rbd)"
  read CLOUDINIT_STORAGEID
  if [[ $CLOUDINIT_STORAGEID == "" ]]; then
    CLOUDINIT_STORAGEID="rbd"
  fi
  echo "CLOUDINIT_STORAGEID=${CLOUDINIT_STORAGEID}" >> auto-gen/pve.env

  echo "Please entre the download folder for raw images (default: /mnt/pve/cephfs/raw/):"
  read DOWNLOAD_FOLDER
  if [[ $DOWNLOAD_FOLDER == "" ]]; then
    DOWNLOAD_FOLDER=/mnt/pve/cephfs/raw/
  fi
  echo "DOWNLOAD_FOLDER=${DOWNLOAD_FOLDER}" >> auto-gen/pve.env

  echo "Please entre the cloud image URL (default: https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.raw):"
  read CLOUD_IMAGE_URL
  if [[ $CLOUD_IMAGE_URL == "" ]]; then
    CLOUD_IMAGE_URL=https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.raw
  fi
  echo "CLOUD_IMAGE_URL=${CLOUD_IMAGE_URL}" >> auto-gen/pve.env
  
  echo "Please enter Ceph pool name (default: rbd):"
  read POOL_NAME
  if [[ $POOL_NAME == "" ]]; then
    POOL_NAME="rbd"
  fi
  echo "POOL_NAME=${POOL_NAME}" >> auto-gen/pve.env

  echo "Please enter Kubernetes namespace (default: homelab):"
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
  echo "(00)   <<Exit and CLEAN UP"
  echo "(0)    <Exit"
  echo "----------------------------------------------------"
  echo "[1]....INFRASTRUCTURE"
  echo "[2]....STORAGE"
  echo "[3]....DEPLOYMENT"
  echo "----------------------------------------------------"
  echo "(4)....Monitor VMs status"
  echo "(5)....Monitor K8s cluster status (k9s)"
  echo "(6)....Monitor Ceph cluster status"
  echo "(7)....Monitor RBD images list"
  echo "(8)....Monitor Ceph pool list"
  echo "(9)....Monitor auto generated files (tree)"
  echo "(10)...Print environment variables"
  echo "-----------------------------------------------------------"
  read OPTION
  case $OPTION in
    00)
      echo "Cleaning up..."
      rm -rf auto-gen/
      rm -rf ceph-csi
      exit 0
      ;;
    0)
      exit 0
      ;;
    4) # Monitor VMs status
      ssh -i ${MY_PUBLIC_KEY} -t ${SSH_USERNAME}@${PVE1} "watch pvesh get /cluster/resources --type vm"
      ;;
    5) # Monitor K8s cluster status (k9s)
      k9s -A
      echo "Do you want to install k9s to monitor K8s cluster? (y/N)"
      read -r INSTALL_K9S
      if [[ $INSTALL_K9S == "y" ]]; then
        brew install derailed/k9s/k9s
      fi
      ;;
    6)
      # Ceph Status
      ssh -i ${MY_PUBLIC_KEY} -t ${SSH_USERNAME}@${PVE1} "watch ceph -s"
      ;;
    7) # Monitor Ceph cluster status
      ssh -i ${MY_PUBLIC_KEY} -t ${SSH_USERNAME}@${PVE1} "watch rbd ls -p ${POOL_NAME}"
      ;;
    8) # Monitor Ceph pool list
      ssh -i ${MY_PUBLIC_KEY} -t ${SSH_USERNAME}@${PVE1} "watch ceph osd pool ls"
      ;;
    9) # Monitor auto generated files (tree)
      watch tree auto-gen
      echo "Do you want to install tree to monitor auto generated files? (y/N)"
      read -r INSTALL_TREE
      if [[ $INSTALL_TREE == "y" ]]; then
        brew install tree
      fi
      ;;
    10) # Print environment variables
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
##############################################################
##############################################################
# INFRASTRUCTURE
##############################################################
##############################################################
    1)
        while true; do
        clear
        echo "----------------------------------------------------"
        echo "---------------- INFRASTRUCTURE --------------------"
        echo "----------------------------------------------------"
        echo "Please select one of the following options:"
        echo "----------------------------------------------------"
        echo "(0)    <BACK"
        echo "----------------------------------------------------"
        echo "[1]....Initiate the infrastructure"
        echo "[2]....Download cloud image"
        echo "[3]....Create VMs"
        echo "[4]....Install k3sup on mac"
        echo "[5]....Deploy Kubernetes cluster (k3s)"
        echo "----------------------------------------------------"
        echo "(6)....Wipe clean Kubernetes cluster's nodes"
        echo "(7)....ssh into PVE1"
        echo "(8)....ssh into node1"
        echo "(911)..NUKE (Delete VMs)"
        echo "----------------------------------------------------"
        read INFRA_OPTION
        case $INFRA_OPTION in
        0)
          break
          ;;
        1) ## Initiate the infrastructure
          echo "Cleaning PVE keys ..."
          for PVE in ${PVE1} ${PVE2} ${PVE3}
          do
            ssh-keygen -f ~/.ssh/known_hosts -R "${PVE}" &>/dev/null
          done
          echo "Cleaing kurbenetes keys ..."
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

          echo "Do you want to copy the groups.cfg to the PVE1 host (${PVE1})? (y/N)"
          read COPY_GROUPS_CFG
          if [[ $COPY_GROUPS_CFG == "y" ]]; then
            scp config/groups.cfg ${SSH_USERNAME}@${PVE1}:/etc/pve/ha/groups.cfg
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
          echo "Deleting old raw images in ${DOWNLOAD_FOLDER} on all PVE nodes ..."
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
            echo "creating VM: node${ID}"
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
ha-manager add vm:${VM_ID} --state started --max_relocate 4 --max_restart 1 --group ${VM_NAME}
rm -f /tmp/${SSH_FILE}
___EOF___
          ID=$(( ID+1 ))
          done
        END_OF_SCRIPT
        ;;
        4) ## Install k3sup on mac
        echo "Installing k3s"
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
            echo "Fixing iptables-legacy on node${ID}"
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
        6) ## Wipe clean Kubernetes cluster's nodes
          ID=1
          for PLACEMENT in ${VM_PLACEMENT[@]}
          do
            echo "Removing k3s in node${ID}"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${NODE_IP_PREFIX}${ID} bash <<'____EOF____'
#!/bin/bash
k3s-uninstall.sh &>/dev/null
k3s-agent-uninstall.sh &>/dev/null
____EOF____
            ID=$(( ID+1 ))
          done
          END_OF_SCRIPT
          ;;
        7) ## ssh into PVE1
          ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1}
          END_OF_SCRIPT
          ;;
        8) ## ssh into node1
          ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${NODE_IP_PREFIX}1
          END_OF_SCRIPT
          ;;
        911) ## Destroy all VMs in all PVEs
          for PVE in ${PVE1} ${PVE2} ${PVE3}
          do
            echo "Removing VMs in PVE: ${PVE} ..."
            QM_LIST=$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE} qm list)
            ID=1
            for PLACEMENT in ${VM_PLACEMENT[@]}
            do
              NODE_ID=${VM_ID_PREFIX}${ID}
              QM_LIST_GREPD=$( echo $QM_LIST | grep $NODE_ID )
              echo "Checking VM: $NODE_ID"
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
          echo "Invalid option"
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
    2)
      while true; do
        clear
        echo "----------------------------------------------------"
        echo "------------------- STORAGE ------------------------"
        echo "----------------------------------------------------"
        echo "Please select one of the following options:"
        echo "----------------------------------------------------"
        echo "(0)    <BACK"
        echo "----------------------------------------------------"
        echo "[1]....Zap disks"
        echo "[2]....Create \"$POOL_NAME\" RBD Pool"
        echo "[3]....Create RBD Images"
        echo "[4]....Mount RBD images"
        echo "[5]....-- Copy files to RBD images -->"
        echo "[6]....<-- Copy files from RBD images --"
        echo "[7]....Unmount RBD images"
        echo "[8]....Delete RBD images"
        echo "----------------------------------------------------"
        read STORAGE_OPTION
        case $STORAGE_OPTION in
        0)
          break
          ;;
        1)
            # Zap disk in PVE1
            echo "PVE1 Disks:"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} "find /dev/disk/by-id/ -type l|xargs -I{} ls -l {}|grep -v -E '[0-9]$' |sort -k11|cut -d' ' -f9,10,11,12"
            echo "Please enter the disk name to zap in PVE1:"
            read PVE1_CEPH_DISK
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} ceph-volume lvm zap ${PVE1_CEPH_DISK} --destroy

            # Zap disk in PVE2
            echo "PVE2 Disks:"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE2} "find /dev/disk/by-id/ -type l|xargs -I{} ls -l {}|grep -v -E '[0-9]$' |sort -k11|cut -d' ' -f9,10,11,12"
            echo "Please enter the disk name to zap in PVE2:"
            read PVE2_CEPH_DISK
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE2} ceph-volume lvm zap ${PVE2_CEPH_DISK} --destroy

            # Zap disk in PVE3
            echo "PVE3 Disks:"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE3} "find /dev/disk/by-id/ -type l|xargs -I{} ls -l {}|grep -v -E '[0-9]$' |sort -k11|cut -d' ' -f9,10,11,12"
            echo "Please enter the disk name to zap in PVE3:"
            read PVE3_CEPH_DISK
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE3} ceph-volume lvm zap ${PVE3_CEPH_DISK} --destroy

            END_OF_SCRIPT 
            ;;
        2)
            echo "Creating RBD pool $POOL_NAME ..."
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} pveceph pool create $POOL_NAME --application rbd --pg_autoscale_mode on
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} pveceph lspools
            END_OF_SCRIPT
            ;;
        3)
            echo "Please enter the RBD image name to mount in /mnt/rbd: (Default: rbd-image)"
            read RBD_IMAGE
            if [[ $RBD_IMAGE == "" ]]; then
              RBD_IMAGE="rbd-image"
            fi
            echo "Please enter the size of the RBD image (Default 1G):"
            read SIZE
            if [[ $SIZE == "" ]]; then
              SIZE=1G
            fi
            echo "Creating ${RBD_IMAGE} RDB with size ${SIZE} at pool rbd"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} "rbd create ${RBD_IMAGE} --size=${SIZE} --pool=$POOL_NAME"
            END_OF_SCRIPT
            ;;
        4) # Mount RBD images
            echo "Please enter the RBD image name to mount in /mnt/rbd: (Default: rbd-image)"
            read RBD_IMAGE
            if [[ $RBD_IMAGE == "" ]]; then
              RBD_IMAGE="rbd-image"
            fi
            echo "Mapping and mounting ${RBD_IMAGE} RBD to /mnt/rbd/${RBD_IMAGE} folder"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} "rbd map ${RBD_IMAGE} --pool $POOL_NAME  --id admin --keyring /etc/pve/priv/ceph.client.admin.keyring"
            
            echo "RBD image has been mapped but not mounted yet. Do you want to make filesystem (mkfs.xfs) on the mapped $RBD_IMAGE RBD image before mounting? (y/N)"
            read MKFS_RBD_IMAGE
            if [[ $MKFS_RBD_IMAGE == "y" ]]; then
              MKFS_RBD_IMAGE=true
            else
              MKFS_RBD_IMAGE=false
            fi
            if [ $MKFS_RBD_IMAGE == "true" ]; then
              ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} "mkfs.xfs /dev/rbd/$POOL_NAME/${RBD_IMAGE}"
            fi

            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} "mkdir -p /mnt/rbd/${RBD_IMAGE}"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} "mount /dev/rbd/$POOL_NAME/${RBD_IMAGE} /mnt/rbd/${RBD_IMAGE}"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} df -h
            END_OF_SCRIPT
            ;;
        5) # Copy data to RBD images
            echo "Please enter the RBD image name (Default: rbd-image)"
            read RBD_IMAGE
            if [[ $RBD_IMAGE == "" ]]; then
              RBD_IMAGE="rbd-image"
            fi

            echo "Do you want to delete the data in the mounted volumes before copying? (y/N)"
            read DELETE_DATA_IN_MOUNTED_VOLUMES
            if [[ $DELETE_DATA_IN_MOUNTED_VOLUMES == "y" ]]; then
              echo "Deleting/Cleaning ..."
              ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} rm -rf /mnt/rbd/$RBD_IMAGE/*
            fi
            mkdir -p rbd/$RBD_IMAGE
            echo "Please put your files in "rbd/$RBD_IMAGE" folder (rbd/$RBD_IMAGE folder just created in your computer if not exist"
            echo "Press any key to continue ..."
            read
            echo "Copying ..."
            rsync -r --progress rbd/$RBD_IMAGE/* ${SSH_USERNAME}@${PVE1}:/mnt/rbd/$RBD_IMAGE/
            END_OF_SCRIPT
            ;;
        6) # Copy data from RBD images
            echo "Please enter the RBD image name to mount in /mnt/rbd/$RBD_IMAGE (Default: rbd-image)"
            read RBD_IMAGE
            if [[ $RBD_IMAGE == "" ]]; then
              RBD_IMAGE="rbd-image"
            fi

            echo "Copying ..."
            rsync -r --progress ${SSH_USERNAME}@${PVE1}:/mnt/rbd/$RBD_IMAGE/* rbd/$RBD_IMAGE/
            END_OF_SCRIPT
            ;;
        7) # Unmount RBD 
            echo "Please enter the RBD image name to mount in /mnt/rbd/ (Default: rbd-image)"
            read RBD_IMAGE
            if [[ $RBD_IMAGE == "" ]]; then
              RBD_IMAGE="rbd-image"
            fi

            echo "Unmounting and unmapping ${RBD_IMAGE} .."
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} "umount /mnt/rbd/${RBD_IMAGE}"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} "rbd unmap -o force ${RBD_IMAGE} --pool=$POOL_NAME --id admin --keyring /etc/pve/priv/ceph.client.admin.keyring"
            END_OF_SCRIPT
            ;;
        8) # Delete RBD image            
            echo "List of current RBD images:"
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} "rbd ls --pool $POOL_NAME"

            echo "Please enter the RBD image name to delete (Default: rbd-image)"
            read RBD_IMAGE
            if [[ $RBD_IMAGE == "" ]]; then
              RBD_IMAGE="rbd-image"
            fi
            ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} "rbd rm ${RBD_IMAGE} --pool $POOL_NAME"
            ;;
        *)
          echo "Invalid option"
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
    3)
      if [ ! -f "auto-gen/ceph.env" ]; then
        echo "auto-gen/ceph.env file not found .."
        echo "Getting FSID and ADMIN_USER_KEY from Proxmox cluster .. please wait .."
        echo "FSID="$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} "ceph fsid") > auto-gen/ceph.env
        echo "ADMIN_USER_KEY="$(ssh -i ${MY_PUBLIC_KEY} ${SSH_USERNAME}@${PVE1} cat /etc/pve/priv/ceph.client.admin.keyring | grep key |  sed 's/.*key = //') >> auto-gen/ceph.env
        echo "MON1=${PVE1}" >> auto-gen/ceph.env
        echo "MON2=${PVE2}" >> auto-gen/ceph.env
        echo "MON3=${PVE3}" >> auto-gen/ceph.env
        echo "Getting KUBECONFIG from Kubernetes cluster .. please wait .."
        k3sup install --skip-install --ip $LB --local-path $KUBECONFIG &>/dev/null
      fi
      source auto-gen/ceph.env
      echo "FSID: ${FSID}"
      echo "MON1: ${PVE1}"
      echo "MON2: ${PVE2}"
      echo "MON3: ${PVE3}"
      while true
      do
      clear
      echo "----------------------------------------------------"
      echo "------------------ DEPLOYMENT ----------------------"
      echo "----------------------------------------------------"
      echo "FSID: $FSID"
      echo "ADMIN_USER_KEY: $ADMIN_USER_KEY"
      echo "KUBECONFIG: $KUBECONFIG"
      echo "----------------------------------------------------"
      echo "Please select one of the following options:"
      echo "----------------------------------------------------"
      echo "(0)   <BACK"
      echo "----------------------------------------------------"
      echo "[1]....Install helm & kubectl on mac"
      echo "[2]....Create \"$K8S_NAMESPACE\" namespaces"
      echo "[3]....Deploy Ceph RBD CSI"
      echo "[4]....Create PV and PVC"
      echo "[5]....Deploy manifest"
      echo "[6]....Delete last created manifest"
      echo "----------------------------------------------------"
      echo "(7)....Delete Ceph RBD CSI"
      echo "(8)....Delete All PVs and PVCs"
      echo "----------------------------------------------------"
      read DEPLOYMENT_OPTION
      case $DEPLOYMENT_OPTION in
        0)
          break
          ;;
        1)
          brew install helm
          brew install kubectl
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
          echo "FSID: ${FSID}"
          echo "ADMIN_USER_KEY: ${ADMIN_USER_KEY}"
          echo "MON1: ${PVE1}"
          echo "MON2: ${PVE2}"
          echo "MON3: ${PVE3}"
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
          echo "Please enter the volume name (the same as RBD image name) (Default: rbd-image)"
          read RBD_IMAGE_NAME
          if [[ $RBD_IMAGE_NAME == "" ]]; then
            RBD_IMAGE_NAME="rbd-image"
          fi
          echo "Please enter the volume size (in GB) (Default: 1G)"
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
          clear
          echo "--------------------------------------------------------------------"
          echo "----------------------- MANIFEST EDITOR ----------------------------"
          echo "--------------------------------------------------------------------"
          echo "Please copy and past your manifest in the next nano screen to deploy"
          echo "the app in namespace $K8S_NAMESPACE:"
          echo "--------------------------------------------------------------------"
          echo "HINT: to save and exit press CTRL+X, then press Y, then press ENTER"
          echo "--------------------------------------------------------------------"
          echo "Press any key to continue ..."
          read
          nano auto-gen/manifest.yaml
          kubectl apply -n $K8S_NAMESPACE -f auto-gen/manifest.yaml
          END_OF_SCRIPT
          ;;
        6)
          echo "DELETEING LAST CREATED MANIFEST ..."
          kubectl delete -n $K8S_NAMESPACE -f auto-gen/manifest.yaml
          ;;
        7)
          echo "DELETEING CEPH CSI ..."
          source auto-gen/ceph.env
          echo "FSID: ${FSID}"
          echo "ADMIN_USER_KEY: ${ADMIN_USER_KEY}"
          echo "MON1: ${PVE1}"
          echo "MON2: ${PVE2}"
          echo "MON3: ${PVE3}"
          _filesGenerationCeph
          kubectl delete -n kube-system -f auto-gen/csi/
          END_OF_SCRIPT
          ;;
        8)
          echo "DELETEING ALL PVs and PVCs ..."
          kubectl delete -n $K8S_NAMESPACE -f auto-gen/pvc/
          kubectl delete -f auto-gen/pv/
          END_OF_SCRIPT
          ;;
        *)
          echo "Invalid option"
          sleep 1
          ;;
        esac
      done
      ;;
    *)
      echo "Invalid option"
      sleep 1
     ;;
  esac
done