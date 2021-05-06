# frozen_string_literal: true

require_relative "earrrl/version"

class Earrrl
  class Error < StandardError; end

  # TODO! change the params here
  # TODO! make sure there is one key that points to a redis set rather than :N and :T
  EARRRL_SCRIPT = <<~LUA
    -- parameters and state
    local lambda = 0.06931471805599453 -- 10 seconds half-life
    local rate_limit = 0.5
    local time_array = redis.call("time")
    local now = time_array[1]+0.000001*time_array[2] -- seconds + microseconds
    local Nkey = KEYS[1]..":N"
    local Tkey = KEYS[1]..":T"
    
    local N = redis.call("get", Nkey)
    if N == false then
      N = 0
    end
    
    local T = redis.call("get", Tkey)
    if T == false then
      T = 0
    end
    
    local delta_t = T-now
    
    -- functions
    local function evaluate()
      return N*lambda*math.exp(lambda*delta_t)
    end
    
    local function update()
      redis.call("set", Nkey, 1+N*math.exp(lambda*delta_t))
      redis.call("set", Tkey, now)
    end
    
    local function is_rate_limited()
      local estimated_rate = evaluate()
      local limited = estimated_rate > rate_limit
      update()
      return {limited, tostring(estimated_rate)}
    end
    
    -- the whole big show
    return is_rate_limited()
  LUA

  def initialize(redis_instance)
    @redis = redis_instance
    @earrrl_hash = @redis.script "load", EARRRL_SCRIPT
  end


  # returns estimated rate prior to this update and updates the estimator with this request amount
  def check(key, update: true, weight: 1)
    # TODO! connect update and weight to script
    resp = @redis.evalsha(@earrrl_hash,[1],[key])
    return !!resp[0], resp[1].to_f
  end


  # TODO! do we need cleanup methods like delete key or delete all keys?
end
