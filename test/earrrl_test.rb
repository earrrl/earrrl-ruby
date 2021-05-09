require "minitest/autorun"
require "redis"
require "earrrl"

class EarrrlTest < Minitest::Test
  def setup
    @redis = Redis.new
    @earrrl = Earrrl.new(@redis)
    @key = "billy"
  end

  def test_check_and_update
    @redis.del("#{@key}:N")
    @redis.del("#{@key}:T")
    assert @earrrl.check(@key) == 0
    assert @earrrl.check(@key) > 0
  end
end


# TODO!
# * unit test inputs (validations, converting half_life to lambda)
# * unit test w/ and w/o rate_limit (if no rate limit, then the estimated rate is returned)
# * integration test half_life (unit test will make sure that lambda case works)
#   * a hit every .01 sec half_life of 0.1 will mean that after 0.1 the estimate should be near 50requests per sec
#   * after waiting 0.1 second, the estimate should be near 25 request per sec
