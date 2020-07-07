## itop-tickets DBInsertNoReload()

DBInsertNoReload()
MakeTicketRef()
ItopCounter::IncClass()
iTopCounter::Inc()
iTopMutex->Lock();

ref 指工单编号，因此多主集群可能导致生成的 工单编号 错误。

```
    public function MakeTicketRef()
    {
          $iNextId = ItopCounter::IncClass(get_class($this));
          $sRef = $this->MakeTicketRef($iNextId);
          $this->SetIfNull('ref', $sRef);
          $iKey = parent::DBInsertNoReload();
          return $iKey;
    }

        protected function MakeTicketRef($iNextId)
        {
                return sprintf(static::GetTicketRefFormat(), $iNextId);
        }

        public static function GetTicketRefFormat()
        {
                return 'T-%06d';
        }
```

### 调用 API 测试
同时调用 3 个节点的 API，使用 parallel 实现并行

执行 `run-api.sh`