## test unique rule
唯一性检查是一个比较重要的功能，应测试是否受 Lock 功能影响。

测试思路：

默认模型中 Person 的唯一性检查规则规定员工号唯一，尝试创建具有相同员工号的 Person，试试会不会有问题。和单节点做对照。

### 调用 API 测试
同时调用 3 个节点的 API，使用 parallel 实现并行

执行 `run-api.sh`