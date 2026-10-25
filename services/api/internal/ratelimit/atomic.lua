#!lua flags=no-cluster
-- Subject state is prepared and validated entirely in memory. The directory
-- reservation is conservative: any failure may consume capacity, never quota.
-- The only business-state write is the last SET PX; Redis does not roll back
-- earlier writes in a script when OOM/another command fails.
local req = cjson.decode(ARGV[1])
if req.proof.expectedGeneration and req.proof.expectedGeneration~=req.generation then return {'STALE'} end
-- Wrong Redis types and malformed serialized state are known state loss,
-- rather than an ordinary timeout eligible for verified-DB fallback.
local function keytype(key) return redis.call('TYPE',key).ok end
local sentinelType=keytype(KEYS[1])
local subjectType=keytype(KEYS[2])
local directoryType=keytype(KEYS[3])
if sentinelType~='string' then return {'NAMESPACE_LOST'} end
if (subjectType~='none' and subjectType~='string') or (directoryType~='none' and directoryType~='zset') then return {'LOST'} end
local sentinel = redis.call('GET', KEYS[1])
if sentinel ~= req.sentinel then return {'NAMESPACE_LOST'} end
local clock = redis.call('TIME')
local now = tonumber(clock[1])*1000 + math.floor(tonumber(clock[2])/1000)
local raw = redis.call('GET', KEYS[2])
local member = redis.call('ZSCORE', KEYS[3], req.subject)
if raw and (not member or redis.call('PTTL',KEYS[2]) <= 0) then return {'LOST'} end
if not raw and member and tonumber(member) > now then return {'LOST'} end
local state
if raw then
  local ok
  ok,state=pcall(cjson.decode,raw)
  if not ok or type(state)~='table' or state.generation ~= req.generation or type(state.incarnation)~='string' or type(state.actions)~='table' or type(state.dedup)~='table' or type(state.reserves)~='table' then return {'LOST'} end
  for _,v in pairs(state.dedup) do
    if type(v)~='table' or type(v.expires)~='number' or type(v.fingerprint)~='string' or type(v.nonce)~='string' then return {'LOST'} end
  end
  for _,v in pairs(state.reserves) do
    if type(v)~='table' or type(v.expires)~='number' or type(v.amount)~='number' or v.amount<0 then return {'LOST'} end
  end
  for _,action in pairs(state.actions) do
    if type(action)~='table' then return {'LOST'} end
    if action.tokens~=nil then
      if type(action.tokens)~='number' or type(action.at)~='number' then return {'LOST'} end
    else
      for _,events in pairs(action) do
        if type(events)~='table' then return {'LOST'} end
        for _,v in pairs(events) do
          if type(v)~='table' or type(v.at)~='number' or type(v.cost)~='number' or v.cost<0 then return {'LOST'} end
        end
      end
    end
  end
else
  state={generation=req.generation,incarnation=req.incarnation,actions={},dedup={},reserves={}}
