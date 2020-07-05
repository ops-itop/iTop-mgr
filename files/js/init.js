shell.connect('root@192.168.10.101', 'root');
var cluster = dba.createCluster('itopMgr', {adoptFromGR: true});
cluster.status();
