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

defmodule OdoTest do
  use ExUnit.Case

  test "new_bucket creates a bucket with the given name and makes it available via the registry" do
    assert Registry.lookup(:odo_bucket_registry, "test_bucket_start") == []

    assert {:ok, bucket} = Odo.Bucket.new_bucket("test_bucket_start")

    assert [{^bucket, nil}] = Registry.lookup(:odo_bucket_registry, "test_bucket_start")
  end

  test "stop_bucket stops the running bucket" do
    assert Registry.lookup(:odo_bucket_registry, "test_bucket_stop") == []

    assert {:ok, bucket} = Odo.Bucket.new_bucket("test_bucket_stop")

    assert [{^bucket, nil}] = Registry.lookup(:odo_bucket_registry, "test_bucket_stop")

    assert :ok = Odo.Bucket.stop_bucket("test_bucket_stop")

    refute Process.alive?(bucket)
  end

  test "get_token returns the right value when the bucket isn't full" do
    assert {:ok, _bucket} = Odo.Bucket.new_bucket("test_bucket_token")
    assert {:go, 99, _10_000} = Odo.Bucket.get_token("test_bucket_token")
  end

  test "handle_call :get_token handles a full bucket correctly" do
    state = %{
        tokens: 100,
        bucket_size: 100,
        tick_started_at: :erlang.system_time(:millisecond),
        tick_duration: 10_000,
        tick_refill_amount: 100,
        buffer: 0
    }

    assert {:reply, {:stop, _until}, ^state} = Odo.Bucket.handle_call(:get_token, nil, state)
  end

  test "handle_call :get_token handles an non-full bucket correctly" do
      state = %{
          tokens: 1,
          bucket_size: 100,
          tick_started_at: :erlang.system_time(:millisecond),
          tick_duration: 10_000,
          tick_refill_amount: 100,
          buffer: 0
      }

    assert {:reply, {:go, 98, _10_000}, %{tokens: 2}} = Odo.Bucket.handle_call(:get_token, nil, state)
  end

    test "handle_call :get_token handles a refilled bucket correctly" do
        state = %{
            tokens: 100,
            bucket_size: 100,
            tick_started_at: :erlang.system_time(:millisecond) - 12_000,
            tick_duration: 10_000,
            tick_refill_amount: 100,
            buffer: 0
        }

      assert {:reply, {:go, 99, _8_000}, %{tokens: 1}} = Odo.Bucket.handle_call(:get_token, nil, state)
    end

    test "update token bucket increases the token count by 1 when the bucket is not full and the bucket has not been refilled" do
        bucket_creation_time = :erlang.system_time(:millisecond)
        bucket_size = 10
        bucket_refill_duration = 1_000
        tick_refill_amount = bucket_size
        expected_state = %{
            tokens: 1,
            tick_started_at: bucket_creation_time,
            bucket_size: bucket_size,
            tick_refill_amount: tick_refill_amount,
            tick_duration: bucket_refill_duration,
            buffer: 0
        }

        initial_state = %{
            tokens: 0,
            tick_started_at: bucket_creation_time,
            bucket_size: bucket_size,
            tick_refill_amount: tick_refill_amount,
            tick_duration: bucket_refill_duration,
            buffer: 0
        }

        assert {:reply, {:go, 9, 1_000}, ^expected_state} = Odo.Bucket.update_token_bucket(bucket_creation_time, initial_state)
    end

    test "update token bucket tells us to stop when bucket is full and wait for the right amount of time" do
        bucket_creation_time = :erlang.system_time(:millisecond)
        bucket_size = 100
        bucket_refill_duration = 1_000
        tick_refill_amount = bucket_size

        expected_state = %{
            tokens: 100,
            tick_started_at: bucket_creation_time,
            tick_refill_amount: tick_refill_amount,
            bucket_size: bucket_size,
            tick_duration: bucket_refill_duration,
            buffer: 0
        }

        assert {:reply, {:stop, 1_000}, ^expected_state} = Odo.Bucket.update_token_bucket(bucket_creation_time, expected_state)
    end

    test "update token bucket resets the bucket when the refill period is over" do
        now = :erlang.system_time(:millisecond)
        bucket_size = 100
        bucket_refill_duration = 1_000
        bucket_creation_time = now - 2_000
        tick_refill_amount = bucket_size

        expected_state = %{
            tokens: 1,
            tick_started_at: now,
            bucket_size: bucket_size,
            tick_refill_amount: tick_refill_amount,
            tick_duration: bucket_refill_duration,
            buffer: 0
        }

        state = %{
            tokens: 99,
            tick_started_at: bucket_creation_time,
            bucket_size: bucket_size,
            tick_refill_amount: tick_refill_amount,
            tick_duration: bucket_refill_duration,
            buffer: 0
        }

        assert {:reply, {:go, 99, 1_000}, ^expected_state} = Odo.Bucket.update_token_bucket(now, state)
    end

    test "update token bucket partially empties the bucket depending on how many update ticks have taken place" do
        now = :erlang.system_time(:millisecond)
        bucket_size = 100
        bucket_refill_duration = 1_000
        bucket_creation_time = now - 1_100
        tick_refill_amount = 10

        expected_state = %{
            tokens: 86,
            tick_started_at: bucket_creation_time + 1_000,
            bucket_size: bucket_size,
            tick_refill_amount: tick_refill_amount,
            tick_duration: bucket_refill_duration,
            buffer: 0
        }

        state = %{
            tokens: 95,
            tick_started_at: bucket_creation_time,
            bucket_size: bucket_size,
            tick_refill_amount: tick_refill_amount,
            tick_duration: bucket_refill_duration,
            buffer: 0
        }

        assert {:reply, {:go, 14, 900}, ^expected_state} = Odo.Bucket.update_token_bucket(now, state)
    end

    test "set_tick_start updates the tick start time" do
      now = :erlang.system_time(:millisecond)
      bucket_size = 100
      bucket_refill_duration = 1_000
      bucket_creation_time = now - 1_000
      tick_refill_amount = 10
      buffer = 200

      new_start_time = now + 1_000

      expected_state = %{
          tokens: 100,
          tick_started_at: new_start_time,
          bucket_size: bucket_size,
          tick_refill_amount: tick_refill_amount,
          tick_duration: bucket_refill_duration,
          buffer: buffer
      }

      state = %{
          tokens: 100,
          tick_started_at: bucket_creation_time,
          bucket_size: bucket_size,
          tick_refill_amount: tick_refill_amount,
          tick_duration: bucket_refill_duration,
          buffer: buffer
      }

      assert {:reply, {:ok, ^new_start_time}, ^expected_state} = Odo.Bucket.handle_call({:set_tick_start, new_start_time}, nil, state)
    end

    test "set_tick_end correctly updates the tick start time" do
      now = :erlang.system_time(:millisecond)
      bucket_size = 100
      bucket_refill_duration = 1_000
      bucket_creation_time = now + 1_000
      tick_refill_amount = 10
      buffer = 100

      new_tick_end = now + 2_000
      expected_tick_start = new_tick_end - bucket_refill_duration

      state = %{
          tokens: 100,
          tick_started_at: bucket_creation_time,
          bucket_size: bucket_size,
          tick_refill_amount: tick_refill_amount,
          tick_duration: bucket_refill_duration,
          buffer: buffer
      }

      expected_state = %{
          tokens: 100,
          tick_started_at: expected_tick_start,
          bucket_size: bucket_size,
          tick_refill_amount: tick_refill_amount,
          tick_duration: bucket_refill_duration,
          buffer: buffer
      }

      assert {:reply, {:ok, ^expected_tick_start}, ^expected_state} = Odo.Bucket.handle_call({:set_tick_end, new_tick_end}, nil, state)
    end

    test "reset correctly updates the state to an initial condition with no buffer" do
      now = :erlang.system_time(:millisecond)
      bucket_size = 100
      bucket_refill_duration = 1_000
      bucket_creation_time = now + 1_000
      tick_refill_amount = 10
      buffer = 100

      state = %{
        tokens: 100,
        tick_started_at: bucket_creation_time,
        bucket_size: bucket_size,
        tick_refill_amount: tick_refill_amount,
        tick_duration: bucket_refill_duration,
        buffer: buffer
      }

      expected_state = %{state | tick_started_at: :init, tokens: 0}

      assert {:reply, :ok, ^expected_state} = Odo.Bucket.handle_call(:reset, nil, state)
    end

    test "reset correctly updates the state to an initial condition with buffer" do
      now = :erlang.system_time(:millisecond)
      bucket_size = 100
      bucket_refill_duration = 1_000
      bucket_creation_time = now + 1_000
      tick_refill_amount = 10
      buffer = 100


      new_buffer = 200

      state = %{
        tokens: 100,
        tick_started_at: bucket_creation_time,
        bucket_size: bucket_size,
        tick_refill_amount: tick_refill_amount,
        tick_duration: bucket_refill_duration + buffer,
        buffer: buffer
      }

      expected_state = %{state | tick_started_at: :init, buffer: new_buffer, tick_duration: 1_200, tokens: 0}

      assert {:reply, :ok, ^expected_state} = Odo.Bucket.handle_call({:reset, new_buffer}, nil, state)
    end
end
