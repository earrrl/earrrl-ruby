# frozen_string_literal: true


module Earrrl
  class ScriptLoader

    EARRRL_SCRIPT = <<~LUA
      -- parameters and state
      local lambda = ARGV[1]
      local increment = ARGV[2]
      
      local flat_NT = redis.pcall("hgetall",KEYS[1])
      local N = 0.0
      local T = 0.0
      if #flat_NT == 4 and flat_NT[1] == "N" and flat_NT[3] == "T" then
          N = flat_NT[2]
          T = flat_NT[4]
      end
      if N == 0.0 and T == 0.0 and (flat_NT["err"] or #flat_NT > 0) then
          -- something is wrong with this key (otherwiser N and T would be non-zero by now), just delete it and start over
          redis.call("del", KEYS[1]) -- TODO! test
      end

      local time_array = redis.call("time")
      local now = time_array[1]+0.000001*time_array[2] -- seconds + microseconds
  
      
      -- prepare
      local n_exp_lambda_del_t = N*math.exp(lambda * (T - now))
  
      -- evaluate
      local estimated_rate = lambda*n_exp_lambda_del_t
  
      -- update
      if increment ~= 0 then
        redis.call("hset", KEYS[1], "N", increment + n_exp_lambda_del_t, "T", now)
      end
      
      return tostring(estimated_rate)
    LUA

    def self.load(redis_instance)
      Earrrl::Limiter.set_script_token(redis_instance.script "load", EARRRL_SCRIPT)
    end

  end
end