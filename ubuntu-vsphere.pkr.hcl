packer {
  required_version = ">= 1.7.0"
}

//////////////////////////////////////////////
//
//               Authentication
//
//////////////////////////////////////////////

variable "vsphere-password" {
  type    = string
  default = "PasswordIsSetInSecretFile"
  sensitive   = true
}

variable "vsphere-server" {
  type    = string
  default = "vsphere-01"
}

variable "vsphere-user" {
  type    = string
  default = "administrator@vsphere.local"
  sensitive   = true
}


//////////////////////////////////////////////
//
//               vSphere Settings
//
//////////////////////////////////////////////

variable "vsphere-cluster" {
  type    = string
  default = "Cluster"
}

variable "vsphere-datacenter" {
  type    = string
  default = "Home"
}

variable "vsphere-datastore" {
  type    = string
  default = "Datastore"
}

variable "vsphere-folder" {
  type = string
  description = "Folder to place VM in vSphere"
  default = "Templates"
}

variable "vsphere-resource-pool"{
  type = string
  description = "Resource Pool to create VM in"
  default = "Low"
}

variable "vsphere-content-libary"{
  type = string
  description = "Content libary to store the template in"
  default = "VM"
}

variable "git-branch"{
  type = string
  description = "branch name"
  default = "development"
}

variable "os_family"{
  type = string
  description = "Windows or Linux"
  default = "Linux"  
}

//////////////////////////////////////////////
//
//               Vm Settings
//
//////////////////////////////////////////////

variable "vm-cpu-num" {
  type    = string
  default = "1"
}

variable "vm-disk-size" {
  type    = string
  default = "25600"
}

variable "vm-mem-size" {
  type    = string
  default = "1024"
}

variable "vm-name" {
  type    = string
  default = "Ubuntu"
}

variable "iso_url" {
  type    = string
  default = "[Datastore] ISO-Linux/ubuntu-20.04.2-live-server-amd64.iso"
}

variable "vsphere-network" {
  type    = string
  default = "VM Network"
}

//////////////////////////////////////////////
//
//               Builder Settings
//
//////////////////////////////////////////////

source "vsphere-iso" "ubuntu" {
  CPUs                  = "${var.vm-cpu-num}"
  CPU_hot_plug          = true
  RAM                   = "${var.vm-mem-size}"
  RAM_hot_plug          = true
  RAM_reserve_all       = false
  boot_command = [
    "<esc><esc><esc>",
    "<enter><wait>",
    "/casper/vmlinuz ",
    "root=/dev/sr0 ",
    "initrd=/casper/initrd ",
    "autoinstall ",
    "ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/",
    "<enter>"
  ]
  boot_order            = "disk,cdrom,floppy"
  boot_wait             = "2s"
  insecure_connection   = "true"
  cluster               = "${var.vsphere-cluster}"
  datacenter            = "${var.vsphere-datacenter}"
  datastore             = "${var.vsphere-datastore}"
  resource_pool         = "${var.vsphere-resource-pool}"
  folder                = "${var.vsphere-folder}/${var.git-branch}/${var.os_family}"
  usb_controller        = ["usb"]
  disk_controller_type  = ["pvscsi","lsilogic"]
  cdrom_type            = "ide"
  firmware              = "bios"
  storage{
    disk_size             = "${var.vm-disk-size}"
    disk_thin_provisioned = true
    disk_controller_index = 0
  }
  guest_os_type         = "ubuntu64Guest"
  iso_paths             = ["${var.iso_url}"]
  network_adapters{
    network             = "${var.vsphere-network}"
    network_card        = "vmxnet3"
  }
  tools_upgrade_policy  = true
  ip_wait_timeout       = "1h"
  notes                 = "Packer generated Ubuntu template on ${timestamp()}"
  password              = "${var.vsphere-password}"
  ssh_password          = "ubuntu"
  ssh_username          = "ubuntu"
  ssh_timeout           = "30m"
  username              = "${var.vsphere-user}"
  vcenter_server        = "${var.vsphere-server}"
  vm_name               = lower(format("%s_pkr", var.vm-name ) )
  shutdown_command      = "echo root | sudo -S -E shutdown -P now"
  http_directory        = "http"
  remove_cdrom          = true


  #convert_to_template   = true
  content_library_destination {
    library             = "${var.vsphere-content-libary}"
    ovf                 = false
    destroy             = false
  }
}



build {
  sources = ["source.vsphere-iso.ubuntu"] 

  provisioner "file" {
    source = "files/login.warn"
    destination = "/tmp/login.warn"
  }

  provisioner "file" {
    source = "files/cloud.cfg"
    destination = "/tmp/cloud.cfg"
  }

  provisioner "shell" {
   #Wait for cloud-init to finish possible RACE CONDITION in packer build. 
    inline = [
      "echo 'Checking cloud-init status'",
      "sudo /usr/bin/cloud-init status --wait"]
  }

  provisioner "shell" {
   #commands to run before the vm is converted to a template
    inline = [
      #ensure a unique machine id every time we deploy from the template
      "echo '' | sudo tee /etc/machine-id > /dev/null",
      #cleanup motd
      "sudo rm /etc/update-motd.d/10-help-text",
      #rsyslog config
      "sudo ufw allow 514/udp",
      "sudo sed -i 's+#module(load=\"imudp\")+module(load=\"imudp\")+' /etc/rsyslog.conf",
      "sudo sed -i 's+#input(type=\"imudp\" port=\"514\")+input(type=\"imudp\" port=\"514\")+' /etc/rsyslog.conf",
      "sudo sed -i '7i *.* @192.168.50.100:514' /etc/rsyslog.conf",
      #Login warning banner
      "sudo sed -i 's+#Banner none+Banner /etc/ssh/login.warn+g' /etc/ssh/sshd_config",
      "sudo mv /tmp/login.warn /etc/ssh/login.warn",
      #Disable no password logins
      "sudo sed -i 's+#PermitEmptyPasswords no+PermitEmptyPasswords no+g' /etc/ssh/sshd_config",
      #Enable max auth tries
      "sudo sed -i 's+##MaxAuthTries 6+MaxAuthTries 6+g' /etc/ssh/sshd_config",
      "sudo mv /tmp/cloud.cfg /etc/cloud/cloud.cfg",
      "sudo chmod 644 /etc/cloud/cloud.cfg",
      "sudo chown root:root /etc/cloud/cloud.cfg",
      "echo 'Reset Cloud-Init'",
      "sudo rm /etc/cloud/cloud.cfg.d/*.cfg",
      "sudo cloud-init clean -s -l",
      #sssd setup
      
      #"vmware-toolbox-cmd config set deployPkg enable-custom-scripts true",
      "sudo apt-get update -y && sudo apt-get upgrade -y && sudo apt-get dist-upgrade -y"

    ]

  }
}