# frozen_string_literal: true

require_relative "earrrl/version"

class Earrrl
  class Error < StandardError; end

  EARRRL_SCRIPT = <<~LUA
    -- parameters and state
    local lambda = %{lambda}
    local time_array = redis.call("time")
    local now = time_array[1]+0.000001*time_array[2] -- seconds + microseconds

    local flat_NT = redis.call("hgetall",KEYS[1])
    local N = 0.0
    local T = 0.0
    if #flat_NT == 4 and flat_NT[1] == "N" and flat_NT[3] == "T" then
        N = flat_NT[2]
        T = flat_NT[4]
    end
    if N == 0.0 and T == 0.0 and #flat_NT > 0 then
        -- something is wrong with this key (otherwiser N and T would be non-zero by now), just delete it and start over
        redis.call("del", KEYS[1]) -- TODO! test
    end
    
    -- prepare
    local n_exp_lambda_del_t = N*math.exp(lambda * (T - now))

    -- evaluate
    local estimated_rate = lambda*n_exp_lambda_del_t

    -- update
    if ARGV[1] ~= 0 then
      redis.call("hset", KEYS[1], "N", ARGV[1] + n_exp_lambda_del_t, "T", now)
    end
    
    return tostring(estimated_rate)
  LUA

  def initialize(redis_instance, prefix, lambda: nil, half_life: nil, rate_limit: nil)
    # you may specify lambda or half_life but not both
    if (lambda && half_life) || (!lambda && !half_life)
      raise Exception.new "one of lambda or half_life must be specified"
    end
    if !prefix.is_a? String
      raise Exception.new "prefix must be a String"
    end
    if lambda && lambda <= 0.0
      raise Exception.new "lambda must be greater than 0.0"
    end
    if half_life && half_life <= 0.0
      raise Exception.new "half_life must be greater than 0.0"
    end
    if rate_limit && rate_limit <= 0.0
      raise Exception.new "rate_limit must be greater than 0.0"
    end
    @redis = redis_instance
    @prefix = prefix
    @lambda = lambda
    @lambda = Math.log(2)/half_life if half_life
    @rate_limit = rate_limit

    script = EARRRL_SCRIPT % {lambda:lambda}
    # TODO! how in ruby do we ensure that this script is only registered once? How do we prevent someone from misunderstanding and creating a new EARRRL instance every time they want to use it
    @earrrl_hash = @redis.script "load", script
  end

  # returns the estimated rate before updating the state and then updates the state
  # if not specified, this update amount defaults to 1
  # if update amount is 0 then the state is not updated
  def update_and_return_rate(key, amount=1)
    rate = @redis.evalsha(@earrrl_hash,["#{@prefix}:#{key}"], [amount])
    return rate.to_f
  end

  # returns whether or not this key is rate limited based on the estimated rate before updating the state and then updates the state
  # if not specified, this update amount defaults to 1
  # if update amount is 0 then the state is not updated
  # if rate_limit was not specified at initialization then this raises an exception
  def update_and_rate_limited?(key, amount=1)
    if !@rate_limit
      raise Exception.new "rate limit was not specified when Earrrl was initialized"
    end
    rate = update_and_return_rate(key, amount)
    return rate.to_f > @rate_limit
  end

end
