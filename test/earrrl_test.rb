require "minitest/autorun"
require "redis"
require "earrrl"

class EarrrlTest < Minitest::Test
  def setup
    @redis = Redis.new
    @prefix = rand(36**10).to_s(36)
  end

  def test_lua_script_integration
    half_life = 10
    earrrl = Earrrl.new(@redis, @prefix, half_life:half_life)
    key = "some_user"
    redis_now = @redis.time
    redis_now = redis_now[0].to_i + 0.000001*redis_now[1].to_i
    lambd =  Math.log(2)/half_life

    assert_equal({}, @redis.hgetall("#{@prefix}:#{key}"), "we haven't updated this key, it shouldn't exist yet")

    estimated_rate = earrrl.update_and_return_rate(key, 1)
    assert_equal(0.0, estimated_rate)
    earrrl_state = @redis.hgetall("#{@prefix}:#{key}")
    first_t = earrrl_state["T"].to_f
    assert_equal(1.0, earrrl_state["N"].to_f, "the first update to N for the amount 1 should make N=1")
    assert_in_delta(redis_now, first_t, 0.01, "T should be updated to redis's NOW time")

    estimated_rate = earrrl.update_and_return_rate(key, 2)
    assert_in_delta(lambd, estimated_rate, 0.0001, "since almost no time has passed, the estimated rate should be lambda*N (and N = 1)")
    assert(estimated_rate < lambd, "since some time has passed, estimated_rate should be SLIGHTLY less than lambda")
    earrrl_state = @redis.hgetall("#{@prefix}:#{key}")
    assert_in_delta(3.0, earrrl_state["N"].to_f, 0.0001, "since almost no time has passed the value of N should be _almost_ 1 + 2 (the sum of the above update amounts)")
    assert(earrrl_state["N"].to_f < 3.0, "after the second update, N should be almost 3, but no more than 3")
    assert_in_delta(redis_now, earrrl_state["T"].to_f, 0.01, "T should be updated to redis's NOW time")
    assert_in_delta(redis_now, earrrl_state["T"].to_f, 0.02, "T should be updated to redis's NOW time")
    assert(earrrl_state["T"].to_f > first_t, "almost not time has passed, but _some_ has so the most recent T should be larger than the first")
  end
end


# TODO!
# * unit test inputs (validations, converting half_life to lambda)
# * unit test w/ and w/o rate_limit (if no rate limit, then the estimated rate is returned)
