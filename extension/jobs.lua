-- Bounded cooperative work: return to Aseprite between CPU-heavy chunks.
local registry=debug.getregistry()
local key='Merthius/Collabsprite/jobs/v1'
if registry[key] then return registry[key] end
local J={budget=0.008}
registry[key]=J
function J.new(fn) return {thread=coroutine.create(fn)} end
function J.checkpoint(progress)
  if J.active==coroutine.running() and os.clock()-J.started>=J.budget then
    coroutine.yield(progress)
  end
end
function J.step(job)
  J.active=job.thread;J.started=os.clock()
  local ok,value=coroutine.resume(job.thread)
  J.active=nil
  job.elapsed=math.max(job.elapsed or 0,os.clock()-J.started)
  if not ok then job.error=tostring(value);job.done=true
  elseif coroutine.status(job.thread)=='dead' then job.value=value;job.done=true
  else job.progress=value end
  return job.done
end
return J
