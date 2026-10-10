package authprivacy

import (
 "context"
 "errors"
 "fmt"
 "sync"
 "time"
)

// WorkerConfig gives each durable work class a batch and deadline. Concurrency
// bounds simultaneous work classes, independently of HTTP admission limits.
type WorkerConfig struct {
 Interval time.Duration
 TaskTimeout time.Duration
 MaxBackoff time.Duration
 BatchSize int
 Concurrency int
 ReceiptLease time.Duration
 ACKRetention time.Duration
}

func DefaultWorkerConfig() WorkerConfig {
 return WorkerConfig{Interval:2*time.Second,TaskTimeout:15*time.Second,MaxBackoff:30*time.Second,BatchSize:16,Concurrency:1,ReceiptLease:30*time.Second,ACKRetention:24*time.Hour}
}

func (c WorkerConfig) Validate() error {
 if c.Interval<500*time.Millisecond || c.Interval>time.Minute || c.TaskTimeout<time.Second || c.TaskTimeout>time.Minute || c.MaxBackoff<c.Interval || c.MaxBackoff>5*time.Minute || c.BatchSize<1 || c.BatchSize>100 || c.Concurrency<1 || c.Concurrency>8 || c.ReceiptLease<c.TaskTimeout+5*time.Second || c.ReceiptLease>5*time.Minute || c.ACKRetention<0 || c.ACKRetention>30*24*time.Hour {
  return errors.New("invalid durable worker bounds")
 }
 return nil
}

// Observations identify the work class and limits without addresses, keys,
// tokens or receipt contents. Processed reports driven candidates, not committed
// effects; maintenance commands without a count report zero. Observers must not
// log underlying SQL details.
type WorkerObservation struct {
 Name string
 Processed int
 Duration time.Duration
 Failed bool
 BatchLimit int
}

type WorkerObserver func(WorkerObservation)

type durableTask struct {
 name string
 run func(context.Context,int) (int,error)
}

type DurableWorker struct {
 config WorkerConfig
 tasks []durableTask
 observe WorkerObserver
}

func NewCommunityWorker(c *Community,config WorkerConfig,sign Signer,receive ReceiptReceiver,observe WorkerObserver) (*DurableWorker,error) {
 if c==nil || sign==nil || receive==nil { return nil,errors.New("community worker dependencies are required") }
 if err:=config.Validate(); err!=nil { return nil,err }
 countTask:=func(run func(context.Context,int)(int64,error)) func(context.Context,int)(int,error) {
  return func(ctx context.Context,n int)(int,error) { count,err:=run(ctx,n); return int(count),err }
 }
 tasks:=[]durableTask{
  {"closures",countTask(c.FinalizeDueClosures)},
  {"posts",countTask(c.PublishAcceptedPosts)},
  {"post_payload_cleanup",countTask(c.CleanupPostPayloads)},
  {"receipts",func(ctx context.Context,limit int)(int,error) {
   jobs,err:=c.ClaimReceiptJobs(ctx,limit,config.ReceiptLease)
   if err!=nil { return 0,err }
   processed:=0
   for _,job:=range jobs {
    if err=ctx.Err(); err!=nil { return processed,err }
    err=c.ProcessReceiptJob(ctx,job,sign,receive)
    processed++
    if err!=nil && !errors.Is(err,ErrReceiptPending) { return processed,err }
   }
   return processed,nil
  }},
  {"ack_cleanup",func(ctx context.Context,n int)(int,error) { count,err:=c.CleanupAcknowledgedBatch(ctx,config.ACKRetention,n); return int(count),err }},
  {"closure_cleanup",countTask(c.CleanupClosureStatuses)},
  {"session_results_cleanup",countTask(c.CleanupSessionResults)},
  {"sessions_cleanup",countTask(c.CleanupOldSessions)},
  {"devices_cleanup",countTask(c.CleanupRecentDevices)},
  {"recovery_cleanup",countTask(c.CleanupRecoveryState)},
  {"credentials_cleanup",countTask(c.CleanupCredentialState)},
 }
 return &DurableWorker{config:config,tasks:tasks,observe:observe},nil
}

func NewVerifierWorker(e *Eligibility,config WorkerConfig,observe WorkerObserver) (*DurableWorker,error) {
 if e==nil { return nil,errors.New("verifier worker dependency is required") }
 if err:=config.Validate(); err!=nil { return nil,err }
 tasks:=[]durableTask{
  {"mail",e.ResumeQueuedMail},
  {"confirmations",e.ResumePendingConfirmations},
  {"confirmation_cleanup",e.CleanupConfirmations},
  {"otp_cleanup",func(ctx context.Context,n int)(int,error) { return 0,e.CleanupOTP(ctx,n) }},
 }
 return &DurableWorker{config:config,tasks:tasks,observe:observe},nil
}

// RunOnce has no overlapping rounds. Context cancellation stops accepting work
// and waits for the bounded in-flight tasks, including their durable finalizers.
func (w *DurableWorker) RunOnce(ctx context.Context) error {
 if w==nil || w.config.Validate()!=nil { return errors.New("invalid durable worker") }
 jobs:=make(chan durableTask)
 var wg sync.WaitGroup
 var lock sync.Mutex
 var failures []error
 concurrency:=min(w.config.Concurrency,len(w.tasks))
 for i:=0;i<concurrency;i++ {
  wg.Add(1)
  go func() {
   defer wg.Done()
   for task:=range jobs {
    if ctx.Err()!=nil { return }
    started:=time.Now()
    taskCtx,cancel:=context.WithTimeout(ctx,w.config.TaskTimeout)
    count,err:=task.run(taskCtx,w.config.BatchSize)
    cancel()
    lock.Lock()
    if err!=nil { failures=append(failures,fmt.Errorf("%s: %w",task.name,err)) }
    if w.observe!=nil { w.observe(WorkerObservation{Name:task.name,Processed:count,Duration:time.Since(started),Failed:err!=nil,BatchLimit:w.config.BatchSize}) }
    lock.Unlock()
   }
  }()
 }
 dispatch:
 for _,task:=range w.tasks {
  select { case jobs<-task: case <-ctx.Done(): break dispatch }
 }
 close(jobs)
 wg.Wait()
 if ctx.Err()!=nil { return ctx.Err() }
 return errors.Join(failures...)
}

// Run applies capped exponential backoff after errors. Restarting schedules the
// same persistent operations and never resets their expiry or risk budgets.
func (w *DurableWorker) Run(ctx context.Context) error {
 if w==nil || w.config.Validate()!=nil { return errors.New("invalid durable worker") }
 delay:=w.config.Interval
 for {
  if ctx.Err()!=nil { return nil }
  err:=w.RunOnce(ctx)
  if ctx.Err()!=nil { return nil }
  if err==nil { delay=w.config.Interval } else { delay=min(w.config.MaxBackoff,delay*2) }
  timer:=time.NewTimer(delay)
  select { case <-ctx.Done(): timer.Stop(); return nil; case <-timer.C: }
 }
}
