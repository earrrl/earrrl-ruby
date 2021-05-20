gem "mocha"

require "minitest/autorun"
require 'mocha/minitest'

require "redis"
require "earrrl"


class EarrrlTest < Minitest::Test
  def setup
    @redis = Redis.new
    Earrrl::ScriptLoader.load(@redis)
    @prefix = rand(36**10).to_s(36)
  end

  def test_lua_script_integration
    half_life = 10
    earrrl = Earrrl::Limiter.new(@redis, @prefix, half_life:half_life)
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
    assert_in_delta(lambd, estimated_rate, 0.0001, "since almost no time has passed, the estimated rate should be epsilon*N (and N = 1)")
    assert(estimated_rate < lambd, "since some time has passed, estimated_rate should be SLIGHTLY less than epsilon")
    earrrl_state = @redis.hgetall("#{@prefix}:#{key}")
    assert_in_delta(3.0, earrrl_state["N"].to_f, 0.0001, "since almost no time has passed the value of N should be _almost_ 1 + 2 (the sum of the above update amounts)")
    assert(earrrl_state["N"].to_f < 3.0, "after the second update, N should be almost 3, but no more than 3")
    assert_in_delta(redis_now, earrrl_state["T"].to_f, 0.01, "T should be updated to redis's NOW time")
    assert_in_delta(redis_now, earrrl_state["T"].to_f, 0.02, "T should be updated to redis's NOW time")
    assert(earrrl_state["T"].to_f > first_t, "almost not time has passed, but _some_ has so the most recent T should be larger than the first")
  end

  # if the value stored at the key is of the wrong type, then delete it and start anew
  def test_lua_drop_bad_key
    earrrl = Earrrl::Limiter.new(@redis, @prefix, half_life:10)
    key = "some_user"
    redis_now = @redis.time
    redis_now = redis_now[0].to_i + 0.000001*redis_now[1].to_i
    @redis.set("#{@prefix}:#{key}","chunky_bacon")
    estimated_rate = earrrl.update_and_return_rate(key, 1)
    assert_equal 0, estimated_rate
    earrrl_state = @redis.hgetall("#{@prefix}:#{key}")
    assert_equal "1", earrrl_state["N"]
    assert_in_delta(redis_now, earrrl_state["T"].to_f, 0.01, "T should be updated to redis's NOW time")
  end

  # if the value stored at the key is of the wrong type, then delete it and start anew
  def test_lua_drop_bad_key_2
    earrrl = Earrrl::Limiter.new(@redis, @prefix, half_life:10)
    key = "some_user"
    redis_now = @redis.time
    redis_now = redis_now[0].to_i + 0.000001*redis_now[1].to_i
    @redis.hset("#{@prefix}:#{key}","a", "1", "b", "2")
    estimated_rate = earrrl.update_and_return_rate(key, 1)
    assert_equal 0, estimated_rate
    earrrl_state = @redis.hgetall("#{@prefix}:#{key}")
    assert_equal "1", earrrl_state["N"]
    assert_in_delta(redis_now, earrrl_state["T"].to_f, 0.01, "T should be updated to redis's NOW time")
  end

  def test_initialize__one_of_epsilon_half_life
    err = assert_raises ArgumentError do
      Earrrl::Limiter.new(@redis, @prefix, epsilon: 3, half_life:10)
    end
    assert_match(/one of epsilon or half_life must be specified/, err.message)

    err = assert_raises ArgumentError do
      Earrrl::Limiter.new(@redis, @prefix)
    end
    assert_match(/one of epsilon or half_life must be specified/, err.message)
  end

  def test_initialize__negative_epsilon
    err = assert_raises ArgumentError do
      Earrrl::Limiter.new(@redis, @prefix, epsilon: -3)
    end
    assert_match(/epsilon must be greater than 0.0/, err.message)
  end

  def test_initialize__negative_rate_limit
    err = assert_raises ArgumentError do
      Earrrl::Limiter.new(@redis, @prefix, half_life: 3, rate_limit: -4)
    end
    assert_match(/rate_limit must be greater than 0.0/, err.message)
  end

  def test_initialize__negative_half_life
    err = assert_raises ArgumentError do
      Earrrl::Limiter.new(@redis, @prefix, half_life: -3)
    end
    assert_match(/half_life must be greater than 0.0/, err.message)
  end

  def test_update_and_return_rate
    half_life = 10
    epsilon = Math.log(2)/half_life
    earrrl = Earrrl::Limiter.new(@redis, @prefix, half_life:half_life)
    @redis.expects(:evalsha).with() do |hash, key, args|
      assert_match(/^[a-f0-9]{40}$/, hash)
      assert_equal ["#{@prefix}:my_key"], key
      assert_equal [epsilon, 1], args
    end.returns("123.4")
    assert_equal 123.4, earrrl.update_and_return_rate("my_key")
  end

  def test_update_and_return_rate__with_amount
    half_life = 10
    epsilon = Math.log(2)/half_life
    earrrl = Earrrl::Limiter.new(@redis, @prefix, half_life:half_life)
    @redis.expects(:evalsha).with() do |hash, key, args|
      assert_match(/^[a-f0-9]{40}$/, hash)
      assert_equal ["#{@prefix}:my_key"], key
      assert_equal [epsilon,2], args
    end.returns("123.4")
    assert_equal 123.4, earrrl.update_and_return_rate("my_key", 2)
  end

  def test_update_and_return_limited__err_if_no_rate_limit
    earrrl = Earrrl::Limiter.new(@redis, @prefix, half_life:10)
    earrrl.expects(:update_and_return_rate).never
    err = assert_raises ArgumentError do
      earrrl.update_and_rate_limited?("my_key")
    end
    assert_match(/rate_limit was not specified at initialization/, err.message)
  end

  def test_update_and_return_limited
    earrrl = Earrrl::Limiter.new(@redis, @prefix, half_life:10, rate_limit: 100)
    earrrl.expects(:update_and_return_rate).with("my_key", 1).returns(200)
    assert earrrl.update_and_rate_limited?("my_key")
  end

  def test_update_and_return_limited__with_amount
    earrrl = Earrrl::Limiter.new(@redis, @prefix, half_life:10, rate_limit: 100)
    earrrl.expects(:update_and_return_rate).with("my_key", 2).returns(50)
    refute earrrl.update_and_rate_limited?("my_key", 2)
  end
end
