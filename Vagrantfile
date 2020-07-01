Vagrant.require_version ">= 1.4.3"
VAGRANTFILE_API_VERSION = "2"

BOX='itop-mgr/2.7'

(1..3).each do |i|
  Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
    config.vm.define :"itop-mgr-#{i}" do |node|
      node.vm.box = BOX
      node.vm.network :private_network, ip: "192.168.10.#{i+100}"
      node.vm.hostname = "itop-mgr-#{i}"
      node.vm.synced_folder ".", "/vagrant", disabled: true
      if Vagrant.has_plugin?("vagrant-vbguest")
        node.vbguest.auto_update = false
      end      
      
      node.vm.provider "virtualbox" do |v|
        v.customize ["modifyvm", :id, "--memory", "1536"]
        v.name = "itop-mgr-#{i}"
        v.gui = false
      end
	  
	  node.ssh.shell = "bash -c 'BASH_ENV=/etc/profile exec bash'"
	  node.vm.provision "shell", path: "post-deploy.sh" ,run: "always"
    end
  end
end