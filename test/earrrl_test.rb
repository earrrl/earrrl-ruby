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
    result = @earrrl.check(@key)
    refute result[0]
    assert_equal result[1], 0
  end
end