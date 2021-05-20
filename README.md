# Earrrl::Ruby

EARRRL is the Estimated Average Recent Request Rate Limiter as described in these blog posts:
* [EARRRL – the Estimated Average Recent Request Rate Limiter](http://blog.jnbrymn.com/2021/03/18/estimated-average-recent-request-rate-limiter.html)
* [EARRRL – the Estimated Average Recent Request Rate Limiter - the Mathy Bits](http://blog.jnbrymn.com/2021/03/18/estimated-average-recent-request-rate-limiter-math.html)

EARRRL is used as a rate limiter or as a general purpose rate estimator.

Nice qualities:
* Simple design. EARRRL does not rely on cycling through multiple keys in Redis, ex. one key per user per rate window. Rather it's just one key per user. Similarly, there is no need to TTL the keys in Redis. Instead, keys are kept in Redis until they are removed based on the LRU policy and the memory size.
* EARRRL is not "forgetful" like naive time-window rate limiters. Whereas a naive implementation would block users from executing excessive requests during a time window, in the next time window they can offend again. With EARRRL, if a user's estimated rate exceeds the rate limit, then they will be rate limited indefinitely. EARRRL will allow requests to proceed only after the user reduces their request rate to an appropriate level.
* Not only does EARRRL provide rate limiting functionality, but it provides the estimated rate, which can be useful for other things.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'earrrl-ruby'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install earrrl-ruby
    
 
TODO: discuss Redis setup. It should be simple, just use basic LRU settings and allocate enough memory so that your "spikey" abusers (those that pound the server for a brief interval and then leave it alone for a while) don't get dropped from Redis during periods of inactivity.   

## Usage

```ruby

require "redis"
require "earrrl"

# All keys in redis are prefixed with this.
prefix = "my_api_end_point" 

# half_life is a parameter that controls how quickly the estimator converges in seconds. The larger the half-life, then the longer
# it takes to converge BUT the more accurate the estimate will be once it converges. If the half-life is too long then the
# estimator may let too many requests through before converging. If the half-life is too short, then the estimator might over-react
# to spikey requests.   
half_life = 10 
# As an alternative, you can also specify the accuracy using the epsilon parameter instead of half_life. You can not specify
# both values because they are directly related to one-another. See the blog post above for details. (Note, in the blog post the
# epsilon variable is referred to as lambda, but that is a reserved word in Ruby so we changed it.) 
 
 
# rate_limit specifies the maximum allowable estimated rate in requests per second. 
rate_limit = 100 
 
# Initialize the EARRRL limiter.  
earrrl = Earrrl::Limiter.new(redis, prefix, half_life:half_life, rate_limit: rate_limit)

# Update the rate estimate for "some_user" and return the rate estimate _prior_ to the update.
estimated_rate = earrrl.update_and_return_rate("some_user") 

# If the second argument is not provided, then it is assumed that the update is for 1 requests. But you can provide a second 
# argument if something besides 1 is more appropriate. For example you could weight requests by how much resources they are likely 
# to use. Here we assume that the user makes a request with a weight of 2.5.
estimated_rate = earrrl.update_and_return_rate("some_user", 2.5)

# If you only need the rate limited decision, then use `update_and_rate_limited?`, which returns true if the estimated
# rate (prior to the update)is above the rate_limit specified at EARRRL instantiation. This method also takes an 
# optional second argument to specify the rate.
is_rate_limited = earrrl.update_and_rate_limited?("some_user")

# If you would like to check on the estimated rate or rate limited status without updating the state of the estimator, 
# then just specify a second argument of 0, but typically you will not want to do this (see note below).
estimated_rate = earrrl.update_and_return_rate("some_user", 0)
```

**Important usage note:** It may be tempting to check the rate limit prior to making the request, and then _if the user is not rate limited_ actually make the request. E.g. something like this

```ruby
# WRONG WAY TO USE EARRRL
is_rate_limited = earrrl.update_and_rate_limited?("some_user", 0)

if !is_rate_limited
  do_big_expensive_request
  earrrl.update_and_rate_limited?("some_user", 3)
end
```

This is a bad idea. If you check the rate limit without updating the state of the rate limiter, then you are subject to a nasty race condition where a bad actor may simultaneously send many requests and not be rate limited until after the first mega-match of requests returns. By atomically checking and updating the rate estimate, you effectively serialize the user's requests and circumvent this problem. In any case, this usage above doesn't make sense for EARRRL, because it is not estimating how many requests that _you_ allow to proceed, but is instead estimating the rate at which requests are received (whether or not they are serviced). If you only update requests that come in under the rate limit, then bad actors with high request rates will periodically touch the rate limit, but will be allowed to offend again and again.  


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/JnBrymn/earrrl-ruby. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/JnBrymn/earrrl-ruby/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
