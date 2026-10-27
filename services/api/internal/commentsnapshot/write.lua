if r.op=='prepare' then
  if c.state~='READY' then error('SNAPSHOT_UNAVAILABLE') end
  local l,stats=readLedger()
  local own,total,bytes,first=stats.own,stats.count,stats.bytes,stats.first
  if stats.match then
      local id=stats.match
      local e=l.entries[id]
      if e.owner~=r.owner or e.scope~=r.scope then error('SNAPSHOT_REQUEST') end
      if e.state=='active' and e.expires>now then return {'REUSED',id,tostring(e.expires),tostring(e.flags)} end
      if e.state~='pending' or e.lease<=now or e.token~=r.token or id~=r.id or e.digest~=r.digest then error('SNAPSHOT_UNAVAILABLE') end
      local old=redis.call('GET',KEYS[3])
      if old and old~=ARGV[2] then bad() end
      if c.until_ms<e.expires+60000 then c.until_ms=e.expires+60000;redis.call('SET',KEYS[1],cjson.encode(c)) end
      if not old then redis.call('SET',KEYS[3],ARGV[2],'NX','PXAT',tostring(e.expires)) end
      return {'PREPARED',id,tostring(e.expires),tostring(e.flags)}
  end
  if math.abs(now-r.created)>r.clockSkew or r.expires~=r.created+1800000 or r.expires<=now then error('SNAPSHOT_UNAVAILABLE') end
  if #ARGV[2]>r.maxPayload or #ARGV[2]<153 then error('SNAPSHOT_TOO_LARGE') end
  if l.entries[r.id] or redis.call('EXISTS',KEYS[3])~=0 then bad() end
  if own+r.legacy>=r.maxAccount then
    local wait=math.max(1,math.ceil((first-now)/1000))
    if r.legacy>0 then wait=math.min(wait,r.legacyWait) end
    return {'QUOTA',tostring(math.max(1,wait))}
  end
  if total>=r.maxEntries or bytes+r.cost>r.maxModuleBytes then error('SNAPSHOT_CAPACITY') end
  l.add=newRecord();l.count=l.count+1
  l.until_ms=math.max(l.until_ms,r.expires+60000)
  save(l)
  -- Reservation precedes both the high-watermark and the data write. An error
  -- at any later command is conservatively charged, never rolled back blindly.
  c.until_ms=math.max(c.until_ms,l.until_ms)
  redis.call('SET',KEYS[1],cjson.encode(c))
  redis.call('SET',KEYS[3],ARGV[2],'NX','PXAT',tostring(r.expires))
  return {'PREPARED',r.id,tostring(r.expires),tostring(r.flags)}
end
local l,stats=readLedger()
if r.op=='drain' then
  c.state='DRAINING';redis.call('SET',KEYS[1],cjson.encode(c));return {'DRAINING'}
end
if r.op=='publish' or r.op=='abort' then
  local e=l.entries[r.id]
  if not e or e.owner~=r.owner or e.token~=r.token or e.digest~=r.digest then error('SNAPSHOT_UNAVAILABLE') end
  if r.op=='publish' then
    if e.state=='active' and e.expires>now then return {'ACTIVE'} end
    if e.state~='pending' or e.lease<=now or e.expires<=now or redis.call('GET',KEYS[3])~=ARGV[2] then error('SNAPSHOT_UNAVAILABLE') end
    -- Only patch when save would preserve both the header and absolute expiry.
    -- Missing new ACL permissions retain the original SET path; SET revocation
    -- must not be bypassed by a separately granted SETRANGE permission.
    local h=l.until_ms
    local expiryArg=tostring(h)
    local offset,stateByte=e.position+204,char(2)
    local activeReply={'ACTIVE'}
    if h==c.until_ms and h>now
       and expiryArg:match('^[0-9]+$') and tonumber(expiryArg)==h
       and redis.acl_check_cmd('SET',KEYS[2],'','PXAT',expiryArg)
       and redis.acl_check_cmd('PEXPIRETIME',KEYS[2])
       and redis.acl_check_cmd('SETRANGE',KEYS[2],offset,stateByte)
       and redis.call('PEXPIRETIME',KEYS[2])==h then
      redis.call('SETRANGE',KEYS[2],offset,stateByte)
      return activeReply
    end
    e.stateCode=2;l.patch=e;save(l);return {'ACTIVE'}
  end
  if e.state=='active' then return {'ACTIVE'} end
  e.stateCode=3;l.patch=e;save(l);return {'ABORTING'}
end
if r.op=='release' then
  save(l);return {'RELEASED',tostring(stats.bytes)}
end
bad()
