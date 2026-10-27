local r=cjson.decode(ARGV[1])
local sub,byte,pack,unpack,char=string.sub,string.byte,struct.pack,struct.unpack,string.char
local zero16,zero32=string.rep('\0',16),string.rep('\0',32)
local clock=redis.call('TIME')
local now=tonumber(clock[1])*1000+math.floor(tonumber(clock[2])/1000)
local function bad() error('SNAPSHOT_INTEGRITY') end
local function integer(v,lo,hi) return type(v)=='number' and v==math.floor(v) and v>=lo and v<=hi end
local function hexraw(s)
  if type(s)~='string' or #s%2~=0 or s:find('[^0-9a-f]') then bad() end
  return (s:gsub('..',function(v) return string.char(tonumber(v,16)) end))
end
local function uuidraw(s)
  if type(s)~='string' or #s~=36 or s:sub(9,9)~='-' or s:sub(14,14)~='-' or s:sub(19,19)~='-' or s:sub(24,24)~='-' then bad() end
  local raw=hexraw((s:gsub('-','')));if #raw~=16 then bad() end;return raw
end
local function uuidtext(raw)
  local s=(raw:gsub('.',function(v) return string.format('%02x',string.byte(v)) end))
  return s:sub(1,8)..'-'..s:sub(9,12)..'-'..s:sub(13,16)..'-'..s:sub(17,20)..'-'..s:sub(21)
end
local function safe64(raw,p)
  local a,b=byte(raw,p,p+1)
  if a~=0 or b>31 then bad() end
