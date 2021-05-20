# frozen_string_literal: true

module Earrrl
  class Limiter
    class ScriptNotLoadedError < StandardError; end

    def self.script_token(redis)
      if !defined? @script_token
        self.load_script!(redis)
      end
      @script_token
    end

    def self.load_script!(redis)
      @script_token = Earrrl::ScriptLoader.load(redis)
    end

    def initialize(redis_instance, prefix, epsilon: nil, half_life: nil, rate_limit: nil)
      # you may specify epsilon or half_life but not both
      if (epsilon && half_life) || (!epsilon && !half_life)
        raise ArgumentError, "one of epsilon or half_life must be specified"
      end
      if !prefix.is_a? String
        raise ArgumentError, "prefix must be a String"
      end
      if epsilon && epsilon <= 0.0
        raise ArgumentError, "epsilon must be greater than 0.0"
      end
      if half_life && half_life <= 0.0
        raise ArgumentError, "half_life must be greater than 0.0"
      end
      if rate_limit && rate_limit <= 0.0
        raise ArgumentError, "rate_limit must be greater than 0.0"
      end
      @redis = redis_instance
      @prefix = prefix
      @epsilon = epsilon
      @epsilon = Math.log(2)/half_life if half_life
      @rate_limit = rate_limit
    end

    # returns the estimated rate before updating the state and then updates the state
    # if not specified, this update amount defaults to 1
    # if update amount is 0 then the state is not updated
    def update_and_return_rate(key, amount=1)
      rate = nil

      begin
        rate = @redis.evalsha(self.class.script_token(@redis), ["#{@prefix}:#{key}"], [@epsilon, amount])
      rescue Redis::CommandError => e
        if e.message =~ /NOSCRIPT/
          rate = @redis.evalsha(self.class.load_script!(@redis), ["#{@prefix}:#{key}"], [@epsilon, amount])
        else
          raise e
        end
      end

      return rate.to_f
    end

    # returns whether or not this key is rate limited based on the estimated rate before updating the state and then updates the state
    # if not specified, this update amount defaults to 1
    # if update amount is 0 then the state is not updated
    # if rate_limit was not specified at initialization then this raises an exception
    def update_and_rate_limited?(key, amount=1)
      if !@rate_limit
        raise ArgumentError, "rate_limit was not specified at initialization"
      end
      rate = update_and_return_rate(key, amount)
      return rate.to_f > @rate_limit
    end

  end
end