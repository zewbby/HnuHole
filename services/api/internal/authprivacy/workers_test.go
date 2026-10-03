package authprivacy

import (
 "context"
 "errors"
 "sync"
 "sync/atomic"
 "testing"
 "time"
)

func TestDurableWorkerBoundsConcurrencyAndPropagatesCancellation(t *testing.T) {
 config:=DefaultWorkerConfig()
 config.Concurrency=2
 var active,peak atomic.Int32
 entered:=make(chan struct{},3)
 release:=make(chan struct{})
 task:=func(ctx context.Context,limit int)(int,error) {
  if limit!=config.BatchSize { t.Errorf("batch bound changed: %d",limit) }
  current:=active.Add(1)
  defer active.Add(-1)
  for old:=peak.Load(); current>old && !peak.CompareAndSwap(old,current); old=peak.Load() {}
  if deadline,ok:=ctx.Deadline(); !ok || time.Until(deadline)>config.TaskTimeout { t.Error("task lacks configured deadline") }
  entered<-struct{}{}
  select { case <-release: return 1,nil; case <-ctx.Done(): return 0,ctx.Err() }
 }
 var observed []WorkerObservation
 var observeMu sync.Mutex
 worker:=&DurableWorker{config:config,tasks:[]durableTask{{"first",task},{"second",task},{"third",task}},observe:func(o WorkerObservation){ observeMu.Lock(); observed=append(observed,o); observeMu.Unlock() }}
 ctx,cancel:=context.WithCancel(context.Background())
 defer cancel()
 done:=make(chan error,1)
 go func(){ done<-worker.RunOnce(ctx) }()
 for i:=0;i<2;i++ { select { case <-entered: case <-time.After(3*time.Second): t.Fatal("workers did not start") } }
 select { case <-entered: t.Fatal("third task exceeded concurrency bound"); default: }
 cancel()
 select { case err:=<-done: if !errors.Is(err,context.Canceled) { t.Fatalf("lost cancellation: %v",err) }; case <-time.After(3*time.Second): t.Fatal("cancellation did not stop tasks") }
 if peak.Load()!=2 || active.Load()!=0 { t.Fatalf("unexpected active tasks peak=%d remaining=%d",peak.Load(),active.Load()) }
 observeMu.Lock(); defer observeMu.Unlock()
 if len(observed)!=2 { t.Fatalf("observation count = %d",len(observed)) }
 for _,o:=range observed { if !o.Failed || o.BatchLimit!=config.BatchSize { t.Fatalf("missing task bound/error observation: %+v",o) } }
}

func TestDurableWorkerConfigRejectsUnboundedOrShortLeases(t *testing.T) {
 for _,change:=range []func(*WorkerConfig){
  func(c *WorkerConfig){ c.BatchSize=0 },
  func(c *WorkerConfig){ c.Concurrency=9 },
  func(c *WorkerConfig){ c.TaskTimeout=0 },
  func(c *WorkerConfig){ c.Interval=0 },
  func(c *WorkerConfig){ c.MaxBackoff=0 },
  func(c *WorkerConfig){ c.ReceiptLease=c.TaskTimeout },
  func(c *WorkerConfig){ c.ACKRetention=-time.Second },
 } {
  config:=DefaultWorkerConfig(); change(&config)
  if config.Validate()==nil { t.Fatalf("invalid bounds accepted: %+v",config) }
 }
}

func TestDurableWorkerStopsBackoffWithoutAnotherAttempt(t *testing.T) {
 config:=DefaultWorkerConfig()
 config.Interval=time.Second
 failed:=make(chan struct{},1)
 var calls atomic.Int32
 worker:=&DurableWorker{config:config,tasks:[]durableTask{{"failed",func(context.Context,int)(int,error){ calls.Add(1); failed<-struct{}{}; return 0,errors.New("durable work failure") }}}}
 ctx,cancel:=context.WithCancel(context.Background())
 defer cancel()
 done:=make(chan error,1)
 go func(){ done<-worker.Run(ctx) }()
 select { case <-failed: case <-time.After(3*time.Second): t.Fatal("worker did not attempt durable task") }
 cancel()
 select { case err:=<-done: if err!=nil { t.Fatal(err) }; case <-time.After(3*time.Second): t.Fatal("backoff prevented shutdown") }
 if calls.Load()!=1 { t.Fatal("cancelled worker retried during backoff") }
}

func TestDurableWorkerTaskDeadlineEndsBlockingWork(t *testing.T) {
 config:=DefaultWorkerConfig()
 config.TaskTimeout=time.Second
 config.ReceiptLease=6*time.Second
 var calls atomic.Int32
 worker:=&DurableWorker{config:config,tasks:[]durableTask{{"blocked",func(ctx context.Context,limit int)(int,error){ calls.Add(1); <-ctx.Done(); return 0,ctx.Err() }}}}
 ctx,cancel:=context.WithTimeout(context.Background(),3*time.Second)
 defer cancel()
 if err:=worker.RunOnce(ctx); !errors.Is(err,context.DeadlineExceeded) { t.Fatalf("task timeout did not stop blocked work: %v",err) }
 if calls.Load()!=1 { t.Fatal("timed-out task repeated in the same bounded pass") }
}
