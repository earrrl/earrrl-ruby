# frozen_string_literal: true

require_relative "earrrl/version"

class Earrrl
  class Error < StandardError; end

  # TODO! change the params here
  EARRRL_SCRIPT = <<~LUA
    -- parameters and state
    local lambda = %{lambda}
    local rate_limit = %{rate_limit}
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
        -- something is wrong with this key, just delete it and start over
        redis.call("del", KEYS[1]) -- TODO! test
    end
    
    -- TODO! pull in lambda
    local exp_lambda_del_t = math.exp(lambda * (T - now))

    
    -- functions

    local function evaluate()
      return N*lambda*exp_lambda_del_t
    end
    
    local function update()
      redis.call("hset", KEYS[1], "N", ARGV[1] + N * exp_lambda_del_t, "T", now)
    end
    
    local function is_rate_limited()
      local estimated_rate = evaluate()
      update()
      return tostring(estimated_rate) -- TODO! can I remove tostring ?
    end
    

    -- the whole big show

    return is_rate_limited()
    -- TODO! remove all function calls and just make a script (removes pointer dereferences and makes script tiny bit faster)
  LUA

  #TODO! delete
  # EARRRL_SCRIPT = <<~LUA
  #   return ARGV[1]+1
  # LUA

  attr_accessor :redis, :earrrl_hash #TODO! delete

  def initialize(redis_instance, lambda: nil, half_life: nil, rate_limit: nil)
    #TODO! add key prefix
    # you may specify lambda or half_life but not both
    if (lambda && half_life) || (!lambda && !half_life)
      raise Exception.new "one of lambda or half_life must be specified"
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
    @lambda = lambda
    @lambda = Math.log(2)/half_life if half_life
    @rate_limit = rate_limit

    # TODO! how in ruby do we ensure that this script is only registered once? How do we prevent someone from misunderstanding and creating a new EARRRL instance every time they want to use it
    script = EARRRL_SCRIPT % {lambda:lambda, rate_limit:rate_limit||0.0}
    @earrrl_hash = @redis.script "load", script
  end


  # returns estimated rate prior to this update and updates the estimator with this request amount
  # if not specified, this update amount defaults to 1
  def update(key, amount)
    resp = @redis.evalsha(@earrrl_hash,[key], [amount])
    puts "RESPONSE #{resp}"
    return resp
  end

  #TODO! functions to add
  # * rate_limited?(key) returns the rate_limited? but doesn't update anything (errors if rate_limit wasnt set)
  # * before_update_rate_limited?(key, update=1) returns the rate_limited? evaluated before updated and then updates (errors if rate_limit wasnt set)
  # * get_rate_estimate(key) returns the rate estimate but doesn't update anything
  # * before_update_get_rate_estimate(key) returns the rate estimate but doesn't update anything and then updates


  # TODO! do we need cleanup methods like delete key or delete all keys?
end


# TODO! delete
#  require "earrrl";require "redis";e = Earrrl.new(Redis.new, lambda:0.07); e.update("asdf", 1)