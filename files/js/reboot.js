shell.connect('root@192.168.10.101', 'root');
dba.rebootClusterFromCompleteOutage('itopMgr')
var cluster = dba.getCluster('itopMgr');
cluster.status();
