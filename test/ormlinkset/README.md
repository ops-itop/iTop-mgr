## test unique rule
并发更新 Person 的 team_list，观察是否创建重复的 lnkPersonToTeam。

### 调用 API 测试
同时调用 3 个节点的 API，使用 parallel 实现并行

执行 `run-api.sh`

### 结论
多主，单主 MGR 以及单节点都出现重复 lnk，此测试用例设计可能有误。