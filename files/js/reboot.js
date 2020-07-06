shell.connect('root@192.168.10.101', 'root');
dba.rebootClusterFromCompleteOutage('itopMgr',{rejoinInstances:["192.168.10.102:3306","192.168.10.103:3306"]})
var cluster = dba.getCluster('itopMgr');
cluster.status();
