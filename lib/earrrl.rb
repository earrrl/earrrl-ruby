# frozen_string_literal: true

require_relative "earrrl/version"

class Earrrl
  class Error < StandardError; end

  # TODO! change the params here
  EARRRL_SCRIPT = <<~LUA
    -- parameters and state
    local lambda = 0.06931471805599453 -- 10 seconds half-life
    local rate_limit = 0.5
    local time_array = redis.call("time")
    local now = time_array[1]+0.000001*time_array[2] -- seconds + microseconds

    local flat_NT = redis.call("hgetall",KEYS[1])
    local N = 0.0
    local T = 0.0
    if #flat_NT == 4 then
      if flat_NT[1] == "N" then
        N = flat_NT[2]
        T = flat_NT[4]
      else
        T = flat_NT[2]
        N = flat_NT[4]
      end
    end

    local delta_t = T-now

    
    -- functions

    local function evaluate()
      return N*lambda*math.exp(lambda*delta_t)
    end
    
    local function update()
      redis.call("hset", KEYS[1], "N", 1+N*math.exp(lambda*delta_t), "T", now)
    end
    
    local function is_rate_limited()
      local estimated_rate = evaluate()
      local limited = estimated_rate > rate_limit
      update()
      return tostring(estimated_rate)
    end
    

    -- the whole big show

    return is_rate_limited()
  LUA

  def initialize(redis_instance)
    @redis = redis_instance
    @earrrl_hash = @redis.script "load", EARRRL_SCRIPT
  end


  # returns estimated rate prior to this update and updates the estimator with this request amount
  # if not specified, this update amount defaults to 1
  def check(key, update: true, weight: 1)
    resp = @redis.evalsha(@earrrl_hash,[1],[key]).to_f
    puts "RESPONSE #{resp}"
    return resp
  end


  # TODO! do we need cleanup methods like delete key or delete all keys?
end