end
local prefix='HNCSL02\0'..uuidraw(r.epoch)..hexraw(r.hash)
local rawControl=redis.call('GET',KEYS[1])
if not rawControl or #rawControl>2048 then bad() end
local ok,c=pcall(cjson.decode,rawControl)
if not ok or type(c)~='table' or c.ledgerFormat~=2 or c.epoch~=r.epoch or c.hash~=r.hash or not integer(c.until_ms,0,9007199254740991) or (c.state~='READY' and c.state~='DRAINING') then bad() end
r.idRaw=ARGV[3];r.owner=ARGV[4];r.request=ARGV[5];r.scope=ARGV[6];r.token=ARGV[7];r.digest=ARGV[8]
if r.id and (#r.idRaw~=16 or r.idRaw~=uuidraw(r.id)) then bad() end
local states={'pending','active','aborting'}
local function dueValues(state,lease,expires) return state==3 or (state==1 and lease<=now) or expires<=now end
local function readLedger()
  local stats={count=0,bytes=r.fixedBytes,own=0,first=now+86400000,ids={}}
  local raw=redis.call('GET',KEYS[2])
  if not raw then
    if c.until_ms>now then bad() end
    return {raw=prefix..struct.pack('>!1I8I4',c.until_ms,0),entries={},until_ms=c.until_ms,count=0},stats
  end
  if #raw<68 or #raw>r.maxLedgerBytes or raw:sub(1,56)~=prefix then bad() end
  safe64(raw,57)
  local until_ms,count=struct.unpack('>!1I8I4',raw,57)
  if count>r.maxEntries or #raw~=68+206*count then bad() end
  local l={raw=raw,entries={},until_ms=until_ms,count=count}
  local op=r.op
  local ownerUsage=op=='prepare' or op=='usage'
  local requestLookup=op=='prepare' or op=='lookup'
  local requestedOwner,requestedRequest,requestedID=r.owner,r.request,r.idRaw
  local maxBytes=r.maxModuleBytes
  local counted,bytes,own,first=0,r.fixedBytes,0,stats.first
  local seen,requests={},{}
  local release,segments,last,removed,removedBytes={}, {},69,0,0
  if op=='release' then
    if #ARGV[9]%16~=0 or #ARGV[9]/16>r.maxEntries or #KEYS~=#ARGV[9]/16+2 then bad() end
    for p=1,#ARGV[9],16 do
      local id=ARGV[9]:sub(p,p+15);if release[id] then bad() end;release[id]=(p-1)/16+3
    end
  end
  for p=69,#raw,206 do
    local id=sub(raw,p,p+15)
    local request=sub(raw,p+48,p+79)
    if id==zero16 or seen[id] or requests[request] then bad() end
    seen[id]=true;requests[request]=true
    -- Split uint64 fields into exact uint32 words. Validate the high words
    -- before combining, so no out-of-range uint64 is first rounded to double.
    local cost,ch,cl,eh,el,lh,ll,flags,state=unpack('>!1I4I4I4I4I4I4I4BB',raw,p+176)
    if ch>2097151 or eh>2097151 or lh>2097151 then bad() end
    local created,expires,lease=ch*4294967296+cl,eh*4294967296+el,lh*4294967296+ll
    if cost<4096 or cost>maxBytes or created<1 or created>9007199252880991 or expires~=created+1800000 or lease<created-2000 or lease>created+32000 or (flags~=2 and flags~=6 and flags~=10 and flags~=18) or state<1 or state>3 or until_ms<expires+60000 then bad() end
    counted=counted+1;bytes=bytes+cost
    local owner=sub(raw,p+16,p+47)
    if owner==zero32 then bad() end
    if ownerUsage and owner==requestedOwner then own=own+1;first=math.min(first,state==2 and expires or lease) end
    if id==requestedID or (requestLookup and request==requestedRequest) then
      local text=uuidtext(id)
      l.entries[text]={position=p,owner=owner,request=request,scope=raw:sub(p+80,p+111),token=raw:sub(p+112,p+143),digest=raw:sub(p+144,p+175),cost=cost,created=created,expires=expires,lease=lease,flags=flags,state=states[state],stateCode=state}
      if requestLookup and request==requestedRequest then stats.match=text end
    end
    if op=='due' and dueValues(state,lease,expires) then stats.ids[#stats.ids+1]=id end
    if release[id] and dueValues(state,lease,expires) and redis.call('EXISTS',KEYS[release[id]])==0 then
      segments[#segments+1]=raw:sub(last,p-1);last=p+206;removed=removed+1;removedBytes=removedBytes+cost
    end
  end
  if counted~=count or bytes>maxBytes then bad() end
  stats.count,stats.bytes,stats.own,stats.first=counted,bytes,own,first
  if op=='release' then
    segments[#segments+1]=raw:sub(last);l.body=table.concat(segments);l.count=count-removed;stats.bytes=stats.bytes-removedBytes
  end
  return l,stats
end
local function save(l)
  local until_ms=math.max(l.until_ms,c.until_ms)
  if until_ms<=now then until_ms=now+60000 end
  local header=prefix..pack('>!1I8I4',until_ms,l.count)
  local raw
  if l.body then
    raw=header..l.body
  elseif l.add then
    raw=header..sub(l.raw,69)..l.add
  elseif l.patch then
    local p=l.patch.position+205
    raw=header..sub(l.raw,69,p-1)..char(l.patch.stateCode)..sub(l.raw,p+1)
  else
    raw=header..sub(l.raw,69)
  end
  if #raw>r.maxLedgerBytes then error('SNAPSHOT_CAPACITY') end
  if #raw~=68+206*l.count then bad() end
  l.until_ms=until_ms
  redis.call('SET',KEYS[2],raw,'PXAT',tostring(until_ms))
end
local function newRecord()
  if #r.idRaw~=16 or #r.owner~=32 or #r.request~=32 or #r.scope~=32 or #r.token~=32 or #r.digest~=32 or not integer(r.cost,4096,4294967295) or not integer(r.created,1,9007199252880991) or not integer(r.expires,r.created+1800000,r.created+1800000) or (r.flags~=2 and r.flags~=6 and r.flags~=10 and r.flags~=18) then bad() end
  return r.idRaw..r.owner..r.request..r.scope..r.token..r.digest..struct.pack('>!1I4I8I8I8BB',r.cost,r.created,r.expires,now+30000,r.flags,1)
end