end
-- Retire cold-window events even if another action keeps this subject alive.
for _,action in pairs(state.actions) do
  if action.tokens==nil then
    for index,events in pairs(action) do
      local kept={}
      for _,v in ipairs(events) do if not v.expiry or v.expiry>now then kept[#kept+1]=v end end
      action[index]=kept
    end
  end
end
if req.proof.incarnation and req.proof.incarnation ~= '' and req.proof.incarnation ~= state.incarnation then return {'LOST'} end
local entries=0
for key,v in pairs(state.dedup) do
  if v.expires <= now then state.dedup[key]=nil else entries=entries+1 end
end
local operation=req.proof.operation
local old=operation and state.dedup[operation]
if old then
  if old.fingerprint ~= req.proof.fingerprint or (req.kind~='confirm' and old.nonce ~= req.proof.nonce) then return {'CONFLICT'} end
  if req.kind ~= 'confirm' then return {'REPLAY',state.incarnation} end
end
if req.kind~='confirm' and req.proof.deadline and req.proof.deadline > 0 and now >= req.proof.deadline then return {'EXPIRED'} end
if req.kind == 'probe' then return {'ABSENT',state.incarnation} end
if req.kind == 'confirm' then
  if operation then state.dedup[operation]=nil end
end
-- Grant a positive partial chunk when less than 64KiB remains. A small body
-- must not fail merely because the reservation quantum is larger than it.
if req.kind=='reserve' then
  local available=req.amount
  for _,charge in ipairs(req.charges) do
    if charge.reserve and charge.rule.mode=='enforce' then
      local current=state.actions[charge.rule.action] or {}
      for index,w in ipairs(charge.rule.windows) do
        local total=0
        for _,v in ipairs(current[tostring(index)] or {}) do if v.at>now-w.ms then total=total+v.cost end end
        available=math.min(available,math.max(0,w.limit-total))
      end
    end
  end
  req.amount=math.max(1,available)
  for _,charge in ipairs(req.charges) do if charge.reserve then charge.cost=req.amount end end
end
local usedEvents=0
local remaining=1
local wait=0
local apply={}
local observed=false
for _,charge in ipairs(req.charges) do
  local rule=charge.rule
  if charge.cost < 0 then return {'INVALID'} end
  local current=state.actions[rule.action] or {}
  if rule.bucket then
    local capacity=rule.bucket.capacity*1000
    local at=current.at or now
    local available=math.min(capacity,(current.tokens or capacity)+math.max(0,now-at)*rule.bucket.perSecond)
    local needed=charge.cost*1000
    if needed>capacity then if rule.mode=='observe' then observed=true else return {'INVALID'} end end
    if available<needed then
      if rule.mode=='observe' then observed=true else wait=math.max(wait,math.ceil((needed-available)/rule.bucket.perSecond)) end
    end
    apply[#apply+1]={action=rule.action,value={tokens=math.max(0,available-needed),at=math.max(now,at)}}
  else
    local windows={}
    for index,w in ipairs(rule.windows) do
      local events={}
      local total=0
      local previous=current[tostring(index)] or {}
      for _,v in ipairs(previous) do
        if v.at>now-w.ms then
          events[#events+1]=v
          total=total+v.cost
        end
      end
      if req.kind == 'settle' then
        local reserve=state.reserves[req.transfer]
        if not reserve or req.actual<0 or req.actual>reserve.amount then return {'INVALID'} end
        local matched=false
        for _,v in ipairs(events) do
          if v.id == req.transfer then total=total-v.cost+req.actual; v.cost=req.actual; v.at=now; v.expiry=now+w.ms;v.id=nil;matched=true end
        end
        if not matched and req.actual>0 then events[#events+1]={at=now,cost=req.actual,expiry=now+w.ms};total=total+req.actual end
      else
        if charge.cost>w.limit then if rule.mode=='observe' then observed=true else return {'INVALID'} end end
        if total+charge.cost>w.limit then
          table.sort(events,function(a,b) return a.at<b.at end)
          local release=total+charge.cost-w.limit
          for _,v in ipairs(events) do
            release=release-v.cost
            if release<=0 then
              if rule.mode=='observe' then observed=true else wait=math.max(wait,v.at+w.ms-now) end
              break
            end
          end
        end
        if charge.cost>0 and (rule.mode~='observe' or total+charge.cost<=w.limit) then
          -- An unsettled reservation stays budgeted for the full window after
          -- the last permitted read. On settlement its actual receipt time wins.
          events[#events+1]={at=req.kind=='reserve' and charge.reserve and now+req.readMS or now,cost=charge.cost,expiry=(req.kind=='reserve' and charge.reserve and now+req.readMS or now)+w.ms,id=charge.reserve and req.transfer or nil}
        end
      end
      usedEvents=usedEvents+#events
      windows[tostring(index)]=events
    end
    apply[#apply+1]={action=rule.action,value=windows}
  end
end
if wait>0 then return {'DENY',tostring(math.min(86400,math.max(1,math.ceil(wait/1000))))} end
if req.kind=='check' then return {'ALLOW',state.incarnation,observed and '1' or '0','0'} end
if req.kind=='reset' then for _,charge in ipairs(req.charges) do state.actions[charge.rule.action]=nil end;apply={} end
if usedEvents>req.maxEvents then return {'CAPACITY'} end
if operation and req.kind~='confirm' and entries>=req.maxDedup then return {'CAPACITY'} end
local reserves=0
for id,v in pairs(state.reserves) do
  if v.expires<=now then state.reserves[id]=nil else reserves=reserves+1 end
end
if req.kind=='reserve' then
  if state.reserves[req.transfer] then return {'INVALID'} end
  if reserves>=req.maxReserves then return {'CAPACITY'} end
  state.reserves[req.transfer]={amount=req.amount,expires=now+req.readMS+req.reserveMS}
elseif req.kind=='settle' then
  state.reserves[req.transfer]=nil
end
for _,v in ipairs(apply) do state.actions[v.action]=v.value end
local totalEvents=0
for _,action in pairs(state.actions) do
  if action.tokens==nil then for _,events in pairs(action) do totalEvents=totalEvents+#events end end
end
if totalEvents>req.maxEvents then return {'CAPACITY'} end
if operation and req.kind~='confirm' then
  state.dedup[operation]={fingerprint=req.proof.fingerprint,nonce=req.proof.nonce,expires=now+req.dedupMS}
end
local encoded=cjson.encode(state)
if string.len(encoded)>req.maxBytes then return {'CAPACITY'} end
-- Directory expiry extends beyond the actual subject TTL to identify missing
-- subjects while still allowing ordinary, expected expiry to create new state.
redis.call('ZREMRANGEBYSCORE',KEYS[3],'-inf',now)
if not member and redis.call('ZCARD',KEYS[3])>=req.maxSubjects then return {'CAPACITY'} end
redis.call('ZADD',KEYS[3],now+req.retention,req.subject)
redis.call('PEXPIRE',KEYS[3],req.retention+1000)
redis.call('SET',KEYS[2],encoded,'PX',req.retention)
return {'ALLOW',state.incarnation,observed and '1' or '0',tostring(req.kind=='reserve' and req.amount or 0)}
