#!/bin/bash
function redoMain() {
	for id in `seq 1 3`;do
		vagrant destroy -f mgr-$id
	done
}
redoMain
vagrant up
