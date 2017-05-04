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

defmodule GetTokenBench do
    use Benchfella

    @now :erlang.system_time(:millisecond)
    @the_near_future @now + 10
    @the_still_pretty_near_future @now + 10_001
    @the_state_of_now %{tokens: 1, tick_started_at: @now, tick_refill_amount: 100, bucket_size: 100, tick_duration: 10_000, buffer: 500}
    @the_full_state %{tokens: 100, tick_started_at: @now, tick_refill_amount: 100, bucket_size: 100, tick_duration: 10_000, buffer: 500}
    @bucket "bench"

    setup_all do
        Odo.BucketSupervisor.start_link()
        Registry.start_link(:unique, :odo_bucket_registry)
        Odo.BucketSupervisor.start_child(@bucket, 100, 100, 10_000, 500)
        {:ok, nil}
    end

    teardown_all _arg do
        Supervisor.stop(Odo.BucketSupervisor)
        Supervisor.stop(:odo_bucket_registry)
    end

    bench "update_token_bucket with fresh bucket" do
        Odo.Bucket.update_token_bucket(@the_near_future, @the_state_of_now)
    end

    bench "update_token_bucket with a full bucket" do
        Odo.Bucket.update_token_bucket(@the_near_future, @the_full_state)
    end

    bench "update_token_bucket with an expired bucket" do
        Odo.Bucket.update_token_bucket(@the_still_pretty_near_future, @the_state_of_now)
    end

    bench "get_token" do
        Odo.Bucket.get_token(@bucket)
        :ok
    end
end
