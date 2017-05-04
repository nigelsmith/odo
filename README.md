# Odo

## Description

Odo is a simple, GenServer based, token bucket rate limiter for communicating with rate limtied APIs.  Full documentation 
can be found at [https://hexdocs.pm/odo](https://hexdocs.pm/odo).

## Installation

The package can be installed by adding `odo` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:odo, "~> 0.1.0"}]
end
```

you will also need to list it in your applications unless using Elixir ~> 1.4 which infers applications from
your dependency list.

## Usage

You can create a new bucket like so:

```elixir
Odo.Bucket.new_bucket("my bucket")
```

and to obtain a token:

```elixir
status = Odo.Bucket.get_token("my bucket")
```

The status return value will be one of the following forms.  When it's ok to proceed with your request you will receive
`{:ok, tokens_remaining, until}` with `until` being the time in milliseconds until he next tick or refill occurs.

When the bucket is full the reply will be `{:stop, until}`, again with `until` measured in milliseconds letting you know
when the next window of opportunity to make a request will open up.

#### Configuration

You may also configure the bucket with the following options:

```elixir
Odo.Bucket.new_bucket("my bucket", tokens: 20, tick_duration: 10_000, tick_refill_amount: 20, buffer: 200)
```

`tick_duration: value` specifies the intervals at which the bucket is refilled in milliseconds whilst `tick_refill_amount`
provides for the amount to add in each tick.  The `buffer: value` lets you provide a buffer to add to the tick duration.
You may want to do that in order to account for latency or other delays between the time you secure a token from the bucket
and the time that the request to the remote API actually arrives.

For example, if you dispatch 10 requests within a 10 second window you can be sure that you do not exceed that amount,
but you do not have a guarantee about when those requests are actually delivered to the remote service.  If the latency
between your client and the remote API varies, it is possible for a later request to arrive out of order and so fit
within the earlier timing window of the remote service.  This won't usually matter unless you're pushing close to the
rate limit of the remote API.

In any event, matching the characteristics and quirks of the remote service will still mean having to guard against
rate limiting restrictions in your own code.
 






