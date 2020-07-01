#!/bin/bash

BOX="itop-mgr/2.7"
for id in `seq 1 3`;do
	vagrant destroy -f itop-mgr-$id
done

cd box
rm -f package.box

vagrant up
vagrant package
du -sh *
vagrant box remove $BOX
vagrant box add package.box --name="$BOX"

cd ..
vagrant up