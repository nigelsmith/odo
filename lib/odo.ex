#   Copyright 2017 Nigel Smith
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

defmodule Odo.Bucket do
    @moduledoc """
    `Odo.Bucket` is a simple `GenServer` based token bucket.

    To start a new token bucket call `Odo.Bucket.new_bucket/2` with the name for the bucket and values for the
    number of tokens the bucket should hold.

    Once the bucket is running call `Odo.Bucket.get_token/1` with the name of the bucket.
    """

    use GenServer


    #    The state for the rate limiter which takes the form of the current number of tokens in the bucket,
    #    the time the bucket count began at and the time skew (or buffer) estimated for the remote service.
    @typedoc false
    @type rate_state :: %{
        tokens: pos_integer,
        tick_started_at: pos_integer | :init,
        bucket_size: pos_integer,
        tick_duration: pos_integer,
        tick_refill_amount: pos_integer,
        buffer: non_neg_integer
    }

    @doc """
    new_bucket starts a new bucket process.  It takes the bucket name, the number of tokens the bucket holds, the
    refill duration and (optionally) the skew, or buffer, to add to the bucket refill time.

    You may need to add a buffer to the token refill time if you're operating near the rate limit and need to account
    for latency effects - i.e. you dispatch 10 tokens in a given time but they do not arrive at their destination within
    that same timeframe.
    """
    @spec new_bucket(name :: String.t, [tokens: pos_integer, tick_refill_amount: pos_integer, tick_duration: pos_integer, buffer: non_neg_integer]) :: Supervisor.on_start_child
    def new_bucket(name, opts \\ []) do
        tokens = Keyword.get(opts, :tokens, 100)
        bucket_refill_amount = Keyword.get(opts, :tick_refill_amount, tokens)
        refill_duration = Keyword.get(opts, :tick_duration, 10_000)
        buffer = Keyword.get(opts, :buffer, 0)

        Odo.BucketSupervisor.start_child(name, tokens, bucket_refill_amount, refill_duration, buffer)
    end

    @doc false
    def start_link(name, bucket_size, bucket_refill_amount, bucket_refill_duration, buffer) do
        GenServer.start_link(__MODULE__, {name, bucket_size, bucket_refill_amount, bucket_refill_duration, buffer}, name: via(name))
    end

    defp via(name) do
        {:via, Registry, {:odo_bucket_registry, name}}
    end

    def init({_name, bucket_size, tick_refill_amount, tick_duration, buffer}) do
        {:ok,
            %{
                tokens: 0,
                tick_started_at: :init,
                bucket_size: bucket_size,
                tick_refill_amount: tick_refill_amount,
                tick_duration: tick_duration + buffer,
                buffer: buffer
            }
        }
    end

    @doc """
    `Odo.Bucket.get_token/1` attempts to claim a token and responds with `{:go, tokens_remaining, until}` if the call
    is safe to proceed or with `{:stop, until}` that tells the caller to wait until the next likely availability of
    tokens in terms of `until` number of milliseconds.
    """
    @spec get_token(String.t) :: {:go, tokens_remaining :: pos_integer, until :: pos_integer} | {:stop, until :: pos_integer}
    def get_token(name) do
        GenServer.call(via(name), :get_token)
    end

    @doc """
    `Odo.Bucket.reset/2` restarts the bucket timer with the given buffer from the next call to `Odo.Bucket.get_token/1`
    """
    @spec reset(name :: String.t, buffer :: non_neg_integer) :: {:ok, new_buffer :: non_neg_integer}
    def reset(name, buffer) do
      GenServer.call(via(name), {:reset, buffer})
    end

    @doc """
    `Odo.Bucket.reset/1` restarts the bucket timer from the next call to `Odo.Bucket.get_token/1`
    """
    @spec reset(name :: String.t) :: :ok
    def reset(name) do
      GenServer.call(via(name), :reset)
    end

    @doc """
    `Odo.Bucket.set_tick_start/2` updates the start of the current bucket refill tick to the figure provided.  If the
    remote server provides information about the current status of the rate limit you can use that to update the bucket
    manually and better match the remote server.
    """
    @spec set_tick_start(name :: String.t, start_time: pos_integer) :: {:ok, new_tick_start :: pos_integer}
    def set_tick_start(name, start_time) do
      GenServer.call(via(name), {:set_tick_start, start_time})
    end


    @doc """
    `Odo.Bucket.set_tick_end/2` updates the start of the current bucket refill tick based on the time it was due to end.
    If the remote server lets you know when the next refill will happen you can provde this time and the current tick
    start time will be recalculated.
    """
    @spec set_tick_end(name :: String.t, tick_end :: pos_integer) :: {:ok, new_tick_start :: pos_integer}
    def set_tick_end(name, tick_end) do
      GenServer.call(via(name), {:set_tick_end, tick_end})
    end

    @doc """
    `Odo.Bucket.stop_bucket/1` stops the named bucket process.
    """
    @spec stop_bucket(name :: String.t) :: :ok | {:error, String.t}
    def stop_bucket(name) do
      case Registry.lookup(:odo_bucket_registry, name) do
        [{pid, _}] -> Supervisor.terminate_child(Odo.BucketSupervisor, pid)
        [] -> {:error, "No such bucket #{name}"}
      end
    end

    def handle_call({:set_tick_end, tick_end}, _, %{tick_duration: tick_duration} = state) do
      new_tick_start = tick_end - tick_duration
      {:reply, {:ok, new_tick_start}, %{state | tick_started_at: new_tick_start}}
    end

    def handle_call({:set_tick_start, start_time}, _, state) do
      {:reply, {:ok, start_time}, %{state | tick_started_at: start_time}}
    end

    def handle_call(:reset, _, state) do
      {:reply, :ok, %{state | tick_started_at: :init, tokens: 0}}
    end

    def handle_call({:reset, buffer}, _, %{buffer: cur_buffer, tick_duration: cur_tick_duration} = state) do
      {:reply, :ok, %{state | tick_started_at: :init, tokens: 0, buffer: buffer, tick_duration: cur_tick_duration - cur_buffer + buffer}}
    end

    def handle_call(:get_token, _, %{tick_started_at: :init} = state) do
      now = :erlang.system_time(:millisecond)

      update_token_bucket(now, %{state | tick_started_at: now})
    end

    def handle_call(:get_token, _, state) do
      now = :erlang.system_time(:millisecond)

      update_token_bucket(now, state)
    end

    @doc false
    @spec update_token_bucket(update_time :: non_neg_integer, state :: rate_state) :: {:reply, :ok | {:stop, pos_integer}, state :: rate_state}
    def update_token_bucket(update_time,
    %{
      tokens: tokens,
      bucket_size: bucket_size,
      tick_refill_amount: tick_refill_amount,
      tick_started_at: tick_started_at,
      tick_duration: tick_duration
    } = state) do

        diff =  update_time - tick_started_at
        ticks = div(diff, tick_duration)
        until = tick_duration - rem(diff, tick_duration)
        current_tick_started_at = tick_started_at + ticks * tick_duration

        cond do
            ticks > 0 ->
              new_tokens = calc_tokens(tokens, ticks, tick_refill_amount)
              {:reply, {:go, bucket_size - new_tokens, until}, %{state | tokens: new_tokens, tick_started_at: current_tick_started_at}}

            tokens + 1 > bucket_size -> {:reply, {:stop, until}, state}

            true -> {:reply, {:go, bucket_size - (tokens + 1), until}, %{state | tokens: tokens + 1}}
        end
    end

    @spec calc_tokens(current_tokens :: non_neg_integer, ticks :: pos_integer, refill_amount :: pos_integer) :: pos_integer
    defp calc_tokens(current_tokens, ticks, refill_amount) do
      tokens = current_tokens - (ticks * refill_amount) + 1

      if tokens <= 0, do: 1, else: tokens
    end
end
