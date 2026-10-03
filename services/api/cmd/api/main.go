package main

import (
 "context"
 "flag"
 "log/slog"
 "os"
 "os/signal"
 "syscall"

 "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
 "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyruntime"
)

func main() {
 path:=flag.String("config","","private development C JSON configuration")
 flag.Parse()
 if *path==""{slog.Error("-config is required");os.Exit(1)}
 config,err:=authprivacyruntime.LoadConfig(*path,authprivacyhttp.CommunityService)
 if err!=nil{slog.Error("C configuration rejected","error",err);os.Exit(1)}
 ctx,stop:=signal.NotifyContext(context.Background(),os.Interrupt,syscall.SIGTERM);defer stop()
 if err=authprivacyruntime.Run(ctx,config,authprivacyhttp.CommunityService);err!=nil{slog.Error("C stopped","error",err);os.Exit(1)}
}
