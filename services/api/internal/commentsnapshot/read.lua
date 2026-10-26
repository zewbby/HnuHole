if r.op=='load' then
  local data=redis.call('GET',KEYS[2])
  if not data then return {'INVALID'} end
  local ttl=redis.call('PTTL',KEYS[2])
  if #data>r.maxPayload or ttl<1 or ttl>1800000+r.clockSkew then bad() end
  return {'DATA',data,tostring(now)}
end
local l,stats=readLedger()
if r.op=='lookup' then
  if stats.match then
      local id=stats.match
      local e=l.entries[id]
      if e.owner~=r.owner or e.scope~=r.scope then error('SNAPSHOT_REQUEST') end
      if e.state=='active' and e.expires>now then return {'REUSED',id,tostring(e.expires),tostring(e.flags)} end
      error('SNAPSHOT_UNAVAILABLE')
  end
  return {'ABSENT'}
end
if r.op=='probe' then
  local e=l.entries[r.id]
  if e and e.state=='active' and e.owner==r.owner and e.token==r.token and e.digest==r.digest and e.expires>now then return {'ACTIVE'} end
  return {'PENDING'}
end
if r.op=='due' then
  table.sort(stats.ids)
  local result={'DUE',tostring(stats.bytes)}
  for _,id in ipairs(stats.ids) do result[#result+1]=id end
  return result
end
if r.op=='usage' then
  return {tostring(stats.own),tostring(stats.bytes),tostring(math.max(1,math.ceil((stats.first-now)/1000)))}
end
bad()
